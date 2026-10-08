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
// Piksel Macerası: Super Mario tarzı yan kaydırmalı platform oyunu.
// Girişte karakter seçimi (Şantiye Şefi / Programcı), üç bölüm, altın,
// soru blokları, düşmanlar, can ve bayrak hedefi.
// ---------------------------------------------------------------------------
enum _PlatformerHero { chief, coder }

// Çekiçli şef daha hızlı koşar; programcı daha yükseğe zıplar.
const double _chiefRun = .175;
const double _coderRun = .128;
const double _chiefJump = -.38;
const double _coderJump = -.42;
// Ivme: programci daha yavas ama daha cevik hizlanir; sef ust hizada kalir.
const double _chiefAccel = .011;
const double _coderAccel = .0135;
// Çekiç vuruş menzili: şefin çekici üç kat uzundur (eski 1.45 → 4.35 karo).
// Böylece önündeki düşmanı ve karoları çok daha uzaktan biçer.
const double _hammerReach = 4.35;
const double _hammerBehind = .9;
const double _hammerVertical = 1.15;
// Seviye başına koşu/zıplama ivmesine eklenen büyüme katsayısı.
const double _growthPerLevel = .055;

class _HeroInfo {
  final String name;
  final String tagline;
  final String ability;
  final double runSpeed;
  final double jumpSpeed;
  final double accel;
  final double runStat;
  final double jumpStat;
  const _HeroInfo(
    this.name,
    this.tagline,
    this.ability,
    this.runSpeed,
    this.jumpSpeed,
    this.accel,
    this.runStat,
    this.jumpStat,
  );
}

const Map<_PlatformerHero, _HeroInfo> _heroInfo = {
  _PlatformerHero.chief: _HeroInfo(
    'Şantiye Şefi',
    'Kasklı, yelekli; elinde üç kat uzun çekiç.',
    'Hızlı koşar · çekici üç kat erişir, tuğla/sandık/varil kırar · alet kutusu: YER SARSINTISI',
    _chiefRun,
    _chiefJump,
    _chiefAccel,
    5,
    3,
  ),
  _PlatformerHero.coder: _HeroInfo(
    'Programcı',
    'Kapüşonlu, gözlüklü; elinde USB bellek.',
    'Yükseğe zıplar · USB kıvılcımıyla uzaktan vurur · alet kutusu: ÜÇLÜ KIVILCIM',
    _coderRun,
    _coderJump,
    _coderAccel,
    3,
    5,
  ),
};

enum _Phase { select, ready, playing, dying, clear, gameover, win }

/// Kahramanın sandıktan çıkan alet kutusuyla kazandığı geçici özel silah.
/// quake: çekicin yeri sarsar (şef) · spread: üçlü kıvılcım yelpazesi (programcı).
enum _SpecialWeapon { quake, spread }

/// Sekiz farklı düşman türü: her biri ayrı davranış ve ayrı görüntü.
/// nut: kestane (ezilir) · spiky: dikenli (ezilmez) · flyer: uçan yarasa,
/// hopper: sıçrayan örümcek · turret: fışkıran bitki · guard: kalkanlı muhafız,
/// brute: ağır kaya golemi (3 can) · charger: hızlanıp saldıran koç.
enum _EnemyKind { nut, spiky, flyer, hopper, turret, guard, brute, charger }

enum _PickupKind { coin, heart, star, gem, weapon }

int _enemyStartHp(_EnemyKind kind) => switch (kind) {
  _EnemyKind.guard => 2,
  _EnemyKind.charger => 2,
  _EnemyKind.brute => 3,
  _ => 1,
};

class _Enemy {
  double x;
  double y;
  double vy = 0;
  int dir = -1;
  final _EnemyKind kind;
  final double homeY;
  int hp;
  int cool;
  int hurt = 0;
  // Koç için hücum sayacı.
  int charge = 0;
  bool dead = false;
  bool remove = false;
  int deadTicks = 0;
  double t = 0;
  _Enemy(this.x, this.y, _EnemyKind kind, this.homeY)
      : kind = kind,
        hp = _enemyStartHp(kind),
        cool = switch (kind) {
          _EnemyKind.turret => 70,
          _EnemyKind.charger => 90,
          _ => 40,
        };
}

class _Pickup {
  double x;
  double y;
  double vy;
  final _PickupKind kind;
  int life = 560;
  bool grounded = false;
  bool remove = false;
  int t = 0;
  _Pickup(this.x, this.y, this.vy, this.kind);
}

class _Spark {
  double x;
  double y;
  final double vx;
  final double vy;
  int life = 70;
  bool dead = false;
  _Spark(this.x, this.y, this.vx, [this.vy = 0]);
}

/// Taret fışkırtması: yavaş ama üzerinden atlanamayan mermi.
class _Bolt {
  double x;
  double y;
  final double vx;
  final double vy;
  int life = 170;
  bool dead = false;
  _Bolt(this.x, this.y, this.vx, this.vy);
}

class _Dust {
  double x;
  double y;
  final double vx;
  double vy;
  int life = 18;
  bool remove = false;
  _Dust(this.x, this.y, this.vx, this.vy);
}

class _PopFx {
  final double x;
  double y;
  final String text;
  final Color color;
  int life = 28;
  _PopFx(this.x, this.y, this.text, this.color);
}

class _Debris {
  double x;
  double y;
  final double vx;
  double vy;
  int life = 32;
  _Debris(this.x, this.y, this.vx, this.vy);
}

/// Her bölüm kendi paletini kullanır: çayır, çöl gün batımı, gece fabrikası.
class _LevelTheme {
  final String name;
  final List<Color> sky;
  final Color ground, groundTop, groundShade;
  final Color hill, hillFar, cloud;
  final Color brick, brickTop, platform, platformTop;
  final Color block, blockTop;
  final Color pipe, pipeDark;
  final bool night;
  const _LevelTheme(
    this.name,
    this.sky,
    this.ground,
    this.groundTop,
    this.groundShade,
    this.hill,
    this.hillFar,
    this.cloud,
    this.brick,
    this.brickTop,
    this.platform,
    this.platformTop,
    this.block,
    this.blockTop,
    this.pipe,
    this.pipeDark,
    this.night,
  );
}

const List<_LevelTheme> _levelThemes = [
  _LevelTheme(
    'Çayır',
    [Color(0xff0f2a4d), Color(0xff2f6ea8), Color(0xff8fc7e8)],
    Color(0xff7a4a21), Color(0xff3fae5a), Color(0xff2b7d41),
    Color(0x33236a4b), Color(0x1f2f8a5c), Color(0x55ffffff),
    Color(0xffc46a2b), Color(0xffe0873f),
    Color(0xff6b7280), Color(0xff9ca3af),
    Color(0xfff6b93b), Color(0xffffd97a),
    Color(0xff16a34a), Color(0xff22c55e),
    false,
  ),
  _LevelTheme(
    'Çöl',
    [Color(0xff4a1d3f), Color(0xffa8496b), Color(0xfff0a35e)],
    Color(0xff9c6b32), Color(0xffe2b56b), Color(0xffb98a45),
    Color(0x447a4a21), Color(0x33a8496b), Color(0x44ffd9a0),
    Color(0xffb06a3a), Color(0xffd98a52),
    Color(0xff8a6a4a), Color(0xffb08a63),
    Color(0xfff6b93b), Color(0xffffd97a),
    Color(0xff8a7a4a), Color(0xffa89a5a),
    false,
  ),
  _LevelTheme(
    'Gece',
    [Color(0xff05070f), Color(0xff141a33), Color(0xff2b2f5c)],
    Color(0xff3c3f4a), Color(0xff5a6478), Color(0xff2a2d38),
    Color(0x33202546), Color(0x22262c52), Color(0x22aabfff),
    Color(0xff6b4a7a), Color(0xff8a5f9c),
    Color(0xff4a5568), Color(0xff6b7a92),
    Color(0xffd9a13b), Color(0xffffd97a),
    Color(0xff3a7a5a), Color(0xff4aa57a),
    true,
  ),
];

/// Oyun sesleri Android tarafında SoundPool ile çalınır; ek bağımlılık yok.
/// Platform kanalı yoksa (örneğin masaüstü/önizleme) sessizce atlanır.
const MethodChannel _arcadeSfxChannel = MethodChannel('zerolog/system');
bool _arcadeSfxMuted = false;

void _arcadePlaySfx(String name) {
  if (_arcadeSfxMuted) return;
  _arcadeSfxChannel
      .invokeMethod<void>('playArcadeSfx', <String, String>{'name': name})
      .catchError((Object _) {});
}

/// 14 satırlık ASCII seviye üretici.
/// '#' zemin, '=' platform, 'B' tuğla, '?' soru bloğu, 'H' can bloğu,
/// 'V' sandık, 'W' varil, 'K' alet kutusu (üçü de kırılır ve ödül düşürür),
/// 'P' boru, 'o' altın, 'F' bayrak, '@' doğuş noktası.
/// Düşmanlar: 'E' kestane, 'S' dikenli, 'Y' uçan yarasa, 'J' sıçrayan,
/// 'n' taret, 'G' kalkanlı muhafız, 'X' kaya golemi, 'C' koç.
class _LevelBuilder {
  final List<String> rows;
  _LevelBuilder(int cols) : rows = List.filled(14, '.' * cols);

  void put(int row, int col, String ch) {
    if (row < 0 || row >= rows.length || col < 0 || col >= rows[row].length) {
      return;
    }
    rows[row] = rows[row].substring(0, col) + ch + rows[row].substring(col + 1);
  }

  void fillRange(int row, int from, int to, String ch) {
    for (var col = from; col <= to; col++) {
      put(row, col, ch);
    }
  }

  void ground(int from, int to) {
    fillRange(12, from, to, '#');
    fillRange(13, from, to, '#');
  }

  void coins(int row, Iterable<int> cols) {
    for (final col in cols) {
      put(row, col, 'o');
    }
  }

  void pipe(int col) {
    fillRange(11, col, col + 1, 'P');
    fillRange(10, col, col + 1, 'P');
  }

  void stairsUp(int from, int steps) {
    for (var i = 0; i < steps; i++) {
      for (var r = 0; r <= i; r++) {
        put(11 - r, from + i, '#');
      }
    }
  }
}

List<String> _buildPlatformLevel(int index) {
  switch (index) {
    case 1:
      return _platformLevel2();
    case 2:
      return _platformLevel3();
    default:
      return _platformLevel1();
  }
}

List<String> _platformLevel1() {
  final b = _LevelBuilder(92);
  b.ground(0, 29);
  b.ground(33, 54);
  b.ground(58, 77);
  b.ground(81, 91);
  b.fillRange(8, 10, 10, '?');
  b.fillRange(8, 11, 11, 'B');
  b.fillRange(8, 12, 12, '?');
  b.fillRange(8, 20, 20, 'H');
  b.fillRange(8, 21, 22, 'B');
  b.fillRange(5, 17, 19, 'B');
  b.fillRange(9, 26, 28, '=');
  b.fillRange(8, 33, 35, '=');
  b.fillRange(9, 40, 42, '=');
  b.fillRange(9, 50, 52, '=');
  b.fillRange(7, 62, 64, '=');
  b.pipe(45);
  b.pipe(70);
  b.stairsUp(85, 3);
  // Kırılabilir sandık ve variller; içinden ödül çıkar.
  b.put(11, 14, 'V');
  b.put(11, 15, 'V');
  b.put(11, 24, 'W');
  b.put(11, 47, 'W');
  b.put(11, 48, 'W');
  b.put(11, 76, 'V');
  b.coins(11, [6, 7, 8]);
  b.coins(4, [18]);
  b.coins(7, [33, 34, 35]);
  b.coins(8, [26, 27, 28]);
  b.coins(8, [50, 52]);
  b.coins(10, [30, 31, 32]);
  b.coins(10, [55, 56, 57]);
  b.coins(10, [78, 79, 80]);
  b.coins(6, [62, 63, 64]);
  // Düşman kadrosu: altı türün beşi burada tanıtılır.
  b.put(11, 16, 'E');
  b.put(11, 28, 'C');
  b.put(11, 36, 'E');
  b.put(11, 44, 'X');
  b.put(11, 50, 'E');
  b.put(11, 62, 'G');
  b.put(11, 68, 'n');
  b.put(11, 73, 'J');
  b.put(11, 84, 'S');
  b.put(6, 26, 'Y');
  b.put(5, 55, 'Y');
  // Özel silah sandığı.
  b.put(11, 40, 'K');
  b.put(11, 2, '@');
  b.put(6, 89, 'F');
  return b.rows;
}

List<String> _platformLevel2() {
  final b = _LevelBuilder(100);
  b.ground(0, 19);
  b.ground(24, 39);
  b.ground(44, 63);
  b.ground(68, 87);
  b.ground(92, 99);
  b.fillRange(8, 6, 7, 'B');
  b.fillRange(8, 8, 8, '?');
  b.fillRange(8, 9, 9, 'B');
  b.fillRange(8, 13, 13, 'H');
  b.fillRange(5, 15, 17, '=');
  b.fillRange(9, 26, 27, 'B');
  b.fillRange(9, 28, 28, '?');
  b.pipe(32);
  b.fillRange(8, 36, 38, '=');
  b.fillRange(9, 46, 48, '=');
  b.fillRange(7, 50, 52, '=');
  b.fillRange(8, 56, 56, '?');
  b.fillRange(8, 57, 57, 'B');
  b.fillRange(8, 58, 58, '?');
  b.pipe(74);
  b.fillRange(9, 78, 80, 'B');
  b.fillRange(6, 83, 85, '=');
  b.stairsUp(93, 3);
  b.put(11, 12, 'V');
  b.put(11, 13, 'V');
  b.put(11, 35, 'W');
  b.put(11, 53, 'V');
  b.put(11, 60, 'W');
  b.put(11, 86, 'W');
  b.coins(11, [3, 4]);
  b.coins(4, [15, 17]);
  b.coins(7, [36, 37, 38]);
  b.coins(6, [50, 52]);
  b.coins(5, [84]);
  b.coins(10, [20, 21, 22, 23]);
  b.coins(10, [40, 41, 42, 43]);
  b.coins(10, [64, 65, 66, 67]);
  b.coins(10, [88, 89, 90, 91]);
  b.put(11, 5, 'E');
  b.put(11, 18, 'E');
  b.put(11, 26, 'X');
  b.put(11, 30, 'E');
  b.put(11, 37, 'S');
  b.put(11, 46, 'n');
  b.put(11, 49, 'E');
  b.put(11, 50, 'C');
  b.put(11, 56, 'G');
  b.put(11, 62, 'E');
  b.put(11, 71, 'J');
  b.put(11, 78, 'G');
  b.put(11, 80, 'E');
  b.put(11, 83, 'C');
  b.put(11, 84, 'S');
  b.put(5, 30, 'Y');
  b.put(4, 60, 'Y');
  b.put(4, 85, 'Y');
  b.put(11, 34, 'K');
  b.put(11, 76, 'K');
  b.put(11, 2, '@');
  b.put(6, 97, 'F');
  return b.rows;
}

