part of 'main.dart';

/// ZeroLog Retro uses original, offline implementations and original artwork.
/// It does not bundle ROMs, copyrighted game assets, ads, or network calls.
class RetroGame {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String category;
  final bool gamepad;

  const RetroGame(
    this.id,
    this.title,
    this.subtitle,
    this.icon,
    this.category, {
    this.gamepad = false,
  });
}

const _retroGames = <RetroGame>[
  RetroGame(
    'pixel_platform',
    'Piksel Macerası',
    'Kahramanını seç; zıpla, altın topla, bayrağa ulaş.',
    Icons.sports_martial_arts_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'tank_arena',
    'Tank Arenası',
    'Duvarları kullan, düşman tanklarını alt et.',
    Icons.shield_moon_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'space_defense',
    'Uzay Savunması',
    'Dalga dalga gelen filoyu durdur.',
    Icons.rocket_launch_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'snake',
    'Yılan',
    'Yemi topla; kendi kuyruğuna ve sınıra çarpma.',
    Icons.gesture_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'brick_breaker',
    'Tuğla Kırıcı',
    'Topu sektir, bütün tuğlaları temizle.',
    Icons.grid_view_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'racket_duel',
    'Raket Düellosu',
    'Raketten önce 7 sayı al.',
    Icons.sports_tennis_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'block_drop',
    'Blok Düşürme',
    'Parçaları döndür, satırları tamamla.',
    Icons.view_module_rounded,
    'Puzzle',
    gamepad: true,
  ),
  RetroGame(
    'reversi',
    'Reversi',
    'Taşları çevir; tahtanın çoğunu ele geçir.',
    Icons.circle_outlined,
    'Puzzle',
  ),
  RetroGame(
    'mines',
    'Mayın Tarlası',
    'Sayı ipuçlarını kullan, mayınları işaretle.',
    Icons.flag_rounded,
    'Puzzle',
  ),
  RetroGame(
    'merge',
    'Sayı Birleştirme',
    'Aynı sayıları birleştir, en yüksek değere ulaş.',
    Icons.apps_rounded,
    'Puzzle',
  ),
];

class RetroArcadePage extends StatefulWidget {
  const RetroArcadePage({super.key});

  @override
  State<RetroArcadePage> createState() => _RetroArcadePageState();
}

