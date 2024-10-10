import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

/// The current status of an [UltravoxSession].
enum UltravoxSessionStatus {
  /// The voice session is not connected and not attempting to connect.
  ///
  /// This is the initial state of a voice session.
  disconnected(live: false),

  /// The client is disconnecting from the voice session.
  disconnecting(live: false),

  /// The client is attempting to connect to the voice session.
  connecting(live: false),

  /// The client is connected to the voice session and the server is warming up.
  idle(live: true),

  /// The client is connected and the server is listening for voice input.
  listening(live: true),

  /// The client is connected and the server is considering its response.
  ///
  /// The user can still interrupt.
  thinking(live: true),

  /// The client is connected and the server is playing response audio.
  ///
  /// The user can interrupt as needed.
  speaking(live: true);

  const UltravoxSessionStatus({required this.live});

  final bool live;
}

enum Role {
  user,
  agent,
}

enum Medium {
  voice,
  text,
}

/// A transcription of a single utterance.
class Transcript {
  /// The possibly-incomplete text of an utterance.
  final String text;

  /// Whether the text is complete or the utterance is ongoing.
  final bool isFinal;

  /// Who emitted the utterance.
  final Role speaker;

  /// The medium through which the utterance was emitted.
  final Medium medium;

  Transcript({
    required this.text,
    required this.isFinal,
    required this.speaker,
    required this.medium,
  });
}

/// A collection of [Transcript]s for an [UltravoxSession].
///
/// [Transcripts] is a [ChangeNotifier] that notifies listeners when
/// transcripts are updated or new transcripts are added.
class Transcripts extends ChangeNotifier {
  final _transcripts = <Transcript>[];

  List<Transcript> get transcripts => List.unmodifiable(_transcripts);

  void _addOrUpdateTranscript(Transcript transcript) {
    if (_transcripts.isNotEmpty &&
        !_transcripts.last.isFinal &&
        _transcripts.last.speaker == transcript.speaker) {
      _transcripts.replaceRange(
          _transcripts.length - 1, _transcripts.length, [transcript]);
    } else {
      _transcripts.add(transcript);
    }
    notifyListeners();
  }
}

/// The result type returned by a ClientToolImplementation.
class ClientToolResult {
  /// The result of the client tool.
  ///
  /// This is exactly the string that will be seen by the model. Often JSON.
  final String result;

  /// The type of response the tool is providing.
  ///
  /// Most tools simply provide information back to the model, in which case
  /// responseType need not be set. For other tools that are instead interpreted
  /// by the server to affect the call, responseType may be set to indicate how
  /// the call should be altered. In this case, [result] should be JSON with
  /// instructions for the server. The schema depends on the response type.
  /// See https://docs.ultravox.ai/tools for more information.
  final String? responseType;

  ClientToolResult(this.result, {this.responseType});
}

/// A function that fulfills a client-implemented tool.
///
/// The function should take an object containing the tool's parameters (parsed
/// from JSON) and return a [ClientToolResult] object. It may or may not be
/// asynchronous.
typedef ClientToolImplementation = FutureOr<ClientToolResult> Function(
    Object data);

/// Manages a single session with Ultravox.
///
/// In addition to providing methods to manage a call, [UltravoxSession] exposes
/// several notifiers that allow UI elements to listen for specific state
/// changes.
class UltravoxSession {
  /// A [ValueNotifier] that emits events when the session status changes.
  final statusNotifier = ValueNotifier<UltravoxSessionStatus>(
    UltravoxSessionStatus.disconnected,
  );

  /// A quick accessor for the session's current status.
  ///
  /// Listen to [statusNotifier] to receive updates when this changes.
  UltravoxSessionStatus get status => statusNotifier.value;

  /// A [ChangeNotifier] that emits events when new transcripts are available.
  final transcriptsNotifier = Transcripts();

  /// A quick accessor for the session's current transcripts.
  ///
  /// Listen to [transcriptsNotifier] to receive updates on transcript changes.
  List<Transcript> get transcripts => transcriptsNotifier.transcripts;

  /// A [ValueNotifier] that emits events when new experimental messages are
  /// received.
  ///
  /// Experimental messages are messages that are not part of the released
  /// Ultravox API but may be selected for testing new features or debugging.
  /// The messages received depend on the `experimentalMessages` provided to
  /// [UltravoxSession.create].
  final experimentalMessageNotifier = ValueNotifier<Map<String, dynamic>>({});

