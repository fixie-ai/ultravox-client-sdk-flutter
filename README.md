# Ultravox client SDK for Flutter
Flutter client SDK for [Ultravox](https://ultravox.ai).

<!-- TODO: Link to pub package once published.
[![pub package](https://img.shields.io/pub/v/ultravox_client?label=ultravox_client&color=orange)](https://pub.dev/packages/ultravox_client)
-->

## Getting started

```bash
flutter add ultravox_client
```

Or you can directly add to your `pubspec.yaml`:

```yaml
---
dependencies:
  ultravox_client: <version>
```

## Usage

```dart
final session = UltravoxSession.create();
final state = await session.joinCall(joinUrl);
state.addListener(myListener);
```

See the included example app for a more complete example. To get a `joinUrl`, you'll want to integrate your server with the [Ultravox REST API](https://fixie-ai.github.io/ultradox/).
