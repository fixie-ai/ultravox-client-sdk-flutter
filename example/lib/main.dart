import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ultravox_client/ultravox_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultravox Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(
          255,
          255,
          95,
          109,
        )),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Ultravox Flutter Example Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  UltravoxSession? _session;
  bool _debug = false;
  final LinkedHashSet<int> _transcriptArrivalOrder = LinkedHashSet<int>();
  bool _connected = false;

  @override
  void dispose() {
    if (_session != null) {
      _session!.statusNotifier.removeListener(_onStatusChange);
      _session!.dataMessageNotifier.removeListener(_onDataMessage);
      unawaited(_session!.leaveCall());
    }
    super.dispose();
  }

  void _onStatusChange() {
    if (_session?.status.live != _connected) {
      // Refresh the UI when we connect and disconnect.
      setState(() {
        _connected = _session?.status.live ?? false;
      });
    }
  }

  void _onDataMessage() {
    final message = _session!.lastDataMessage;
    if (message["type"] == "transcript" && message.containsKey("ordinal")) {
      final ordinal = message["ordinal"] as int;
      if (!_transcriptArrivalOrder.contains(ordinal)) {
        setState(() {
          _transcriptArrivalOrder.add(ordinal);
        });
      }
    }
  }

  Future<void> _startCall(String joinUrl) async {
    if (_session != null) {
      return;
    }
    setState(() {
      _session =
          UltravoxSession.create(experimentalMessages: _debug ? {"debug"} : {});
    });
    _session!.statusNotifier.addListener(_onStatusChange);
    _session!.dataMessageNotifier.addListener(_onDataMessage);
    _session!.registerToolImplementation("getSecretMenu", _getSecretMenu);
    await _session!.joinCall(joinUrl, clientVersion: "UltravoxExampleApp");
  }

  ClientToolResult _getSecretMenu(Object params) {
    return ClientToolResult(json.encode({
      "date": DateTime.now().toIso8601String(),
      "specialItems": [
        {
          "name": "Banana smoothie",
          "price": 3.99,
        },
        {
          "name": "Butter pecan ice cream (one scoop)",
          "price": 1.99,
        }
      ],
    }));
  }

  Future<void> _endCall() async {
    _transcriptArrivalOrder.clear();
    if (_session == null) {
      return;
    }
    _session!.statusNotifier.removeListener(_onStatusChange);
    _session!.dataMessageNotifier.removeListener(_onDataMessage);
    await _session!.leaveCall();
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mainBodyChildren = <Widget>[];
    if (_session == null) {
      final textController = TextEditingController();
      final textInput = TextField(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Join URL',
        ),
        controller: textController,
      );
      mainBodyChildren.add(Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            textInput,
            const SizedBox(height: 20, width: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Text.rich(TextSpan(
                    text: 'Debug',
                    style: TextStyle(fontWeight: FontWeight.bold))),
                Switch(
                  value: _debug,
                  onChanged: (value) => setState(() => _debug = value),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  icon: const Icon(Icons.call),
                  onPressed: () => _startCall(textController.text),
                  label: const Text('Start Call'),
                ),
              ],
            )
          ],
        ),
      ));
    } else if (!_connected) {
      mainBodyChildren.add(const Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CircularProgressIndicator(),
          Text('Connecting...'),
        ],
      )));
    } else {
      mainBodyChildren.add(
        Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListenableBuilder(
                listenable: _session!.transcriptsNotifier,
                builder: (BuildContext context, Widget? child) {
                  return ListView(
                      reverse: true, // Fill from bottom, clip at top.
                      children: [
                        for (final transcript in _session!.transcripts.reversed)
                          TranscriptWidget(transcript: transcript),
                      ]);
                })),
      );
      final textController = TextEditingController();
      final textInput = TextField(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
        ),
        controller: textController,
      );
      mainBodyChildren.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Expanded(child: textInput),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            onPressed: () {
              _session!.sendText(textController.text);
              textController.clear();
            },
            label: const Text('Send'),
          ),
        ],
      ));
      mainBodyChildren.add(const SizedBox(height: 20));
      mainBodyChildren.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ListenableBuilder(
              listenable: _session!.micMutedNotifier,
              builder: (BuildContext context, Widget? child) {
                return ElevatedButton.icon(
                  icon: _session!.micMuted
                      ? const Icon(Icons.mic_off)
                      : const Icon(Icons.mic),
                  onPressed: () {
                    _session!.micMuted = !_session!.micMuted;
                  },
                  label: _session!.micMuted
                      ? const Text('Unmute')
                      : const Text('Mute'),
                );
              }),
          ListenableBuilder(
              listenable: _session!.speakerMutedNotifier,
              builder: (BuildContext context, Widget? child) {
                return ElevatedButton.icon(
                  icon: _session!.speakerMuted
                      ? const Icon(Icons.volume_off)
                      : const Icon(Icons.volume_up),
                  onPressed: () {
                    _session!.speakerMuted = !_session!.speakerMuted;
                  },
                  label: _session!.speakerMuted
                      ? const Text('Unmute Agent')
                      : const Text('Mute Agent'),
                );
              }),
          ElevatedButton.icon(
            icon: const Icon(Icons.call_end),
            onPressed: _endCall,
            label: const Text('End Call'),
          ),
        ],
      ));
      if (_debug) {
        mainBodyChildren.add(const SizedBox(height: 20));
        mainBodyChildren.add(const Text.rich(TextSpan(
            text: 'Last Debug Message:',
            style: TextStyle(fontWeight: FontWeight.w700))));

        mainBodyChildren.add(ListenableBuilder(
          listenable: _session!.experimentalMessageNotifier,
          builder: (BuildContext context, Widget? child) {
            final message = _session!.lastExperimentalMessage;
            if (message.containsKey("type") && message["type"] == "debug") {
              return DebugMessageWidget(message: message);
            } else {
              return const SizedBox(height: 20);
            }
          },
        ));

        mainBodyChildren.add(const SizedBox(height: 10));
        mainBodyChildren.add(const Text.rich(TextSpan(
            text: 'Transcript Arrival Order:',
            style: TextStyle(fontWeight: FontWeight.w700))));
        mainBodyChildren.add(Text(_transcriptArrivalOrder.join(", ")));
      }
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Row(
          children: [
            const Expanded(flex: 2, child: Column()),
            Expanded(
              flex: 6,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: mainBodyChildren,
              ),
            ),
            const Expanded(flex: 2, child: Column()),
          ],
        ),
      ),
    );
  }
}

class TranscriptWidget extends StatelessWidget {
  const TranscriptWidget({super.key, required this.transcript});

  final Transcript transcript;

  @override
  Widget build(BuildContext context) {
    return RichText(
        text:
            TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [
      TextSpan(
        text: transcript.speaker == Role.user ? 'You: ' : 'Agent: ',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: transcript.text),
    ]));
  }
}

class DebugMessageWidget extends StatelessWidget {
  const DebugMessageWidget({super.key, required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    List<InlineSpan> children = [];
    for (final entry in message.entries) {
      children.add(TextSpan(
        text: '${entry.key}: ',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ));
      children.add(TextSpan(text: '${entry.value}\n'));
    }
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall,
        children: children,
      ),
    );
  }
}
