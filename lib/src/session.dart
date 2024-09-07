import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

/// The current status of an [UltravoxSession].
enum UltravoxSessionStatus {
  /// The voice session is not connected and not attempting to connect.
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
  /// The user can still interrupt.
  thinking(live: true),

  /// The client is connected and the server is playing response audio.
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

/// A state object for an [UltravoxSession].
/// [UltravoxSessionState] is a [ChangeNotifier] that manages the state of a
/// single session and notifies listeners when the state changes.
class UltravoxSessionState extends ChangeNotifier {
  final _transcripts = <Transcript>[];
  var _status = UltravoxSessionStatus.disconnected;
  Map<String, dynamic>? _lastExperimentalMessage;

  UltravoxSessionStatus get status => _status;
  List<Transcript> get transcripts => List.unmodifiable(_transcripts);
  Map<String, dynamic>? get lastExperimentalMessage => _lastExperimentalMessage;

  set status(UltravoxSessionStatus value) {
    _status = value;
    notifyListeners();
  }

  void addOrUpdateTranscript(Transcript transcript) {
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

  set lastExperimentalMessage(Map<String, dynamic>? value) {
    _lastExperimentalMessage = value;
    notifyListeners();
  }
}

/// Manages a single session with Ultravox.
class UltravoxSession {
  final _state = UltravoxSessionState();
  final Set<String> _experimentalMessages;
  final lk.Room _room;
  final lk.EventsListener<lk.RoomEvent> _listener;
  late WebSocketChannel _wsChannel;

  UltravoxSession(this._room, this._experimentalMessages)
      : _listener = _room.createListener();

  UltravoxSession.create({Set<String>? experimentalMessages})
      : this(lk.Room(), experimentalMessages ?? {});

  UltravoxSessionState get state => _state;

  /// Connects to call using the given [joinUrl].
  Future<UltravoxSessionState> joinCall(String joinUrl) async {
    if (_state.status != UltravoxSessionStatus.disconnected) {
      throw Exception('Cannot join a new call while already in a call');
    }
    _changeStatus(UltravoxSessionStatus.connecting);
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
    return _state;
  }

  /// Leaves the current call (if any).
  Future<void> leaveCall() async {
    _disconnect();
  }

  /// Sends a message via text. The agent will also respond via text.
  Future<void> sendText(String text) async {
    if (!_state.status.live) {
      throw Exception(
          'Cannot send text while not connected. Current status: ${_state.status}');
    }
    final message = jsonEncode({'type': 'input_text_message', 'text': text});
    _room.localParticipant?.publishData(utf8.encode(message), reliable: true);
  }

  void _changeStatus(UltravoxSessionStatus status) {
    _state.status = status;
  }

  Future<void> _disconnect() async {
    if (_state.status == UltravoxSessionStatus.disconnected) {
      return;
    }
    _changeStatus(UltravoxSessionStatus.disconnecting);
    await Future.wait([
      _room.disconnect(),
      _wsChannel.sink.close(),
    ]);
    _changeStatus(UltravoxSessionStatus.disconnected);
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
        _changeStatus(UltravoxSessionStatus.idle);
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
            _changeStatus(UltravoxSessionStatus.listening);
            break;
          case 'thinking':
            _changeStatus(UltravoxSessionStatus.thinking);
            break;
          case 'speaking':
            _changeStatus(UltravoxSessionStatus.speaking);
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
        _state.addOrUpdateTranscript(transcript);
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
          _state.addOrUpdateTranscript(transcript);
        } else if (data['delta'] != null) {
          final last = _state.transcripts.last;
          if (last.speaker == Role.agent) {
            final transcript = Transcript(
              text: last.text + (data['delta'] as String),
              isFinal: data['final'] as bool,
              speaker: Role.agent,
              medium: medium,
            );
            _state.addOrUpdateTranscript(transcript);
          }
        }
        break;
      default:
        if (_experimentalMessages.isNotEmpty) {
          _state.lastExperimentalMessage = data as Map<String, dynamic>;
        }
    }
  }
}
