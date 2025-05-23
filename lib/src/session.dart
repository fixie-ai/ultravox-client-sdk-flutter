import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

const ultravoxSdkVersion = '0.0.9';

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

/// How the agent should proceed after a tool invocation.
enum AgentReaction {
  /// The agent should speak after the tool invocation.
  ///
  /// This is the default and is recommended for tools that retrieve information
  /// for the agent to act on.
  speaks(val: "speaks"),

  /// The agent should listen after the tool invocation.
  ///
  /// This is recommended for tools the user is expected to act on, such as
  /// certain clear UI changes.
  listens(val: "listens"),

  /// The agent should speak after the tool invocation if and only if it did not
  /// speak immediately before the tool invocation.
  ///
  /// This is recommended for tools whose primary purpose is a side effect like
  /// recording information collected from the user.
  speaksOnce(val: "speaks-once");

  const AgentReaction({required this.val});

  final String val;
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
  final _transcripts = <Transcript?>[];

  List<Transcript> get transcripts =>
      List.unmodifiable(_transcripts.whereType<Transcript>());

  void _addOrUpdateTranscript(
      int ordinal, Medium medium, Role speaker, bool isFinal,
      {String? text, String? delta}) {
    while (_transcripts.length < ordinal) {
      _transcripts.add(null);
    }
    if (_transcripts.length == ordinal) {
      _transcripts.add(Transcript(
        text: text ?? delta ?? '',
        isFinal: isFinal,
        speaker: speaker,
        medium: medium,
      ));
    } else {
      final priorText = _transcripts[ordinal]?.text ?? '';
      _transcripts[ordinal] = Transcript(
        text: text ?? priorText + (delta ?? ''),
        isFinal: isFinal,
        speaker: speaker,
        medium: medium,
      );
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

  /// How the agent should proceed after the tool invocation.
  final AgentReaction? agentReaction;

  /// The new call state, if it should change.
  ///
  /// Call state can be sent to other tools using an automatic parameter.
  final Map<String, Object>? updateCallState;

  ClientToolResult(this.result,
      {this.responseType, this.agentReaction, this.updateCallState});
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

  /// A [ValueNotifier] that emits events when any new data messages are
  /// received, including those typically handled by this SDK.
  ///
  /// See https://docs.ultravox.ai/datamessages for message types.
  final dataMessageNotifier = ValueNotifier<Map<String, dynamic>>({});

  /// A quick accessor for the last data message received.
  ///
  /// Listen to [dataMessageNotifier] to receive updates.
  Map<String, dynamic> get lastDataMessage => dataMessageNotifier.value;

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
  Future<void> joinCall(String joinUrl, {String? clientVersion}) async {
    if (status != UltravoxSessionStatus.disconnected) {
      throw Exception('Cannot join a new call while already in a call');
    }
    statusNotifier.value = UltravoxSessionStatus.connecting;
    var url = Uri.parse(joinUrl);
    final queryParams = Map<String, String>.from(url.queryParameters);
    var uvClientVersion = "flutter_$ultravoxSdkVersion";
    if (clientVersion != null) {
      uvClientVersion += ":$clientVersion";
    }
    queryParams.addAll({'clientVersion': uvClientVersion, 'apiVersion': '1'});
    if (_experimentalMessages.isNotEmpty) {
      queryParams.addAll({
        'experimentalMessages': _experimentalMessages.join(','),
      });
    }
    url = url.replace(queryParameters: queryParams);
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
    await sendData({'type': 'set_output_medium', 'medium': medium.name});
  }

  /// Sends a message via text.
  Future<void> sendText(String text, {bool? deferResponse}) async {
    if (!status.live) {
      throw Exception(
          'Cannot send text while not connected. Current status: $status');
    }
    final Map<String, Object> data = {
      'type': 'input_text_message',
      'text': text
    };
    if (deferResponse != null) {
      data['deferResponse'] = deferResponse;
    }
    await sendData(data);
  }

  /// Sends an arbitrary data message to the server.
  ///
  /// See https://docs.ultravox.ai/datamessages for message types.
  Future<void> sendData(Map<String, Object> data) async {
    if (!data.containsKey("type")) {
      throw Exception("Data must contain a 'type' key");
    }
    final message = jsonEncode(data);
    final messageBytes = utf8.encode(message);
    if (messageBytes.length > 1024) {
      _wsChannel.sink.add(message);
    } else {
      await _room.localParticipant?.publishData(messageBytes, reliable: true);
    }
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
    final data = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
    dataMessageNotifier.value = data;
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
        final medium = data['medium'] == 'voice' ? Medium.voice : Medium.text;
        final role = data['role'] == 'agent' ? Role.agent : Role.user;
        final ordinal = data['ordinal'] as int;
        final isFinal = data['final'] as bool? ?? false;
        if (data['text'] != null) {
          transcriptsNotifier._addOrUpdateTranscript(
              ordinal, medium, role, isFinal,
              text: data['text'] as String);
        } else if (data['delta'] != null) {
          transcriptsNotifier._addOrUpdateTranscript(
              ordinal, medium, role, isFinal,
              delta: data['delta'] as String);
        }
        break;
      case 'client_tool_invocation':
        await _invokeClientTool(data['toolName'] as String,
            data['invocationId'] as String, data['parameters'] as Object);
      default:
        if (_experimentalMessages.isNotEmpty) {
          experimentalMessageNotifier.value = data;
        }
    }
  }

  Future<void> _invokeClientTool(
      String toolName, String invocationId, Object parameters) async {
    final tool = _registeredTools[toolName];
    if (tool == null) {
      await sendData({
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
      final Map<String, Object> data = {
        'type': 'client_tool_result',
        'invocationId': invocationId,
        'result': result.result,
      };
      if (result.responseType != null) {
        data['responseType'] = result.responseType!;
      }
      if (result.agentReaction != null) {
        data['agentReaction'] = result.agentReaction!.val;
      }
      if (result.updateCallState != null) {
        data['updateCallState'] = result.updateCallState!;
      }
      await sendData(data);
    } catch (e) {
      await sendData({
        'type': 'client_tool_result',
        'invocationId': invocationId,
        'errorType': 'implementation-error',
        'errorMessage': e.toString(),
      });
    }
  }
}