List<String> _platformLevel3() {
  final b = _LevelBuilder(110);
  b.ground(0, 17);
  b.ground(22, 37);
  b.ground(42, 57);
  b.ground(62, 75);
  b.ground(80, 95);
  b.ground(100, 109);
  b.fillRange(8, 5, 5, '?');
  b.fillRange(8, 6, 7, 'B');
  b.fillRange(5, 10, 12, '=');
  b.fillRange(9, 24, 25, 'B');
  b.fillRange(9, 26, 26, '?');
  b.fillRange(9, 27, 27, 'B');
  b.fillRange(7, 30, 32, '=');
  b.fillRange(8, 34, 34, 'H');
  b.pipe(48);
  b.fillRange(9, 52, 54, '=');
  b.fillRange(7, 55, 57, '=');
  b.fillRange(9, 64, 66, '=');
  b.pipe(70);
  b.fillRange(8, 84, 85, 'B');
  b.fillRange(8, 86, 86, '?');
  b.fillRange(6, 90, 92, '=');
  b.stairsUp(101, 4);
  b.put(11, 9, 'V');
  b.put(11, 10, 'V');
  b.put(11, 25, 'W');
  b.put(11, 44, 'V');
  b.put(11, 68, 'W');
  b.put(11, 88, 'V');
  b.put(11, 104, 'W');
  b.coins(4, [10, 12]);
  b.coins(6, [30, 31, 32]);
  b.coins(8, [52, 54]);
  b.coins(8, [65]);
  b.coins(5, [91]);
  b.coins(10, [18, 19, 20, 21]);
  b.coins(10, [38, 39, 40, 41]);
  b.coins(10, [58, 59, 60, 61]);
  b.coins(9, [76, 77, 78, 79]);
  b.coins(10, [96, 97, 98, 99]);
  b.put(11, 7, 'E');
  b.put(11, 24, 'X');
  b.put(11, 28, 'E');
  b.put(11, 33, 'S');
  b.put(11, 36, 'G');
  b.put(11, 45, 'E');
  b.put(11, 46, 'C');
  b.put(11, 50, 'n');
  b.put(11, 51, 'S');
  b.put(11, 55, 'J');
  b.put(11, 62, 'E');
  b.put(11, 73, 'G');
  b.put(11, 82, 'E');
  b.put(11, 84, 'C');
  b.put(11, 85, 'J');
  b.put(11, 90, 'S');
  b.put(11, 92, 'n');
  b.put(11, 94, 'G');
  b.put(11, 106, 'E');
  b.put(5, 20, 'Y');
  b.put(4, 45, 'Y');
  b.put(6, 66, 'Y');
  b.put(5, 90, 'Y');
  b.put(11, 65, 'K');
  b.put(11, 102, 'K');
  b.put(11, 2, '@');
  b.put(6, 107, 'F');
  return b.rows;
}

class _PlatformerGame extends StatefulWidget {
  final bool showPad;
  const _PlatformerGame({required this.showPad});
  @override
  State<_PlatformerGame> createState() => _PlatformerState();
}

class _PlatformerState extends State<_PlatformerGame> {
  static const int _rows = 14;
  static const double _pw = .72;
  static const double _ph = .88;
  static const double _gravity = .016;
  static const double _maxFall = .30;
  static const int _levelCount = 3;

  _Phase _phase = _Phase.select;
  _PlatformerHero? _hero;
  int _levelIndex = 0;
  List<String> _grid = const [];
  int _cols = 0;
  int _flagCol = 0;
  double _goalX = 1;
  _LevelTheme _theme = _levelThemes.first;

  double _x = 0, _y = 0, _vx = 0, _vy = 0;
  int _facing = 1;
  bool _grounded = false;
  int _score = 0, _coinCount = 0, _lives = 3, _time = 150;
  int _clock = 0, _phaseTicks = 0, _timeTicks = 0, _clearBonus = 0;
  int _invuln = 0, _jumpBuffer = 0, _attackAnim = 0, _attackCd = 0;
  int _coyote = 0, _star = 0, _stepTick = 0, _broken = 0;
  // Büyüme: XP toplandıkça kahraman seviye atlar ve güçlenir.
  int _level = 1, _xp = 0, _xpNext = 120, _levelFlash = 0;
  // Alet kutusundan gelen geçici özel silah ve ekran sarsıntısı.
  _SpecialWeapon? _special;
  int _specialTicks = 0, _shake = 0;
  double _squash = 0;
  bool _wasGrounded = true;
  bool _jumpHeld = false, _jumpCut = false;
  bool _holdLeft = false, _holdRight = false;
  double _camera = 0;
  double _viewCols = 13;

  final List<_Enemy> _enemies = [];
  final List<_Pickup> _pickups = [];
  final List<_Spark> _sparks = [];
  final List<_Bolt> _bolts = [];
  final List<_Dust> _dust = [];
  final List<_PopFx> _pops = [];
  final List<_Debris> _debris = [];
  final Map<String, int> _bumps = {};
  final math.Random _rng = math.Random(20261007);

  Timer? _timer;

  _HeroInfo? get _info => _hero == null ? null : _heroInfo[_hero];
  bool get _powered => _star > 0;

  /// Seviyeye bağlı büyüme çarpanı: koşu, zıplama ve saldırı gücünü artırır.
  double get _growth => 1 + (_level - 1) * _growthPerLevel;
  bool get _specialActive => _special != null && _specialTicks > 0;

  /// XP kazanır; eşiği aşınca seviye atlar, can yenilenir ve görsel efektler
  /// tetiklenir. Yeni seviyede bir sonraki eşik büyüyerek zorlaşır.
  void _gainXp(int amount) {
    _xp += amount;
    while (_xp >= _xpNext) {
      _xp -= _xpNext;
      _level++;
      _xpNext = (_xpNext * 1.4).round();
      _lives = math.min(5, _lives + 1);
      _levelFlash = 90;
      _shake = 10;
      _pops.add(
        _PopFx(
          _x,
          _y - .8,
          'SEVİYE $_level!',
          const Color(0xffffe066),
        ),
      );
      for (var i = 0; i < 8; i++) {
        _dust.add(
          _Dust(_x + .1 + i * .06, _y + .1, (i - 4) * .04, -.06),
        );
      }
      _arcadePlaySfx('power');
    }
  }

  static _EnemyKind _kindFor(String ch) {
    switch (ch) {
      case 'S':
        return _EnemyKind.spiky;
      case 'Y':
        return _EnemyKind.flyer;
      case 'J':
        return _EnemyKind.hopper;
      case 'n':
        return _EnemyKind.turret;
      case 'G':
        return _EnemyKind.guard;
      case 'X':
        return _EnemyKind.brute;
      case 'C':
        return _EnemyKind.charger;
      default:
        return _EnemyKind.nut;
    }
  }

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

  // --- kurulum -------------------------------------------------------------

  void _loadLevel(int index) {
    final grid = _buildPlatformLevel(index);
    _levelIndex = index;
    _grid = grid;
    _cols = grid.first.length;
    _theme = _levelThemes[index.clamp(0, _levelThemes.length - 1)];
    _enemies.clear();
    _pickups.clear();
    _sparks.clear();
    _bolts.clear();
    _dust.clear();
    _pops.clear();
    _debris.clear();
    _bumps.clear();
    _flagCol = 0;
    var spawnCol = 1, spawnRow = 11;
    for (var row = 0; row < _rows; row++) {
      for (var col = 0; col < _cols; col++) {
        final ch = _grid[row][col];
        if (ch == 'E' || ch == 'S' || ch == 'Y' || ch == 'J' || ch == 'n' || ch == 'G' || ch == 'X' || ch == 'C') {
          final kind = _kindFor(ch);
          final y = kind == _EnemyKind.flyer ? row.toDouble() : row + 1 - .78;
          _enemies.add(_Enemy(col + .14, y, kind, row.toDouble()));
          _setTile(row, col, '.');
        } else if (ch == 'F') {
          _flagCol = col;
          _setTile(row, col, '.');
        } else if (ch == '@') {
          spawnCol = col;
          spawnRow = row;
          _setTile(row, col, '.');
        }
      }
    }
    _goalX = math.max(1.0, _flagCol - .3);
    _x = spawnCol + .14;
    _y = spawnRow + 1 - _ph;
    _vx = 0;
    _vy = 0;
    _facing = 1;
    _grounded = false;
    _wasGrounded = false;
    _time = 150;
    _timeTicks = 0;
    _invuln = 90;
    _star = 0;
    _broken = 0;
    _coyote = 0;
    _squash = 0;
    _attackAnim = 0;
    _attackCd = 0;
    _jumpBuffer = 0;
    _jumpCut = false;
    _special = null;
    _specialTicks = 0;
    _shake = 0;
    _levelFlash = 0;
    _camera = 0;
    _phase = _Phase.ready;
    _phaseTicks = 80;
  }

  void _chooseHero(_PlatformerHero hero) {
    setState(() {
      _hero = hero;
      _score = 0;
      _coinCount = 0;
      _lives = 3;
      _level = 1;
      _xp = 0;
      _xpNext = 120;
      _special = null;
      _specialTicks = 0;
      _holdLeft = false;
      _holdRight = false;
      _jumpHeld = false;
      _loadLevel(0);
    });
  }

  // --- karo ve çarpışma ----------------------------------------------------

