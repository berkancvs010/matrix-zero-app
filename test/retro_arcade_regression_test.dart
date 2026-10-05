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
      expect(source, contains("    '$id',"));
    }

    final catalog = source.substring(
      source.indexOf('const _retroGames = <RetroGame>['),
      source.indexOf('];', source.indexOf('const _retroGames = <RetroGame>[')) + 2,
    );
    expect(RegExp(r'RetroGame\(').allMatches(catalog).length, 9);
  });

  test('gamepad-enabled games receive the page gamepad state', () {
    expect(
      source,
      contains("case 'breakout':\n        return _BreakoutGame(showPad: showPad);"),
    );
    expect(
      source,
      isNot(contains("case 'breakout': return const _BreakoutGame();")),
    );
  });

  test('gamepad is wired to concrete actions', () {
    expect(source, contains('class _VirtualGamepad'));
    expect(source, contains('behavior: HitTestBehavior.opaque'));
    expect(source, contains('a: rotate'));
    expect(source, contains('b: _resetGame'));
    expect(source, isNot(contains('b:()=>setState(_resetGame)')));
  });

  test('snake food placement cannot loop forever on a full board', () {
    expect(source, contains('final available = <math.Point<int>>'));
    expect(source, contains('if (available.isEmpty)'));
    expect(source, isNot(contains('do { food = math.Point')));
  });

  test('breakout has real brick state and collision handling', () {
    expect(
      source,
      contains('final List<bool> bricks = List<bool>.filled(30, true);'),
    );
    expect(source, contains('bricks[index] = false;'));
    expect(source, contains('bricks.every((brick) => !brick)'));
    expect(source, contains('_BreakPainter(x, y, paddle, bricks)'));
  });

  test('pong serve direction is captured before resetting the ball', () {
    expect(source, contains('final servedFromLeft = bx < 0;'));
    expect(source, contains('vx = servedFromLeft ? .012 : -.012;'));
    expect(source, isNot(contains('vx = bx < .1 ? .012 : -.012;')));
  });

  test('space shooter consumes one shot and one score per enemy hit', () {
    expect(source, contains('final hitEnemies = <Offset>{};'));
    expect(source, contains('final hitShots = <Offset>{};'));
    expect(source, contains('if (!hitShots.contains(s)) s'));
  });

  test('tetris has all seven tetrominoes and real game over', () {
    expect(source, contains('// I, O, T, J, L, S, Z.'));
    expect(source, contains('bool over = false;'));
    expect(source, contains('if (!can(x, y))'));
    expect(source, contains('over = true;'));
    expect(source, contains("score: over ? 'OYUN BİTTİ • \$score'"));
    expect(source, contains('if (over) {\n      return;\n    }'));
  });

  test('2048 has terminal-state protection', () {
    expect(source, contains('bool over = false, won = false;'));
    expect(source, contains('bool _movesAvailable()'));
    expect(source, contains('if (over || won) return;'));
  });

  test('minesweeper blocks input after win or loss', () {
    expect(source, contains('if (over || won || flags[i] || open[i]) {'));
    expect(source, contains('if (over || won || open[i]) {'));
  });

  test('retro game timers are disposed', () {
    expect(source, contains('tm?.cancel();'));
    expect(source, contains('timer?.cancel();'));
    expect(source, contains('super.dispose();'));
  });
}