class _RetroArcadePageState extends State<RetroArcadePage> {
  String _filter = 'Tümü';
  static const _filters = ['Tümü', 'Arcade', 'Puzzle'];

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    final games = _retroGames
        .where((game) => _filter == 'Tümü' || game.category == _filter)
        .toList();

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        title: const Text('Retro Oyun Salonu'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(Icons.videogame_asset_rounded, color: theme.primary),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
              child: _RetroHero(theme: theme),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 42,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  return ChoiceChip(
                    label: Text(filter == 'Tümü' ? 'Tüm oyunlar' : filter),
                    selected: filter == _filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  );
                },
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            sliver: SliverGrid.builder(
              itemCount: games.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .91,
              ),
              itemBuilder: (context, index) {
                final game = games[index];
                return _RetroCard(
                  game: game,
                  index: _retroGames.indexOf(game) + 1,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RetroGamePage(game: game),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RetroHero extends StatelessWidget {
  final dynamic theme;
  const _RetroHero({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primary.withValues(alpha: .24),
            theme.surface,
            const Color(0xff101a2a),
          ],
        ),
        border: Border.all(color: theme.primary.withValues(alpha: .22)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -4,
            top: -4,
            child: Icon(
              Icons.sports_esports_rounded,
              size: 92,
              color: theme.primary.withValues(alpha: .13),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '10 ÖZGÜN OYUN',
                  style: TextStyle(
                    color: theme.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Retro Oyun Salonu',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Arcade ve puzzle klasikleri. İnternetsiz, reklamsız; her oyun için dokunmatik veya sanal gamepad kontrolü.',
                style: TextStyle(
                  color: theme.text.withValues(alpha: .62),
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  _heroTag(Icons.wifi_off_rounded, 'Offline'),
                  const SizedBox(width: 8),
                  _heroTag(Icons.verified_user_outlined, 'Özgün içerik'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroTag(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: theme.text.withValues(alpha: .72)),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            color: theme.text.withValues(alpha: .72),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _RetroCard extends StatelessWidget {
  final RetroGame game;
  final int index;
  final VoidCallback onTap;
  const _RetroCard({
    required this.game,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    final puzzle = game.category == 'Puzzle';
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: puzzle
                                ? const [Color(0xff163b46), Color(0xff142333)]
                                : const [Color(0xff412547), Color(0xff182337)],
                          ),
                        ),
                        child: CustomPaint(
                          painter: _PixelGridPainter(
                            game.colorIndex,
                            game == _retroGames.last,
                          ),
                          child: Center(
                            child: Icon(
                              game.icon,
                              size: 45,
                              color: puzzle
                                  ? const Color(0xff5ce1c1)
                                  : const Color(0xffffc857),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .38),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    if (game.gamepad)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: Icon(
                          Icons.gamepad_rounded,
                          color: Colors.white70,
                          size: 15,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                game.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.text.withValues(alpha: .55),
                  height: 1.25,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on RetroGame {
  int get colorIndex => _retroGames.indexOf(this);
}

class _PixelGridPainter extends CustomPainter {
  final int seed;
  final bool numbers;
  const _PixelGridPainter(this.seed, this.numbers);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .045);
    const step = 18.0;
    for (var x = 0; x < size.width; x += step.toInt()) {
      for (var y = 0; y < size.height; y += step.toInt()) {
        if ((x ~/ 18 + y ~/ 18 + seed) % 4 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(x.toDouble() + 4, y.toDouble() + 4, 3, 3),
            paint,
          );
        }
      }
    }
    if (numbers) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '2   4\n  8   16',
          style: TextStyle(
            color: Color(0x33ffffff),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(
          size.width - textPainter.width - 8,
          size.height - textPainter.height - 8,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter oldDelegate) =>
      seed != oldDelegate.seed || numbers != oldDelegate.numbers;
}

class RetroGamePage extends StatefulWidget {
  final RetroGame game;
  const RetroGamePage({super.key, required this.game});

  @override
  State<RetroGamePage> createState() => _RetroGamePageState();
}

class _RetroGamePageState extends State<RetroGamePage> {
  int _nonce = 0;
  bool _showPad = true;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    return Scaffold(
      backgroundColor: const Color(0xff090e18),
      appBar: AppBar(
        backgroundColor: const Color(0xff090e18),
        foregroundColor: theme.text,
        title: Text(widget.game.title),
        actions: [
          if (widget.game.gamepad)
            IconButton(
              tooltip: _showPad ? 'Gamepadı gizle' : 'Gamepadı göster',
              onPressed: () => setState(() => _showPad = !_showPad),
              icon: Icon(
                _showPad ? Icons.gamepad_rounded : Icons.gamepad_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Oyunu sıfırla',
            onPressed: () => setState(() => _nonce++),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: KeyedSubtree(
          key: ValueKey(_nonce),
          child: _game(widget.game.id),
        ),
      ),
    );
  }

  Widget _game(String id) {
    switch (id) {
      case 'pixel_platform':
        return _PlatformerGame(showPad: _showPad);
      case 'tank_arena':
        return _TankGame(showPad: _showPad);
      case 'space_defense':
        return _SpaceGame(showPad: _showPad);
      case 'snake':
        return _SnakeGame(showPad: _showPad);
      case 'brick_breaker':
        return _BreakoutGame(showPad: _showPad);
      case 'racket_duel':
        return _PongGame(showPad: _showPad);
      case 'block_drop':
        return _BlockDropGame(showPad: _showPad);
      case 'reversi':
        return const _ReversiGame();
      case 'mines':
        return const _MinesGame();
      case 'merge':
        return const _MergeGame();
      default:
        return const Center(
          child: Text('Oyun bulunamadı', style: TextStyle(color: Colors.white)),
        );
    }
  }
}

class _ArcadeFrame extends StatelessWidget {
  final Widget child;
  final String score;
  final Widget? controls;
  const _ArcadeFrame({required this.child, required this.score, this.controls});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: Color(0xff57e389)),
                const SizedBox(width: 7),
                const Text(
                  'OYUNDA',
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  score,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xff070b13),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: Colors.white.withValues(alpha: .09)),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 24),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  if (controls != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: controls!,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _VirtualGamepad extends StatelessWidget {
  final VoidCallback? up, down, left, right, a, b;
  const _VirtualGamepad({
    this.up,
    this.down,
    this.left,
    this.right,
    this.a,
    this.b,
  });

  Widget _button(IconData icon, VoidCallback? action, String label) =>
      Semantics(
        button: true,
        enabled: action != null,
        label: label,
        child: SizedBox(
          width: 48,
          height: 48,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: action,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: action == null ? .035 : .12,
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: action == null ? Colors.white10 : Colors.white24,
                ),
              ),
              child: Icon(
                icon,
                color: action == null ? Colors.white24 : Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(Icons.keyboard_arrow_up_rounded, up, 'Yukarı'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(Icons.keyboard_arrow_left_rounded, left, 'Sol'),
              const SizedBox(width: 4),
              _button(Icons.keyboard_arrow_down_rounded, down, 'Aşağı'),
              const SizedBox(width: 4),
              _button(Icons.keyboard_arrow_right_rounded, right, 'Sağ'),
            ],
          ),
        ],
      ),
      const Spacer(),
      if (b != null) ...[
        _button(Icons.close_rounded, b, 'Yeniden başlat'),
        const SizedBox(width: 8),
      ],
      if (a != null) _button(Icons.circle_rounded, a, 'Aksiyon'),
    ],
  );
}

// ---------------------------------------------------------------------------
// Piksel Macerası v3: 6 benzersiz bölüm, 6 biyom, 7 düşman sınıfı + boss,
// rastgele ganimet, envanter, kalkan, dash, doğal hareket, coyote time,
// jump buffer, değişken zıplama, gizli/alternatif yollar ve güçlü feedback.
// ---------------------------------------------------------------------------
enum _PlatformerHero { chief, coder }
enum _PixelWorld { valley, cave, factory, cloud, ruins, volcano }
enum _EnemyKind { walker, spike, shooter, flyer, charger, brute, bomber, boss }
enum _LootKind { coin, heart, bomb, ammo, weapon, shield, speed, jump, gem }
enum _Phase { select, ready, playing, dying, clear, gameover, win }

class _HeroInfo {
  final String name, tagline, ability;
  final double runSpeed, jumpSpeed, runStat, jumpStat;
  const _HeroInfo(this.name, this.tagline, this.ability, this.runSpeed,
      this.jumpSpeed, this.runStat, this.jumpStat);
}

const _heroInfo = <_PlatformerHero, _HeroInfo>{
  _PlatformerHero.chief: _HeroInfo('Şantiye Şefi', 'Kasklı, dayanıklı ve çekiçli.',
      'Çekiç yakın düşmanları ezer; tuğlaları kırar.', .19, -.40, 5, 3),
  _PlatformerHero.coder: _HeroInfo('Programcı', 'Enerji çekirdekli çevik kahraman.',
      'Enerji atışı uzaktan vurur; daha yüksek zıplar.', .15, -.45, 3, 5),
};

class _PixelPlatform {
  final int row, x, length;
  const _PixelPlatform(this.row, this.x, this.length);
}

class _PixelEnemy {
  double x, y, vx;
  final _EnemyKind kind;
  int hp, cooldown = 0;
  bool dead = false;
  _PixelEnemy(this.x, this.y, this.kind, {this.vx = -.035, this.hp = 1});
}

class _PixelShot {
  double x, y, vx, vy;
  int life;
  final bool bomb;
  final int damage;
  _PixelShot(this.x, this.y, this.vx, this.vy, {this.life = 70, this.bomb = false, this.damage = 1});
}

class _PixelLoot {
  double x, y, vy = 0;
  final _LootKind kind;
  bool taken = false;
  _PixelLoot(this.x, this.y, this.kind);
}

class _PixelParticle {
  double x, y, vx, vy, size;
  int life;
  final Color color;
  _PixelParticle(this.x, this.y, this.vx, this.vy, this.size, this.life, this.color);
}

class _PixelText {
  double x, y;
  final String text;
  final Color color;
  int life = 30;
  _PixelText(this.x, this.y, this.text, this.color);
}

class _EnemySpawn {
  final int x;
  final _EnemyKind kind;
  const _EnemySpawn(this.x, this.kind);
}

class _PixelLevel {
  final int no, length;
  final _PixelWorld world;
  final String name, objective;
  final List<int> gaps, blocks, secrets, spikes;
  final List<_PixelPlatform> platforms;
  final List<_EnemySpawn> enemies;
  final bool boss;
  final String bossName;
  const _PixelLevel(this.no, this.length, this.world, this.name, this.objective,
      this.gaps, this.blocks, this.secrets, this.spikes, this.platforms,
      this.enemies, {this.boss = false, this.bossName = ''});
}

const _pixelLevels = <_PixelLevel>[
  _PixelLevel(1, 138, _PixelWorld.valley, 'Yeşil Vadi',
      'Alternatif patikaları keşfet.',
      [22, 23, 50, 51, 79, 80, 109, 110],
      [11, 12, 13, 31, 32, 58, 59, 88, 89, 117, 118],
      [17, 43, 72, 99, 125],
      [27, 28, 61, 62, 94, 95, 121],
      [_PixelPlatform(9, 14, 5), _PixelPlatform(7, 42, 5), _PixelPlatform(10, 70, 6), _PixelPlatform(8, 101, 5), _PixelPlatform(6, 118, 6)],
      [_EnemySpawn(18, _EnemyKind.walker), _EnemySpawn(36, _EnemyKind.spike), _EnemySpawn(57, _EnemyKind.walker), _EnemySpawn(74, _EnemyKind.charger), _EnemySpawn(101, _EnemyKind.walker), _EnemySpawn(124, _EnemyKind.spike)]),
  _PixelLevel(2, 154, _PixelWorld.cave, 'Kristal Mağarası',
      'Kristal tünellerde yükseği hedefle.',
      [25, 26, 55, 56, 85, 86, 118, 119, 142],
      [9, 10, 11, 35, 36, 64, 65, 91, 92, 121, 122, 135, 136],
      [18, 48, 77, 103, 131],
      [30, 31, 69, 70, 97, 98, 127],
      [_PixelPlatform(9, 14, 5), _PixelPlatform(7, 45, 6), _PixelPlatform(10, 73, 5), _PixelPlatform(7, 101, 6), _PixelPlatform(5, 126, 6)],
      [_EnemySpawn(19, _EnemyKind.flyer), _EnemySpawn(39, _EnemyKind.shooter), _EnemySpawn(60, _EnemyKind.flyer), _EnemySpawn(82, _EnemyKind.spike), _EnemySpawn(104, _EnemyKind.shooter), _EnemySpawn(129, _EnemyKind.flyer)]),
  _PixelLevel(3, 168, _PixelWorld.factory, 'Neon Fabrika',
      'Enerji hatlarını aş, çekirdeğe ulaş.',
      [27, 28, 57, 58, 88, 89, 121, 122, 150, 151],
      [8, 9, 10, 37, 38, 66, 67, 96, 97, 128, 129, 157, 158],
      [18, 47, 78, 106, 137],
      [31, 32, 70, 71, 103, 104, 143, 144],
      [_PixelPlatform(10, 13, 6), _PixelPlatform(7, 40, 5), _PixelPlatform(9, 68, 6), _PixelPlatform(6, 99, 7), _PixelPlatform(8, 128, 6)],
      [_EnemySpawn(17, _EnemyKind.shooter), _EnemySpawn(42, _EnemyKind.bomber), _EnemySpawn(61, _EnemyKind.charger), _EnemySpawn(81, _EnemyKind.shooter), _EnemySpawn(109, _EnemyKind.bomber), _EnemySpawn(133, _EnemyKind.charger)],
      boss: true, bossName: 'Çekirdek Muhafızı'),
  _PixelLevel(4, 176, _PixelWorld.cloud, 'Bulut Şehri',
      'Rüzgâr koridorlarında gökyüzüne tırman.',
      [18, 19, 38, 39, 59, 60, 83, 84, 107, 108, 135, 136, 158],
      [14, 15, 16, 32, 33, 53, 54, 76, 77, 100, 101, 125, 126, 145, 146, 166],
      [24, 45, 68, 91, 116, 149],
      [29, 30, 71, 72, 112, 113, 153],
      [_PixelPlatform(10, 10, 5), _PixelPlatform(8, 28, 6), _PixelPlatform(6, 49, 6), _PixelPlatform(9, 67, 5), _PixelPlatform(5, 89, 7), _PixelPlatform(8, 114, 6), _PixelPlatform(6, 140, 6), _PixelPlatform(9, 160, 5)],
      [_EnemySpawn(17, _EnemyKind.flyer), _EnemySpawn(41, _EnemyKind.flyer), _EnemySpawn(63, _EnemyKind.charger), _EnemySpawn(83, _EnemyKind.shooter), _EnemySpawn(105, _EnemyKind.flyer), _EnemySpawn(130, _EnemyKind.charger), _EnemySpawn(150, _EnemyKind.shooter), _EnemySpawn(166, _EnemyKind.flyer)]),
  _PixelLevel(5, 188, _PixelWorld.ruins, 'Antik Harabeler',
      'Yıkıntıların altındaki gizli yolu bul.',
      [31, 32, 62, 63, 95, 96, 128, 129, 163, 164],
      [12, 13, 14, 41, 42, 71, 72, 103, 104, 136, 137, 171, 172],
      [22, 52, 84, 116, 147, 178],
      [35, 36, 77, 78, 111, 112, 156],
      [_PixelPlatform(10, 17, 5), _PixelPlatform(8, 47, 6), _PixelPlatform(6, 81, 7), _PixelPlatform(9, 108, 5), _PixelPlatform(7, 140, 6), _PixelPlatform(5, 169, 7)],
      [_EnemySpawn(20, _EnemyKind.walker), _EnemySpawn(45, _EnemyKind.brute), _EnemySpawn(69, _EnemyKind.shooter), _EnemySpawn(89, _EnemyKind.charger), _EnemySpawn(116, _EnemyKind.brute), _EnemySpawn(139, _EnemyKind.walker), _EnemySpawn(161, _EnemyKind.bomber), _EnemySpawn(178, _EnemyKind.brute)]),
  _PixelLevel(6, 205, _PixelWorld.volcano, 'Volkan Kalesi',
      'Lav gölünü geç ve kalenin çekirdeğini yok et.',
      [26, 27, 56, 57, 87, 88, 120, 121, 151, 152, 181, 182],
      [10, 11, 12, 43, 44, 73, 74, 102, 103, 133, 134, 164, 165, 193, 194],
      [20, 49, 80, 111, 143, 174],
      [30, 31, 64, 65, 95, 96, 128, 129, 158, 159, 187],
      [_PixelPlatform(9, 14, 5), _PixelPlatform(7, 40, 6), _PixelPlatform(10, 67, 5), _PixelPlatform(8, 95, 7), _PixelPlatform(6, 122, 6), _PixelPlatform(9, 150, 6), _PixelPlatform(7, 178, 7)],
      [_EnemySpawn(18, _EnemyKind.charger), _EnemySpawn(37, _EnemyKind.bomber), _EnemySpawn(67, _EnemyKind.brute), _EnemySpawn(91, _EnemyKind.shooter), _EnemySpawn(118, _EnemyKind.bomber), _EnemySpawn(140, _EnemyKind.brute), _EnemySpawn(165, _EnemyKind.charger), _EnemySpawn(184, _EnemyKind.bomber)],
      boss: true, bossName: 'Lav Muhafızı'),
];

class _PlatformerGame extends StatefulWidget {
  final bool showPad;
  const _PlatformerGame({required this.showPad});
  @override
  State<_PlatformerGame> createState() => _PlatformerState();
}

class _PlatformerState extends State<_PlatformerGame> {
  static const _rows = 14, _pw = .72, _ph = .88, _gravity = .018, _maxFall = .34;
  final _levels = _pixelLevels;
  final _enemies = <_PixelEnemy>[];
  final _shots = <_PixelShot>[];
  final _loot = <_PixelLoot>[];
  final _texts = <_PixelText>[];
  final _particles = <_PixelParticle>[];
  final _rng = math.Random();
  Timer? _timer;
  _Phase _phase = _Phase.select;
  _PlatformerHero? _hero;
  int _level = 0, _score = 0, _coins = 0, _lives = 3, _hp = 3;
  int _ammo = 8, _bombs = 2, _weapon = 1, _time = 210;
  int _clock = 0, _phaseTicks = 0, _timeTicks = 0, _invuln = 0;
  int _jumpBuffer = 0, _coyote = 0, _attackCd = 0, _dashCd = 0, _dashTicks = 0;
  int _shield = 0, _speed = 0, _jumpBoost = 0, _bossHp = 0, _shake = 0;
  bool _left = false, _right = false, _jumpHeld = false;
  double _x = 1.2, _y = 11, _vx = 0, _vy = 0, _camera = 0;
  int _facing = 1, _flag = 0, _cols = 0;
  List<String> _grid = const [];

  _HeroInfo? get _info => _hero == null ? null : _heroInfo[_hero];
  bool get _grounded => _hitY(_x, _y + .025, _pw, _ph) != null;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _choose(_PlatformerHero h) {
    setState(() {
      _hero = h;
      _score = 0;
      _coins = 0;
      _lives = 3;
      _hp = 3;
      _ammo = 8;
      _bombs = 2;
      _weapon = 1;
      _shield = 0;
      _speed = 0;
      _jumpBoost = 0;
      _load(0);
    });
  }

  void _load(int n) {
    final d = _levels[n];
    _level = n;
    _cols = d.length;
    _grid = List.generate(_rows, (_) => List.filled(_cols, '.').join());
    for (var x = 0; x < _cols; x++) {
      if (!d.gaps.contains(x)) {
        _set(12, x, '#');
        _set(13, x, '#');
      }
    }
    for (final p in d.platforms) {
      for (var x = 0; x < p.length; x++) {
        _set(p.row, p.x + x, '=');
      }
    }
    for (final x in d.blocks) {
      _set(8, x, x % 5 == 0 ? '?' : 'B');
      if (x + 1 < _cols && x % 3 == 0) _set(8, x + 1, 'B');
    }
    for (var x = 7; x < _cols - 7; x += 19) {
      _set(10, x, 'o');
      if (x + 1 < _cols) _set(9, x + 1, 'o');
      if (x + 2 < _cols && x % 2 == 0) _set(8, x + 2, 'o');
    }
    for (final x in d.secrets) {
      _set(7, x, 'H');
      if (x + 1 < _cols) _set(7, x + 1, 'H');
    }
    for (final x in d.spikes) {
      _set(11, x, '^');
    }
    for (var x = 16; x < _cols - 12; x += 31) {
      _set(6, x, 'H');
      _set(6, x + 1, 'H');
      _set(6, x + 2, 'H');
    }
    _flag = _cols - 5;
    _set(6, _flag, 'F');

    _enemies.clear();
    for (final e in d.enemies) {
      final hp = switch (e.kind) {
        _EnemyKind.brute => 3,
        _EnemyKind.shooter => 2,
        _EnemyKind.bomber => 2,
        _ => 1,
      };
      final y = e.kind == _EnemyKind.flyer ? 5.6 : 11.05;
      _enemies.add(_PixelEnemy(e.x.toDouble(), y, e.kind, hp: hp));
    }
    _bossHp = d.boss ? 12 : 0;
    if (d.boss) {
      _enemies.add(_PixelEnemy((_cols - 14).toDouble(), 10.55, _EnemyKind.boss,
          hp: 12, vx: -.018));
    }

    _loot.clear();
    for (final x in [14, 44, 71, 101, 132, _cols - 20]) {
      if (x > 3 && x < _cols - 2) _loot.add(_PixelLoot(x.toDouble(), 10.45, _LootKind.coin));
    }
    _loot.add(_PixelLoot((_cols * .40).floorToDouble(), 6.35, _LootKind.ammo));
    _loot.add(_PixelLoot((_cols * .55).floorToDouble(), 6.35, _LootKind.bomb));
    _loot.add(_PixelLoot((_cols * .68).floorToDouble(), 6.35, _LootKind.shield));
    _loot.add(_PixelLoot((_cols * .82).floorToDouble(), 6.35, _LootKind.jump));

    _shots.clear();
    _texts.clear();
    _particles.clear();
    _x = 1.2;
    _y = 11;
    _vx = 0;
    _vy = 0;
    _camera = 0;
    _facing = 1;
    _time = 210;
    _timeTicks = 0;
    _invuln = 75;
    _jumpBuffer = 0;
    _coyote = 0;
    _attackCd = 0;
    _dashCd = 0;
    _dashTicks = 0;
    _shake = 0;
    _phase = _Phase.ready;
    _phaseTicks = 75;
  }

  void _set(int row, int col, String ch) {
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) return;
    final r = _grid[row];
    _grid[row] = r.substring(0, col) + ch + r.substring(col + 1);
  }

  String _tile(int row, int col) => row < 0 || row >= _rows || col < 0 || col >= _cols ? '.' : _grid[row][col];

  bool _solid(int row, int col) {
    if (col < 0 || col >= _cols) return true;
    final c = _tile(row, col);
    return c == '#' || c == 'B' || c == '?' || c == 'U' || c == '=' || c == 'H';
  }

  int? _hitY(double x, double y, double w, double h) {
    final l = x.floor();
    final r = (x + w - .002).floor();
    final t = y.floor();
    final b = (y + h - .002).floor();
    for (var row = t; row <= b; row++) {
      for (var col = l; col <= r; col++) {
        if (_solid(row, col)) return row;
      }
    }
    return null;
  }

  int? _hitX(double x, double y, double w, double h) {
    final l = x.floor();
    final r = (x + w - .002).floor();
    final t = y.floor();
    final b = (y + h - .002).floor();
    for (var col = l; col <= r; col++) {
      for (var row = t; row <= b; row++) {
        if (_solid(row, col)) return col;
      }
    }
    return null;
  }

  double get _maxX => math.max(0, _cols - _pw);

  void _moveX(double dx) {
    if (dx == 0) return;
    final nx = _x + dx;
    final hit = _hitX(nx, _y, _pw, _ph);
    if (hit == null) {
      _x = nx.clamp(0, _maxX).toDouble();
    } else {
      _x = (dx > 0 ? hit - _pw - .002 : hit + 1.002).clamp(0, _maxX).toDouble();
      _vx = 0;
    }
  }

  void _moveY(double dy) {
    final ny = _y + dy;
    final hit = _hitY(_x, ny, _pw, _ph);
    if (hit == null) {
      _y = ny;
      return;
    }
    if (dy > 0) {
      _y = hit - _ph - .002;
      _vy = 0;
    } else {
      _y = hit + 1.002;
      _vy = 0;
      _bump(hit);
    }
  }

  void _bump(int row) {
    final c = (_x + _pw / 2).floor();
    for (final col in [c, c - 1, c + 1]) {
      final ch = _tile(row, col);
      if (ch == '?' || ch == 'H') {
        _set(row, col, 'U');
        _coins++;
        _score += 25;
        _burst(col + .5, row - .2, const Color(0xffffd166), 8);
        if (_rng.nextInt(100) < 35) _loot.add(_PixelLoot(col.toDouble(), row - 1.15, _randomLoot()));
        return;
      }
      if (ch == 'B' && _hero == _PlatformerHero.chief) {
        _set(row, col, '.');
        _score += 15;
        _burst(col + .5, row + .3, const Color(0xffe8a07b), 10);
        return;
      }
    }
  }

  void _jump() {
    if (_phase == _Phase.playing) _jumpBuffer = 8;
  }

  void _attack() {
    if (_phase != _Phase.playing || _attackCd > 0) return;
    if (_hero == _PlatformerHero.chief) {
      _attackCd = 13;
      final reach = 1.45 + _weapon * .08;
      for (final e in _enemies) {
        final ahead = (e.x - _x) * _facing > -.42;
        if (!e.dead && ahead && (e.x - _x).abs() < reach && (e.y - _y).abs() < 1.25) {
          _damage(e, 1 + (_weapon ~/ 2));
        }
      }
      _burst(_x + _facing * .85, _y + .35, const Color(0xffffdc6e), 5);
    } else if (_ammo > 0) {
      _ammo--;
      _attackCd = 10;
      final damage = 1 + (_weapon ~/ 2);
      final speed = .30 + _weapon * .015;
      for (var i = 0; i < (_weapon >= 4 ? 2 : 1); i++) {
        _shots.add(_PixelShot(_x + (_facing > 0 ? .66 : -.2), _y + .3 + i * .08,
            _facing * speed, 0, life: 65, damage: damage));
      }
    }
  }

  void _bomb() {
    if (_phase != _Phase.playing || _bombs <= 0) return;
    _bombs--;
    _shots.add(_PixelShot(_x + (_facing > 0 ? .65 : -.2), _y + .1,
        _facing * .17, -.21, life: 75, bomb: true, damage: 2 + _weapon ~/ 2));
    _burst(_x + _facing * .5, _y + .3, const Color(0xffff7b00), 4);
  }

  void _dash() {
    if (_phase != _Phase.playing || _dashCd > 0) return;
    _dashCd = 52;
    _dashTicks = 8;
    _invuln = math.max(_invuln, 15);
    _burst(_x + .35, _y + .45, const Color(0xff67e8f9), 7);
  }

  void _damage(_PixelEnemy e, int amount) {
    if (e.dead) return;
    e.hp -= amount;
    _score += 20;
    _shake = math.max(_shake, 3);
    _burst(e.x + .35, e.y + .35, _enemyColor(e.kind), 8);
    _texts.add(_PixelText(e.x, e.y - .2, '-$amount', const Color(0xffffe28a)));
    if (e.hp <= 0) {
      e.dead = true;
      _score += e.kind == _EnemyKind.boss ? 900 : 60;
      if (e.kind == _EnemyKind.boss) _bossHp = 0;
      _dropLoot(e.x, e.y);
      _burst(e.x + .35, e.y + .35, _enemyColor(e.kind), e.kind == _EnemyKind.boss ? 28 : 12);
    }
  }

  void _dropLoot(double x, double y) {
    final count = _rng.nextInt(100) < 22 ? 2 : 1;
    for (var i = 0; i < count; i++) {
      _loot.add(_PixelLoot(x + (i * .28), y - .15, _randomLoot()));
    }
  }

  _LootKind _randomLoot() {
    final roll = _rng.nextInt(100);
    if (roll < 12) return _LootKind.weapon;
    if (roll < 25) return _LootKind.ammo;
    if (roll < 36) return _LootKind.bomb;
    if (roll < 46) return _LootKind.heart;
    if (roll < 56) return _LootKind.shield;
    if (roll < 66) return _LootKind.speed;
    if (roll < 76) return _LootKind.jump;
    if (roll < 96) return _LootKind.coin;
    return _LootKind.gem;
  }

  void _hurt() {
    if (_invuln > 0 || _phase != _Phase.playing) return;
    if (_shield > 0) {
      _shield = 0;
      _invuln = 35;
      _shake = 6;
      _texts.add(_PixelText(_x, _y - .2, 'KALKAN!', const Color(0xff60a5fa)));
      _burst(_x + .35, _y + .4, const Color(0xff60a5fa), 18);
      return;
    }
    _hp--;
    _invuln = 70;
    _shake = 8;
    _burst(_x + .35, _y + .4, const Color(0xffff5d73), 14);
    if (_hp <= 0) {
      _lives--;
      if (_lives <= 0) {
        _phase = _Phase.gameover;
      } else {
        _phase = _Phase.dying;
        _phaseTicks = 55;
        _vy = -.30;
      }
    }
  }

  void _collect() {
    for (final l in _loot) {
      if (l.taken) continue;
      if ((l.x - _x).abs() < .78 && (l.y - _y).abs() < .92) {
        l.taken = true;
        _score += 10;
        switch (l.kind) {
          case _LootKind.coin:
            _coins++;
            break;
          case _LootKind.heart:
            _hp = math.min(3, _hp + 1);
            break;
          case _LootKind.bomb:
            _bombs = math.min(12, _bombs + 2);
            break;
          case _LootKind.ammo:
            _ammo = math.min(60, _ammo + 8);
            break;
          case _LootKind.weapon:
            _weapon = math.min(5, _weapon + 1);
            _score += 80;
            break;
          case _LootKind.shield:
            _shield = 520;
            break;
          case _LootKind.speed:
            _speed = 520;
            break;
          case _LootKind.jump:
            _jumpBoost = 520;
            break;
          case _LootKind.gem:
            _score += 300;
            break;
        }
        _texts.add(_PixelText(l.x, l.y - .15, _lootLabel(l.kind), _lootColor(l.kind)));
        _burst(l.x + .3, l.y + .3, _lootColor(l.kind), l.kind == _LootKind.gem ? 18 : 7);
      }
    }
    _loot.removeWhere((l) => l.taken);
  }

  String _lootLabel(_LootKind k) => switch (k) {
        _LootKind.weapon => 'SİLAH +1',
        _LootKind.ammo => 'MERMİ',
        _LootKind.bomb => 'BOMBA',
        _LootKind.heart => 'CAN',
        _LootKind.shield => 'KALKAN',
        _LootKind.speed => 'HIZ',
        _LootKind.jump => 'ZIPLAMA',
        _LootKind.coin => '+ALTIN',
        _LootKind.gem => 'NADİR KRİSTAL',
      };

  Color _lootColor(_LootKind k) => switch (k) {
        _LootKind.weapon => const Color(0xffff8a3d),
        _LootKind.ammo => const Color(0xff67e8f9),
        _LootKind.bomb => const Color(0xfff59e0b),
        _LootKind.heart => const Color(0xffff5d73),
        _LootKind.shield => const Color(0xff60a5fa),
        _LootKind.speed => const Color(0xffa78bfa),
        _LootKind.jump => const Color(0xff34d399),
        _LootKind.coin => const Color(0xffffd166),
        _LootKind.gem => const Color(0xfff0abfc),
      };

  Color _enemyColor(_EnemyKind k) => switch (k) {
        _EnemyKind.walker => const Color(0xffef4444),
        _EnemyKind.spike => const Color(0xff8b5cf6),
        _EnemyKind.shooter => const Color(0xfffb7185),
        _EnemyKind.flyer => const Color(0xff38bdf8),
        _EnemyKind.charger => const Color(0xfff59e0b),
        _EnemyKind.brute => const Color(0xff7c3aed),
        _EnemyKind.bomber => const Color(0xff94a3b8),
        _EnemyKind.boss => const Color(0xfff43f5e),
      };

  void _burst(double x, double y, Color color, int count) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final speed = .025 + _rng.nextDouble() * .12;
      _particles.add(_PixelParticle(x, y, math.cos(a) * speed,
          math.sin(a) * speed - .03, .045 + _rng.nextDouble() * .08,
          18 + _rng.nextInt(16), color));
    }
  }

  void _tick() {
    if (!mounted) return;
    if (_phase == _Phase.select || _phase == _Phase.gameover || _phase == _Phase.win) return;
    setState(() {
      _clock++;
      if (_phase == _Phase.ready) {
        if (--_phaseTicks <= 0) _phase = _Phase.playing;
        return;
      }
      if (_phase == _Phase.dying) {
        _y += _vy;
        _vy += .018;
        if (--_phaseTicks <= 0) _load(_level);
        return;
      }
      if (_phase == _Phase.clear) {
        if (--_phaseTicks <= 0) {
          if (_level + 1 < _levels.length) {
            _load(_level + 1);
          } else {
            _phase = _Phase.win;
          }
        }
        return;
      }
      _play();
    });
  }

  void _play() {
    if (++_timeTicks >= 40) {
      _timeTicks = 0;
      if (--_time <= 0) {
        _hurt();
        _time = 35;
      }
    }
    if (_invuln > 0) _invuln--;
    if (_attackCd > 0) _attackCd--;
    if (_dashCd > 0) _dashCd--;
    if (_shield > 0) _shield--;
    if (_speed > 0) _speed--;
    if (_jumpBoost > 0) _jumpBoost--;
    if (_shake > 0) _shake--;

    final dir = (_right ? 1 : 0) - (_left ? 1 : 0);
    final info = _info!;
    final maxSpeed = info.runSpeed * (_speed > 0 ? 1.35 : 1);
    const accel = .032;
    const friction = .022;
    if (dir != 0) {
      _vx += dir * accel;
      _vx = _vx.clamp(-maxSpeed, maxSpeed).toDouble();
      _facing = dir;
    } else if (_vx.abs() > friction) {
      _vx -= _vx.sign * friction;
    } else {
      _vx = 0;
    }
    if (_dashTicks > 0) {
      _dashTicks--;
      _vx = _facing * .42;
    }
    _moveX(_vx);

    final groundedBefore = _grounded;
    if (groundedBefore) _coyote = 7;
    if (_jumpBuffer > 0 && (groundedBefore || _coyote > 0)) {
      _vy = info.jumpSpeed * (_jumpBoost > 0 ? 1.18 : 1);
      _jumpBuffer = 0;
      _coyote = 0;
      _burst(_x + .35, _y + .85, const Color(0xffdff7ff), 4);
    }
    if (!_jumpHeld && _vy < -.10) _vy *= .55;
    _vy = math.min(_maxFall, _vy + _gravity);
    _moveY(_vy);
    if (_grounded) {
      _coyote = 7;
    } else if (_coyote > 0) {
      _coyote--;
    }
    if (_jumpBuffer > 0) _jumpBuffer--;

    _hazardTick();
    if (_y > _rows + 1) {
      _hurt();
      if (_phase == _Phase.playing) _load(_level);
      return;
    }
    _collect();
    _enemiesTick();
    _shotsTick();
    _particlesTick();
    _textsTick();
    _cameraTick();
    if (_x >= _flag - 1 && _bossHp <= 0) {
      _score += _time * 4;
      _phase = _Phase.clear;
      _phaseTicks = 90;
      _burst(_x + .3, _y + .4, const Color(0xff43d17d), 18);
    }
  }

  void _hazardTick() {
    final l = _x.floor();
    final r = (_x + _pw - .02).floor();
    for (final col in [l, r]) {
      if (_tile(11, col) == '^' && _y > 10.2) {
        _hurt();
        return;
      }
    }
  }

  void _enemiesTick() {
    for (final e in _enemies) {
      if (e.dead) continue;
      e.cooldown--;
      switch (e.kind) {
        case _EnemyKind.flyer:
          e.y = 5.4 + math.sin((_clock + e.x * 7) * .055) * .9;
          e.x += e.vx;
          break;
        case _EnemyKind.shooter:
          if (e.cooldown <= 0 && (e.x - _x).abs() < 12) {
            e.cooldown = 58;
            _shots.add(_PixelShot(e.x, e.y, _x < e.x ? -.15 : .15, 0, life: 78,
                damage: 1));
          }
          break;
        case _EnemyKind.bomber:
          if (e.cooldown <= 0 && (e.x - _x).abs() < 11) {
            e.cooldown = 78;
            _shots.add(_PixelShot(e.x, e.y, _x < e.x ? -.11 : .11, -.18,
                bomb: true, life: 78, damage: 1));
          }
          e.x += e.vx;
          break;
        case _EnemyKind.charger:
          final distance = (_x - e.x).abs();
          e.vx = distance < 5 ? (_x < e.x ? -.095 : .095) : (e.vx.sign * .035);
          e.x += e.vx;
          break;
        case _EnemyKind.brute:
          e.x += _x < e.x ? -.024 : .024;
          break;
        case _EnemyKind.boss:
          final near = (_x - e.x).abs() < 7;
          e.x += _x < e.x ? -.017 : .017;
          if (e.cooldown <= 0) {
            e.cooldown = near ? 42 : 30;
            _shots.add(_PixelShot(e.x, e.y, _x < e.x ? -.14 : .14,
                near ? -.11 : 0, bomb: true, life: 88, damage: 1));
            if (e.hp <= 6) {
            _shots.add(_PixelShot(e.x, e.y - .5, _x < e.x ? -.10 : .10,
                -.20, bomb: true, life: 80, damage: 1));
          }
          }
          break;
        case _EnemyKind.walker:
        case _EnemyKind.spike:
          e.x += e.vx;
          break;
      }
      if (e.x < 2 || e.x > _cols - 2) e.vx = -e.vx;

      final close = (e.x - _x).abs() < .72 && (e.y - _y).abs() < .86;
      if (close) {
        if (_vy > .06 && _y < e.y - .25 && e.kind != _EnemyKind.spike) {
          _damage(e, 1 + (_weapon >= 3 ? 1 : 0));
          _vy = -.18;
        } else {
          _hurt();
        }
      }
    }
    _enemies.removeWhere((e) => e.dead);
  }

  void _shotsTick() {
    for (final q in _shots) {
      q.x += q.vx;
      q.y += q.vy;
      if (q.bomb) q.vy += .008;
      q.life--;

      if ((q.x - _x).abs() < .55 && (q.y - _y).abs() < .75) {
        if (q.bomb) {
          _explode(q.x, q.y, q.damage);
        } else {
          _hurt();
        }
        q.life = 0;
        continue;
      }

      if (q.bomb && q.y > 10.5) {
        _explode(q.x, q.y, q.damage);
        q.life = 0;
      } else {
        for (final e in _enemies) {
          if (!e.dead && (e.x - q.x).abs() < .62 && (e.y - q.y).abs() < .75) {
            _damage(e, q.damage);
            q.life = 0;
            break;
          }
        }
      }
      if (_solid(q.y.floor(), q.x.floor())) q.life = 0;
    }
    _shots.removeWhere((q) => q.life <= 0 || q.x < _camera - 3 || q.x > _camera + 18);
  }

  void _explode(double x, double y, int damage) {
    _shake = 8;
    _burst(x, y, const Color(0xffff8a3d), 24);
    for (final e in _enemies) {
      if (!e.dead && (e.x - x).abs() < 2.1 && (e.y - y).abs() < 1.55) _damage(e, damage);
    }
    if ((x - _x).abs() < 2.1 && (y - _y).abs() < 1.55) _hurt();
  }

  void _particlesTick() {
    for (final p in _particles) {
      p.x += p.vx;
      p.y += p.vy;
      p.vy += .003;
      p.life--;
    }
    _particles.removeWhere((p) => p.life <= 0);
  }

  void _textsTick() {
    for (final t in _texts) {
      t.y -= .018;
      t.life--;
    }
    _texts.removeWhere((t) => t.life <= 0);
  }

  void _cameraTick() {
    final target = (_x - 5).clamp(0, math.max(0, _cols - 13)).toDouble();
    _camera += (target - _camera) * .12;
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    final down = e is KeyDownEvent;
    final up = e is KeyUpEvent;
    if (!down && !up) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _left = down;
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _right = down;
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      if (down) {
        _jumpHeld = true;
        _jump();
      } else {
        _jumpHeld = false;
      }
      return KeyEventResult.handled;
    }
    if (down && (k == LogicalKeyboardKey.keyX || k == LogicalKeyboardKey.keyK)) {
      _attack();
      return KeyEventResult.handled;
    }
    if (down && k == LogicalKeyboardKey.keyC) {
      _bomb();
      return KeyEventResult.handled;
    }
    if (down && (k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight)) {
      _dash();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => _ArcadeFrame(
        score: _phase == _Phase.select
            ? 'KARAKTER SEÇ'
            : _phase == _Phase.gameover
                ? 'OYUN BİTTİ • $_score'
                : _phase == _Phase.win
                    ? 'ZAFER • $_score'
                    : '$_score PTS • ALTIN $_coins • CAN $_lives/$_hp • BÖLÜM ${_level + 1}/6 • SİLAH $_weapon • BOMBA $_bombs • MERMİ $_ammo',
        controls: widget.showPad && _phase != _Phase.select
            ? _PlatformerControls(
                onLeft: (v) => _left = v,
                onRight: (v) => _right = v,
                onJumpDown: () {
                  _jumpHeld = true;
                  _jump();
                },
                onJumpUp: () => _jumpHeld = false,
                onAttack: _attack,
                onBomb: _bomb,
                onDash: _dash,
                attackIcon: _hero == _PlatformerHero.coder ? Icons.bolt : Icons.hardware,
              )
            : null,
        child: _phase == _Phase.select ? _select() : _stage(),
      );

  Widget _stage() => Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            if (_phase == _Phase.gameover || _phase == _Phase.win) {
              setState(() => _phase = _Phase.select);
            }
          },
          child: CustomPaint(
            painter: _PixelAdventurePainter(this),
            size: Size.infinite,
          ),
        ),
      );

  Widget _select() => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            const Text('PIKSEL MACERASI',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 21, letterSpacing: 2)),
            const SizedBox(height: 4),
            const Text('6 BİYOM • 6 BÖLÜM • 7 DÜŞMAN • BOSS • RASTGELE GANİMET',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 10.5)),
            const SizedBox(height: 14),
            _HeroCard(hero: _PlatformerHero.chief, onTap: () => _choose(_PlatformerHero.chief)),
            const SizedBox(height: 10),
            _HeroCard(hero: _PlatformerHero.coder, onTap: () => _choose(_PlatformerHero.coder)),
            const SizedBox(height: 12),
            const Text('A/D veya ←/→ Hareket • W/↑/Space Zıpla • X Saldır • C Bomba • Shift Dash\nKalkan, hız, zıplama ve silah seviyesini topla. Düşmanlar rastgele ganimet bırakır.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.5)),
          ],
        ),
      );
}


