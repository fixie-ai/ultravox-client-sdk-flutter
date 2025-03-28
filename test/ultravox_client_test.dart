import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ultravox_client/ultravox_client.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:mockito/mockito.dart';
import 'dart:convert';

import 'fake_lk.dart';

void main() {
  group('UltravoxSession mute tests', () {
    late FakeRoom room;
    late UltravoxSession session;

    setUp(() {
      room = FakeRoom();
      session = UltravoxSession(room, {});
    });

    test('micMuted getter and setter', () {
      int micMuteCounter = 0;
      session.micMutedNotifier.addListener(() {
        micMuteCounter++;
      });

      expect(session.micMuted, false);

      session.micMuted = true;
      expect(session.micMuted, true);
      expect(micMuteCounter, 1);

      session.micMuted = true; // Should not trigger listener
      expect(micMuteCounter, 1);

      session.micMuted = false;
      expect(session.micMuted, false);
      expect(micMuteCounter, 2);
    });

    test('speakerMuted getter and setter', () {
      int speakerMuteCounter = 0;
      session.speakerMutedNotifier.addListener(() {
        speakerMuteCounter++;
      });

      expect(session.speakerMuted, false);

      session.speakerMuted = true;
      expect(session.speakerMuted, true);
      expect(speakerMuteCounter, 1);

      session.speakerMuted = true; // Should not trigger listener
      expect(speakerMuteCounter, 1);

      session.speakerMuted = false;
      expect(session.speakerMuted, false);
      expect(speakerMuteCounter, 2);
    });

    group('client tool implementations', () {
      invokeTool(
          FutureOr<ClientToolResult> Function(Object params) impl) async {
        session.registerToolImplementation("test-tool", impl);
        await session.handleSocketMessage(json.encode({
          "type": "room_info",
          "roomUrl": "wss://test-room",
          "token": "test-token"
        }));
        final data = {
          "type": "client_tool_invocation",
          "toolName": "test-tool",
          "invocationId": "call_1",
          "parameters": {"foo": "bar"}
        };
        room.emit(lk.DataReceivedEvent(
            participant: room.remoteParticipant,
            data: utf8.encode(json.encode(data)),
            topic: null));
        await Future<dynamic>.delayed(const Duration(milliseconds: 1));
      }

      test('basic', () async {
        ClientToolResult impl(Object params) {
          expect(params, {"foo": "bar"});
          return ClientToolResult("baz");
        }

        await invokeTool(impl);

        final sentData = verify(
                room.localParticipant.publishData(captureAny, reliable: true))
            .captured
            .single;
        final sentJson = json.decode(utf8.decode(sentData as List<int>));
        expect(sentJson, {
          "type": "client_tool_result",
          "invocationId": "call_1",
          "result": "baz"
        });
      });

      test('async tool', () async {
        Future<ClientToolResult> impl(Object params) async {
          expect(params, {"foo": "bar"});
          await Future<void>.delayed(Duration.zero);
          return ClientToolResult("baz");
        }

        await invokeTool(impl);

        final sentData = verify(
                room.localParticipant.publishData(captureAny, reliable: true))
            .captured
            .single;
        final sentJson = json.decode(utf8.decode(sentData as List<int>));
        expect(sentJson, {
          "type": "client_tool_result",
          "invocationId": "call_1",
          "result": "baz"
        });
      });

      test('setting response type', () async {
        ClientToolResult impl(Object params) {
          expect(params, {"foo": "bar"});
          return ClientToolResult('{"strict": true}', responseType: "hang-up");
        }

        await invokeTool(impl);

        final sentData = verify(
                room.localParticipant.publishData(captureAny, reliable: true))
            .captured
            .single;
        final sentJson = json.decode(utf8.decode(sentData as List<int>));
        expect(sentJson, {
          "type": "client_tool_result",
          "invocationId": "call_1",
          "result": '{"strict": true}',
          "responseType": "hang-up"
        });
      });

      test('setting agent reaction', () async {
        ClientToolResult impl(Object params) {
          expect(params, {"foo": "bar"});
          return ClientToolResult('{"strict": true}',
              agentReaction: AgentReaction.speaksOnce);
        }

        await invokeTool(impl);

        final sentData = verify(
                room.localParticipant.publishData(captureAny, reliable: true))
            .captured
            .single;
        final sentJson = json.decode(utf8.decode(sentData as List<int>));
        expect(sentJson, {
          "type": "client_tool_result",
          "invocationId": "call_1",
          "result": '{"strict": true}',
          "agentReaction": "speaks-once"
        });
      });

      test('error', () async {
        final testError = Exception("test error");
        ClientToolResult impl(Object params) {
          expect(params, {"foo": "bar"});
          throw testError;
        }

        await invokeTool(impl);

        final sentData = verify(
                room.localParticipant.publishData(captureAny, reliable: true))
            .captured
            .single;
        final sentJson = json.decode(utf8.decode(sentData as List<int>));
        expect(sentJson, {
          "type": "client_tool_result",
          "invocationId": "call_1",
          "errorType": "implementation-error",
          "errorMessage": testError.toString(),
        });
      });
    });
  });
}