  /// A quick accessor for the last experimental message received.
  ///
  /// Listen to [experimentalMessageNotifier] to receive updates.
  Map<String, dynamic> get lastExperimentalMessage =>
      experimentalMessageNotifier.value;

  /// A [ValueNotifier] that emits events when the user's mic is muted or unmuted.
  final micMutedNotifier = ValueNotifier<bool>(false);

  /// A [ValueNotifier] that emits events when the user's speaker (i.e. output audio from the agent) is muted or unmuted.
  final speakerMutedNotifier = ValueNotifier<bool>(false);

  /// The mute status of the user's microphone.
  ///
  /// Listen to [micMutedNotifier] to receive updates.
  bool get micMuted => micMutedNotifier.value;

  /// Sets the mute status of the user's microphone.
  set micMuted(bool muted) {
    if (muted != micMutedNotifier.value) {
      _room.localParticipant?.setMicrophoneEnabled(!muted);
      micMutedNotifier.value = muted;
    }
  }

  /// Toggles the mute status of the user's microphone.
  void toggleMicMuted() => micMuted = !micMuted;

  /// The mute status for the user's speaker (i.e. output audio from the agent).
  ///
  /// Listen to [speakerMutedNotifier] to receive updates.
  bool get speakerMuted => speakerMutedNotifier.value;

  /// Sets the mute status of the user's speaker (i.e. output audio from the agent).
  set speakerMuted(bool muted) {
    if (muted != speakerMutedNotifier.value) {
      for (final participant in _room.remoteParticipants.values) {
        for (final publication in participant.audioTrackPublications) {
          if (muted) {
            publication.track?.disable();
          } else {
            publication.track?.enable();
          }
        }
      }
      speakerMutedNotifier.value = muted;
    }
  }

  /// Toggles the mute status of the user's speaker (i.e. output audio from the agent).
  void toggleSpeakerMuted() => speakerMuted = !speakerMuted;

  final Set<String> _experimentalMessages;
  final lk.Room _room;
  final lk.EventsListener<lk.RoomEvent> _listener;
  late WebSocketChannel _wsChannel;
  final _registeredTools = <String, ClientToolImplementation>{};

  UltravoxSession(this._room, this._experimentalMessages)
      : _listener = _room.createListener();

  UltravoxSession.create({Set<String>? experimentalMessages})
      : this(lk.Room(), experimentalMessages ?? {});

  /// Registers a client tool implementation using the given name.
  ///
  /// If the call is started with a client-implemented tool, this implementation
  /// will be invoked when the model calls the tool.
  /// See https://docs.ultravox.ai/tools for more information.
  void registerToolImplementation(String name, ClientToolImplementation impl) {
    _registeredTools[name] = impl;
  }

  /// Convenience batch wrapper for [registerToolImplementation].
  void registerToolImplementations(
      Map<String, ClientToolImplementation> implementations) {
    implementations.forEach(registerToolImplementation);
  }

  /// Connects to a call using the given [joinUrl].
  Future<void> joinCall(String joinUrl) async {
    if (status != UltravoxSessionStatus.disconnected) {
      throw Exception('Cannot join a new call while already in a call');
    }
    statusNotifier.value = UltravoxSessionStatus.connecting;
    var url = Uri.parse(joinUrl);
    if (_experimentalMessages.isNotEmpty) {
      final queryParameters = Map<String, String>.from(url.queryParameters)
        ..addAll({
          'experimentalMessages': _experimentalMessages.join(','),
        });
      url = url.replace(queryParameters: queryParameters);
    }
    _wsChannel = WebSocketChannel.connect(url);
    await _wsChannel.ready;
    _wsChannel.stream.listen((event) async {
      await handleSocketMessage(event);
    });
  }

  /// Leaves the current call (if any).
  Future<void> leaveCall() async {
    _disconnect();
  }

  /// Sets the agent's output medium.
  ///
  /// If the agent is currently speaking, this will take effect at the end of
  /// the agent's utterance. Also see [speakerMuted].
  Future<void> setOutputMedium(Medium medium) async {
    if (!status.live) {
      throw Exception(
          'Cannot set speaker medium while not connected. Current status: $status');
    }
    await _sendData({'type': 'set_output_medium', 'medium': medium.name});
  }

  /// Sends a message via text.
  Future<void> sendText(String text) async {
    if (!status.live) {
      throw Exception(
          'Cannot send text while not connected. Current status: $status');
    }
    await _sendData({'type': 'input_text_message', 'text': text});
  }