class _HeroCard extends StatelessWidget {
  final _PlatformerHero hero;
  final VoidCallback onTap;

  const _HeroCard({
    required this.hero,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final info = _heroInfo[hero]!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xff111827),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hero == _PlatformerHero.chief
                ? const Color(0xffffb703)
                : const Color(0xff38bdf8),
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xff0b1220),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                hero == _PlatformerHero.chief
                    ? Icons.engineering
                    : Icons.code,
                color: hero == _PlatformerHero.chief
                    ? const Color(0xffffb703)
                    : const Color(0xff38bdf8),
                size: 30,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    info.tagline,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    info.ability,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }
}

class _PixelAdventurePainter extends CustomPainter {
  final _PlatformerState s;
  const _PixelAdventurePainter(this.s);

  Color _sky(_PixelWorld w) => switch (w) {
        _PixelWorld.valley => const Color(0xff163b57),
        _PixelWorld.cave => const Color(0xff1d1932),
        _PixelWorld.factory => const Color(0xff171827),
        _PixelWorld.cloud => const Color(0xff7bb7df),
        _PixelWorld.ruins => const Color(0xff312838),
        _PixelWorld.volcano => const Color(0xff351824),
      };

  Color _ground(_PixelWorld w) => switch (w) {
        _PixelWorld.valley => const Color(0xff6d4728),
        _PixelWorld.cave => const Color(0xff4d3b63),
        _PixelWorld.factory => const Color(0xff3f4052),
        _PixelWorld.cloud => const Color(0xff8797aa),
        _PixelWorld.ruins => const Color(0xff6b5240),
        _PixelWorld.volcano => const Color(0xff532c24),
      };

