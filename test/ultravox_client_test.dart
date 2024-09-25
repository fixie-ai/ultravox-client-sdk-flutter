import 'package:flutter_test/flutter_test.dart';

import 'package:ultravox_client/ultravox_client.dart';

void main() {
  test('muteMic', () {
    final session = UltravoxSession.create();
    int muteCounter = 0;
    session.micMutedNotifier.addListener(() {
      muteCounter++;
    });
    session.muteMic();
    expect(muteCounter, 1);
    session.muteMic();
    expect(muteCounter, 1);
    session.unmuteMic();
    expect(muteCounter, 2);
    session.muteMic();
    expect(muteCounter, 3);
    session.unmuteMic();
    expect(muteCounter, 4);
    session.unmuteMic();
    expect(muteCounter, 5);
  });
}
