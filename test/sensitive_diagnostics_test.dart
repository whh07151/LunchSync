import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session diagnostics never embed location, capabilities, or exceptions', () {
    final createSource = File(
      'lib/features/session/session_create_screen.dart',
    ).readAsStringSync();
    final joinSource = File(
      'lib/features/session/join_session_screen.dart',
    ).readAsStringSync();

    for (final forbidden in <String>[
      'name=\$name',
      '\${hostPos.latitude},\${hostPos.longitude}',
      'id=\${session.id}',
      '\${invitation.inviteCode}',
      ': \$e',
      '스택: \$st',
    ]) {
      expect(createSource, isNot(contains(forbidden)), reason: forbidden);
    }

    for (final forbidden in <String>[': \$fromQuery', ': \$fromPath', ': \$e']) {
      expect(joinSource, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('Flutter diagnostics never print raw responses, secrets, ids, or exceptions', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final unsafeException = RegExp(r'\$(?:e|st)\b|\$\{(?:e|st)\}');
    final unsafeInterpolations = <String>[
      'response.body',
      r'$path',
      r'$accessToken',
      r'${accessToken',
      r'$inviteCode',
      r'${invitation.inviteCode}',
      r'$paymentKey',
      r'$orderId',
      r'$sessionId',
      r'${session.id}',
      '.latitude',
      '.longitude',
    ];

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      final calls = RegExp(
        r'debugPrint\([\s\S]*?\);',
      ).allMatches(source).map((match) => match.group(0)!);

      for (final call in calls) {
        expect(
          unsafeException.hasMatch(call),
          isFalse,
          reason: '${file.path}: $call',
        );
        for (final forbidden in unsafeInterpolations) {
          expect(call, isNot(contains(forbidden)), reason: '${file.path}: $call');
        }
      }
    }
  });
}