  @override
  void paint(Canvas c, Size size) {
    if (s._grid.isEmpty) return;
    final w = s._levels[s._level].world;
    c.drawRect(Offset.zero & size, Paint()..color = _sky(w));
    _background(c, size, w);

    final t = math.min(size.width / 13, size.height / _PlatformerState._rows);
    if (t <= 0) return;
    final ox = (size.width - 13 * t) / 2;
    final oy = (size.height - _PlatformerState._rows * t) / 2;
    final shakeX = s._shake > 0 ? math.sin(s._clock * 2.1) * s._shake * .35 : 0;
    final shakeY = s._shake > 0 ? math.cos(s._clock * 1.7) * s._shake * .22 : 0;
    c.save();
    c.translate(ox + shakeX, oy + shakeY);

    final first = s._camera.floor() - 1;
    for (var row = 0; row < _PlatformerState._rows; row++) {
      for (var col = first; col <= first + 16; col++) {
        final ch = s._tile(row, col);
        if (ch == '.') continue;
        final r = Rect.fromLTWH((col - s._camera) * t, row * t, t, t);
        if (ch == '#') {
          c.drawRect(r, Paint()..color = _ground(w));
          c.drawRect(Rect.fromLTWH(r.left, r.top, t, t * .15),
              Paint()..color = _topAccent(w));
        } else if (ch == 'B' || ch == '?' || ch == 'U') {
          final colr = ch == '?'
              ? const Color(0xfff4b63d)
              : ch == 'U'
                  ? const Color(0xff6b7280)
                  : _blockColor(w);
          c.drawRect(r, Paint()..color = colr);
          c.drawRect(Rect.fromLTWH(r.left, r.top, t, t * .10), Paint()..color = Colors.white24);
          if (ch == '?') {
            final p = TextPainter(
              text: const TextSpan(text: '?', style: TextStyle(color: Color(0xff5a3b08), fontWeight: FontWeight.w900, fontSize: 22)),
              textDirection: TextDirection.ltr,
            )..layout();
            p.paint(c, Offset(r.left + (t - p.width) / 2, r.top + (t - p.height) / 2));
          }
        } else if (ch == '=') {
          c.drawRRect(RRect.fromRectAndRadius(r.deflate(t * .03), Radius.circular(t * .10)), Paint()..color = _platformColor(w));
          c.drawRect(Rect.fromLTWH(r.left, r.top, t, t * .12), Paint()..color = Colors.white54);
        } else if (ch == 'H') {
          c.drawRect(r, Paint()..color = Colors.white.withValues(alpha: .025));
          if ((s._clock + col * 3) % 36 < 3) c.drawCircle(r.center, t * .08, Paint()..color = Colors.white24);
        } else if (ch == '^') {
          final path = Path()
            ..moveTo(r.left, r.bottom)
            ..lineTo(r.center.dx, r.top + t * .08)
            ..lineTo(r.right, r.bottom)
            ..close();
          c.drawPath(path, Paint()..color = const Color(0xffe8edf2));
        } else if (ch == 'o') {
          c.drawCircle(r.center, t * .20, Paint()..color = const Color(0xffffd166));
          c.drawCircle(Offset(r.center.dx - t * .06, r.center.dy - t * .06), t * .06, Paint()..color = Colors.white54);
        } else if (ch == 'F') {
          c.drawRect(Rect.fromLTWH(r.center.dx, r.top, t * .07, t * 7.2), Paint()..color = Colors.white70);
          c.drawRect(Rect.fromLTWH(r.center.dx, r.top, t * 1.45, t), Paint()..color = const Color(0xff43d17d));
        }
      }
    }

    for (final l in s._loot) {
      if (l.taken) continue;
      final p = Offset((l.x - s._camera + .5) * t, l.y * t);
      final r = Rect.fromCenter(center: p, width: t * .42, height: t * .42);
      c.drawCircle(p, t * .23, Paint()..color = _lootColor(l.kind));
      if (l.kind == _LootKind.gem) {
        final path = Path()
          ..moveTo(p.dx, p.dy - t * .30)
          ..lineTo(p.dx + t * .22, p.dy)
          ..lineTo(p.dx, p.dy + t * .30)
          ..lineTo(p.dx - t * .22, p.dy)
          ..close();
        c.drawPath(path, Paint()..color = const Color(0xfff0abfc));
      }
      c.drawRect(r.deflate(t * .16), Paint()..color = Colors.white24);
    }

    for (final q in s._shots) {
      final p = Offset((q.x - s._camera) * t, q.y * t);
      c.drawCircle(p, t * (q.bomb ? .21 : .11), Paint()..color = q.bomb ? const Color(0xffff7b00) : const Color(0xff67e8f9));
    }

    for (final p in s._particles) {
      final a = (p.life / 34).clamp(0.0, 1.0);
      c.drawRect(Rect.fromCenter(center: Offset((p.x - s._camera) * t, p.y * t), width: p.size * t, height: p.size * t),
          Paint()..color = p.color.withValues(alpha: a));
    }

    for (final e in s._enemies.where((x) => !x.dead)) {
      _enemy(c, e, t);
    }

    if (!(s._invuln > 0 && (s._clock ~/ 4).isOdd)) {
      _drawHeroFigure(
        c,
        Rect.fromLTWH((s._x - s._camera) * t, s._y * t,
            _PlatformerState._pw * t, _PlatformerState._ph * t),
        s._hero ?? _PlatformerHero.chief,
        s._facing,
        runPhase: s._clock ~/ 5 % 2,
        air: !s._grounded,
        attack: s._attackCd > 0 ? 5 : 0,
      );
    }
    if (s._shield > 0) {
      c.drawCircle(Offset((s._x - s._camera + .36) * t, (s._y + .42) * t), t * .58,
          Paint()..style = PaintingStyle.stroke..strokeWidth = t * .06..color = const Color(0xff60a5fa).withValues(alpha: .60));
    }

    for (final z in s._texts) {
      final p = TextPainter(
        text: TextSpan(text: z.text, style: TextStyle(color: z.color.withValues(alpha: z.life / 30), fontWeight: FontWeight.w900, fontSize: t * .31)),
        textDirection: TextDirection.ltr,
      )..layout();
      p.paint(c, Offset((z.x - s._camera) * t, z.y * t));
    }
    c.restore();

    final d = s._levels[s._level];
    final h = TextPainter(
      text: TextSpan(
        text: '${s._level + 1}/6  ${d.name}   ♥ ${s._hp}  ◆ ${s._bombs}  ⚡ ${s._ammo}  ⬢ ${s._weapon}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width - 20);
    h.paint(c, const Offset(10, 10));

    if (s._shield > 0) _chip(c, size, 10, 28, 'KALKAN', const Color(0xff60a5fa));
    if (s._speed > 0) _chip(c, size, 72, 28, 'HIZ', const Color(0xffa78bfa));
    if (s._jumpBoost > 0) _chip(c, size, 110, 28, 'ZIP', const Color(0xff34d399));
    if (s._bossHp > 0) {
      final boss = d.bossName;
      final bw = size.width * .52;
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((size.width - bw) / 2, 44, bw, 9), const Radius.circular(5)),
          Paint()..color = Colors.black54);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH((size.width - bw) / 2, 44, bw * (s._bossHp / 12), 9), const Radius.circular(5)),
          Paint()..color = const Color(0xfff43f5e));
      final bp = TextPainter(
        text: TextSpan(text: boss, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      bp.paint(c, Offset((size.width - bp.width) / 2, 54));
    }

    if (s._phase == _Phase.ready) _overlay(c, size, 'BÖLÜM ${s._level + 1}', d.name, d.objective);
    if (s._phase == _Phase.clear) _overlay(c, size, 'BÖLÜM TAMAM', 'Yeni biyom yükleniyor...', 'Hazır ol!');
    if (s._phase == _Phase.gameover) _overlay(c, size, 'OYUN BİTTİ', 'Skor ${s._score}', 'Dokun → karakter seç');
    if (s._phase == _Phase.win) _overlay(c, size, 'ZAFER!', '6 bölüm tamamlandı • ${s._score} PTS', 'Piksel Macerası tamamlandı');
  }

  void _background(Canvas c, Size z, _PixelWorld w) {
    final p = Paint();
    switch (w) {
      case _PixelWorld.valley:
        p.color = const Color(0xff24526d);
        c.drawCircle(Offset(z.width * .16, z.height * .75), z.height * .25, p);
        p.color = const Color(0xff2e6a67);
        c.drawCircle(Offset(z.width * .60, z.height * .76), z.height * .33, p);
        break;
      case _PixelWorld.cave:
        for (var i = 0; i < 10; i++) {
          c.drawCircle(Offset((i * 87) % z.width, z.height * (.18 + (i % 4) * .16)), 3 + i % 3, Paint()..color = const Color(0xff8b5cf6).withValues(alpha: .20));
        }
        break;
      case _PixelWorld.factory:
        final grid = Paint()..color = const Color(0xff67e8f9).withValues(alpha: .07)..strokeWidth = 1;
        for (var x = 0.0; x < z.width; x += 24) {
          c.drawLine(Offset(x, 0), Offset(x, z.height), grid);
        }
        for (var y = 0.0; y < z.height; y += 24) {
          c.drawLine(Offset(0, y), Offset(z.width, y), grid);
        }
        break;
      case _PixelWorld.cloud:
        for (var i = 0; i < 9; i++) {
          final p2 = Paint()..color = Colors.white.withValues(alpha: .16);
          final x = (i * 83.0 + math.sin(s._clock * .01 + i) * 14) % (z.width + 60) - 30;
          c.drawCircle(Offset(x, 42 + (i % 4) * 38), 24, p2);
          c.drawCircle(Offset(x + 24, 48 + (i % 4) * 38), 18, p2);
        }
        break;
      case _PixelWorld.ruins:
        final r = Paint()..color = const Color(0xffb18b5a).withValues(alpha: .16);
        for (var i = 0; i < 6; i++) {
          c.drawRect(Rect.fromLTWH(i * z.width / 6 + 12, z.height * .18, 18, z.height * .46), r);
          c.drawRect(Rect.fromLTWH(i * z.width / 6 + 3, z.height * .17, 36, 12), r);
        }
        break;
      case _PixelWorld.volcano:
        c.drawCircle(Offset(z.width * .78, z.height * .38), z.height * .23, Paint()..color = const Color(0xffef4444).withValues(alpha: .16));
        c.drawCircle(Offset(z.width * .20, z.height * .22), z.height * .12, Paint()..color = const Color(0xffff7b00).withValues(alpha: .12));
        break;
    }
  }

