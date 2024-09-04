import 'package:flutter_test/flutter_test.dart';

import 'package:ultravox_client/ultravox_client.dart';

void main() {
  test('update transcript', () {
    final state = UltravoxSessionState();
    final transcript1 = Transcript(
      text: 'Hello',
      isFinal: false,
      speaker: Role.user,
      medium: Medium.voice,
    );
    final transcript2 = Transcript(
      text: 'Hello world!',
      isFinal: true,
      speaker: Role.user,
      medium: Medium.voice,
    );
    state.addOrUpdateTranscript(transcript1);

    var fired = false;
    state.addListener(() {
      fired = true;
      expect(state.transcripts, [transcript2]);
    });
    state.addOrUpdateTranscript(transcript2);
    expect(fired, true);
  });

  test('add transcript', () {
    final state = UltravoxSessionState();
    final transcript1 = Transcript(
      text: 'Hello world!',
      isFinal: true,
      speaker: Role.user,
      medium: Medium.voice,
    );
    final transcript2 = Transcript(
      text: 'Something else',
      isFinal: false,
      speaker: Role.user,
      medium: Medium.voice,
    );
    state.addOrUpdateTranscript(transcript1);

    var fired = false;
    state.addListener(() {
      fired = true;
      expect(state.transcripts, [transcript1, transcript2]);
    });
    state.addOrUpdateTranscript(transcript2);
    expect(fired, true);
  });
}
