import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/app_info.dart';

/// The version shown in the diagnostics report and About screen used to drift
/// from the real build (a report was filed as 1.4.1+6 while the app was 1.5.x,
/// which made device reports harder to trust). Keep them in lock-step.
void main() {
  test('AppInfo matches the pubspec version', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    final match = RegExp(r'^version:\s*(\S+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has no version: x.y.z+n');
    final name = match!.group(1)!;
    final code = match.group(2)!;
    expect(AppInfo.version, name,
        reason: 'AppInfo.version is stale — bump it with pubspec.yaml');
    expect(AppInfo.buildNumber, code,
        reason: 'AppInfo.buildNumber is stale — bump it with pubspec.yaml');
  });
}
