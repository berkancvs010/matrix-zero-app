import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('lib/retro_arcade.dart').readAsStringSync();

  test('retro menu exposes ten distinct arcade and puzzle games', () {
    const ids = [
      'pixel_platform',
      'tank_arena',
      'space_defense',
      'snake',
      'brick_breaker',
      'racket_duel',
      'block_drop',
      'reversi',
      'mines',
      'merge',
    ];
    final start = source.indexOf('const _retroGames = <RetroGame>[');
    final end = source.indexOf('];', start);
    final catalog = source.substring(start, end + 2);

    expect(RegExp(r'RetroGame\(').allMatches(catalog).length, 10);
    for (final id in ids) {
      expect(catalog, contains("'$id'"));
      expect(source, contains("case '$id':"));
    }
    expect(catalog, contains("'Arcade'"));
    expect(catalog, contains("'Puzzle'"));
  });

  test('every catalog entry resolves to a playable game widget', () {
    for (final type in [
      '_PlatformerGame',
      '_TankGame',
      '_SpaceGame',
      '_SnakeGame',
      '_BreakoutGame',
      '_PongGame',
      '_BlockDropGame',
      '_ReversiGame',
      '_MinesGame',
      '_MergeGame',
    ]) {
      expect(source, contains(type));
    }
    expect(source, contains("default:\n        return const Center("));
  });

  test(
    'platform game has jump, collision, collectibles and a finish state',
    () {
      expect(source, contains('class _PlatformerState'));
      expect(source, contains('void _jump()'));
      expect(source, contains('bool _solid(int col, int row)'));
      expect(source, contains('_collectCoins();'));
      expect(source, contains('_x >= 46.2'));
    },
  );

  test(
    'tank battle includes player shots, enemy shots, cover and terminal states',
    () {
      expect(source, contains('class _TankState'));
      expect(source, contains('void _fire()'));
      expect(source, contains('bullet.enemy'));
      expect(source, contains(r"_walls.contains('$bx:$by')"));
      expect(source, contains('_enemies.isEmpty'));
    },
  );

  test('Reversi offers legal moves and plays a CPU turn', () {
    expect(source, contains('class _ReversiState'));
    expect(source, contains('List<int> _legal(int player)'));
    expect(source, contains('void _cpuTurn()'));
    expect(source, contains('_moveValue(b).compareTo(_moveValue(a))'));
  });

  test('long-running game timers are cancelled when games close', () {
    expect(source, contains('_timer?.cancel();'));
    expect(source, contains('super.dispose();'));
    expect(source, contains('Timer.periodic'));
  });
}