  Color _topAccent(_PixelWorld w) => switch (w) {
        _PixelWorld.valley => const Color(0xff46b86a),
        _PixelWorld.cave => const Color(0xff8b5cf6),
        _PixelWorld.factory => const Color(0xffd45d8c),
        _PixelWorld.cloud => const Color(0xfff4f7fb),
        _PixelWorld.ruins => const Color(0xffc29b68),
        _PixelWorld.volcano => const Color(0xffdf6c32),
      };

  Color _blockColor(_PixelWorld w) => switch (w) {
        _PixelWorld.valley => const Color(0xffbd6231),
        _PixelWorld.cave => const Color(0xff704e9b),
        _PixelWorld.factory => const Color(0xffc04e85),
        _PixelWorld.cloud => const Color(0xffa9b8c8),
        _PixelWorld.ruins => const Color(0xff9a714a),
        _PixelWorld.volcano => const Color(0xff9c4430),
      };

  Color _platformColor(_PixelWorld w) => switch (w) {
        _PixelWorld.valley => const Color(0xff6fcf97),
        _PixelWorld.cave => const Color(0xff62d4d8),
        _PixelWorld.factory => const Color(0xff4ed7e7),
        _PixelWorld.cloud => const Color(0xffeef6ff),
        _PixelWorld.ruins => const Color(0xffd1b07a),
        _PixelWorld.volcano => const Color(0xfff08a48),
      };

  Color _lootColor(_LootKind k) => switch (k) {
        _LootKind.coin => const Color(0xffffd166),
        _LootKind.heart => const Color(0xffff5d73),
        _LootKind.bomb => const Color(0xfff59e0b),
        _LootKind.ammo => const Color(0xff67e8f9),
        _LootKind.weapon => const Color(0xffff8a3d),
        _LootKind.shield => const Color(0xff60a5fa),
        _LootKind.speed => const Color(0xffa78bfa),
        _LootKind.jump => const Color(0xff34d399),
        _LootKind.gem => const Color(0xfff0abfc),
      };


  void _drawHeroFigure(
    Canvas c,
    Rect r,
    _PlatformerHero hero,
    int facing, {
    int runPhase = 0,
    bool air = false,
    int attack = 0,
  }) {
    final accent = hero == _PlatformerHero.chief
        ? const Color(0xffffb703)
        : const Color(0xff38bdf8);
    final dark = const Color(0xff172033);
    final skin = const Color(0xffffc7a8);

    final cx = r.center.dx;
    final scale = r.width;

    final body = Rect.fromLTWH(
      cx - scale * .19,
      r.top + scale * .38,
      scale * .38,
      scale * .34,
    );

    final head = Rect.fromLTWH(
      cx - scale * .17,
      r.top + scale * .16,
      scale * .34,
      scale * .25,
    );

    c.drawRRect(
      RRect.fromRectAndRadius(
        body,
        Radius.circular(scale * .055),
      ),
      Paint()..color = dark,
    );

    c.drawRRect(
      RRect.fromRectAndRadius(
        head,
        Radius.circular(scale * .07),
      ),
      Paint()..color = skin,
    );

    // Kask / saç
    c.drawRect(
      Rect.fromLTWH(
        head.left - scale * .025,
        head.top - scale * .035,
        head.width + scale * .05,
        scale * .075,
      ),
      Paint()..color = accent,
    );

    // Göz
    final eyeX = facing >= 0
        ? head.right - scale * .075
        : head.left + scale * .075;
    c.drawCircle(
      Offset(eyeX, head.top + head.height * .52),
      scale * .018,
      Paint()..color = Colors.black,
    );

    final legOffset = air
        ? 0.0
        : (runPhase == 0 ? scale * .055 : -scale * .055);

    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx - scale * .14 + legOffset,
          body.bottom - scale * .01,
          scale * .095,
          scale * .25,
        ),
        Radius.circular(scale * .025),
      ),
      Paint()..color = dark,
    );

    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          cx + scale * .045 - legOffset,
          body.bottom - scale * .01,
          scale * .095,
          scale * .25,
        ),
        Radius.circular(scale * .025),
      ),
      Paint()..color = dark,
    );

    final armY = body.top + body.height * .25;
    final armX = facing >= 0 ? body.right : body.left;

    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          facing >= 0 ? body.right - scale * .015 : body.left - scale * .08,
          armY,
          scale * .095,
          scale * .09,
        ),
        Radius.circular(scale * .025),
      ),
      Paint()..color = accent,
    );

    if (attack > 0) {
      final weaponX = facing >= 0 ? r.right : r.left;
      c.drawLine(
        Offset(armX, armY + scale * .045),
        Offset(
          weaponX + (facing >= 0 ? scale * .18 : -scale * .18),
          armY - scale * .01,
        ),
        Paint()
          ..color = hero == _PlatformerHero.chief
              ? const Color(0xffd7dde8)
              : const Color(0xff67e8f9)
          ..strokeWidth = scale * .055
          ..strokeCap = StrokeCap.square,
      );
    }
  }

  void _enemy(Canvas c, _PixelEnemy e, double t) {
    final p = Offset((e.x - s._camera) * t, e.y * t);
    final r = Rect.fromCenter(center: p, width: t * (e.kind == _EnemyKind.boss ? .95 : .72), height: t * (e.kind == _EnemyKind.boss ? .92 : .78));
    final paint = Paint()..color = s._enemyColor(e.kind);
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(t * .12)), paint);
    if (e.kind == _EnemyKind.spike) {
      final path = Path()
        ..moveTo(r.left, r.bottom)
        ..lineTo(r.center.dx, r.top)
        ..lineTo(r.right, r.bottom)
        ..close();
      c.drawPath(path, Paint()..color = const Color(0xffd8dce2));
    } else {
      c.drawCircle(Offset(p.dx - t * .14, p.dy - t * .10), t * .06, Paint()..color = Colors.white);
      c.drawCircle(Offset(p.dx + t * .14, p.dy - t * .10), t * .06, Paint()..color = Colors.white);
    }
    if (e.kind == _EnemyKind.boss) {
      final bw = r.width * (e.hp / 12).clamp(0.0, 1.0);
      c.drawRect(Rect.fromLTWH(r.left, r.top - t * .20, bw, t * .07), Paint()..color = const Color(0xffffd166));
      c.drawRect(Rect.fromLTWH(r.left + r.width * .23, r.top + r.height * .36, r.width * .54, r.height * .16), Paint()..color = Colors.black38);
    }
  }

  void _chip(Canvas c, Size z, double x, double y, String label, Color color) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, label.length * 6.1 + 12, 16), const Radius.circular(8)), Paint()..color = color.withValues(alpha: .20));
    final p = TextPainter(text: TextSpan(text: label, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout();
    p.paint(c, Offset(x + 6, y + 4));
  }

  void _overlay(Canvas c, Size z, String a, String b, String d) {
    c.drawRect(Offset.zero & z, Paint()..color = Colors.black.withValues(alpha: .62));
    final p = TextPainter(
      text: TextSpan(text: '$a\n', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900), children: [
        TextSpan(text: '$b\n', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        TextSpan(text: d, style: const TextStyle(color: Colors.white54, fontSize: 10)),
      ]),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: z.width - 30);
    p.paint(c, Offset((z.width - p.width) / 2, (z.height - p.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _PixelAdventurePainter old) => true;
}

class _PlatformerControls extends StatelessWidget {
  final ValueChanged<bool> onLeft, onRight;
  final VoidCallback onJumpDown, onJumpUp, onAttack, onBomb, onDash;
  final IconData attackIcon;
  const _PlatformerControls({
    required this.onLeft,
    required this.onRight,
    required this.onJumpDown,
    required this.onJumpUp,
    required this.onAttack,
    required this.onBomb,
    required this.onDash,
    required this.attackIcon,
  });

  Widget _hold(IconData i, String l, void Function(bool) f) => Semantics(
        button: true,
        label: l,
        child: Listener(
          onPointerDown: (_) => f(true),
          onPointerUp: (_) => f(false),
          onPointerCancel: (_) => f(false),
          child: SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(i, color: Colors.white, size: 23),
            ),
          ),
        ),
      );

  Widget _tap(IconData i, String l, VoidCallback f) => Semantics(
        button: true,
        label: l,
        child: GestureDetector(
          onTap: f,
          child: SizedBox(
            width: 48,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: Icon(i, color: Colors.white, size: 23),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _hold(Icons.chevron_left_rounded, 'Sol', onLeft),
          const SizedBox(width: 5),
          _hold(Icons.chevron_right_rounded, 'Sağ', onRight),
          const Spacer(),
          _tap(Icons.bolt_rounded, 'Dash', onDash),
          const SizedBox(width: 5),
          _tap(Icons.bubble_chart_rounded, 'Bomba', onBomb),
          const SizedBox(width: 5),
          _tap(attackIcon, 'Saldırı', onAttack),
          const SizedBox(width: 5),
          _hold(Icons.keyboard_arrow_up_rounded, 'Zıpla', (v) {
            if (v) {
              onJumpDown();
            } else {
              onJumpUp();
            }
          }),
        ],
      );
}

// ---------------------------------------------------------------------------
// Tank arena: grid movement, destructible-looking cover, enemy volleys
// ---------------------------------------------------------------------------
class _TankGame extends StatefulWidget {
  final bool showPad;
  const _TankGame({required this.showPad});
  @override
  State<_TankGame> createState() => _TankState();
}

class _TankUnit {
  math.Point<int> position;
  math.Point<int> direction;
  _TankUnit(this.position, this.direction);
}

class _TankBullet {
  double x, y;
  final int dx, dy;
  final bool enemy;
  _TankBullet(this.x, this.y, this.dx, this.dy, this.enemy);
}

class _TankState extends State<_TankGame> {
  static const _cols = 13, _rows = 16;
  static const _walls = <String>{
    '3:3',
    '4:3',
    '8:3',
    '9:3',
    '3:4',
    '9:4',
    '1:7',
    '2:7',
    '5:7',
    '6:7',
    '7:7',
    '10:7',
    '11:7',
    '4:10',
    '5:10',
    '7:10',
    '8:10',
    '2:12',
    '10:12',
  };
  Timer? _timer;
  final List<_TankUnit> _enemies = [];
  final List<_TankBullet> _bullets = [];
  math.Point<int> _player = const math.Point(6, 14);
  math.Point<int> _direction = const math.Point(0, -1);
  int _lives = 3, _score = 0, _ticks = 0;
  bool _over = false, _won = false;

  @override
  void initState() {
    super.initState();
    _reset();
    _timer = Timer.periodic(const Duration(milliseconds: 45), (_) {
      if (mounted && !_over && !_won) setState(_tick);
    });
  }

  bool _blocked(math.Point<int> p) =>
      p.x < 0 ||
      p.x >= _cols ||
      p.y < 0 ||
      p.y >= _rows ||
      p == _player ||
      _walls.contains('${p.x}:${p.y}') ||
      _enemies.any((e) => e.position == p);

  void _move(int dx, int dy) {
    if (_over || _won) return;
    final d = math.Point(dx, dy);
    setState(() {
      _direction = d;
      final next = math.Point(_player.x + dx, _player.y + dy);
      if (!_blocked(next)) _player = next;
    });
  }

  void _fire() {
    if (_over || _won) return;
    _bullets.add(
      _TankBullet(
        _player.x + .5 + _direction.x * .55,
        _player.y + .5 + _direction.y * .55,
        _direction.x,
        _direction.y,
        false,
      ),
    );
  }

  void _tick() {
    _ticks++;
    if (_ticks % 14 == 0) {
      for (final enemy in _enemies) {
        final options = [
          const math.Point(0, 1),
          const math.Point(1, 0),
          const math.Point(-1, 0),
          const math.Point(0, -1),
        ];
        final direction = options[math.Random().nextInt(options.length)];
        final next = math.Point(
          enemy.position.x + direction.x,
          enemy.position.y + direction.y,
        );
        if (!_blocked(next) && next.y < 13) enemy.position = next;
        enemy.direction = direction;
      }
    }
    if (_ticks % 27 == 0 && _enemies.isNotEmpty) {
      final enemy = _enemies[math.Random().nextInt(_enemies.length)];
      _bullets.add(
        _TankBullet(
          enemy.position.x + .5 + enemy.direction.x * .55,
          enemy.position.y + .5 + enemy.direction.y * .55,
          enemy.direction.x,
          enemy.direction.y,
          true,
        ),
      );
    }
    final hitEnemies = <_TankUnit>{};
    final remaining = <_TankBullet>[];
    for (final bullet in _bullets) {
      bullet.x += bullet.dx * .30;
      bullet.y += bullet.dy * .30;
      final bx = bullet.x.floor(), by = bullet.y.floor();
      if (bx < 0 ||
          bx >= _cols ||
          by < 0 ||
          by >= _rows ||
          _walls.contains('$bx:$by')) {
        continue;
      }
      if (bullet.enemy && bx == _player.x && by == _player.y) {
        _lives--;
        if (_lives <= 0) _over = true;
        continue;
      }
      final enemyIndex = _enemies.indexWhere(
        (unit) => unit.position.x == bx && unit.position.y == by,
      );
      if (!bullet.enemy && enemyIndex >= 0) {
        hitEnemies.add(_enemies[enemyIndex]);
        _score += 100;
        continue;
      }
      if (bullet.x < 0 ||
          bullet.x >= _cols ||
          bullet.y < 0 ||
          bullet.y >= _rows) {
        continue;
      }
      remaining.add(bullet);
    }
    _bullets
      ..clear()
      ..addAll(remaining);
    _enemies.removeWhere(hitEnemies.contains);
    if (_enemies.isEmpty) _won = true;
  }

  void _reset() {
    _player = const math.Point(6, 14);
    _direction = const math.Point(0, -1);
    _lives = 3;
    _score = 0;
    _ticks = 0;
    _over = false;
    _won = false;
    _enemies
      ..clear()
      ..addAll([
        _TankUnit(const math.Point(2, 1), const math.Point(0, 1)),
        _TankUnit(const math.Point(6, 1), const math.Point(0, 1)),
        _TankUnit(const math.Point(10, 1), const math.Point(0, 1)),
      ]);
    _bullets.clear();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ArcadeFrame(
    score: _won
        ? 'KAZANDIN • $_score'
        : _over
        ? 'TANK KAYBEDİLDİ'
        : '$_score PTS  •  ♥ $_lives',
    controls: widget.showPad
        ? _VirtualGamepad(
            up: () => _move(0, -1),
            down: () => _move(0, 1),
            left: () => _move(-1, 0),
            right: () => _move(1, 0),
            a: _fire,
            b: () => setState(_reset),
          )
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over || _won) {
          setState(_reset);
        } else {
          _fire();
        }
      },
      onHorizontalDragEnd: (d) =>
          _move((d.primaryVelocity ?? 0) > 0 ? 1 : -1, 0),
      onVerticalDragEnd: (d) => _move(0, (d.primaryVelocity ?? 0) > 0 ? 1 : -1),
      child: CustomPaint(
        painter: _TankPainter(
          player: _player,
          direction: _direction,
          enemies: _enemies,
          bullets: _bullets,
          over: _over,
          won: _won,
        ),
        size: Size.infinite,
      ),
    ),
  );
}

