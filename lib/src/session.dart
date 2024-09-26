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

  /// A [ValueNotifier] that emits events when the user is muted or unmuted.
  final userMutedNotifier = ValueNotifier<bool>(false);

  /// A quick accessor for the user's current mute status.
  ///
  /// Listen to [userMutedNotifier] to receive updates.
  bool get userMuted => userMutedNotifier.value;

  /// A [ValueNotifier] that emits events when the agent is muted or unmuted.
  final agentMutedNotifier = ValueNotifier<bool>(false);

  /// A quick accessor for the agent's current mute status.
  ///
  /// Listen to [agentMutedNotifier] to receive updates.
  bool get agentMuted => agentMutedNotifier.value;

  final Set<String> _experimentalMessages;
  final lk.Room _room;
  final lk.EventsListener<lk.RoomEvent> _listener;
  late WebSocketChannel _wsChannel;

  UltravoxSession(this._room, this._experimentalMessages)
      : _listener = _room.createListener();

  UltravoxSession.create({Set<String>? experimentalMessages})
      : this(lk.Room(), experimentalMessages ?? {});

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
      await _handleSocketMessage(event);
    });
  }

  /// Mutes the user, the agent, or both.
  ///
  /// If a given [Role] is already muted, this method does nothing for that
  /// role.
  void mute(Set<Role> roles) {
    if (roles.contains(Role.user)) {
      if (!userMuted) {
        _room.localParticipant?.setMicrophoneEnabled(false);
      }
      userMutedNotifier.value = true;
    }
    if (roles.contains(Role.agent)) {
      if (!agentMuted) {
        for (final participant in _room.remoteParticipants.values) {
          for (final publication in participant.audioTrackPublications) {
            publication.track?.disable();
          }
        }
      }
      agentMutedNotifier.value = true;
    }
  }

  /// Unmutes the user, the agent, or both.
  ///
  /// If a given [Role] is not currently muted, this method does nothing for
  /// that role.
  void unmute(Set<Role> roles) {
    if (roles.contains(Role.user)) {
      if (userMuted) {
        _room.localParticipant?.setMicrophoneEnabled(true);
      }
      userMutedNotifier.value = false;
    }
    if (roles.contains(Role.agent)) {
      if (agentMuted) {
        for (final participant in _room.remoteParticipants.values) {
          for (final publication in participant.audioTrackPublications) {
            publication.track?.enable();
          }
        }
      }
      agentMutedNotifier.value = false;
    }
  }

  /// Leaves the current call (if any).
  Future<void> leaveCall() async {
    _disconnect();
  }

  /// Sends a message via text. The agent will also respond via text.
  Future<void> sendText(String text) async {
    if (!status.live) {
      throw Exception(
          'Cannot send text while not connected. Current status: $status');
    }
    final message = jsonEncode({'type': 'input_text_message', 'text': text});
    _room.localParticipant?.publishData(utf8.encode(message), reliable: true);
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

  Future<void> _handleSocketMessage(dynamic event) async {
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

  void _handleDataMessage(lk.DataReceivedEvent event) {
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
      default:
        if (_experimentalMessages.isNotEmpty) {
          experimentalMessageNotifier.value = data as Map<String, dynamic>;
        }
    }
  }
}