  String _tileAt(int row, int col) {
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) return '.';
    return _grid[row][col];
  }

  void _setTile(int row, int col, String ch) {
    final r = _grid[row];
    _grid[row] = r.substring(0, col) + ch + r.substring(col + 1);
  }

  bool _solid(int col, int row) {
    if (_grid.isEmpty) return false;
    if (col < 0 || col >= _cols) return true;
    switch (_tileAt(row, col)) {
      case '#':
      case '=':
      case 'B':
      case '?':
      case 'H':
      case 'U':
      case 'P':
      case 'V':
      case 'W':
      case 'K':
        return true;
      default:
        return false;
    }
  }

  int? _boxRow(double x, double y, double w, double h) {
    final left = x.floor();
    final right = (x + w - .002).floor();
    final top = y.floor();
    final bottom = (y + h - .002).floor();
    for (var row = top; row <= bottom; row++) {
      for (var col = left; col <= right; col++) {
        if (_solid(col, row)) return row;
      }
    }
    return null;
  }

  int? _boxCol(double x, double y, double w, double h) {
    final left = x.floor();
    final right = (x + w - .002).floor();
    final top = y.floor();
    final bottom = (y + h - .002).floor();
    for (var col = left; col <= right; col++) {
      for (var row = top; row <= bottom; row++) {
        if (_solid(col, row)) return col;
      }
    }
    return null;
  }

  double get _maxX => math.max(0.0, _cols - _pw);

  void _moveX(double vx) {
    if (vx == 0) return;
    final next = _x + vx;
    final hit = _boxCol(next, _y, _pw, _ph);
    if (hit == null) {
      _x = next.clamp(0.0, _maxX).toDouble();
      return;
    }
    _x = (vx > 0 ? hit - _pw - .002 : hit + 1 + .002)
        .clamp(0.0, _maxX)
        .toDouble();
  }

  void _moveY(double vy) {
    final next = _y + vy;
    final hit = _boxRow(_x, next, _pw, _ph);
    if (hit == null) {
      _y = next;
      _grounded = false;
      return;
    }
    if (vy > 0) {
      _y = hit - _ph - .002;
      _grounded = true;
      _vy = 0;
    } else {
      _y = hit + 1 + .002;
      _vy = 0;
      _headBump(hit);
    }
  }

  void _headBump(int row) {
    final left = _x.floor();
    final right = (_x + _pw - .002).floor();
    final hits = <int>[];
    for (var col = left; col <= right; col++) {
      if (_solid(col, row)) hits.add(col);
    }
    if (hits.isEmpty) return;
    final cx = _x + _pw / 2;
    hits.sort((a, b) => (a + .5 - cx).abs().compareTo((b + .5 - cx).abs()));
    _bumpBlock(hits.first, row);
  }

  void _bumpBlock(int col, int row) {
    final ch = _tileAt(row, col);
    if (ch == '?') {
      _setTile(row, col, 'U');
      _bumps['$col:$row'] = 10;
      _coinCount++;
      _score += 10;
      _pops.add(_PopFx(col.toDouble(), row - .7, '+10', const Color(0xffffd66b)));
    } else if (ch == 'H') {
      _setTile(row, col, 'U');
      _bumps['$col:$row'] = 10;
      _lives = math.min(5, _lives + 1);
      _pops.add(
        _PopFx(col.toDouble(), row - .7, '+1 CAN', const Color(0xffff8a9b)),
      );
    } else if (ch == 'B') {
      _bumps['$col:$row'] = 8;
    } else if (ch == 'V' || ch == 'W' || ch == 'K') {
      _smashProp(col, row);
    }
  }

  // --- girdi ve yetenekler -------------------------------------------------

  void _jump() {
    if (_phase != _Phase.playing) return;
    _jumpBuffer = 10;
  }

  void _attack() {
    if (_phase != _Phase.playing || _attackCd > 0 || _hero == null) return;
    if (_hero == _PlatformerHero.chief) {
      final quake = _specialActive && _special == _SpecialWeapon.quake;
      _attackAnim = quake ? 13 : 9;
      _attackCd = quake ? 20 : 16;
      if (quake) _shake = 12;
      _hammerHit(quake: quake, power: quake ? 2 : 1);
      _arcadePlaySfx(quake ? 'smash' : 'swing');
    } else {
      final spread = _specialActive && _special == _SpecialWeapon.spread;
      final maxSparks = spread ? 4 : 2;
      if (_sparks.length >= maxSparks) return;
      _attackAnim = 6;
      _attackCd = spread ? 13 : 18;
      final muzzleX = _x + (_facing > 0 ? _pw + .05 : -.25);
      final muzzleY = _y + .28;
      if (spread) {
        // Üçlü kıvılcım yelpazesi: yatay, yukarı ve aşağı açılı.
        for (final vy in [-.07, 0.0, .07]) {
          _sparks.add(_Spark(muzzleX, muzzleY, _facing * .25, vy));
        }
      } else {
        _sparks.add(_Spark(muzzleX, muzzleY, _facing * .22));
      }
      _arcadePlaySfx('shoot');
    }
  }

  /// Çekiç savurması. Vuruş menzili üç kat uzundur (`_hammerReach`), önündeki
  /// tüm kırılabilir karoları biçer. `quake` (özel silah) arka tarafı da vurur.
  void _hammerHit({bool quake = false, int power = 1}) {
    final cx = _x + _pw / 2;
    for (final e in _enemies) {
      if (e.dead) continue;
      final dx = e.x + .36 - cx;
      final inFront = quake || dx * _facing >= -_hammerBehind;
      if (inFront &&
          dx.abs() < _hammerReach &&
          (e.y - _y).abs() < _hammerVertical) {
        _damageEnemy(e, _facing, power: power);
      }
    }
    // Kırılabilir karoları çekicin uzanabildiği karo aralığında süpürür:
    // bitişik karodan başlayıp üç karo ileriye kadar.
    final reached = <int>{};
    final near = _facing > 0 ? cx.floor() : (cx - 2.0).floor();
    for (var i = 0; i < 4; i++) {
      reached.add(near + _facing * i);
    }
    if (quake) reached.add((cx - _facing * 2).round());
    for (final col in reached) {
      for (final row in [(_y + .2).floor(), (_y + _ph - .1).floor()]) {
        final ch = _tileAt(row, col);
        if (ch == 'B') {
          _setTile(row, col, '.');
          _score += 5;
          _gainXp(4);
          _breakFx(col, row);
          _arcadePlaySfx('smash');
        } else if (ch == 'V' || ch == 'W' || ch == 'K') {
          _smashProp(col, row);
        }
      }
    }
  }

  /// Dönüş değeri: düşman bu vuruşta öldü mü (kalkan önü blokladıysa false).
  bool _damageEnemy(_Enemy e, int attackDir, {int power = 1}) {
    if (e.dead) return false;
    final frontal = attackDir != 0 && e.dir == -attackDir;
    if (e.kind == _EnemyKind.guard && e.hp > 1 && frontal) {
      _pops.add(_PopFx(e.x, e.y - .3, 'KLING', Colors.white70));
      _arcadePlaySfx('clang');
      return false;
    }
    e.hp -= power;
    e.hurt = 12;
    if (e.hp > 0) {
      // Sağlam düşman geri savrulur ama ayakta kalır.
      e.x += attackDir * .10;
      _pops.add(_PopFx(e.x, e.y - .3, 'VURUŞ', Colors.white70));
      _arcadePlaySfx('clang');
      return false;
    }
    final points = switch (e.kind) {
      _EnemyKind.guard => 40,
      _EnemyKind.brute => 70,
      _EnemyKind.charger => 50,
      _EnemyKind.turret => 35,
      _ => 30,
    };
    _killEnemy(e, points);
    return true;
  }

  void _killEnemy(_Enemy e, int points) {
    e.dead = true;
    e.deadTicks = 22;
    _score += points;
    _gainXp(12);
    _pops.add(_PopFx(e.x, e.y - .3, '+$points', const Color(0xffffd66b)));
    _dropLoot(e.x + .1, e.y, e.kind);
    _arcadePlaySfx('stomp');
  }

  /// Düşman türüne göre ödül tablosu.
  void _dropLoot(double x, double y, _EnemyKind kind) {
    final roll = _rng.nextInt(100);
    _PickupKind drop;
    switch (kind) {
      case _EnemyKind.nut:
        drop = roll < 55
            ? _PickupKind.coin
            : roll < 85 ? _PickupKind.gem : _PickupKind.heart;
        break;
      case _EnemyKind.spiky:
        drop = roll < 50 ? _PickupKind.gem : _PickupKind.coin;
        break;
      case _EnemyKind.flyer:
        drop = roll < 45 ? _PickupKind.coin : _PickupKind.gem;
        break;
      case _EnemyKind.hopper:
        drop = roll < 40
            ? _PickupKind.heart
            : roll < 82 ? _PickupKind.coin : _PickupKind.star;
        break;
      case _EnemyKind.turret:
        drop = roll < 60 ? _PickupKind.gem : _PickupKind.coin;
        break;
      case _EnemyKind.guard:
        drop = roll < 45 ? _PickupKind.heart : _PickupKind.gem;
        break;
      case _EnemyKind.brute:
        drop = roll < 40
            ? _PickupKind.heart
            : roll < 80 ? _PickupKind.gem : _PickupKind.weapon;
        break;
      case _EnemyKind.charger:
        drop = roll < 50
            ? _PickupKind.gem
            : roll < 82 ? _PickupKind.coin : _PickupKind.weapon;
        break;
    }
    _pickups.add(_Pickup(x, y, -.14, drop));
  }

  void _dropRandomLoot(double x, double y) {
    final roll = _rng.nextInt(100);
    final kind = roll < 42
        ? _PickupKind.coin
        : roll < 72
            ? _PickupKind.gem
            : roll < 90
                ? _PickupKind.heart
                : roll < 96 ? _PickupKind.star : _PickupKind.weapon;
    _pickups.add(_Pickup(x, y, -.16, kind));
  }

  /// Sandık (V), varil (W) veya alet kutusunu (K) kırar; ödülü serbest bırakır.
  /// Alet kutusundan her zaman geçici özel silah çıkar.
  void _smashProp(int col, int row) {
    final ch = _tileAt(row, col);
    if (ch != 'V' && ch != 'W' && ch != 'K') return;
    _setTile(row, col, '.');
    _broken++;
    _score += 5;
    _gainXp(8);
    _bumps.remove('$col:$row');
    _debris.add(_Debris(col + .15, row + .15, -.07, -.14));
    _debris.add(_Debris(col + .6, row + .15, .07, -.14));
    _debris.add(_Debris(col + .15, row + .6, -.05, -.06));
    _debris.add(_Debris(col + .6, row + .6, .05, -.06));
    if (ch == 'K') {
      _pickups.add(
        _Pickup(col + .1, row + .1, -.16, _PickupKind.weapon),
      );
      _pops.add(
        _PopFx(col + .4, row - .3, 'ALET!', const Color(0xff8be9fd)),
      );
    } else {
      _dropRandomLoot(col.toDouble(), row.toDouble());
    }
    _arcadePlaySfx('smash');
  }

  void _breakFx(int col, int row) {
    _debris.add(_Debris(col + .15, row + .15, -.07, -.14));
    _debris.add(_Debris(col + .6, row + .15, .07, -.14));
    _debris.add(_Debris(col + .15, row + .6, -.05, -.06));
    _debris.add(_Debris(col + .6, row + .6, .05, -.06));
  }

  // --- oyun döngüsü --------------------------------------------------------

  void _tick() {
    if (!mounted) return;
    if (_phase == _Phase.select ||
        _phase == _Phase.gameover ||
        _phase == _Phase.win) {
      return;
    }
    setState(() {
      _clock++;
      switch (_phase) {
        case _Phase.ready:
          _tickFx();
          _phaseTicks--;
          if (_phaseTicks <= 0) _phase = _Phase.playing;
          break;
        case _Phase.playing:
          _tickPlaying();
          break;
        case _Phase.dying:
          _tickFx();
          _y += _vy;
          _vy = math.min(.42, _vy + .02);
          _phaseTicks--;
          if (_phaseTicks <= 0) {
            if (_lives > 0) {
              _loadLevel(_levelIndex);
            } else {
              _phase = _Phase.gameover;
            }
          }
          break;
        case _Phase.clear:
          _tickFx();
          if (_phaseTicks % 14 == 0) {
            _pops.add(
              _PopFx(
                _camera + 3 + (_phaseTicks % 7),
                3 + (_phaseTicks % 5) * .6,
                '★',
                const Color(0xff9be38a),
              ),
            );
          }
          _phaseTicks--;
          if (_phaseTicks <= 0) {
            if (_levelIndex + 1 < _levelCount) {
              _loadLevel(_levelIndex + 1);
            } else {
              _phase = _Phase.win;
            }
          }
          break;
        default:
          break;
      }
    });
  }

  void _tickPlaying() {
    final info = _info;
    if (info == null) return;
    if (_star > 0) _star--;
    if (_specialTicks > 0) _specialTicks--;
    if (_shake > 0) _shake--;
    _timeTicks++;
    if (_timeTicks >= 40) {
      _timeTicks = 0;
      if (_time > 0) _time--;
      if (_time == 0) {
        _die();
        return;
      }
    }

    final dir = (_holdRight ? 1 : 0) - (_holdLeft ? 1 : 0);
    final top = info.runSpeed * (_powered ? 1.18 : 1.0) * _growth;
    if (dir != 0) {
      // Ani yön değişiminde kayma (skid) hissi.
      if (_vx * dir < 0 && _vx.abs() > .04) {
        _squash = math.max(_squash, .35);
        _runDust(.5);
      }
      _vx += dir * info.accel;
      if (_vx.abs() > top) _vx = dir * top;
      _facing = dir;
    } else {
      _vx *= .82;
      if (_vx.abs() < .004) _vx = 0;
    }
    _moveX(_vx);

    if ((_grounded || _coyote > 0) && _jumpBuffer > 0) {
      _vy = info.jumpSpeed * _growth;
      _grounded = false;
      _coyote = 0;
      _jumpBuffer = 0;
      _jumpCut = false;
      _squash = -.6;
      _jumpDust();
      _arcadePlaySfx('jump');
    }
    if (!_jumpHeld && _vy < 0 && !_jumpCut) {
      _vy *= .5;
      _jumpCut = true;
    }
    _vy = math.min(_maxFall, _vy + _gravity);
    _moveY(_vy);
    if (_jumpBuffer > 0) _jumpBuffer--;
    if (_grounded) {
      _coyote = 7;
    } else if (_coyote > 0) {
      _coyote--;
    }

    // İnişte ezilme + toz bulutu: hareketi yumuşatır.
    if (_grounded && !_wasGrounded) {
      _squash = 1;
      _landDust();
      _arcadePlaySfx('land');
    }
    _wasGrounded = _grounded;
    if (_squash.abs() > .01) {
      _squash = _squash > 0 ? _squash - .085 : _squash + .085;
    } else {
      _squash = 0;
    }

    // Boşluğa düşen oyuncu bir can kaybeder.
    if (_y > _rows + 1) {
      _die();
      return;
    }

    _stepTick++;
    if (_grounded && _vx.abs() > info.runSpeed * .55 && _stepTick % 11 == 0) {
      _runDust(.35);
    }

    _collectCoins();
    _collectPickups();
    _tickEnemies();
    _tickSparks();
    _tickBolts();
    _tickPickups();
    _tickDust();
    _playerVsEnemies();
    _tickFx();
    _tickCamera();

    if (_phase == _Phase.playing && _x >= _goalX) _clearLevel();
  }

  void _landDust() {
    _dust.add(_Dust(_x - .18, _y + _ph - .1, -.1, -.03));
    _dust.add(_Dust(_x + .58, _y + _ph - .1, .1, -.03));
  }

  void _jumpDust() {
    _dust.add(_Dust(_x - .05, _y + _ph - .05, -.08, -.05));
    _dust.add(_Dust(_x + .45, _y + _ph - .05, .08, -.05));
  }

  void _runDust(double power) {
    _dust.add(
      _Dust(
        _x + (_facing > 0 ? .05 : _pw - .05),
        _y + _ph - .06,
        -_facing * .12 * power,
        -.045 * power,
      ),
    );
  }

  void _tickDust() {
    for (final d in _dust) {
      d.x += d.vx;
      d.y += d.vy;
      d.vy += .0015;
      d.life--;
      if (d.life <= 0) d.remove = true;
    }
    _dust.removeWhere((d) => d.remove);
  }

  void _collectCoins() {
    final left = _x.floor();
    final right = (_x + _pw - .002).floor();
    final top = _y.floor();
    final bottom = (_y + _ph - .002).floor();
    for (var row = top; row <= bottom; row++) {
      for (var col = left; col <= right; col++) {
        if (_tileAt(row, col) == 'o') {
          _setTile(row, col, '.');
          _coinCount++;
          _score += 10;
          _pops.add(
            _PopFx(col.toDouble(), row - .2, '+10', const Color(0xffffd66b)),
          );
        }
      }
    }
  }

  /// Altı düşman türünün ayrı ayrı davranışı.
  void _tickEnemies() {
    for (final e in _enemies) {
      e.t++;
      if (e.hurt > 0) e.hurt--;
      if (e.dead) {
        e.deadTicks--;
        continue;
      }
      switch (e.kind) {
        case _EnemyKind.flyer:
          e.x += e.dir * .038;
          e.y = e.homeY + math.sin(e.t * .05) * 1.05;
          final ahead = (e.x + (e.dir > 0 ? .74 : -.02)).floor();
          if (_solid(ahead, (e.y + .4).floor()) ||
              e.x < .2 ||
              e.x > _cols - 1.0) {
            e.dir = -e.dir;
          }
          break;
        case _EnemyKind.turret:
          e.cool--;
          if (e.cool <= 0) {
            e.cool = 95;
            final toPlayer = _x > e.x;
            _bolts.add(
              _Bolt(
                e.x + (toPlayer ? .6 : .1),
                e.y + .2,
                toPlayer ? .055 : -.055,
                0,
              ),
            );
            _arcadePlaySfx('shoot');
          }
          break;
        case _EnemyKind.hopper:
          e.vy = math.min(_maxFall, e.vy + _gravity);
          final hopRow = _boxRow(e.x, e.y + e.vy, .72, .78);
          if (hopRow == null) {
            e.y += e.vy;
          } else if (e.vy > 0) {
            e.y = hopRow - .78 - .002;
            e.vy = 0;
            e.cool = 55 + _rng.nextInt(45);
          } else {
            e.y = hopRow + 1 + .002;
            e.vy = 0;
          }
          if (e.cool > 0) e.cool--;
          if (e.cool <= 0 && e.vy == 0) {
            e.vy = -.30;
            e.dir = _x + _pw / 2 < e.x + .36 ? -1 : 1;
            _arcadePlaySfx('hop');
          }
          if (e.vy == 0) {
            final nx = e.x + e.dir * .022;
            if (_boxCol(nx, e.y, .72, .78) == null) e.x = nx;
          }
          break;
        case _EnemyKind.charger:
          _tickCharger(e);
          break;
        case _EnemyKind.nut:
        case _EnemyKind.spiky:
        case _EnemyKind.guard:
        case _EnemyKind.brute:
          _tickWalker(e, _enemyWalkSpeed(e.kind));
          break;
      }
    }
    _enemies.removeWhere((e) => e.remove || (e.dead && e.deadTicks <= 0));
  }

  static double _enemyWalkSpeed(_EnemyKind kind) => switch (kind) {
    _EnemyKind.nut => .032,
    _EnemyKind.guard => .042,
    _EnemyKind.brute => .019,
    _ => .024,
  };

  /// Yerde yürüyen düşmanlar (kestane, dikenli, muhafız, golem): yerçekimi,
  /// zemin teması ve kenarda dönme. Dikenli hariç boşluğa düşmez.
  void _tickWalker(_Enemy e, double speed) {
    e.vy = math.min(_maxFall, e.vy + _gravity);
    final walkRow = _boxRow(e.x, e.y + e.vy, .72, .78);
    if (walkRow == null) {
      e.y += e.vy;
    } else if (e.vy > 0) {
      e.y = walkRow - .78 - .002;
      e.vy = 0;
    } else {
      e.y = walkRow + 1 + .002;
      e.vy = 0;
    }
    final nx = e.x + e.dir * speed;
    var blocked = _boxCol(nx, e.y, .72, .78) != null;
    if (!blocked && e.kind != _EnemyKind.spiky) {
      // Kestane ve muhafız boşluktan düşmez, kenarda döner.
      final footRow = (e.y + .82).floor();
      final ahead = (nx + (e.dir > 0 ? .76 : 0)).floor();
      if (!_solid(ahead, footRow)) blocked = true;
    }
    if (blocked) {
      e.dir = -e.dir;
    } else {
      e.x = nx;
    }
    if (e.y > _rows + 2) e.remove = true;
  }

  /// Koç: yavaş yürür, oyuncuyla aynı hizada olunca hızla üzerine atılır.
  void _tickCharger(_Enemy e) {
    _tickWalker(e, e.charge > 0 ? .11 : .02);
    if (e.charge > 0) {
      e.charge--;
      return;
    }
    if (e.cool > 0) e.cool--;
    final aligned = (e.y - _y).abs() < 1.1;
    final aheadDir = _x + _pw / 2 >= e.x + .36 ? 1 : -1;
    if (e.cool <= 0 && aligned && aheadDir == e.dir) {
      e.charge = 45;
      e.cool = 150;
      _pops.add(_PopFx(e.x, e.y - .3, 'KOŞ!', const Color(0xffff9f6b)));
      _arcadePlaySfx('hop');
    }
  }

  void _tickPickups() {
    for (final p in _pickups) {
      p.t++;
      p.life--;
      if (p.life <= 0) {
        p.remove = true;
        continue;
      }
      if (!p.grounded) {
        p.vy = math.min(_maxFall, p.vy + _gravity * .8);
        final hit = _boxRow(p.x, p.y + p.vy, .5, .5);
        if (hit == null) {
          p.y += p.vy;
        } else {
          p.y = hit - .5 - .002;
          p.vy = 0;
          p.grounded = true;
        }
        if (p.y > _rows + 2) p.remove = true;
      }
    }
    _pickups.removeWhere((p) => p.remove);
  }

  void _collectPickups() {
    for (final p in _pickups) {
      if (p.remove) continue;
      final dx = p.x + .25 - (_x + _pw / 2);
      final dy = p.y + .25 - (_y + _ph / 2);
      if (dx.abs() > .62 || dy.abs() > .68) continue;
      p.remove = true;
      switch (p.kind) {
        case _PickupKind.coin:
          _coinCount++;
          _score += 10;
          _gainXp(12);
          _pops.add(_PopFx(p.x, p.y - .3, '+10', const Color(0xffffd66b)));
          _arcadePlaySfx('coin');
          break;
        case _PickupKind.gem:
          _score += 50;
          _gainXp(40);
          _pops.add(_PopFx(p.x, p.y - .3, '+50', const Color(0xff7ff2b0)));
          _arcadePlaySfx('coin');
          break;
        case _PickupKind.heart:
          _lives = math.min(5, _lives + 1);
          _pops.add(_PopFx(p.x, p.y - .3, '+1 CAN', const Color(0xffff8a9b)));
          _arcadePlaySfx('power');
          break;
        case _PickupKind.star:
          _star = 420;
          _pops.add(_PopFx(p.x, p.y - .3, 'YILDIZ!', const Color(0xffffe066)));
          _arcadePlaySfx('power');
          break;
        case _PickupKind.weapon:
          _special = _hero == _PlatformerHero.coder
              ? _SpecialWeapon.spread
              : _SpecialWeapon.quake;
          _specialTicks = 520;
          _pops.add(
            _PopFx(
              p.x,
              p.y - .3,
              _special == _SpecialWeapon.quake
                  ? 'YER SARSINTISI!'
                  : 'ÜÇLÜ KIVILCIM!',
              const Color(0xff8be9fd),
            ),
          );
          _arcadePlaySfx('power');
          break;
      }
    }
    _pickups.removeWhere((p) => p.remove);
  }

  void _tickBolts() {
    for (final b in _bolts) {
      b.x += b.vx;
      b.y += b.vy;
      b.life--;
      if (b.life <= 0 || _solid((b.x + .2).floor(), (b.y + .2).floor())) {
        b.dead = true;
        continue;
      }
      final dx = b.x + .2 - (_x + _pw / 2);
      final dy = b.y + .2 - (_y + _ph / 2);
      if (dx.abs() < .48 && dy.abs() < .55 && _invuln <= 0 && !_powered) {
        b.dead = true;
        _die();
        return;
      }
    }
    _bolts.removeWhere((b) => b.dead);
  }

  void _tickSparks() {
    for (final spark in _sparks) {
      spark.x += spark.vx;
      spark.y += spark.vy;
      spark.life--;
      final col = (spark.x + .15).floor();
      final row = (spark.y + .15).floor();
      final ch = _tileAt(row, col);
      if (ch == 'V' || ch == 'W' || ch == 'K') {
        // Kıvılcım sandığa/varile/alet kutusuna çarpınca kırar.
        _smashProp(col, row);
        spark.dead = true;
        continue;
      }
      if (spark.life <= 0 || _solid(col, row)) {
        spark.dead = true;
        continue;
      }
      var consumed = false;
      for (final e in _enemies) {
        if (e.dead) continue;
        if ((e.x + .36 - spark.x).abs() < .58 &&
            (e.y + .39 - spark.y).abs() < .62) {
          _damageEnemy(e, _facing);
          consumed = true;
          break;
        }
      }
      if (!consumed) {
        for (final b in _bolts) {
          if (b.dead) continue;
          if ((b.x - spark.x).abs() < .4 && (b.y - spark.y).abs() < .4) {
            b.dead = true;
            consumed = true;
            _arcadePlaySfx('clang');
            break;
          }
        }
      }
      if (consumed) spark.dead = true;
    }
    _sparks.removeWhere((spark) => spark.dead);
  }

  void _playerVsEnemies() {
    for (final e in _enemies) {
      if (e.dead) continue;
      final dx = _x + _pw / 2 - (e.x + .36);
      final dy = _y + _ph / 2 - (e.y + .39);
      if (dx.abs() > .70 || dy.abs() > .82) continue;
      if (_powered) {
        _killEnemy(e, 50);
        continue;
      }
      final stomping = _vy > 0 && (_y + _ph) - e.y < .55;
      if (stomping && e.kind != _EnemyKind.spiky) {
        // Ezme: zırhsız düşmanı anında öldürür, zırhlı olanı yaralar ve
        // oyuncuyu geri sektirir (kısa dokunulmazlıkla).
        _damageEnemy(e, 0);
        _vy = -.26;
        _grounded = false;
        _squash = .8;
        _invuln = math.max(_invuln, 12);
      } else if (_invuln <= 0) {
        _die();
        return;
      }
    }
  }

  void _tickFx() {
    for (final p in _pops) {
      p.y -= .024;
      p.life--;
    }
    _pops.removeWhere((p) => p.life <= 0);
    for (final d in _debris) {
      d.x += d.vx;
      d.y += d.vy;
      d.vy += .02;
      d.life--;
    }
    _debris.removeWhere((d) => d.life <= 0);
    for (final key in _bumps.keys.toList()) {
      final value = _bumps[key]! - 1;
      if (value <= 0) {
        _bumps.remove(key);
      } else {
        _bumps[key] = value;
      }
    }
    if (_attackAnim > 0) _attackAnim--;
    if (_attackCd > 0) _attackCd--;
    if (_invuln > 0) _invuln--;
    if (_levelFlash > 0) _levelFlash--;
  }

  void _tickCamera() {
    final target = (_x + _vx * 14 - 5.2)
        .clamp(0.0, math.max(0.0, _cols - _viewCols))
        .toDouble();
    _camera += (target - _camera) * .16;
    if ((target - _camera).abs() < .01) _camera = target;
  }

  void _die() {
    if (_phase != _Phase.playing) return;
    _phase = _Phase.dying;
    _phaseTicks = 70;
    _vy = -.34;
    _lives--;
    _arcadePlaySfx('hurt');
  }

  void _clearLevel() {
    _clearBonus = _time * 2 + _broken * 15 + _level * 20;
    _score += _clearBonus;
    _gainXp(30);
    _phase = _Phase.clear;
    _phaseTicks = 130;
    _arcadePlaySfx('clear');
  }

  // --- klavye ---------------------------------------------------------------

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final down = event is KeyDownEvent;
    final up = event is KeyUpEvent;
    if (!down && !up) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      _holdLeft = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      _holdRight = down;
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyZ) {
      if (down) {
        _jumpHeld = true;
        _jump();
      } else {
        _jumpHeld = false;
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX || key == LogicalKeyboardKey.keyK) {
      if (down) _attack();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // --- arayüz ---------------------------------------------------------------

  String _hudText() {
    switch (_phase) {
      case _Phase.select:
        return 'KARAKTER SEÇ';
      case _Phase.gameover:
        return 'OYUN BİTTİ • $_score PTS';
      case _Phase.win:
        return 'ZAFER • $_score PTS';
      default:
        return '$_score PTS • SV $_level • ALTIN $_coinCount • CAN $_lives • '
            'BÖLÜM ${_levelIndex + 1}/$_levelCount • SÜRE $_time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ArcadeFrame(
      score: _hudText(),
      controls: widget.showPad && _phase != _Phase.select
          ? _PlatformerControls(
              onLeft: (v) => _holdLeft = v,
              onRight: (v) => _holdRight = v,
              onJumpDown: () {
                _jumpHeld = true;
                _jump();
              },
              onJumpUp: () => _jumpHeld = false,
              onAttack: _attack,
              attackIcon:
                  _hero == _PlatformerHero.coder ? Icons.bolt : Icons.hardware,
            )
          : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: _phase == _Phase.select ? _buildSelect() : _buildStage(),
          ),
          Positioned(top: 4, right: 4, child: _muteButton()),
        ],
      ),
    );
  }

  Widget _muteButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _arcadeSfxMuted = !_arcadeSfxMuted),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            _arcadeSfxMuted ? Icons.volume_off : Icons.volume_up,
            size: 18,
            color: Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (_phase == _Phase.gameover || _phase == _Phase.win) {
            setState(() => _phase = _Phase.select);
          } else if (_phase == _Phase.playing) {
            _jumpHeld = true;
            _jump();
          }
        },
        onTapUp: (_) => _jumpHeld = false,
        onTapCancel: () => _jumpHeld = false,
        child: CustomPaint(
          painter: _PlatformPainter(this),
          size: Size.infinite,
        ),
      ),
    );
  }

  Widget _buildSelect() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          const Text(
            'KARAKTERİNİ SEÇ',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'İki kahraman, iki farklı oynanış. Bayrağa ilk sen ulaş!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .55),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 14),
          _HeroCard(
            hero: _PlatformerHero.chief,
            onTap: () => _chooseHero(_PlatformerHero.chief),
          ),
          const SizedBox(height: 10),
          _HeroCard(
            hero: _PlatformerHero.coder,
            onTap: () => _chooseHero(_PlatformerHero.coder),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'A zıpla · B saldır (çekiç / USB kıvılcımı)\n'
              'Klavye: ← → koş · W/Boşluk zıpla · X saldır\n'
              'Altın ve kristal topla → seviye atla · alet kutusu → özel silah',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformPainter extends CustomPainter {
  final _PlatformerState s;
  const _PlatformPainter(this.s);

  @override
  void paint(Canvas canvas, Size size) {
    if (s._grid.isEmpty) return;
    final theme = s._theme;
    final sky = Paint()
      ..shader = LinearGradient(
        colors: theme.sky,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    _paintSkyDetails(canvas, size, theme);

    final tile = math.min(size.width / 13, size.height / _PlatformerState._rows);
    if (tile <= 0) return;
    // Kamera yatayda kaydığı için dünya sol kenardan başlar; yalnızca bölüm
    // ekrandan darsa ortalanır. Tüm bölüm genişliğine göre ortalamak, kameraya
    // göre çizilen karoları ekran dışına taşıyıp sadece mavi gökyüzü bırakır.
    final viewCols = size.width / tile;
    s._viewCols = viewCols;
    final ox = s._cols <= viewCols ? (size.width - s._cols * tile) / 2 : 0.0;
    final oy = (size.height - _PlatformerState._rows * tile) / 2;

    // Özel silah (yer sarsıntısı) ekranı hafifçe titretir.
    final shakeX =
        s._shake > 0 ? math.sin(s._clock * 1.7) * s._shake * .07 * tile : 0.0;
    final shakeY =
        s._shake > 0 ? math.cos(s._clock * 2.3) * s._shake * .06 * tile : 0.0;
    canvas.save();
    canvas.translate(ox + shakeX, oy + shakeY);
    _paintScenery(canvas, tile);
    _paintTiles(canvas, tile);
    _paintFlag(canvas, tile);
    for (final e in s._enemies) {
      _paintEnemy(canvas, e, tile);
    }
    for (final p in s._pickups) {
      _paintPickup(canvas, p, tile);
    }
    for (final b in s._bolts) {
      final c = Offset((b.x + .2 - s._camera) * tile, (b.y + .2) * tile);
      canvas.drawCircle(c, tile * .17, Paint()..color = const Color(0xffff8a5c));
      canvas.drawCircle(c, tile * .09, Paint()..color = const Color(0xffffe0b0));
    }
    for (final d in s._dust) {
      final a = (d.life / 18).clamp(0.0, 1.0).toDouble();
      canvas.drawCircle(
        Offset((d.x - s._camera) * tile, d.y * tile),
        tile * .16 * a + tile * .04,
        Paint()..color = Colors.white.withValues(alpha: .30 * a),
      );
    }
    for (final spark in s._sparks) {
      final c = Offset((spark.x - s._camera) * tile, spark.y * tile);
      canvas.drawCircle(c, tile * .30, Paint()..color = const Color(0x55ffd66b));
      canvas.drawCircle(c, tile * .15, Paint()..color = const Color(0xffffefad));
    }
    for (final d in s._debris) {
      final alpha = (d.life / 32).clamp(0.0, 1.0).toDouble();
      canvas.drawRect(
        Rect.fromLTWH(
          (d.x - s._camera) * tile,
          d.y * tile,
          tile * .24,
          tile * .24,
        ),
        Paint()..color = const Color(0xffc46a2b).withValues(alpha: alpha),
      );
    }
    final blinking =
        s._invuln > 0 && s._phase == _Phase.playing && (s._clock ~/ 4).isOdd;
    if (!blinking) {
      final heroRect = Rect.fromLTWH(
        (s._x - s._camera) * tile,
        s._y * tile,
        _PlatformerState._pw * tile,
        _PlatformerState._ph * tile,
      );
      canvas.save();
      if (s._squash.abs() > .01) {
        // Ezilme/uzama ayak noktasına göre ölçeklenir (squash & stretch).
        final pivot = Offset(heroRect.center.dx, heroRect.bottom);
        canvas.translate(pivot.dx, pivot.dy);
        final sy = s._squash > 0 ? 1 - .18 * s._squash : 1 + .12 * -s._squash;
        final sx = s._squash > 0 ? 1 + .16 * s._squash : 1 - .10 * -s._squash;
        canvas.scale(sx, sy);
        canvas.translate(-pivot.dx, -pivot.dy);
      }
      if (s._powered) {
        final glow = Paint()
          ..color = Color.fromRGBO(
            255,
            224,
            102,
            .30 + .20 * math.sin(s._clock * .3).abs(),
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
        canvas.drawCircle(heroRect.center, heroRect.width * .95, glow);
      }
      _drawHeroFigure(
        canvas,
        heroRect,
        s._hero ?? _PlatformerHero.chief,
        s._facing,
        runPhase: s._grounded && s._vx != 0 ? (s._clock ~/ 5) % 2 : 0,
        air: !s._grounded,
        attack: s._attackAnim,
        level: s._level,
      );
      _paintHeroAura(canvas, heroRect, tile);
      if (s._hero == _PlatformerHero.chief && s._attackAnim > 0) {
        _paintHammerArc(canvas, heroRect, tile, s._attackAnim, s._specialActive);
      }
      canvas.restore();
    }
    for (final p in s._pops) {
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: p.text,
          style: TextStyle(
            color: p.color.withValues(
              alpha: (p.life / 28).clamp(0.0, 1.0).toDouble(),
            ),
            fontWeight: FontWeight.w900,
            fontSize: tile * .42,
          ),
        ),
      )..layout();
      tp.paint(
        canvas,
        Offset((p.x + .5 - s._camera) * tile - tp.width / 2, p.y * tile),
      );
    }
    canvas.restore();

    _paintHudBars(canvas, size, tile);

    switch (s._phase) {
      case _Phase.ready:
        _overlay(
          canvas,
          size,
          'BÖLÜM ${s._levelIndex + 1}',
          '${s._info?.name ?? ''} · HAZIR?',
        );
        break;
      case _Phase.dying:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0x22000000),
        );
        break;
      case _Phase.clear:
        _overlay(
          canvas,
          size,
          'BÖLÜM TAMAM!',
          '+${s._clearBonus} saniye bonusu',
        );
        break;
      case _Phase.gameover:
        _overlay(
          canvas,
          size,
          'OYUN BİTTİ',
          'Skor ${s._score} · dokun → karakter seç',
        );
        break;
      case _Phase.win:
        _overlay(
          canvas,
          size,
          'TEBRİKLER!',
          'Üç bölüm tamam · Skor ${s._score} · dokun → karakter seç',
        );
        break;
      default:
        break;
    }
  }

  void _paintSkyDetails(Canvas canvas, Size size, _LevelTheme theme) {
    if (!theme.night) return;
    // Ay ve göz kırpışan yıldızlar (ekran uzayında sabit).
    final moon = Offset(size.width * .82, size.height * .14);
    canvas.drawCircle(moon, 17, Paint()..color = const Color(0xe8fff6d5));
    canvas.drawCircle(
      moon.translate(-5, -4),
      4,
      Paint()..color = const Color(0x33e8dcb0),
    );
    final star = Paint()..color = const Color(0x88ffffff);
    for (var i = 0; i < 26; i++) {
      final x = ((i * 137) % 100) / 100 * size.width;
      final y = ((i * 61) % 45) / 100 * size.height;
      final tw = .5 + .5 * math.sin(s._clock * .06 + i * 1.7).abs();
      canvas.drawCircle(Offset(x, y), 1.0 + tw, star);
    }
  }

  void _paintScenery(Canvas canvas, double tile) {
    final theme = s._theme;
    // Uzak sırtlar (yavaş paralaks).
    final hillFar = Paint()..color = theme.hillFar;
    for (var i = 0; i < s._cols ~/ 11 + 2; i++) {
      final wx = i * 11.0 + (i % 3) * 2.4;
      final x = (wx - s._camera * .4) * tile;
      if (x < -5 * tile || x > 19 * tile) continue;
      final r = (2.4 + (i % 2) * .9) * tile;
      canvas.drawArc(
        Rect.fromLTWH(x - r, 12 * tile - r * .85, r * 2, r * 2),
        math.pi,
        math.pi,
        true,
        hillFar,
      );
    }
    // Yakın tepeler.
    final hill = Paint()..color = theme.hill;
    for (var i = 0; i < s._cols ~/ 9 + 2; i++) {
      final wx = i * 9.0 + (i % 3) * 2.2;
      final x = (wx - s._camera * .55) * tile;
      if (x < -4 * tile || x > 18 * tile) continue;
      final r = (1.8 + (i % 2) * .7) * tile;
      canvas.drawArc(
        Rect.fromLTWH(x - r, 12 * tile - r, r * 2, r * 2),
        math.pi,
        math.pi,
        true,
        hill,
      );
    }
    final cloud = Paint()..color = theme.cloud;
    for (var i = 0; i < s._cols ~/ 7 + 2; i++) {
      final wx = 3 + i * 7.0 + (i % 3) * 1.7;
      final x = (wx - s._camera * .3) * tile;
      if (x < -3 * tile || x > 17 * tile) continue;
      final y = (1.1 + (i % 3) * .7) * tile;
      canvas.drawOval(Rect.fromLTWH(x, y, 2.4 * tile, .9 * tile), cloud);
      canvas.drawOval(
        Rect.fromLTWH(x + .7 * tile, y - .4 * tile, 1.6 * tile, 1.0 * tile),
        cloud,
      );
    }
    // Zemin üzerinde tema dekoru: çalı / kaktüs / sokak lambası.
    for (var i = 0; i < s._cols ~/ 7 + 2; i++) {
      final wx = i * 7.0 + (i % 4) * 1.7 + .5;
      final col = wx.floor();
      if (col < 0 || col >= s._cols || !s._solid(col, 12)) continue;
      final x = (wx - s._camera) * tile;
      if (x < -2 * tile || x > 15 * tile) continue;
      _paintProp(canvas, i % 3, x, 12 * tile, tile, theme);
    }
  }

  void _paintProp(
    Canvas canvas,
    int variant,
    double x,
    double groundY,
    double tile,
    _LevelTheme theme,
  ) {
    if (theme.night) {
      final pole = Paint()..color = const Color(0xff2f3542);
      canvas.drawRect(
        Rect.fromLTWH(x + tile * .46, groundY - tile * 2.2, tile * .08, tile * 2.2),
        pole,
      );
      final bulb = Offset(x + tile * .5, groundY - tile * 2.3);
      canvas.drawCircle(bulb, tile * .40, Paint()..color = const Color(0x33ffe9a8));
      canvas.drawCircle(bulb, tile * .20, Paint()..color = const Color(0xffffe9a8));
      return;
    }
    if (theme.name == 'Çöl') {
      final body = Paint()..color = const Color(0xff4d8f5a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + tile * .40, groundY - tile * 1.5, tile * .34, tile * 1.5),
          Radius.circular(tile * .16),
        ),
        body,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + tile * .10, groundY - tile * 1.05, tile * .34, tile * .20),
          Radius.circular(tile * .10),
        ),
        body,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + tile * .10, groundY - tile * 1.35, tile * .20, tile * .50),
          Radius.circular(tile * .10),
        ),
        body,
      );
      return;
    }
    final leaf = Paint()
      ..color = variant == 0 ? const Color(0xff2f8f4f) : const Color(0xff277a43);
    canvas.drawCircle(Offset(x + tile * .35, groundY - tile * .22), tile * .30, leaf);
    canvas.drawCircle(Offset(x + tile * .68, groundY - tile * .26), tile * .26, leaf);
    canvas.drawCircle(Offset(x + tile * .52, groundY - tile * .40), tile * .24, leaf);
  }

  void _paintTiles(Canvas canvas, double tile) {
    final c0 = s._camera.floor();
    for (var row = 0; row < _PlatformerState._rows; row++) {
      for (var col = c0 - 1; col <= c0 + 14; col++) {
        final ch = s._tileAt(row, col);
        if (ch == '.') continue;
        final bump = s._bumps['$col:$row'];
        final dy = bump == null
            ? 0.0
            : -math.sin((10 - bump) / 10 * math.pi) * .22 * tile;
        final rect = Rect.fromLTWH(
          (col - s._camera) * tile,
          row * tile + dy,
          tile,
          tile,
        );
        switch (ch) {
          case '#':
            _ground(canvas, col, row, rect);
            break;
          case '=':
            canvas.drawRect(rect, Paint()..color = s._theme.platform);
            canvas.drawRect(
              Rect.fromLTWH(rect.left, rect.top, tile, tile * .16),
              Paint()..color = s._theme.platformTop,
            );
            canvas.drawRect(
              Rect.fromLTWH(
                rect.left,
                rect.bottom - tile * .12,
                tile,
                tile * .12,
              ),
              Paint()..color = const Color(0x33000000),
            );
            break;
          case 'B':
            canvas.drawRect(rect, Paint()..color = s._theme.brick);
            canvas.drawRect(
              Rect.fromLTWH(rect.left, rect.top, tile, tile * .14),
              Paint()..color = s._theme.brickTop,
            );
            final mortar = Paint()..color = const Color(0x55000000);
            canvas.drawRect(
              Rect.fromLTWH(rect.left, rect.top + tile * .48, tile, tile * .06),
              mortar,
            );
            canvas.drawRect(
              Rect.fromLTWH(rect.left + tile * .46, rect.top, tile * .06, tile * .48),
              mortar,
            );
            canvas.drawRect(
              Rect.fromLTWH(
                rect.left + tile * .2,
                rect.top + tile * .54,
                tile * .06,
                tile * .46,
              ),
              mortar,
            );
            canvas.drawRect(
              Rect.fromLTWH(
                rect.left + tile * .72,
                rect.top + tile * .54,
                tile * .06,
                tile * .46,
              ),
              mortar,
            );
            break;
          case '?':
            _question(canvas, rect, false);
            break;
          case 'H':
            _question(canvas, rect, true);
            break;
          case 'U':
            canvas.drawRect(rect, Paint()..color = const Color(0xff57534e));
            canvas.drawRect(
              Rect.fromLTWH(rect.left, rect.top, tile, tile * .14),
              Paint()..color = const Color(0xff78716c),
            );
            for (final fx in [.3, .7]) {
              for (final fy in [.35, .7]) {
                canvas.drawCircle(
                  Offset(rect.left + tile * fx, rect.top + tile * fy),
                  tile * .05,
                  Paint()..color = const Color(0xff37322d),
                );
              }
            }
            break;
          case 'P':
            _pipe(canvas, col, row, rect);
            break;
          case 'V':
            _crate(canvas, rect);
            break;
          case 'W':
            _barrel(canvas, rect);
            break;
          case 'K':
            _weaponCrate(canvas, rect);
            break;
          case 'o':
            _coin(canvas, col, rect);
            break;
          default:
            break;
        }
      }
    }
  }

  void _ground(Canvas canvas, int col, int row, Rect rect) {
    final theme = s._theme;
    final tile = rect.width;
    canvas.drawRect(rect, Paint()..color = theme.ground);
    // Küçük doku farkları: aynı sütun her zaman aynı deseni alır.
    final seed = (col * 7 + row * 13) % 3;
    if (seed == 0) {
      canvas.drawCircle(
        Offset(rect.left + tile * .30, rect.top + tile * .62),
        tile * .07,
        Paint()..color = theme.groundShade,
      );
    } else if (seed == 1) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left + tile * .55, rect.top + tile * .68, tile * .22, tile * .12),
        Paint()..color = theme.groundShade,
      );
    }
    final above = s._tileAt(row - 1, col);
    final covered = above == '#' ||
        above == '=' ||
        above == 'B' ||
        above == '?' ||
        above == 'H' ||
        above == 'U' ||
        above == 'P' ||
        above == 'K';
    if (!covered) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top, tile, tile * .30),
        Paint()..color = theme.groundTop,
      );
      canvas.drawRect(
        Rect.fromLTWH(rect.left, rect.top + tile * .30, tile, tile * .07),
        Paint()..color = theme.groundShade,
      );
      // Üstteki çim püskülleri.
      if (seed != 2) {
        final blade = Paint()..color = theme.groundShade;
        canvas.drawRect(
          Rect.fromLTWH(rect.left + tile * .18, rect.top - tile * .10, tile * .06, tile * .12),
          blade,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left + tile * .70, rect.top - tile * .07, tile * .06, tile * .09),
          blade,
        );
      }
    }
  }

  void _crate(Canvas canvas, Rect rect) {
    final tile = rect.width;
    canvas.drawRect(rect, Paint()..color = const Color(0xffa9743c));
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, tile, tile * .12),
      Paint()..color = const Color(0xffc9924f),
    );
    final plank = Paint()..color = const Color(0x66000000);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + tile * .46, tile, tile * .07), plank);
    canvas.drawRect(Rect.fromLTWH(rect.left, rect.top + tile * .88, tile, tile * .07), plank);
    final brace = Paint()
      ..color = const Color(0x44000000)
      ..strokeWidth = tile * .08;
    canvas.drawLine(
      Offset(rect.left + tile * .1, rect.top + tile * .1),
      Offset(rect.right - tile * .1, rect.bottom - tile * .1),
      brace,
    );
    canvas.drawLine(
      Offset(rect.right - tile * .1, rect.top + tile * .1),
      Offset(rect.left + tile * .1, rect.bottom - tile * .1),
      brace,
    );
  }

  /// Alet kutusu: kırıldığında geçici özel silah bırakır.
  void _weaponCrate(Canvas canvas, Rect rect) {
    final tile = rect.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(tile * .1)),
      Paint()..color = const Color(0xff2f3a4d),
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top + tile * .42, tile, tile * .1),
      Paint()..color = const Color(0xffee9f2b),
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.left + tile * .56, rect.top + tile * .12)
        ..lineTo(rect.left + tile * .36, rect.top + tile * .52)
        ..lineTo(rect.left + tile * .52, rect.top + tile * .52)
        ..lineTo(rect.left + tile * .42, rect.top + tile * .88)
        ..lineTo(rect.left + tile * .68, rect.top + tile * .44)
        ..lineTo(rect.left + tile * .52, rect.top + tile * .44)
        ..close(),
      Paint()..color = const Color(0xff8be9fd),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(tile * .1)),
      Paint()
        ..color = const Color(0x33000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _barrel(Canvas canvas, Rect rect) {
    final tile = rect.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(tile * .22)),
      Paint()..color = const Color(0xff8a5a2b),
    );
    final band = Paint()..color = const Color(0xff5a5f66);
    canvas.drawRect(Rect.fromLTWH(rect.left + tile * .05, rect.top + tile * .16, tile * .90, tile * .10), band);
    canvas.drawRect(Rect.fromLTWH(rect.left + tile * .05, rect.top + tile * .74, tile * .90, tile * .10), band);
    canvas.drawRect(
      Rect.fromLTWH(rect.left + tile * .16, rect.top, tile * .14, tile),
      Paint()..color = const Color(0x33ffffff),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(tile * .22)),
      Paint()
        ..color = const Color(0x22000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _question(Canvas canvas, Rect rect, bool heart) {
    final tile = rect.width;
    final base = heart ? const Color(0xffef4444) : const Color(0xfff6b93b);
    canvas.drawRect(rect, Paint()..color = base);
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, tile, tile * .16),
      Paint()..color = Colors.white.withValues(alpha: .3),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = const Color(0x55000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    if (heart) {
      final white = Paint()..color = Colors.white;
      canvas.drawCircle(
        Offset(rect.left + tile * .34, rect.top + tile * .42),
        tile * .14,
        white,
      );
      canvas.drawCircle(
        Offset(rect.left + tile * .66, rect.top + tile * .42),
        tile * .14,
        white,
      );
      final path = Path()
        ..moveTo(rect.left + tile * .12, rect.top + tile * .48)
        ..lineTo(rect.left + tile * .88, rect.top + tile * .48)
        ..lineTo(rect.left + tile * .5, rect.top + tile * .84)
        ..close();
      canvas.drawPath(path, white);
    } else {
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: '?',
          style: TextStyle(
            color: const Color(0xff6b4a06),
            fontWeight: FontWeight.w900,
            fontSize: tile * .62,
          ),
        ),
      )..layout();
      tp.paint(
        canvas,
        Offset(
          rect.left + (tile - tp.width) / 2,
          rect.top + (tile - tp.height) / 2,
        ),
      );
    }
  }

  void _pipe(Canvas canvas, int col, int row, Rect rect) {
    final tile = rect.width;
    final capped = s._tileAt(row - 1, col) != 'P';
    canvas.drawRect(rect, Paint()..color = const Color(0xff16a34a));
    canvas.drawRect(
      Rect.fromLTWH(rect.left + tile * .14, rect.top, tile * .16, tile),
      Paint()..color = const Color(0x66bbf7d0),
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left + tile * .72, rect.top, tile * .28, tile),
      Paint()..color = const Color(0x33145232),
    );
    if (capped) {
      canvas.drawRect(
        Rect.fromLTWH(rect.left - tile * .06, rect.top, tile * 1.12, tile * .34),
        Paint()..color = const Color(0xff22c55e),
      );
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left - tile * .06,
          rect.top + tile * .30,
          tile * 1.12,
          tile * .05,
        ),
        Paint()..color = const Color(0x66145232),
      );
    }
  }

  void _coin(Canvas canvas, int col, Rect rect) {
    final spin = math.sin(s._clock * .18 + col * .9).abs() * .72 + .28;
    final center = rect.center;
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: rect.width * .44 * spin,
        height: rect.height * .5,
      ),
      Paint()..color = const Color(0xfff6b93b),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center,
        width: rect.width * .22 * spin,
        height: rect.height * .28,
      ),
      Paint()..color = const Color(0xfffff3c4),
    );
  }

  void _paintFlag(Canvas canvas, double tile) {
    if (s._flagCol == 0) return;
    final x = (s._flagCol + .5 - s._camera) * tile;
    if (x < -2 * tile || x > 15 * tile) return;
    canvas.drawRect(
      Rect.fromLTWH(x - tile * .05, 5 * tile, tile * .1, 7 * tile),
      Paint()..color = const Color(0xffcbd5e1),
    );
    canvas.drawCircle(
      Offset(x, 5 * tile),
      tile * .14,
      Paint()..color = const Color(0xfff6b93b),
    );
    final wave = math.sin(s._clock * .1) * tile * .16;
    final path = Path()
      ..moveTo(x, 5.2 * tile)
      ..lineTo(x + 1.7 * tile + wave, 5.75 * tile)
      ..lineTo(x, 6.3 * tile)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xff22c55e));
  }

  /// Altı düşman türünün kendine özgü sprite'ı: kestane, dikenli, yarasa,
  /// örümcek, taret bitkisi ve kalkanlı muhafız.
  void _paintEnemy(Canvas canvas, _Enemy e, double tile) {
    final left = (e.x - s._camera) * tile;
    if (left < -2.4 * tile || left > (s._viewCols + 2.4) * tile) return;
    final top = e.y * tile;
    final w = .72 * tile;
    final h = .78 * tile;
    double fx(double f) => left + w * f;
    double fy(double f) => top + h * f;
    void box(double x, double y, double ww, double hh, Color c) =>
        canvas.drawRect(Rect.fromLTWH(fx(x), fy(y), w * ww, h * hh), Paint()..color = c);
    void round(double x, double y, double ww, double hh, double r, Color c) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(fx(x), fy(y), w * ww, h * hh),
            Radius.circular(r),
          ),
          Paint()..color = c,
        );
    void dot(double cx, double cy, double r, Color c) =>
        canvas.drawCircle(Offset(fx(cx), fy(cy)), r, Paint()..color = c);
    void eyes(double ex, double ey, double r,
        [Color pupil = const Color(0xff1a1410)]) {
      final look = e.dir > 0 ? r * .4 : -r * .4;
      dot(ex, ey, r, Colors.white);
      dot(ex + r * 1.5, ey, r, Colors.white);
      dot(ex + look, ey, r * .52, pupil);
      dot(ex + r * 1.5 + look, ey, r * .52, pupil);
    }

    final bodyColor = switch (e.kind) {
      _EnemyKind.nut => const Color(0xffc1701f),
      _EnemyKind.spiky => const Color(0xff7c3aed),
      _EnemyKind.flyer => const Color(0xff64527f),
      _EnemyKind.hopper => const Color(0xff6d9440),
      _EnemyKind.turret => const Color(0xff3f8f4a),
      _EnemyKind.guard => const Color(0xff6b7280),
      _EnemyKind.brute => const Color(0xff6b7280),
      _EnemyKind.charger => const Color(0xff8a6a4a),
    };

    if (e.dead) {
      final k = (e.deadTicks / 22).clamp(0.0, 1.0).toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left,
            top + h * (.44 + .34 * (1 - k)),
            w,
            h * (.34 + .24 * k),
          ),
          Radius.circular(tile * .14),
        ),
        Paint()..color = bodyColor.withValues(alpha: .3 + .6 * k),
      );
      return;
    }

    // Yumuşak gölge (uçanlar hariç) sprite'ı zemine oturtur.
    if (e.kind != _EnemyKind.flyer) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(fx(.5), fy(1.02)),
          width: w * .85,
          height: h * .18,
        ),
        Paint()..color = Colors.black.withValues(alpha: .22),
      );
    }

    switch (e.kind) {
      case _EnemyKind.nut:
        round(.0, .08, 1.0, .4, tile * .16, const Color(0xff6d3a12));
        box(.42, -.1, .16, .2, const Color(0xff4a2708));
        round(.03, .18, .94, .8, tile * .2, const Color(0xffb3641f));
        round(.14, .3, .72, .34, tile * .16, const Color(0xff8a4a12));
        box(.18, .66, .64, .1, const Color(0x33ffffff));
        eyes(.14, .44, tile * .075);
        box(.1, .9, .3, .1, const Color(0x77000000));
        box(.6, .9, .3, .1, const Color(0x77000000));
        break;
      case _EnemyKind.spiky:
        final spike = Paint()..color = const Color(0xff3b1372);
        for (final f in [.1, .32, .54, .76, .98]) {
          canvas.drawPath(
            Path()
              ..moveTo(fx(f) - tile * .08, fy(.26))
              ..lineTo(fx(f), fy(-.12))
              ..lineTo(fx(f) + tile * .08, fy(.26))
              ..close(),
            spike,
          );
        }
        canvas.drawPath(
          Path()
            ..moveTo(fx(.0), fy(.5))
            ..lineTo(fx(-.08), fy(.7))
            ..lineTo(fx(.0), fy(.84))
            ..close(),
          spike,
        );
        canvas.drawPath(
          Path()
            ..moveTo(fx(1.0), fy(.5))
            ..lineTo(fx(1.08), fy(.7))
            ..lineTo(fx(1.0), fy(.84))
            ..close(),
          spike,
        );
        round(.02, .2, .96, .76, tile * .26, const Color(0xff7c3aed));
        round(.2, .32, .6, .3, tile * .14, const Color(0xff9d6bff));
        eyes(.18, .46, tile * .075, const Color(0xff2a0a4a));
        box(.16, .34, .22, .07, const Color(0xff3b1372));
        box(.58, .34, .22, .07, const Color(0xff3b1372));
        break;
      case _EnemyKind.flyer:
        final flap = math.sin(e.t * .38) * h * .22;
        final wing = Paint()..color = const Color(0xff463a63);
        canvas.drawPath(
          Path()
            ..moveTo(fx(.16), fy(.44))
            ..lineTo(fx(-.42), fy(.2) + flap)
            ..lineTo(fx(-.3), fy(.62) + flap * .5)
            ..close(),
          wing,
        );
        canvas.drawPath(
          Path()
            ..moveTo(fx(.84), fy(.44))
            ..lineTo(fx(1.42), fy(.2) - flap)
            ..lineTo(fx(1.3), fy(.62) - flap * .5)
            ..close(),
          wing,
        );
        round(.12, .12, .76, .76, tile * .3, const Color(0xff5b4a7a));
        canvas.drawPath(
          Path()
            ..moveTo(fx(.24), fy(.18))
            ..lineTo(fx(.32), fy(-.16))
            ..lineTo(fx(.46), fy(.18))
            ..close(),
          wing,
        );
        canvas.drawPath(
          Path()
            ..moveTo(fx(.54), fy(.18))
            ..lineTo(fx(.68), fy(-.16))
            ..lineTo(fx(.76), fy(.18))
            ..close(),
          wing,
        );
        final fang = Paint()..color = Colors.white;
        canvas.drawPath(
          Path()
            ..moveTo(fx(.34), fy(.72))
            ..lineTo(fx(.4), fy(.9))
            ..lineTo(fx(.46), fy(.72))
            ..close(),
          fang,
        );
        canvas.drawPath(
          Path()
            ..moveTo(fx(.54), fy(.72))
            ..lineTo(fx(.6), fy(.9))
            ..lineTo(fx(.66), fy(.72))
            ..close(),
          fang,
        );
        eyes(.28, .44, tile * .08, const Color(0xffe11d48));
        break;
      case _EnemyKind.hopper:
        final leg = Paint()
          ..color = const Color(0xff40601f)
          ..strokeWidth = tile * .07
          ..strokeCap = StrokeCap.round;
        final sway = math.sin(e.t * .22) * tile * .1;
        for (final f in [.2, .42, .62, .82]) {
          canvas.drawLine(
            Offset(fx(f), fy(.6)),
            Offset(fx(f) - tile * .22, fy(.92) + sway),
            leg,
          );
        }
        round(.08, .24, .84, .62, tile * .2, const Color(0xff6d9440));
        round(.18, .3, .64, .26, tile * .14, const Color(0xff8fbf55));
        for (final f in [.26, .74]) {
          canvas.drawCircle(
            Offset(fx(f), fy(1.0)),
            tile * .07,
            Paint()..color = const Color(0xff40601f),
          );
        }
        eyes(.24, .42, tile * .075, const Color(0xff2d3a12));
        break;
      case _EnemyKind.turret:
        canvas.drawRect(
          Rect.fromLTWH(fx(.42), fy(.4), w * .16, h * .66),
          Paint()..color = const Color(0xff2f7a3d),
        );
        final leaf = Paint()..color = const Color(0xff44a04f);
        canvas.drawOval(Rect.fromLTWH(fx(-.1), fy(.6), w * .5, h * .22), leaf);
        canvas.drawOval(Rect.fromLTWH(fx(.6), fy(.6), w * .5, h * .22), leaf);
        final open = e.cool < 30 ? 1.0 : .35;
        canvas.drawCircle(
          Offset(fx(.5), fy(.34)),
          tile * .3,
          Paint()..color = const Color(0xffc0392b),
        );
        canvas.drawCircle(
          Offset(fx(.5), fy(.34)),
          tile * .3,
          Paint()
            ..color = const Color(0xff7f1d1d)
            ..style = PaintingStyle.stroke
            ..strokeWidth = tile * .05,
        );
        canvas.drawPath(
          Path()
            ..moveTo(fx(.2), fy(.3))
            ..lineTo(fx(.5), fy(.3 + .34 * open))
            ..lineTo(fx(.8), fy(.3))
            ..close(),
          Paint()..color = const Color(0xff3b0a0a),
        );
        dot(.36, .22, tile * .05, Colors.white);
        dot(.64, .22, tile * .05, Colors.white);
        break;
      case _EnemyKind.brute:
        const rock = Color(0xff6b7280);
        const rockDark = Color(0xff3b4250);
        const rockLight = Color(0xff9aa3b0);
        box(.06, .72, .34, .3, rockDark);
        box(.6, .72, .34, .3, rockDark);
        round(.05, .22, .9, .62, tile * .16, rock);
        final crack = Paint()..color = rockDark;
        canvas.drawRect(Rect.fromLTWH(fx(.28), fy(.34), w * .06, h * .34), crack);
        canvas.drawRect(Rect.fromLTWH(fx(.5), fy(.52), w * .26, h * .06), crack);
        canvas.drawRect(Rect.fromLTWH(fx(.64), fy(.28), w * .06, h * .3), crack);
        round(.1, .26, .34, .2, tile * .06, rockLight);
        round(.56, .44, .32, .2, tile * .06, rockLight);
        dot(.3, .42, tile * .085, const Color(0xffff5d3d));
        dot(.66, .42, tile * .085, const Color(0xffff5d3d));
        box(.0, .48, .16, .32, rockLight);
        box(.9, .48, .16, .32, rockLight);
        round(.2, .16, .6, .14, tile * .05, const Color(0xff3f7a4a));
        break;
      case _EnemyKind.charger:
        final lean = e.charge > 0 ? .12 * e.dir : 0.0;
        const fur = Color(0xff8a6a4a);
        const furDark = Color(0xff5c4530);
        box(.14, .82, .22, .18, furDark);
        box(.62, .82, .22, .18, furDark);
        round(.06, .3, .88, .56, tile * .22, fur);
        round(.16, .36, .6, .26, tile * .16, const Color(0xffa07a54));
        round(.3, .24, .4, .14, tile * .07, furDark);
        round(.6 + lean, .18, .42, .42, tile * .16, const Color(0xff9c7850));
        final horn = Paint()..color = const Color(0xffe8e0c8);
        canvas.drawPath(
          Path()
            ..moveTo(fx(.72 + lean), fy(.24))
            ..lineTo(fx(.64 + lean), fy(-.14))
            ..lineTo(fx(.9 + lean), fy(.02))
            ..close(),
          horn,
        );
        dot(.88 + lean, .44, tile * .05, const Color(0xff2a1c10));
        dot(.72 + lean, .33, tile * .07, Colors.white);
        dot(.74 + lean, .34, tile * .04, const Color(0xffb91c1c));
        if (e.charge > 0) {
          final streak = Paint()
            ..color = const Color(0xccffe08a)
            ..strokeWidth = tile * .05
            ..strokeCap = StrokeCap.round;
          for (final off in [.0, .18, .36]) {
            canvas.drawLine(
              Offset(fx(-.2 - off), fy(.42)),
              Offset(fx(-.55 - off), fy(.42)),
              streak,
            );
          }
        }
        break;
      case _EnemyKind.guard:
        const metal = Color(0xff7d8896);
        const metalDark = Color(0xff4b5666);
        box(.16, .78, .28, .16, const Color(0xff33404f));
        box(.56, .78, .28, .16, const Color(0xff33404f));
        round(.1, .3, .8, .56, tile * .12, metal);
        round(.16, .32, .68, .3, tile * .1, const Color(0xff93a1b0));
        round(.22, .04, .56, .32, tile * .14, metalDark);
        box(.3, .18, .4, .1, const Color(0xff1f2732));
        dot(.36, .26, tile * .05, const Color(0xfff59e0b));
        dot(.64, .26, tile * .05, const Color(0xfff59e0b));
        final shieldX = e.dir > 0 ? .98 : -.32;
        canvas.drawPath(
          Path()
            ..moveTo(fx(shieldX), fy(.3))
            ..lineTo(fx(shieldX + .34 * e.dir), fy(.3))
            ..lineTo(fx(shieldX + .34 * e.dir), fy(.72))
            ..lineTo(fx(shieldX), fy(.9))
            ..close(),
          Paint()..color = const Color(0xff8b6b3f),
        );
        canvas.drawRect(
          Rect.fromLTWH(
            fx(e.dir > 0 ? 1.1 : -.18),
            fy(-.3),
            w * .08,
            h * 1.24,
          ),
          Paint()..color = const Color(0xffcbd5e1),
        );
        break;
    }

    // Vuruş flaşı: hasar aldığında kısa süre beyaz parlar.
    if (e.hurt > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, w, h),
          Radius.circular(tile * .18),
        ),
        Paint()..color = Colors.white.withValues(alpha: .5 * (e.hurt / 12)),
      );
    }
  }

  /// Beş ödül türü: altın, kristal, kalp, yıldız ve alet kutusu.
  void _paintPickup(Canvas canvas, _Pickup p, double tile) {
    final left = (p.x - s._camera) * tile;
    if (left < -2 * tile || left > (s._viewCols + 2) * tile) return;
    final fade = p.life < 90 ? (p.life / 90).clamp(0.0, 1.0).toDouble() : 1.0;
    final cx = left + .25 * tile;
    final cy = p.y * tile + .25 * tile + math.sin(p.t * .12) * tile * .07;
    switch (p.kind) {
      case _PickupKind.coin:
        _pickupGlow(canvas, cx, cy, tile, const Color(0xffffd66b), fade);
        final spin = math.sin(s._clock * .2 + p.t * .06).abs() * .72 + .28;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: tile * .44 * spin,
            height: tile * .5,
          ),
          Paint()..color = const Color(0xfff6b93b).withValues(alpha: fade),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: tile * .2 * spin,
            height: tile * .26,
          ),
          Paint()..color = const Color(0xfffff3c4).withValues(alpha: fade),
        );
        break;
      case _PickupKind.gem:
        _pickupGlow(canvas, cx, cy, tile, const Color(0xff7ff2b0), fade);
        canvas.drawPath(
          Path()
            ..moveTo(cx, cy - tile * .26)
            ..lineTo(cx + tile * .2, cy)
            ..lineTo(cx, cy + tile * .26)
            ..lineTo(cx - tile * .2, cy)
            ..close(),
          Paint()..color = const Color(0xff2dd4bf).withValues(alpha: fade),
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx, cy - tile * .15)
            ..lineTo(cx + tile * .11, cy)
            ..lineTo(cx, cy + tile * .15)
            ..lineTo(cx - tile * .11, cy)
            ..close(),
          Paint()..color = const Color(0xffa7f3d0).withValues(alpha: fade),
        );
        break;
      case _PickupKind.heart:
        _pickupGlow(canvas, cx, cy, tile, const Color(0xffff8a9b), fade);
        final heart = Paint()..color = const Color(0xffef4444).withValues(alpha: fade);
        canvas.drawCircle(Offset(cx - tile * .09, cy - tile * .08), tile * .13, heart);
        canvas.drawCircle(Offset(cx + tile * .09, cy - tile * .08), tile * .13, heart);
        canvas.drawPath(
          Path()
            ..moveTo(cx - tile * .21, cy - tile * .02)
            ..lineTo(cx + tile * .21, cy - tile * .02)
            ..lineTo(cx, cy + tile * .26)
            ..close(),
          heart,
        );
        break;
      case _PickupKind.star:
        _pickupGlow(canvas, cx, cy, tile, const Color(0xffffe066), fade);
        final path = Path();
        final rot = s._clock * .05;
        for (var i = 0; i < 10; i++) {
          final ang = -math.pi / 2 + rot + i * math.pi / 5;
          final rad = i.isEven ? tile * .28 : tile * .12;
          final pt = Offset(cx + math.cos(ang) * rad, cy + math.sin(ang) * rad);
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        canvas.drawPath(
          path,
          Paint()..color = const Color(0xffffd23f).withValues(alpha: fade),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xfffff3c4).withValues(alpha: fade * .8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = tile * .03,
        );
        break;
      case _PickupKind.weapon:
        _pickupGlow(canvas, cx, cy, tile, const Color(0xff8be9fd), fade);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: tile * .5,
              height: tile * .4,
            ),
            Radius.circular(tile * .07),
          ),
          Paint()..color = const Color(0xff2f3a4d).withValues(alpha: fade),
        );
        canvas.drawRect(
          Rect.fromLTWH(cx - tile * .25, cy - tile * .06, tile * .5, tile * .09),
          Paint()..color = const Color(0xffee9f2b).withValues(alpha: fade),
        );
        canvas.drawRect(
          Rect.fromLTWH(cx - tile * .06, cy - tile * .2, tile * .12, tile * .4),
          Paint()..color = const Color(0xffcbd5e1).withValues(alpha: fade),
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx + tile * .02, cy - tile * .18)
            ..lineTo(cx - tile * .08, cy + tile * .02)
            ..lineTo(cx, cy + tile * .02)
            ..lineTo(cx - tile * .03, cy + tile * .2)
            ..lineTo(cx + tile * .1, cy - tile * .02)
            ..lineTo(cx + tile * .01, cy - tile * .02)
            ..close(),
          Paint()..color = const Color(0xff8be9fd).withValues(alpha: fade),
        );
        break;
    }
  }

  void _pickupGlow(
    Canvas canvas,
    double cx,
    double cy,
    double tile,
    Color c,
    double fade,
  ) {
    canvas.drawCircle(
      Offset(cx, cy),
      tile * .34,
      Paint()..color = c.withValues(alpha: .18 * fade),
    );
  }

  /// Kahramanın altına yumuşak gölge ve seviyeye bağlı enerji halesi çizer.
  void _paintHeroAura(Canvas canvas, Rect heroRect, double tile) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(heroRect.center.dx, heroRect.bottom + tile * .05),
        width: heroRect.width * .95,
        height: tile * .22,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: .22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final aura = ((s._level - 1) / 8).clamp(0.0, 1.0).toDouble();
    if (aura <= 0) return;
    final pulse = .5 + .5 * math.sin(s._clock * .12).abs();
    canvas.drawCircle(
      heroRect.center,
      heroRect.width * (.85 + aura * .5),
      Paint()
        ..color = const Color(0xff7ff2b0)
            .withValues(alpha: .06 + aura * .12 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  /// Çekiç savurmasında geniş bir vuruş kavisi gösterir; menzil üç karo.
  void _paintHammerArc(
    Canvas canvas,
    Rect heroRect,
    double tile,
    int attack,
    bool powered,
  ) {
    final k = (attack / 13).clamp(0.0, 1.0).toDouble();
    if (k <= 0) return;
    final dir = s._facing.toDouble();
    final reach = tile * (_hammerReach * (0.55 + 0.45 * k));
    final pivot = Offset(heroRect.center.dx, heroRect.center.dy - tile * .08);
    final tint =
        powered ? const Color(0xff8be9fd) : const Color(0xfffff3c4);
    canvas.drawPath(
      Path()
        ..moveTo(pivot.dx, pivot.dy)
        ..arcTo(
          Rect.fromCircle(center: pivot, radius: reach),
          dir > 0 ? -math.pi * .55 : math.pi * .45,
          dir > 0 ? math.pi * 1.1 : -math.pi * 1.1,
          false,
        )
        ..close(),
      Paint()
        ..shader = RadialGradient(
          colors: [tint.withValues(alpha: .34 * k), Colors.transparent],
        ).createShader(Rect.fromCircle(center: pivot, radius: reach)),
    );
  }

  /// Üstte seviye rozeti, XP çubuğu ve aktif özel silah göstergesi.
  void _paintHudBars(Canvas canvas, Size size, double tile) {
    final barW = math.min(size.width * .36, 190.0);
    final barH = tile * .17;
    const left = 10.0;
    const top = 8.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barW, barH),
        Radius.circular(barH),
      ),
      Paint()..color = Colors.black.withValues(alpha: .35),
    );
    final frac = (_xp / _xpNext).clamp(0.0, 1.0).toDouble();
    if (frac > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barW * frac, barH),
          Radius.circular(barH),
        ),
        Paint()..color = const Color(0xff7ff2b0),
      );
    }
    _badgeText(canvas, 'SV $_level', left + barW + 7, top - 3, tile * .36,
        const Color(0xffffe066));
    _badgeText(canvas, '$_xp/$_xpNext XP', left, top + barH + 3, tile * .26,
        const Color(0xccffffff));
    if (_specialActive) {
      final label = _special == _SpecialWeapon.quake
          ? 'YER SARSINTISI'
          : 'ÜÇLÜ KIVILCIM';
      final secs = (_specialTicks / 40).ceil();
      _badgeText(canvas, '$label · $secs sn', left, top + barH + 3 + tile * .32,
          tile * .27, const Color(0xff8be9fd));
    }
    if (_levelFlash > 0) {
      final a = (_levelFlash / 90).clamp(0.0, 1.0).toDouble();
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: 'SEVİYE $_level!',
          style: TextStyle(
            color: const Color(0xffffe066).withValues(alpha: a),
            fontWeight: FontWeight.w900,
            fontSize: tile * .7,
          ),
        ),
      )..layout();
      tp.paint(
        canvas,
        Offset((size.width - tp.width) / 2, size.height * .18),
      );
    }
  }

  void _badgeText(
    Canvas canvas,
    String text,
    double x,
    double y,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: size,
        ),
      ),
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  void _overlay(Canvas canvas, Size size, String title, String subtitle) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: .6),
    );
    final p = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      text: TextSpan(
        text: '$title\n',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 23,
        ),
        children: [
          TextSpan(
            text: subtitle,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    )..layout(maxWidth: size.width - 30);
    p.paint(
      canvas,
      Offset((size.width - p.width) / 2, (size.height - p.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _PlatformPainter old) => true;
}

class _PlatformerControls extends StatelessWidget {
  final ValueChanged<bool> onLeft, onRight;
  final VoidCallback onJumpDown, onJumpUp, onAttack;
  final IconData attackIcon;
  const _PlatformerControls({
    required this.onLeft,
    required this.onRight,
    required this.onJumpDown,
    required this.onJumpUp,
    required this.onAttack,
    required this.attackIcon,
  });

  Widget _holdButton({
    required IconData icon,
    required String label,
    required void Function(bool) onHold,
    bool big = false,
  }) {
    final size = big ? 60.0 : 52.0;
    return Semantics(
      button: true,
      label: label,
      child: Listener(
        onPointerDown: (_) => onHold(true),
        onPointerUp: (_) => onHold(false),
        onPointerCancel: (_) => onHold(false),
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: big ? 32 : 26),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _holdButton(
        icon: Icons.keyboard_arrow_left_rounded,
        label: 'Sol',
        onHold: onLeft,
      ),
      const SizedBox(width: 6),
      _holdButton(
        icon: Icons.keyboard_arrow_right_rounded,
        label: 'Sağ',
        onHold: onRight,
      ),
      const Spacer(),
      _holdButton(
        icon: attackIcon,
        label: 'Saldırı',
        onHold: (v) {
          if (v) onAttack();
        },
      ),
      const SizedBox(width: 8),
      _holdButton(
        icon: Icons.keyboard_arrow_up_rounded,
        label: 'Zıpla',
        big: true,
        onHold: (v) {
          if (v) {
            onJumpDown();
          } else {
            onJumpUp();
          }
        },
      ),
    ],
  );
}

class _HeroCard extends StatelessWidget {
  final _PlatformerHero hero;
  final VoidCallback onTap;
  const _HeroCard({required this.hero, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final info = _heroInfo[hero]!;
    final chief = hero == _PlatformerHero.chief;
    final accent = chief ? const Color(0xfff6b93b) : const Color(0xff7fb4ff);
    return Material(
      color: chief ? const Color(0xff23324c) : const Color(0xff1c2340),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: .35)),
          ),
          child: Row(
            children: [
              Container(
                width: 84,
                height: 98,
                decoration: BoxDecoration(
                  color: const Color(0xff101a2e),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: CustomPaint(painter: _HeroPreviewPainter(hero)),
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
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.tagline,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .55),
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.ability,
                      style: TextStyle(
                        color: accent.withValues(alpha: .9),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _stat('HIZ', info.runStat, accent),
                    const SizedBox(height: 4),
                    _stat('ZIPLAMA', info.jumpStat, accent),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) => Row(
    children: [
      SizedBox(
        width: 58,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .5),
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: .6,
          ),
        ),
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 5,
            minHeight: 5,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            backgroundColor: Colors.white.withValues(alpha: .08),
          ),
        ),
      ),
    ],
  );
}

