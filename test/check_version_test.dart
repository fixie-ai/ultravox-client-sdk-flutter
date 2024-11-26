import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:ultravox_client/ultravox_client.dart';

void main() {
  test('pubspec version matches SDK constant', () async {
    final file = File("./pubspec.yaml");
    final fileContent = await file.readAsString();
    final pubspec = Pubspec.parse(fileContent);
    final expected = pubspec.version!.canonicalizedVersion;
    expect(ultravoxSdkVersion, expected);
  });
}
