import 'package:flutter_test/flutter_test.dart';

import 'package:ultravox_client/ultravox_client.dart';

void main() {
  test('mute', () {
    final session = UltravoxSession.create();
    int muteCounter = 0;
    session.userMutedNotifier.addListener(() {
      muteCounter++;
    });
    session.mute({Role.user});
    expect(muteCounter, 1);
    session.mute({Role.user});
    expect(muteCounter, 1);
    session.unmute({Role.user});
    expect(muteCounter, 2);
    session.mute({Role.user, Role.agent});
    expect(muteCounter, 3);
    session.unmute({});
    expect(muteCounter, 3);
    session.unmute({Role.agent});
    expect(muteCounter, 3);
  });
}