  Future<void> _disconnect() async {
    if (status == UltravoxSessionStatus.disconnected) {
      return;
    }
    statusNotifier.value = UltravoxSessionStatus.disconnecting;
    await Future.wait([
      _room.disconnect(),
      _wsChannel.sink.close(),
    ]);
    statusNotifier.value = UltravoxSessionStatus.disconnected;
  }

  @visibleForTesting
  Future<void> handleSocketMessage(dynamic event) async {
    if (event is! String) {
      throw Exception('Received unexpected message from socket');
    }
    final message = jsonDecode(event);
    switch (message['type']) {
      case 'room_info':
        await _room.connect(
            message['roomUrl'] as String, message['token'] as String);
        await _room.localParticipant!.setMicrophoneEnabled(true);
        _listener
          ..on<lk.TrackSubscribedEvent>(_handleTrackSubscribed)
          ..on<lk.DataReceivedEvent>(_handleDataMessage);
        statusNotifier.value = UltravoxSessionStatus.idle;
        break;
      default:
      // ignore
    }
  }

  Future<void> _handleTrackSubscribed(lk.TrackSubscribedEvent event) async {
    await _room.startAudio();
  }

  Future<void> _handleDataMessage(lk.DataReceivedEvent event) async {
    final data = jsonDecode(utf8.decode(event.data));
    switch (data['type']) {
      case 'state':
        switch (data['state']) {
          case 'listening':
            statusNotifier.value = UltravoxSessionStatus.listening;
            break;
          case 'thinking':
            statusNotifier.value = UltravoxSessionStatus.thinking;
            break;
          case 'speaking':
            statusNotifier.value = UltravoxSessionStatus.speaking;
            break;
          default:
          // ignore
        }
        break;
      case 'transcript':
        final medium = data['transcript']['medium'] == 'voice'
            ? Medium.voice
            : Medium.text;
        final transcript = Transcript(
          text: data['transcript']['text'] as String,
          isFinal: data['transcript']['final'] as bool,
          speaker: Role.user,
          medium: medium,
        );
        transcriptsNotifier._addOrUpdateTranscript(transcript);
        break;
      case 'voice_synced_transcript':
      case 'agent_text_transcript':
        final medium = data['type'] == 'voice_synced_transcript'
            ? Medium.voice
            : Medium.text;
        if (data['text'] != null) {
          final transcript = Transcript(
            text: data['text'] as String,
            isFinal: data['final'] as bool,
            speaker: Role.agent,
            medium: medium,
          );
          transcriptsNotifier._addOrUpdateTranscript(transcript);
        } else if (data['delta'] != null) {
          final last = transcriptsNotifier._transcripts.lastOrNull;
          if (last?.speaker == Role.agent) {
            final transcript = Transcript(
              text: last!.text + (data['delta'] as String),
              isFinal: data['final'] as bool,
              speaker: Role.agent,
              medium: medium,
            );
            transcriptsNotifier._addOrUpdateTranscript(transcript);
          }
        }
        break;
      case 'client_tool_invocation':
        await _invokeClientTool(data['toolName'] as String,
            data['invocationId'] as String, data['parameters'] as Object);
      default:
        if (_experimentalMessages.isNotEmpty) {
          experimentalMessageNotifier.value = data as Map<String, dynamic>;
        }
    }
  }

  Future<void> _invokeClientTool(
      String toolName, String invocationId, Object parameters) async {
    final tool = _registeredTools[toolName];
    if (tool == null) {
      await _sendData({
        'type': 'client_tool_result',
        'invocationId': invocationId,
        'errorType': 'undefined',
        'errorMessage':
            'Client tool $toolName is not registered (Flutter client)',
      });
      return;
    }
    try {
      final result = await tool(parameters);
      final data = {
        'type': 'client_tool_result',
        'invocationId': invocationId,
        'result': result.result,
      };
      if (result.responseType != null) {
        data['responseType'] = result.responseType!;
      }
      await _sendData(data);
    } catch (e) {
      await _sendData({
        'type': 'client_tool_result',
        'invocationId': invocationId,
        'errorType': 'implementation-error',
        'errorMessage': e.toString(),
      });
    }
  }

  Future<void> _sendData(Object data) async {
    final message = jsonEncode(data);
    await _room.localParticipant
        ?.publishData(utf8.encode(message), reliable: true);
  }
}
