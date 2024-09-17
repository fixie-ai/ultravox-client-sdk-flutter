# Ultravox client SDK for Flutter
Flutter client SDK for [Ultravox](https://ultravox.ai).

[![pub package](https://img.shields.io/pub/v/ultravox_client?label=ultravox_client&color=orange)](https://pub.dev/packages/ultravox_client)

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
await session.joinCall(joinUrl);
session.statusNotifier.addListener(myListener);
await session.leaveCall();
```

See the included example app for a more complete example. To get a `joinUrl`, you'll want to integrate your server with the [Ultravox REST API](https://fixie-ai.github.io/ultradox/).

## Supported platforms

The Ultravox client SDK works on all Flutter platforms: Android, iOS, web, Linux, Windows, and macOS.

## Example app

You can view a demo of the example app at https://fixie-ai.github.io/ultravox-client-sdk-flutter/

You can use the [Ultravox REST API](https://fixie-ai.github.io/ultradox/) to get a `joinUrl`.