class _TankPainter extends CustomPainter {
  final math.Point<int> player, direction;
  final List<_TankUnit> enemies;
  final List<_TankBullet> bullets;
  final bool over, won;
  const _TankPainter({
    required this.player,
    required this.direction,
    required this.enemies,
    required this.bullets,
    required this.over,
    required this.won,
  });
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff101b23),
    );
    final cell = math.min(size.width / 13, size.height / 16).toDouble();
    final left = (size.width - cell * 13) / 2;
    final top = (size.height - cell * 16) / 2;
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 13; x++) {
        final rect = Rect.fromLTWH(
          left + x * cell,
          top + y * cell,
          cell - 1,
          cell - 1,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = (x + y) % 2 == 0
                ? const Color(0xff15252c)
                : const Color(0xff192b31),
        );
        if (_TankState._walls.contains('$x:$y')) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
            Paint()..color = const Color(0xff9a6445),
          );
          canvas.drawLine(
            rect.topLeft + Offset(3, cell * .38),
            rect.topRight + Offset(-3, cell * .38),
            Paint()
              ..color = const Color(0xffffc857)
              ..strokeWidth = 2,
          );
        }
      }
    }
    _drawTank(
      canvas,
      left,
      top,
      cell,
      player,
      direction,
      const Color(0xff68d391),
    );
    for (final enemy in enemies) {
      _drawTank(
        canvas,
        left,
        top,
        cell,
        enemy.position,
        enemy.direction,
        const Color(0xffef6672),
      );
    }
    for (final bullet in bullets) {
      canvas.drawCircle(
        Offset(left + bullet.x * cell, top + bullet.y * cell),
        cell * .13,
        Paint()
          ..color = bullet.enemy
              ? const Color(0xffff6b6b)
              : const Color(0xffffdf70),
      );
    }
    if (over || won) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: .62),
      );
      final p = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: TextSpan(
          text: won ? 'ARENA TEMİZ' : 'OYUN BİTTİ',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
          children: const [
            TextSpan(
              text: '\nDokun ve yeniden başla',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      )..layout(maxWidth: size.width - 20);
      p.paint(
        canvas,
        Offset((size.width - p.width) / 2, (size.height - p.height) / 2),
      );
    }
  }

  void _drawTank(
    Canvas canvas,
    double left,
    double top,
    double cell,
    math.Point<int> p,
    math.Point<int> direction,
    Color color,
  ) {
    final center = Offset(left + (p.x + .5) * cell, top + (p.y + .5) * cell);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: cell * .76, height: cell * .76),
        const Radius.circular(4),
      ),
      Paint()..color = color,
    );
    canvas.drawLine(
      center,
      center + Offset(direction.x * cell * .40, direction.y * cell * .40),
      Paint()
        ..color = const Color(0xffe6edf3)
        ..strokeWidth = cell * .15
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TankPainter old) => true;
}

// ---------------------------------------------------------------------------
// Space-defense shooter
// ---------------------------------------------------------------------------
class _SpaceGame extends StatefulWidget {
  final bool showPad;
  const _SpaceGame({required this.showPad});
  @override
  State<_SpaceGame> createState() => _SpaceState();
}

class _SpaceState extends State<_SpaceGame> {
  Timer? _timer;
  final List<Offset> _shots = [], _enemies = [];
  double _ship = .5;
  int _score = 0, _lives = 3, _waveTick = 0;
  bool _over = false;

  @override
  void initState() {
    super.initState();
    _spawnWave();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (mounted && !_over) setState(_tick);
    });
  }

  void _spawnWave() {
    for (var i = 0; i < 8; i++) {
      _enemies.add(Offset(.13 + (i % 4) * .20, .10 + (i ~/ 4) * .12));
    }
  }

  void _move(double d) {
    if (!_over) setState(() => _ship = (_ship + d).clamp(.05, .95).toDouble());
  }

  void _fire() {
    if (!_over) _shots.add(Offset(_ship, .88));
  }

  void _tick() {
    _waveTick++;
    for (var i = 0; i < _shots.length; i++) {
      _shots[i] = Offset(_shots[i].dx, _shots[i].dy - .025);
    }
    _shots.removeWhere((shot) => shot.dy < .02);
    for (var i = 0; i < _enemies.length; i++) {
      final e = _enemies[i];
      _enemies[i] = Offset(
        e.dx + math.sin((_waveTick / 22) + i) * .0008,
        e.dy + .0015 + (_score / 10000),
      );
    }
    final used = <Offset>{};
    final removeShots = <Offset>{};
    for (final shot in _shots) {
      for (final enemy in _enemies) {
        if (used.contains(enemy)) continue;
        if ((shot.dx - enemy.dx).abs() < .055 &&
            (shot.dy - enemy.dy).abs() < .045) {
          used.add(enemy);
          removeShots.add(shot);
          break;
        }
      }
    }
    _enemies.removeWhere(used.contains);
    _shots.removeWhere(removeShots.contains);
    _score += used.length * 10;
    if (_enemies.any((e) => e.dy > .82)) {
      _lives--;
      _enemies.removeWhere((e) => e.dy > .82);
      if (_lives <= 0) _over = true;
    }
    if (_enemies.isEmpty && !_over) _spawnWave();
  }

  void _reset() {
    setState(() {
      _shots.clear();
      _enemies.clear();
      _ship = .5;
      _score = 0;
      _lives = 3;
      _waveTick = 0;
      _over = false;
      _spawnWave();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ArcadeFrame(
    score: _over
        ? 'FİLO GEÇTİ • $_score'
        : 'DALGA ${1 + _score ~/ 80}  •  $_score  •  ♥ $_lives',
    controls: widget.showPad
        ? _VirtualGamepad(
            left: () => _move(-.07),
            right: () => _move(.07),
            a: _fire,
            b: _reset,
          )
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over) {
          _reset();
        } else {
          _fire();
        }
      },
      onHorizontalDragUpdate: (d) => _move(d.primaryDelta! / 300),
      child: CustomPaint(
        painter: _SpacePainter(_ship, _shots, _enemies, _over),
        size: Size.infinite,
      ),
    ),
  );
}

class _SpacePainter extends CustomPainter {
  final double ship;
  final List<Offset> shots, enemies;
  final bool over;
  const _SpacePainter(this.ship, this.shots, this.enemies, this.over);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xff080d21), Color(0xff172348)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    for (var i = 0; i < 44; i++) {
      final x = ((i * 67 + 17) % 997) / 997 * size.width;
      final y = ((i * 131 + 29) % 991) / 991 * size.height;
      canvas.drawCircle(
        Offset(x, y),
        i % 5 == 0 ? 1.6 : .8,
        Paint()..color = Colors.white.withValues(alpha: i % 4 == 0 ? .65 : .24),
      );
    }
    for (final enemy in enemies) {
      final rect = Rect.fromCenter(
        center: Offset(enemy.dx * size.width, enemy.dy * size.height),
        width: size.width * .07,
        height: size.width * .048,
      );
      final path = Path()
        ..moveTo(rect.left, rect.center.dy)
        ..lineTo(rect.left + rect.width * .23, rect.top)
        ..lineTo(rect.right - rect.width * .16, rect.top)
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.right - rect.width * .16, rect.bottom)
        ..lineTo(rect.left + rect.width * .23, rect.bottom)
        ..close();
      canvas.drawPath(path, Paint()..color = const Color(0xfff36d7d));
      canvas.drawCircle(
        rect.center,
        2,
        Paint()..color = const Color(0xffffd166),
      );
    }
    for (final shot in shots) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(shot.dx * size.width, shot.dy * size.height),
            width: 4,
            height: 13,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xffffe082),
      );
    }
    final center = Offset(ship * size.width, size.height * .90);
    final shipPath = Path()
      ..moveTo(center.dx, center.dy - 19)
      ..lineTo(center.dx + 15, center.dy + 15)
      ..lineTo(center.dx, center.dy + 9)
      ..lineTo(center.dx - 15, center.dy + 15)
      ..close();
    canvas.drawPath(shipPath, Paint()..color = const Color(0xff61d9ff));
    if (over) {
      _paintOverlay(canvas, size, 'FİLO GEÇTİ', 'Dokun ve yeniden başla');
    }
  }

  void _paintOverlay(Canvas canvas, Size size, String title, String subtitle) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: .62),
    );
    final p = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: '$title\n',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 23,
          fontWeight: FontWeight.w900,
        ),
        children: [
          TextSpan(
            text: subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    )..layout(maxWidth: size.width - 20);
    p.paint(
      canvas,
      Offset((size.width - p.width) / 2, (size.height - p.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SpacePainter old) => true;
}

// ---------------------------------------------------------------------------
// Snake
// ---------------------------------------------------------------------------
class _SnakeGame extends StatefulWidget {
  final bool showPad;
  const _SnakeGame({required this.showPad});
  @override
  State<_SnakeGame> createState() => _SnakeState();
}

class _SnakeState extends State<_SnakeGame> {
  static const _width = 15, _height = 19;
  final math.Random _random = math.Random();
  List<math.Point<int>> _snake = [];
  math.Point<int> _direction = const math.Point(1, 0),
      _food = const math.Point(5, 5);
  Timer? _timer;
  int _score = 0;
  bool _over = false;
  @override
  void initState() {
    super.initState();
    _reset();
    _timer = Timer.periodic(const Duration(milliseconds: 135), (_) {
      if (mounted && !_over) setState(_tick);
    });
  }

  void _reset() {
    _snake = [
      const math.Point(5, 8),
      const math.Point(4, 8),
      const math.Point(3, 8),
    ];
    _direction = const math.Point(1, 0);
    _score = 0;
    _over = false;
    _placeFood();
  }

  void _placeFood() {
    final empty = [
      for (var y = 0; y < _height; y++)
        for (var x = 0; x < _width; x++) math.Point(x, y),
    ].where((p) => !_snake.contains(p)).toList();
    if (empty.isEmpty) {
      _over = true;
      return;
    }
    _food = empty[_random.nextInt(empty.length)];
  }

  void _turn(int x, int y) {
    if (_over) return;
    if (x == -_direction.x && y == -_direction.y) return;
    _direction = math.Point(x, y);
  }

  void _tick() {
    final head = _snake.first;
    final next = math.Point(head.x + _direction.x, head.y + _direction.y);
    final eating = next == _food;
    final body = eating ? _snake : _snake.take(_snake.length - 1);
    if (next.x < 0 ||
        next.x >= _width ||
        next.y < 0 ||
        next.y >= _height ||
        body.contains(next)) {
      _over = true;
      return;
    }
    _snake.insert(0, next);
    if (eating) {
      _score += 10;
      _placeFood();
    } else {
      _snake.removeLast();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ArcadeFrame(
    score: _over ? 'BİTTİ • $_score PTS' : '$_score PTS',
    controls: widget.showPad
        ? _VirtualGamepad(
            up: () => setState(() => _turn(0, -1)),
            down: () => setState(() => _turn(0, 1)),
            left: () => setState(() => _turn(-1, 0)),
            right: () => setState(() => _turn(1, 0)),
            a: () {
              if (_over) setState(_reset);
            },
            b: () => setState(_reset),
          )
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over) setState(_reset);
      },
      onPanEnd: (d) {
        final v = d.velocity.pixelsPerSecond;
        setState(() {
          if (v.dx.abs() > v.dy.abs()) {
            _turn(v.dx > 0 ? 1 : -1, 0);
          } else {
            _turn(0, v.dy > 0 ? 1 : -1);
          }
        });
      },
      child: CustomPaint(
        painter: _SnakePainter(_snake, _food, _over),
        size: Size.infinite,
      ),
    ),
  );
}

class _SnakePainter extends CustomPainter {
  final List<math.Point<int>> snake;
  final math.Point<int> food;
  final bool over;
  const _SnakePainter(this.snake, this.food, this.over);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff0c1720),
    );
    final cell = math.min(size.width / 15, size.height / 19).toDouble();
    final ox = (size.width - cell * 15) / 2, oy = (size.height - cell * 19) / 2;
    for (var y = 0; y < 19; y++) {
      for (var x = 0; x < 15; x++) {
        final r = Rect.fromLTWH(
          ox + x * cell,
          oy + y * cell,
          cell - 1,
          cell - 1,
        );
        canvas.drawRect(
          r,
          Paint()
            ..color = (x + y).isEven
                ? const Color(0xff15252e)
                : const Color(0xff112029),
        );
      }
    }
    canvas.drawCircle(
      Offset(ox + (food.x + .5) * cell, oy + (food.y + .5) * cell),
      cell * .30,
      Paint()..color = const Color(0xffff6878),
    );
    for (var i = snake.length - 1; i >= 0; i--) {
      final p = snake[i];
      final r = Rect.fromLTWH(
        ox + p.x * cell + 1,
        oy + p.y * cell + 1,
        cell - 3,
        cell - 3,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(cell * .22)),
        Paint()
          ..color = i == 0
              ? const Color(0xffb7f36b)
              : Color.lerp(
                  const Color(0xff68d391),
                  const Color(0xff25916a),
                  i / snake.length,
                )!,
      );
    }
    if (over) _center(canvas, size, 'GAME OVER', 'Dokun ve yeniden başla');
  }

  void _center(Canvas c, Size s, String t, String sub) {
    c.drawRect(
      Offset.zero & s,
      Paint()..color = Colors.black.withValues(alpha: .62),
    );
    final p = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: '$t\n',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 24,
        ),
        children: [
          TextSpan(
            text: sub,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    )..layout(maxWidth: s.width - 20);
    p.paint(c, Offset((s.width - p.width) / 2, (s.height - p.height) / 2));
  }

  @override
  bool shouldRepaint(covariant _SnakePainter old) => true;
}

