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
    'platform game v3: two heroes, collision, collectibles, six levels and goal',
    () {
      expect(source, contains('class _PlatformerState'));
      expect(source, contains('void _jump()'));
      expect(source, contains('bool _solid(int row, int col)'));
      expect(source, contains('void _collect()'));
      expect(source, contains('_flag = _cols - 5;'));
      expect(
        source,
        contains('if (_x >= _flag - 1 && _bossHp <= 0)'),
      );

      // İki oynanabilir kahraman.
      expect(source, contains('_PlatformerHero.chief'));
      expect(source, contains('_PlatformerHero.coder'));
      expect(source, contains('Şantiye Şefi'));
      expect(source, contains('Programcı'));

      // V3: altı benzersiz bölüm / biyom.
      expect(source, contains('const _pixelLevels = <_PixelLevel>['));
      expect(RegExp(r"_PixelLevel\(\d+").allMatches(source).length, 6);
      expect(source, contains("bossName: 'Çekirdek Muhafızı'"));
      expect(source, contains("bossName: 'Lav Muhafızı'"));

      // Kamera dünya genişliğine göre değil, görünür alan üzerinden çalışıyor.
      expect(source, contains('final first = s._camera.floor() - 1;'));
      expect(source, contains('final ox = (size.width - 13 * t) / 2;'));
      expect(
        source,
        isNot(contains('final ox = (size.width - s._cols * tile) / 2;')),
      );
    },
  );

  test('çekiçli şantiye şefi programcıdan daha hızlı koşar', () {
    expect(
      source,
      contains(
        "_PlatformerHero.chief: _HeroInfo('Şantiye Şefi', 'Kasklı, dayanıklı ve çekiçli.'",
      ),
    );
    expect(source, contains(".19, -.40, 5, 3)"));

    expect(
      source,
      contains(
        "_PlatformerHero.coder: _HeroInfo('Programcı', 'Enerji çekirdekli çevik kahraman.'",
      ),
    );
    expect(source, contains(".15, -.45, 3, 5)"));

    const chiefRun = .19;
    const coderRun = .15;

    expect(chiefRun, greaterThan(coderRun));
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
