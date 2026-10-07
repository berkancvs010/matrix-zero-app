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
    'platform game: two heroes, jump, collision, collectibles and a goal',
    () {
      expect(source, contains('class _PlatformerState'));
      expect(source, contains('void _jump()'));
      expect(source, contains('bool _solid(int col, int row)'));
      expect(source, contains('_collectCoins();'));
      expect(source, contains('_x >= _goalX'));
      // Girişte iki kahramanlı karakter seçimi.
      expect(source, contains('_PlatformerHero.chief'));
      expect(source, contains('_PlatformerHero.coder'));
      expect(source, contains('Şantiye Şefi'));
      expect(source, contains('Programcı'));
      // Üç bölüm ve bayrak hedefi.
      expect(source, contains('_platformLevel1()'));
      expect(source, contains('_platformLevel2()'));
      expect(source, contains('_platformLevel3()'));
      // Kameralı sahnede dünya sol kenardan başlamalı. Tüm bölüm genişliğine
      // göre ortalanırsa karolar ekranın soluna taşar ve yalnızca mavi
      // gökyüzü görünür (oyun "başlamıyor" gibi kalır).
      expect(source, contains('final viewCols = size.width / tile;'));
      expect(
        source,
        isNot(contains('final ox = (size.width - s._cols * tile) / 2;')),
      );
    },
  );

  test('çekiçli şantiye şefi programcıdan daha hızlı koşar', () {
    final chief = RegExp(r'const double _chiefRun = ([\d.]+)')
        .firstMatch(source);
    final coder = RegExp(r'const double _coderRun = ([\d.]+)')
        .firstMatch(source);
    expect(chief, isNotNull);
    expect(coder, isNotNull);
    expect(
      double.parse(chief!.group(1)!),
      greaterThan(double.parse(coder!.group(1)!)),
    );
  });

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
