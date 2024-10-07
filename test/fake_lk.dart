import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

@GenerateNiceMocks([
  MockSpec<lk.LocalParticipant>(),
  MockSpec<lk.RemoteParticipant>(),
])
import 'fake_lk.mocks.dart';

class FakeRoomEvents extends Fake implements lk.EventsListener<lk.RoomEvent> {
  final _listeners = <FutureOr<void> Function(lk.RoomEvent)>[];

  @override
  lk.CancelListenFunc listen(FutureOr<void> Function(lk.RoomEvent) onEvent) {
    _listeners.add(onEvent);
    return () {};
  }

  @override // Copied from real implementation.
  lk.CancelListenFunc on<E>(
    FutureOr<void> Function(E) then, {
    bool Function(E)? filter,
  }) {
    return listen((event) async {
      // event must be E
      if (event is! E) return;
      // filter must be true (if filter is used)
      if (filter != null && !filter(event as E)) return;
      // cast to E
      await then(event as E);
    });
  }

  void emit(lk.RoomEvent event) {
    for (final listener in _listeners) {
      listener(event);
    }
  }
}

class FakeRoom extends Fake implements lk.Room {
  final _events = FakeRoomEvents();

  @override
  lk.EventsListener<lk.RoomEvent> createListener({bool synchronized = false}) {
    return _events;
  }

  @override
  Future<void> connect(
    String url,
    String token, {
    lk.ConnectOptions? connectOptions,
    @Deprecated('deprecated, please use roomOptions in Room constructor')
    lk.RoomOptions? roomOptions,
    lk.FastConnectOptions? fastConnectOptions,
  }) async {}

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView({"remote": remoteParticipant});
  final remoteParticipant = MockRemoteParticipant();

  @override
  final MockLocalParticipant localParticipant = MockLocalParticipant();

  void emit(lk.RoomEvent event) {
    _events.emit(event);
  }
}
