import 'package:flutter_test/flutter_test.dart';
import 'package:ultravox_client/ultravox_client.dart';

void main() {
  group('UltravoxSession mute tests', () {
    late UltravoxSession session;

    setUp(() {
      session = UltravoxSession.create();
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

      session.micMuted = true;  // Should not trigger listener
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

      session.speakerMuted = true;  // Should not trigger listener
      expect(speakerMuteCounter, 1);

      session.speakerMuted = false;
      expect(session.speakerMuted, false);
      expect(speakerMuteCounter, 2);
    });

    test('toggleMicMute', () {
      expect(session.micMuted, false);
      
      session.toggleMicMute();
      expect(session.micMuted, true);

      session.toggleMicMute();
      expect(session.micMuted, false);
    });

    test('toggleSpeakerMute', () {
      expect(session.speakerMuted, false);
      
      session.toggleSpeakerMute();
      expect(session.speakerMuted, true);

      session.toggleSpeakerMute();
      expect(session.speakerMuted, false);
    });
  });
}