class _HeroPreviewPainter extends CustomPainter {
  final _PlatformerHero hero;
  const _HeroPreviewPainter(this.hero);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xff15203a));
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 7, size.width, 7),
      Paint()..color = const Color(0xff2f6d47),
    );
    final unit = math.min(size.width * .8, (size.height - 12) * 7 / 9);
    if (unit <= 0) return;
    final box = Rect.fromCenter(
      center: Offset(size.width / 2, (size.height - 7) / 2),
      width: unit,
      height: unit * 9 / 7,
    );
    _drawHeroFigure(canvas, box, hero, 1);
  }

  @override
  bool shouldRepaint(covariant _HeroPreviewPainter old) => old.hero != hero;
}

/// Piksel kahraman çizimi: çekiçli şef ve USB'li programcı. Şekil 7x9
/// birim kutuya çizilir ve hem oyun sahnesinde hem seçim kartında kullanılır.
void _drawHeroFigure(
  Canvas canvas,
  Rect box,
  _PlatformerHero hero,
  int facing, {
  int runPhase = 0,
  bool air = false,
  int attack = 0,
  int level = 1,
}) {
  final u = box.width / 7;
  final v = box.height / 9;
  void px(double x, double y, double w, double h, Color c, [double r = .14]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(box.left + x * u, box.top + y * v, w * u, h * v),
        Radius.circular(u * r),
      ),
      Paint()..color = c,
    );
  }

  // Figür her zaman sağa bakacak biçimde çizilir; sola bakıyorsa tüm çizim
  // yatayda aynalanır. Böylece gövde, kol ve alet de doğru yöne döner.
  canvas.save();
  if (facing < 0) {
    final ccx = box.center.dx;
    canvas.translate(ccx, 0);
    canvas.scale(-1, 1);
    canvas.translate(-ccx, 0);
  }

  final skin = const Color(0xfff2c49b);
  final step = air ? 0.0 : (runPhase == 0 ? 0.0 : .55);
  final double swing = attack > 0 ? (attack > 12 ? 1.2 : attack * .1) : 0.0;

  if (hero == _PlatformerHero.chief) {
    // Botlar (çelik burun + taban).
    px(.5, 8.0 - step, 2.4, .8, const Color(0xff2d2a26));
    px(.4, 8.72 - step, 2.6, .34, const Color(0xff14110f));
    px(4.0, 8.0 + step, 2.4, .8, const Color(0xff2d2a26));
    px(3.9, 8.72 + step, 2.6, .34, const Color(0xff14110f));
    // İş tulumu ve yelek.
    px(.9, 6.3, 5.2, 1.9, const Color(0xff3f4a5a));
    px(.6, 3.4, 5.8, 3.05, const Color(0xffef7d1a));
    px(.6, 4.55, 5.8, .30, const Color(0xfffff2b0));
    px(.6, 5.15, 5.8, .30, const Color(0xfffff2b0));
    px(3.35, 3.4, .5, 3.05, const Color(0xffc25a05));
    px(.85, 3.75, 1.6, 1.0, const Color(0xffd9660d));
    px(.85, 6.0, 5.3, .5, const Color(0xff7a4a12));
    px(3.0, 6.0, 1.15, .5, const Color(0xfff6b93b));
    // Kafa ve kask.
    px(1.5, 1.5, 4.0, 2.1, skin);
    px(1.6, 3.1, 3.8, .5, const Color(0xffd9a978));
    px(1.0, .55, 5.0, 1.5, const Color(0xfffbbf24));
    px(1.0, .55, 5.0, .45, const Color(0xfffff0b0));
    px(4.25, 1.35, 2.6, .5, const Color(0xffd99e14));
    px(.45, 1.35, .65, .5, const Color(0xffd99e14));
    px(2.55, .05, 1.7, .55, const Color(0xffe0a80f));
    px(4.5, 2.15, .9, .85, Colors.white);
    px(4.85, 2.38, .45, .45, const Color(0xff1f2937));
    px(1.5, 2.35, .9, .5, const Color(0xffdcae7d));
    px(2.1, 3.15, 2.4, .35, const Color(0xff7a5a3a));
    // Eldivenli kol.
    px(4.85, 3.55, 2.0, 1.0, const Color(0xff3f4a5a));
    // Çekiç.
    if (attack > 0) {
      px(4.6, 3.1 - swing, 3.2, .55, const Color(0xff8b5a2b));
      px(4.6, 3.1 - swing, 1.2, .55, const Color(0xff5f3a17));
      px(7.5, 1.9 - swing, 1.9, 2.6, const Color(0xff9ca3af));
      px(7.5, 1.9 - swing, 1.9, .75, const Color(0xffe5e7eb));
      px(8.95, 2.4 - swing, .55, 1.6, const Color(0xff6b7280));
    } else {
      px(5.4, 4.3, .65, 3.2, const Color(0xff8b5a2b));
      px(5.4, 4.3, .65, 1.0, const Color(0xff5f3a17));
      px(4.7, 3.5, 2.0, 1.55, const Color(0xff9ca3af));
      px(4.7, 3.5, 2.0, .5, const Color(0xffe5e7eb));
    }
  } else {
    // Spor ayakkabı.
    px(.5, 8.1 - step, 2.4, .75, const Color(0xff111827));
    px(.4, 8.8 - step, 2.6, .3, const Color(0xffe5e7eb));
    px(4.0, 8.1 + step, 2.4, .75, const Color(0xff111827));
    px(3.9, 8.8 + step, 2.6, .3, const Color(0xffe5e7eb));
    // Kot pantolon.
    px(.8, 6.3, 5.4, 1.9, const Color(0xff1f2937));
    // Ceket ve kapüşon.
    px(.7, 3.3, 5.6, 3.1, const Color(0xff1e3a8a));
    px(1.0, 5.4, 5.0, 1.0, const Color(0xff172554));
    px(3.3, 3.3, .45, 3.1, const Color(0xff60a5fa));
    px(2.55, 3.5, .5, 1.2, const Color(0xff93c5fd));
    px(3.9, 3.5, .5, 1.2, const Color(0xff93c5fd));
    // Yüz ve gözlük.
    px(1.9, 1.8, 3.2, 1.9, skin);
    px(1.8, 2.35, 3.5, .6, const Color(0xff1e293b));
    px(1.95, 2.42, 1.45, .45, const Color(0xff0ea5e9));
    px(3.6, 2.42, 1.45, .45, const Color(0xff0ea5e9));
    px(1.95, 2.42, .5, .45, const Color(0xccffffff));
    px(1.0, .8, 5.2, 1.5, const Color(0xff1e3a8a));
    px(1.6, .55, 4.0, .7, const Color(0xff1e40af));
    px(1.5, 1.5, .9, 1.4, const Color(0xff0f172a));
    px(4.6, 1.5, .9, 1.4, const Color(0xff0f172a));
    // Kol.
    px(5.0, 3.5, 1.8, 1.0, const Color(0xff1e3a8a));
    // USB bellek ve kıvılcım ucu.
    if (attack > 0) {
      px(4.7, 3.1, 2.0, .85, const Color(0xffcbd5e1));
      px(6.5, 3.2, .8, .65, const Color(0xfffbbf24));
      canvas.drawCircle(
        Offset(box.left + 7.7 * u, box.top + 3.6 * v),
        u * 1.15,
        Paint()..color = const Color(0x66ffd66b),
      );
      canvas.drawCircle(
        Offset(box.left + 7.7 * u, box.top + 3.6 * v),
        u * .5,
        Paint()..color = const Color(0xfffff3c4),
      );
    } else {
      px(5.4, 4.6, 1.7, .85, const Color(0xffcbd5e1));
      px(5.4, 4.6, .6, .85, const Color(0xfffbbf24));
    }
  }

  // Seviye rütbesi: ilerledikçe kol üzerinde artan çentikler.
  final chevrons = (level - 1).clamp(0, 4);
  for (var i = 0; i < chevrons; i++) {
    px(.95, 6.8 - i * .4, .5, .34, const Color(0xfffff3c4), .35);
  }

  canvas.restore();
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
