import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/retro_arcade.dart').readAsStringSync();

  test('retro catalog contains only the nine distinct games', () {
    const ids = [
      'space_shooter',
      'breakout',
      'pong',
      'snake',
      'tetris',
      '2048',
      'minesweeper',
      'memory',
      'flappy',
    ];

    for (final id in ids) {
      final pattern = RegExp(
        r'''RetroGame\(\s*['"]''' + RegExp.escape(id) + r'''['"]''',
        multiLine: true,
      );

      expect(
        pattern.hasMatch(source),
        isTrue,
        reason: 'Retro katalogunda $id bulunamadı',
      );
    }

    expect(
      RegExp(
        r'''RetroGame\(\s*['"]''',
        multiLine: true,
      ).allMatches(source).length,
      9,
    );
  });

  test('gamepad is wired to concrete actions', () {
    expect(source, contains('class _VirtualGamepad'));
    expect(source, contains('behavior: HitTestBehavior.opaque'));

    expect(
      RegExp(
        r'down\s*:\s*\(\)\s*=>\s*setState\(\s*_drop\s*\)',
      ).hasMatch(source),
      isTrue,
    );

    expect(RegExp(r'a\s*:\s*rotate').hasMatch(source), isTrue);

    expect(RegExp(r'b\s*:\s*_resetGame').hasMatch(source), isTrue);

    expect(
      RegExp(
        r'b\s*:\s*\(\)\s*=>\s*setState\(\s*_resetGame\s*\)',
      ).hasMatch(source),
      isFalse,
    );
  });

  test('2048 has terminal-state protection', () {
    expect(
      RegExp(r'bool\s+over\s*=\s*false\s*,\s*won\s*=\s*false').hasMatch(source),
      isTrue,
    );

    expect(source, contains('bool _movesAvailable()'));

    expect(
      RegExp(r'if\s*\(\s*over\s*\|\|\s*won\s*\)\s*return\s*;').hasMatch(source),
      isTrue,
    );
  });

  test('retro game timers are disposed', () {
    final disposeCount = RegExp(
      r'void\s+dispose\s*\(\s*\)\s*\{.*?cancel\s*\(\s*\).*?super\.dispose\s*\(\s*\)\s*;',
      multiLine: true,
      dotAll: true,
    ).allMatches(source).length;

    expect(disposeCount, greaterThanOrEqualTo(2));

    expect(
      RegExp(
        r'timer\?\.cancel\s*\(\s*\).*?super\.dispose\s*\(\s*\)\s*;',
        multiLine: true,
        dotAll: true,
      ).hasMatch(source),
      isTrue,
    );
  });
}
