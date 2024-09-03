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
      _session = UltravoxSession.create();
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
            ElevatedButton(
              onPressed: () => _startCall(textController.text),
              child: const Text('Start Call'),
            ),
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