// ---------------------------------------------------------------------------
// Brick breaker
// ---------------------------------------------------------------------------
class _BreakoutGame extends StatefulWidget {
  final bool showPad;
  const _BreakoutGame({required this.showPad});
  @override
  State<_BreakoutGame> createState() => _BreakoutState();
}

class _BreakoutState extends State<_BreakoutGame> {
  double _x = .5, _y = .72, _vx = .011, _vy = -.014, _paddle = .5;
  int _score = 0, _lives = 3, _level = 1;
  bool _over = false;
  Timer? _timer;
  List<bool> _bricks = List<bool>.filled(40, true);
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted && !_over) setState(_tick);
    });
  }

  void _tick() {
    _x += _vx;
    _y += _vy;
    if (_x < .025 || _x > .975) {
      _vx = -_vx;
      _x = _x.clamp(.025, .975).toDouble();
    }
    if (_y < .035) {
      _vy = _vy.abs();
      _y = .035;
    }
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 8; col++) {
        final i = row * 8 + col;
        if (!_bricks[i]) continue;
        final l = .035 + col * .12,
            r = l + .105,
            t = .075 + row * .072,
            b = t + .05;
        if (_x >= l - .018 &&
            _x <= r + .018 &&
            _y >= t - .018 &&
            _y <= b + .018) {
          _bricks[i] = false;
          _score += 10 * _level;
          _vy = -_vy;
          break;
        }
      }
    }
    if (_bricks.every((b) => !b)) {
      _level++;
      _bricks = List<bool>.filled(40, true);
      _vx *= 1.06;
      _vy *= 1.06;
      _serve();
    }
    if (_y > .86 && _y < .95 && (_x - _paddle).abs() < .16 && _vy > 0) {
      _vy = -_vy.abs();
      _vx = (_vx + (_x - _paddle) * .055).clamp(-.025, .025).toDouble();
    }
    if (_y > 1) {
      _lives--;
      if (_lives <= 0) {
        _over = true;
        return;
      }
      _serve();
    }
  }

  void _serve() {
    _x = .5;
    _y = .72;
    _vx = .011 * (_x - _paddle >= 0 ? 1 : -1);
    _vy = -.014;
  }

  void _move(double d) {
    if (!_over) {
      setState(() => _paddle = (_paddle + d).clamp(.12, .88).toDouble());
    }
  }

  void _reset() {
    setState(() {
      _x = .5;
      _y = .72;
      _vx = .011;
      _vy = -.014;
      _paddle = .5;
      _score = 0;
      _lives = 3;
      _level = 1;
      _over = false;
      _bricks = List<bool>.filled(40, true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ArcadeFrame(
    score: _over
        ? 'BİTTİ • $_score'
        : '$_score  •  SEVİYE $_level  •  ♥ $_lives',
    controls: widget.showPad
        ? _VirtualGamepad(left: () => _move(-.08), right: () => _move(.08))
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over) _reset();
      },
      onHorizontalDragUpdate: (d) => _move(d.primaryDelta! / 300),
      onTapDown: (d) => _move(
        d.localPosition.dx / MediaQuery.sizeOf(context).width - _paddle,
      ),
      child: CustomPaint(
        painter: _BreakPainter(_x, _y, _paddle, _bricks, _over),
        size: Size.infinite,
      ),
    ),
  );
}

class _BreakPainter extends CustomPainter {
  final double x, y, paddle;
  final List<bool> bricks;
  final bool over;
  const _BreakPainter(this.x, this.y, this.paddle, this.bricks, this.over);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xff111729));
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 8; col++) {
        if (!bricks[row * 8 + col]) continue;
        final r = Rect.fromLTWH(
          s.width * (.035 + col * .12),
          s.height * (.075 + row * .072),
          s.width * .105,
          s.height * .05,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()
            ..color = [
              const Color(0xfffb7185),
              const Color(0xfffb923c),
              const Color(0xfffacc15),
              const Color(0xff4ade80),
              const Color(0xff60a5fa),
            ][row],
        );
      }
    }
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x * s.width, y * s.height),
          width: 12,
          height: 12,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(paddle * s.width, s.height * .90),
          width: s.width * .26,
          height: 12,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xff62e6c7),
    );
    if (over) {
      c.drawRect(
        Offset.zero & s,
        Paint()..color = Colors.black.withValues(alpha: .6),
      );
      final p = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: const TextSpan(
          text: 'BİTTİ\nDokun ve yeniden başla',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 23,
          ),
        ),
      )..layout(maxWidth: s.width - 20);
      p.paint(c, Offset((s.width - p.width) / 2, (s.height - p.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _BreakPainter old) => true;
}

// ---------------------------------------------------------------------------
// Paddle duel
// ---------------------------------------------------------------------------
class _PongGame extends StatefulWidget {
  final bool showPad;
  const _PongGame({required this.showPad});
  @override
  State<_PongGame> createState() => _PongState();
}

class _PongState extends State<_PongGame> {
  double _bx = .5, _by = .5, _vx = .012, _vy = .008, _me = .5, _ai = .5;
  int _score = 0, _aiScore = 0;
  bool _over = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted && !_over) setState(_tick);
    });
  }

  void _tick() {
    _bx += _vx;
    _by += _vy;
    if (_by < .035 || _by > .965) {
      _vy = -_vy;
      _by = _by.clamp(.035, .965).toDouble();
    }
    _ai += (_by - _ai) * .035;
    if (_vx < 0 && _bx < .075 && (_by - _me).abs() < .14) {
      _vx = _vx.abs() * 1.025;
      _vy += (_by - _me) * .025;
    }
    if (_vx > 0 && _bx > .925 && (_by - _ai).abs() < .14) {
      _vx = -_vx.abs() * 1.015;
      _vy += (_by - _ai) * .015;
    }
    if (_bx < -.03 || _bx > 1.03) {
      if (_bx < 0) {
        _aiScore++;
        _vx = .012;
      } else {
        _score++;
        _vx = -.012;
      }
      _bx = .5;
      _by = .5;
      _vy = .008;
      if (_score >= 7 || _aiScore >= 7) _over = true;
    }
  }

  void _move(double d) {
    if (!_over) setState(() => _me = (_me + d).clamp(.12, .88).toDouble());
  }

  void _reset() {
    setState(() => _resetValues());
  }

  void _resetValues() {
    _bx = .5;
    _by = .5;
    _vx = .012;
    _vy = .008;
    _me = .5;
    _ai = .5;
    _score = 0;
    _aiScore = 0;
    _over = false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: _over
        ? '${_score > _aiScore ? 'KAZANDIN' : 'BİLGİSAYAR KAZANDI'} • $_score–$_aiScore'
        : '$_score  —  $_aiScore',
    controls: widget.showPad
        ? _VirtualGamepad(up: () => _move(-.08), down: () => _move(.08))
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over) _reset();
      },
      onVerticalDragUpdate: (d) => _move(d.primaryDelta! / 300),
      child: CustomPaint(
        painter: _PongPainter(_bx, _by, _me, _ai, _over),
        size: Size.infinite,
      ),
    ),
  );
}

class _PongPainter extends CustomPainter {
  final double bx, by, me, ai;
  final bool over;
  const _PongPainter(this.bx, this.by, this.me, this.ai, this.over);
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xff111729));
    final line = Paint()
      ..color = Colors.white24
      ..strokeWidth = 2;
    for (var y = 0.0; y < s.height; y += 18) {
      c.drawLine(Offset(s.width / 2, y), Offset(s.width / 2, y + 9), line);
    }
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s.width * .06, me * s.height),
          width: 10,
          height: s.height * .21,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xff60a5fa),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s.width * .94, ai * s.height),
          width: 10,
          height: s.height * .21,
        ),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xffff758f),
    );
    c.drawCircle(
      Offset(bx * s.width, by * s.height),
      7,
      Paint()..color = Colors.white,
    );
    if (over) {
      c.drawRect(
        Offset.zero & s,
        Paint()..color = Colors.black.withValues(alpha: .55),
      );
      final p = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: const TextSpan(
          text: 'MAÇ BİTTİ\nDokun ve rövanş al',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
      )..layout(maxWidth: s.width - 20);
      p.paint(c, Offset((s.width - p.width) / 2, (s.height - p.height) / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PongPainter old) => true;
}

// ---------------------------------------------------------------------------
// Falling-block puzzle
// ---------------------------------------------------------------------------
class _BlockDropGame extends StatefulWidget {
  final bool showPad;
  const _BlockDropGame({required this.showPad});
  @override
  State<_BlockDropGame> createState() => _BlockDropState();
}

class _BlockDropState extends State<_BlockDropGame> {
  static const _shapes = <List<List<int>>>[
    [
      [1, 1, 1, 1],
    ],
    [
      [1, 1],
      [1, 1],
    ],
    [
      [0, 1, 0],
      [1, 1, 1],
    ],
    [
      [1, 0, 0],
      [1, 1, 1],
    ],
    [
      [0, 0, 1],
      [1, 1, 1],
    ],
    [
      [1, 1, 0],
      [0, 1, 1],
    ],
    [
      [0, 1, 1],
      [1, 1, 0],
    ],
  ];
  final _random = math.Random();
  List<List<int>> _board = List.generate(20, (_) => List.filled(10, 0));
  Timer? _timer;
  int _kind = 0, _rotation = 0, _x = 4, _y = 0, _score = 0, _lines = 0;
  bool _over = false;
  List<List<int>> get _shape {
    var s = _shapes[_kind].map((r) => List<int>.from(r)).toList();
    for (var n = 0; n < _rotation; n++) {
      final h = s.length, w = s.first.length;
      s = List.generate(w, (yy) => List.generate(h, (xx) => s[h - 1 - xx][yy]));
    }
    return s;
  }

  @override
  void initState() {
    super.initState();
    _spawn();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && !_over) setState(_step);
    });
  }

  bool _can(int nx, int ny) {
    final s = _shape;
    for (var yy = 0; yy < s.length; yy++) {
      for (var xx = 0; xx < s[yy].length; xx++) {
        if (s[yy][xx] == 0) continue;
        final bx = nx + xx, by = ny + yy;
        if (bx < 0 ||
            bx >= 10 ||
            by >= 20 ||
            (by >= 0 && _board[by][bx] != 0)) {
          return false;
        }
      }
    }
    return true;
  }

  void _spawn() {
    _kind = _random.nextInt(_shapes.length);
    _rotation = 0;
    _x = 4;
    _y = 0;
    if (!_can(_x, _y)) _over = true;
  }

  void _step() {
    if (_can(_x, _y + 1)) {
      _y++;
      return;
    }
    final s = _shape;
    for (var yy = 0; yy < s.length; yy++) {
      for (var xx = 0; xx < s[yy].length; xx++) {
        if (s[yy][xx] != 0 && _y + yy >= 0) {
          _board[_y + yy][_x + xx] = _kind + 1;
        }
      }
    }
    final old = _board.length;
    _board.removeWhere((row) => row.every((v) => v != 0));
    final cleared = old - _board.length;
    if (cleared > 0) {
      _lines += cleared;
      _score += [0, 100, 300, 500, 800][cleared.clamp(0, 4).toInt()];
    }
    while (_board.length < 20) {
      _board.insert(0, List.filled(10, 0));
    }
    _spawn();
  }

  void _move(int dx) {
    if (!_over && _can(_x + dx, _y)) setState(() => _x += dx);
  }

  void _rotate() {
    if (_over) return;
    setState(() {
      final old = _rotation;
      _rotation = (_rotation + 1) % 4;
      if (!_can(_x, _y)) _rotation = old;
    });
  }

  void _softDrop() {
    if (!_over) setState(_step);
  }

  void _hardDrop() {
    if (_over) {
      _reset();
      return;
    }
    setState(() {
      while (_can(_x, _y + 1)) {
        _y++;
      }
      _step();
    });
  }

  void _reset() {
    setState(() {
      _board = List.generate(20, (_) => List.filled(10, 0));
      _score = 0;
      _lines = 0;
      _over = false;
      _spawn();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: _over ? 'BİTTİ • $_score' : '$_score PTS  •  $_lines SATIR',
    controls: widget.showPad
        ? _VirtualGamepad(
            left: () => _move(-1),
            right: () => _move(1),
            down: _softDrop,
            up: _hardDrop,
            a: _rotate,
            b: _reset,
          )
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over) _reset();
      },
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx.abs() > 7) _move(d.delta.dx > 0 ? 1 : -1);
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 0) _hardDrop();
      },
      child: CustomPaint(
        painter: _BlockPainter(_board, _shape, _x, _y, _kind, _over),
        size: Size.infinite,
      ),
    ),
  );
}

class _BlockPainter extends CustomPainter {
  final List<List<int>> board, shape;
  final int x, y, kind;
  final bool over;
  const _BlockPainter(
    this.board,
    this.shape,
    this.x,
    this.y,
    this.kind,
    this.over,
  );
  static const colors = [
    Color(0xff56cfe1),
    Color(0xffffc857),
    Color(0xffbb86fc),
    Color(0xff65d891),
    Color(0xffff7b89),
    Color(0xff6ea8fe),
    Color(0xffff9f68),
  ];
  @override
  void paint(Canvas c, Size s) {
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xff0c1320));
    final cell = math.min((s.width - 22) / 10, (s.height - 22) / 20).toDouble();
    final ox = (s.width - cell * 10) / 2, oy = (s.height - cell * 20) / 2;
    for (var yy = 0; yy < 20; yy++) {
      for (var xx = 0; xx < 10; xx++) {
        final v = board[yy][xx];
        _cell(
          c,
          Rect.fromLTWH(ox + xx * cell, oy + yy * cell, cell - 1, cell - 1),
          v == 0 ? const Color(0xff182334) : colors[(v - 1) % colors.length],
        );
      }
    }
    for (var yy = 0; yy < shape.length; yy++) {
      for (var xx = 0; xx < shape[yy].length; xx++) {
        if (shape[yy][xx] != 0 && y + yy >= 0) {
          _cell(
            c,
            Rect.fromLTWH(
              ox + (x + xx) * cell,
              oy + (y + yy) * cell,
              cell - 1,
              cell - 1,
            ),
            colors[kind % colors.length],
          );
        }
      }
    }
    if (over) {
      c.drawRect(
        Offset.zero & s,
        Paint()..color = Colors.black.withValues(alpha: .6),
      );
      final p = TextPainter(
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        text: const TextSpan(
          text: 'KULE DOLDU\nYeniden başlat',
          style: TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w900,
          ),
        ),
      )..layout(maxWidth: s.width - 20);
      p.paint(c, Offset((s.width - p.width) / 2, (s.height - p.height) / 2));
    }
  }

  void _cell(Canvas c, Rect r, Color color) {
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(1), const Radius.circular(3)),
      Paint()..color = color,
    );
    c.drawRect(
      Rect.fromLTWH(r.left + 3, r.top + 3, r.width - 6, 2),
      Paint()..color = Colors.white.withValues(alpha: .19),
    );
  }

  @override
  bool shouldRepaint(covariant _BlockPainter old) => true;
}

