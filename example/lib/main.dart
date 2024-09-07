import 'dart:async';

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
  bool debug = false;

  @override
  void dispose() {
    if (_session != null) {
      _session!.state.removeListener(_onStateChange);
      unawaited(_session!.leaveCall());
    }
    super.dispose();
  }

  void _onStateChange() {
    // Refresh the UI when the session state changes.
    setState(() {});
  }

  Future<void> _startCall(String joinUrl) async {
    if (_session != null) {
      return;
    }
    setState(() {
      _session =
          UltravoxSession.create(experimentalMessages: debug ? {"debug"} : {});
    });
    _session!.state.addListener(_onStateChange);
    await _session!.joinCall(joinUrl);
  }

  Future<void> _endCall() async {
    if (_session == null) {
      return;
    }
    _session!.state.removeListener(_onStateChange);
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
                  value: debug,
                  onChanged: (value) => setState(() => debug = value),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => _startCall(textController.text),
                  child: const Text('Start Call'),
                ),
              ],
            )
          ],
        ),
      ));
    } else if (!_session!.state.status.live) {
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
          child: ListView(
              reverse: true, // Fill from bottom, clip at top.
              children: [
                for (final transcript in _session!.state.transcripts.reversed)
                  TranscriptWidget(transcript: transcript),
              ]),
        ),
      );
      mainBodyChildren.add(
        ElevatedButton(
          onPressed: _endCall,
          child: const Text('End Call'),
        ),
      );
      if (debug) {
        mainBodyChildren.add(const SizedBox(height: 20));
        mainBodyChildren.add(const Text.rich(TextSpan(
            text: 'Last Debug Message:',
            style: TextStyle(fontWeight: FontWeight.w700))));

        if (_session!.state.lastExperimentalMessage != null) {
          mainBodyChildren.add(DebugMessageWidget(
              message: _session!.state.lastExperimentalMessage!));
        }
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
