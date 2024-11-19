## Publishing ultravox_client to pub.dev
The ultravox_client for Flutter is available on [pub.dev](https://pub.dev/packages/ultravox_client).

To publish a new version:
1. **Version Bump** → Increment the version number in `pubspec.yaml` and at the top of `lib/src/session.dart`.
1. **Change Log** → Add the new version number along with a brief summary of what's new to `CHANGELOG.md`.
1. **Error Check** → Run `dart pub publish --dry-run` and deal with any errors or unexpected includes.
1. **Merge to main** → Open a PR in GitHub and get the changes merged. (This also runs tests, so please only publish from main!)
1. **Publish** → Run `dart pub publish`.
1. **Tag/Release** → Create a new tag and release in GitHub please.