// ---------------------------------------------------------------------------
// Reversi with a lightweight, legal-move-aware CPU opponent
// ---------------------------------------------------------------------------
class _ReversiGame extends StatefulWidget {
  const _ReversiGame();
  @override
  State<_ReversiGame> createState() => _ReversiState();
}

class _ReversiState extends State<_ReversiGame> {
  static const _dirs = <math.Point<int>>[
    math.Point(-1, -1),
    math.Point(0, -1),
    math.Point(1, -1),
    math.Point(-1, 0),
    math.Point(1, 0),
    math.Point(-1, 1),
    math.Point(0, 1),
    math.Point(1, 1),
  ];
  late List<int> _board;
  bool _thinking = false, _finished = false;
  String _notice = 'Sen siyah taşlarla başlıyorsun.';
  int _moves = 0;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _board = List.filled(64, 0);
    _board[27] = 2;
    _board[28] = 1;
    _board[35] = 1;
    _board[36] = 2;
    _thinking = false;
    _finished = false;
    _moves = 0;
    _notice = 'Sen siyah taşlarla başlıyorsun.';
  }

  List<int> _flips(int index, int player) {
    if (_board[index] != 0) return const [];
    final x = index % 8, y = index ~/ 8;
    final result = <int>[];
    for (final d in _dirs) {
      var xx = x + d.x, yy = y + d.y;
      final line = <int>[];
      while (xx >= 0 &&
          xx < 8 &&
          yy >= 0 &&
          yy < 8 &&
          _board[yy * 8 + xx] == 3 - player) {
        line.add(yy * 8 + xx);
        xx += d.x;
        yy += d.y;
      }
      if (line.isNotEmpty &&
          xx >= 0 &&
          xx < 8 &&
          yy >= 0 &&
          yy < 8 &&
          _board[yy * 8 + xx] == player) {
        result.addAll(line);
      }
    }
    return result;
  }

  List<int> _legal(int player) => [
    for (var i = 0; i < 64; i++)
      if (_flips(i, player).isNotEmpty) i,
  ];
  void _place(int index, int player) {
    final flips = _flips(index, player);
    if (flips.isEmpty) return;
    _board[index] = player;
    for (final i in flips) {
      _board[i] = player;
    }
    _moves++;
  }

  void _tap(int index) {
    if (_thinking || _finished || _flips(index, 1).isEmpty) return;
    setState(() => _place(index, 1));
    final cpuMoves = _legal(2);
    if (cpuMoves.isEmpty) {
      if (_legal(1).isEmpty) {
        _finish();
      } else {
        setState(() => _notice = 'Rakibin geçiyor; tekrar senin sıran.');
      }
      return;
    }
    setState(() => _thinking = true);
    Future<void>.delayed(const Duration(milliseconds: 420), () => _cpuTurn());
  }

  void _cpuTurn() {
    if (!mounted) return;
    final moves = _legal(2);
    if (moves.isNotEmpty) {
      moves.sort((a, b) => _moveValue(b).compareTo(_moveValue(a)));
      _place(moves.first, 2);
    }
    final playerMoves = _legal(1);
    final cpuMoves = _legal(2);
    if (playerMoves.isEmpty && cpuMoves.isEmpty) {
      _finish();
      return;
    }
    setState(() {
      _thinking = false;
      _notice = playerMoves.isEmpty ? 'Bu tur sen geçiyorsun.' : 'Sıra sende.';
    });
    if (playerMoves.isEmpty && cpuMoves.isNotEmpty) {
      setState(() => _thinking = true);
      Future<void>.delayed(const Duration(milliseconds: 350), () => _cpuTurn());
    }
  }

  int _moveValue(int index) {
    const corners = {0, 7, 56, 63};
    if (corners.contains(index)) return 1000 + _flips(index, 2).length;
    final x = index % 8, y = index ~/ 8;
    final edge = x == 0 || x == 7 || y == 0 || y == 7;
    return _flips(index, 2).length + (edge ? 4 : 0);
  }

  void _finish() {
    final black = _board.where((v) => v == 1).length,
        white = _board.where((v) => v == 2).length;
    setState(() {
      _finished = true;
      _thinking = false;
      _notice = black == white
          ? 'Berabere • $black – $white'
          : black > white
          ? 'Kazandın • $black – $white'
          : 'Bilgisayar kazandı • $black – $white';
    });
  }

  @override
  Widget build(BuildContext c) {
    final legal = _thinking || _finished ? const <int>[] : _legal(1);
    final black = _board.where((v) => v == 1).length,
        white = _board.where((v) => v == 2).length;
    return _ArcadeFrame(
      score: _finished ? 'SONUÇ $_moves HAMLE' : 'SEN $black  •  CPU $white',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 13, color: Color(0xff11151c)),
                const SizedBox(width: 5),
                Text(
                  'SEN $black',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Text('CPU', style: TextStyle(color: Colors.white70)),
                const SizedBox(width: 5),
                const Icon(Icons.circle, size: 13, color: Color(0xfff3f0df)),
                IconButton(
                  onPressed: () => setState(_reset),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: GridView.builder(
                  padding: const EdgeInsets.all(5),
                  itemCount: 64,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemBuilder: (_, i) {
                    final isLegal = legal.contains(i);
                    return GestureDetector(
                      onTap: () => _tap(i),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xff23744f),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: _board[i] != 0
                              ? Container(
                                  width: 25,
                                  height: 25,
                                  decoration: BoxDecoration(
                                    color: _board[i] == 1
                                        ? const Color(0xff10151a)
                                        : const Color(0xfff4f0dd),
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black38,
                                        blurRadius: 3,
                                        offset: Offset(1, 2),
                                      ),
                                    ],
                                  ),
                                )
                              : isLegal
                              ? Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0x995ce1c1),
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
            child: Text(
              _thinking ? 'Bilgisayar düşünüyor…' : _notice,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mines: safe first move, flagging, flood reveal, win/loss state
// ---------------------------------------------------------------------------
class _MinesGame extends StatefulWidget {
  const _MinesGame();
  @override
  State<_MinesGame> createState() => _MinesState();
}

class _MinesState extends State<_MinesGame> {
  static const _side = 8, _mineCount = 10;
  final _random = math.Random();
  late List<bool> _mines, _open, _flags;
  bool _over = false, _won = false, _started = false;
  int _opened = 0;
  @override
  void initState() {
    super.initState();
    _new();
  }

  void _new() {
    _mines = List.filled(_side * _side, false);
    _open = List.filled(_side * _side, false);
    _flags = List.filled(_side * _side, false);
    _over = false;
    _won = false;
    _started = false;
    _opened = 0;
  }

  void _plant(int safe) {
    final choices = [
      for (var i = 0; i < _side * _side; i++)
        if (i != safe) i,
    ]..shuffle(_random);
    for (final i in choices.take(_mineCount)) {
      _mines[i] = true;
    }
    _started = true;
  }

  int _around(int i) {
    final x = i % _side, y = i ~/ _side;
    var count = 0;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final xx = x + dx, yy = y + dy;
        if (xx >= 0 &&
            xx < _side &&
            yy >= 0 &&
            yy < _side &&
            _mines[yy * _side + xx]) {
          count++;
        }
      }
    }
    return count;
  }

  void _reveal(int i) {
    if (_over || _won || _open[i] || _flags[i]) return;
    if (!_started) _plant(i);
    if (_mines[i]) {
      setState(() => _over = true);
      return;
    }
    final queue = <int>[i];
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      if (_open[n] || _flags[n] || _mines[n]) continue;
      _open[n] = true;
      _opened++;
      if (_around(n) == 0) {
        final x = n % _side, y = n ~/ _side;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx >= 0 && xx < _side && yy >= 0 && yy < _side) {
              queue.add(yy * _side + xx);
            }
          }
        }
      }
    }
    if (_opened >= _side * _side - _mineCount) _won = true;
    setState(() {});
  }

  void _flag(int i) {
    if (_over || _won || _open[i]) return;
    setState(() => _flags[i] = !_flags[i]);
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: _won
        ? 'KAZANDIN'
        : _over
        ? 'MAYINA BASTIN'
        : 'MAYIN ${_flags.where((v) => v).length}/$_mineCount',
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 5),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Açmak için dokun • bayrak için basılı tut',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
              IconButton(
                onPressed: () => setState(_new),
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: GridView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _side * _side,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _side,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemBuilder: (_, i) {
                  final showMine = _over && _mines[i];
                  final n = _around(i);
                  return GestureDetector(
                    onLongPress: () => _flag(i),
                    onTap: () => _reveal(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      decoration: BoxDecoration(
                        color: _open[i]
                            ? const Color(0xff1e3440)
                            : const Color(0xff344754),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .06),
                        ),
                      ),
                      child: Center(
                        child: showMine
                            ? const Icon(
                                Icons.brightness_5_rounded,
                                color: Color(0xffff6878),
                                size: 18,
                              )
                            : _flags[i]
                            ? const Icon(
                                Icons.flag_rounded,
                                color: Color(0xffffc857),
                                size: 17,
                              )
                            : _open[i] && n > 0
                            ? Text(
                                '$n',
                                style: TextStyle(
                                  color: [
                                    Colors.transparent,
                                    const Color(0xff66c9ff),
                                    const Color(0xff70df93),
                                    const Color(0xffff8790),
                                    const Color(0xffc3a1ff),
                                    Colors.orange,
                                  ][n.clamp(0, 5).toInt()],
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              )
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_over || _won)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FilledButton.icon(
              onPressed: () => setState(_new),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Yeniden oyna'),
            ),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Number merge puzzle
// ---------------------------------------------------------------------------
class _MergeGame extends StatefulWidget {
  const _MergeGame();
  @override
  State<_MergeGame> createState() => _MergeState();
}

class _MergeState extends State<_MergeGame> {
  final _random = math.Random();
  List<int> _board = List.filled(16, 0);
  int _score = 0;
  bool _over = false, _won = false;

  @override
  void initState() {
    super.initState();
    _new();
  }

  void _new() {
    _board = List.filled(16, 0);
    _score = 0;
    _over = false;
    _won = false;
    _add();
    _add();
  }

  void _add() {
    final empty = [
      for (var i = 0; i < 16; i++)
        if (_board[i] == 0) i,
    ];
    if (empty.isEmpty) return;
    final index = empty[_random.nextInt(empty.length)];
    _board[index] = _random.nextDouble() < .9 ? 2 : 4;
  }

  void _move(int direction) {
    if (_over || _won) return;
    final old = List<int>.from(_board);
    final next = List<int>.filled(16, 0);
    var changed = false;
    for (var line = 0; line < 4; line++) {
      var values = [
        for (var i = 0; i < 4; i++)
          direction <= 2 ? old[line * 4 + i] : old[i * 4 + line],
      ];
      if (direction == 2 || direction == 3) {
        values = values.reversed.toList();
      }
      final compact = values.where((value) => value != 0).toList();
      for (var i = 0; i < compact.length - 1; i++) {
        if (compact[i] == compact[i + 1]) {
          compact[i] *= 2;
          _score += compact[i];
          compact.removeAt(i + 1);
        }
      }
      while (compact.length < 4) {
        compact.add(0);
      }
      if (direction == 2 || direction == 3) {
        final reversed = compact.reversed.toList();
        compact
          ..clear()
          ..addAll(reversed);
      }
      for (var i = 0; i < 4; i++) {
        final index = direction <= 2 ? line * 4 + i : i * 4 + line;
        next[index] = compact[i];
        if (next[index] != old[index]) changed = true;
      }
    }
    if (!changed) return;
    setState(() {
      _board = next;
      _add();
      if (_board.contains(2048)) _won = true;
      if (!_movesAvailable()) _over = true;
    });
  }

  bool _movesAvailable() {
    for (var i = 0; i < 16; i++) {
      if (_board[i] == 0) return true;
      final x = i % 4, y = i ~/ 4;
      if (x < 3 && _board[i] == _board[i + 1]) return true;
      if (y < 3 && _board[i] == _board[i + 4]) return true;
    }
    return false;
  }

  Color _tile(int value) {
    if (value == 0) return const Color(0xff182735);
    final power = (math.log(value) / math.ln2).round();
    const palette = [
      Color(0xff334155),
      Color(0xff2b83a6),
      Color(0xff387e9b),
      Color(0xff6d73bc),
      Color(0xffb36ca6),
      Color(0xffdd865c),
      Color(0xffe6bd58),
    ];
    return palette[power.clamp(0, palette.length - 1).toInt()];
  }

  @override
  Widget build(BuildContext context) {
    return _ArcadeFrame(
      score: _won
          ? '2048 • $_score'
          : _over
          ? 'SON • $_score'
          : '$_score PUAN',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Kaydırarak birleştir',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(_new),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: GestureDetector(
                  onHorizontalDragEnd: (details) =>
                      _move((details.primaryVelocity ?? 0) > 0 ? 2 : 1),
                  onVerticalDragEnd: (details) =>
                      _move((details.primaryVelocity ?? 0) > 0 ? 3 : 4),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: 16,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemBuilder: (context, index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      decoration: BoxDecoration(
                        color: _tile(_board[index]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          _board[index] == 0 ? '' : '${_board[index]}',
                          style: TextStyle(
                            color: _board[index] >= 16
                                ? Colors.white
                                : const Color(0xffeef5f5),
                            fontSize: _board[index] >= 1024 ? 18 : 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_won || _over)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: FilledButton.icon(
                onPressed: () => setState(_new),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Yeni oyun'),
              ),
            ),
        ],
      ),
    );
  }
}
