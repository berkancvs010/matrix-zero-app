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

  test('platform game ships eight enemy types with their own visuals', () {
    final start = source.indexOf('enum _EnemyKind {');
    expect(start, isNot(-1));
    final end = source.indexOf('}', start);
    final values = source.substring(start, end);
    const kinds = [
      'nut',
      'spiky',
      'flyer',
      'hopper',
      'turret',
      'guard',
      'brute',
      'charger',
    ];
    for (final kind in kinds) {
      expect(values, contains(kind));
      expect(source, contains('_EnemyKind.$kind'));
      // Her tür drop tablosunda, davranış döngüsünde ve çizimde ele alınmalı.
      expect(source, contains('case _EnemyKind.$kind:'));
    }
    // Üç yerde ayrı ayrı ele alınmalı: drop, tick ve paint.
    expect('case _EnemyKind.brute:'.allMatches(source).length, greaterThanOrEqualTo(3));
    expect('case _EnemyKind.charger:'.allMatches(source).length, greaterThanOrEqualTo(3));
    expect(
      source,
      contains('void _paintEnemy(Canvas canvas, _Enemy e, double tile)'),
    );
    // Yeni düşmanların kendine özgü davranışları.
    expect(source, contains('void _tickCharger('));
    expect(source, contains('void _tickWalker('));
  });

  test('enemies and breakable props drop five kinds of loot and weapons', () {
    for (final kind in ['coin', 'heart', 'star', 'gem', 'weapon']) {
      expect(source, contains('_PickupKind.$kind'));
    }
    expect(source, contains('void _dropLoot('));
    expect(source, contains('void _smashProp('));
    expect(source, contains('void _paintPickup('));
    // Alet kutusu ve özel silah sistemi.
    expect(source, contains('enum _SpecialWeapon { quake, spread }'));
    expect(source, contains('_SpecialWeapon.quake'));
    expect(source, contains('_SpecialWeapon.spread'));
    expect(source, contains('void _weaponCrate('));
  });

  test('growth system levels up the hero and scales movement', () {
    expect(source, contains('void _gainXp(int amount)'));
    expect(source, contains('_xpNext = (_xpNext * 1.4).round();'));
    expect(source, contains('double get _growth => 1 + (_level - 1) * _growthPerLevel;'));
    // Büyüme hız ve zıplamaya uygulanmalı.
    expect(source, contains('info.runSpeed * (_powered ? 1.18 : 1.0) * _growth'));
    expect(source, contains('_vy = info.jumpSpeed * _growth;'));
    // HUD seviye/XP göstergesi.
    expect(source, contains('void _paintHudBars('));
  });

  test('chief hammer reaches three times as far as before', () {
    final reach = RegExp(r'const double _hammerReach = ([\d.]+)')
        .firstMatch(source);
    expect(reach, isNotNull);
    final value = double.parse(reach!.group(1)!);
    expect(value, closeTo(1.45 * 3, 0.001));
    // Şefin vuruşu bu menzili kullanmalı, eski kısa sabit artık yok.
    expect(source, contains('dx.abs() < _hammerReach'));
    expect(source, isNot(contains('dx.abs() < 1.45')));
    expect(source, contains('_hammerHit(quake: quake, power: quake ? 2 : 1);'));
  });

  test('hero figure mirrors so the tool faces the movement direction', () {
    final start = source.indexOf('void _drawHeroFigure(');
    final end = source.indexOf('// ---------------------------------------------------------------------------', start);
    final figure = source.substring(start, end);
    // Sola bakarken tüm figür yatayda aynalanmalı.
    expect(figure, contains('if (facing < 0) {'));
    expect(figure, contains('canvas.scale(-1, 1);'));
    // Gövde/kol ucu her zaman aynı (kanonik) yönde çizilir.
    expect(source, contains('canvas.scale(-1, 1);'));
  });

  test('each level uses its own visual theme', () {
    expect(source, contains('const List<_LevelTheme> _levelThemes = ['));
    expect(source, contains("'Çayır'"));
    expect(source, contains("'Çöl'"));
    expect(source, contains("'Gece'"));
    expect(source, contains('_theme = _levelThemes['));
  });

  test('removed single-enemy walker drawing is gone', () {
    expect(source, isNot(contains('_paintWalker(')));
    expect(source, isNot(contains('class _Walker')));
  });

  test('every requested sfx has a bundled wav asset', () {
    final names = RegExp(r"_arcadePlaySfx\('([a-z]+)'\)")
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();
    expect(names, isNotEmpty);
    for (final name in names) {
      expect(
        File('assets/sfx/$name.wav').existsSync(),
        isTrue,
        reason: 'missing sound asset for $name',
      );
    }
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/sfx/'));
  });

  test('android host plays arcade sfx without extra plugins', () {
    final host = File(
      'android/app/src/main/kotlin/com/zerolog/app/MainActivity.kt',
    ).readAsStringSync();
    expect(host, contains('"playArcadeSfx"'));
    expect(host, contains('SoundPool'));
  });

  test('momentum, coyote time and squash-stretch smooth out movement', () {
    expect(source, contains('_coyote'));
    expect(source, contains('info.accel'));
    expect(source, contains('_squash'));
    expect(source, contains('void _landDust()'));
    expect(source, contains('void _jumpDust()'));
    expect(source, contains('void _runDust('));
  });
}
