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
    'Zıpla, altınları topla, çıkışa ulaş.',
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
// Original side-scrolling platform game
// ---------------------------------------------------------------------------
class _PlatformerGame extends StatefulWidget {
  final bool showPad;
  const _PlatformerGame({required this.showPad});
  @override
  State<_PlatformerGame> createState() => _PlatformerState();
}

class _PlatformerState extends State<_PlatformerGame> {
  static const _playerHeight = .86;
  static const _playerWidth = .72;
  static const _gaps = {14, 15, 31};
  static const _platforms = <String>{
    '5:8',
    '6:8',
    '7:8',
    '8:8',
    '9:8',
    '11:7',
    '12:7',
    '13:7',
    '18:8',
    '19:8',
    '20:8',
    '21:8',
    '25:6',
    '26:6',
    '27:6',
    '28:6',
    '34:8',
    '35:8',
    '36:8',
    '39:7',
    '40:7',
    '41:7',
  };
  static const _coinSites = <Offset>[
    Offset(4, 8),
    Offset(6, 7),
    Offset(8, 7),
    Offset(12, 6),
    Offset(18, 7),
    Offset(20, 7),
    Offset(26, 5),
    Offset(28, 5),
    Offset(34, 7),
    Offset(36, 7),
    Offset(40, 6),
    Offset(43, 9),
  ];

  Timer? _timer;
  double _x = 1.2, _y = 8.9, _vy = 0, _enemyX = 22;
  int _score = 0, _lives = 3, _direction = 1, _tickCount = 0;
  bool _grounded = true, _over = false, _won = false;
  final Set<int> _collectedCoins = {};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (mounted && !_over && !_won) setState(_tick);
    });
  }

  bool _solid(int col, int row) {
    if (col < 0 || col >= 48) return true;
    if (row == 10) return !_gaps.contains(col);
    return _platforms.contains('$col:$row');
  }

  int? _overlappingSolid(double x, double y) {
    final left = x.floor();
    final right = (x + _playerWidth - .001).floor();
    final top = y.floor();
    final bottom = (y + _playerHeight - .001).floor();
    for (var row = top; row <= bottom; row++) {
      for (var col = left; col <= right; col++) {
        if (_solid(col, row)) return row;
      }
    }
    return null;
  }

  void _move(int direction) {
    if (_over || _won) return;
    _direction = direction;
    final next = (_x + direction * .30).clamp(0.0, 47.0).toDouble();
    if (_overlappingSolid(next, _y) == null) {
      setState(() => _x = next);
      _collectCoins();
    }
  }

  void _jump() {
    if (_over || _won) return;
    if (_grounded) {
      setState(() {
        _vy = -.30;
        _grounded = false;
      });
    }
  }

  void _collectCoins() {
    for (var i = 0; i < _coinSites.length; i++) {
      if (_collectedCoins.contains(i)) continue;
      final coin = _coinSites[i];
      if ((_x + .35 - coin.dx).abs() < .65 &&
          (_y + .45 - coin.dy).abs() < .85) {
        _collectedCoins.add(i);
        _score += 10;
      }
    }
  }

  void _tick() {
    _tickCount++;
    _enemyX += (_tickCount % 140 < 70 ? .025 : -.025);
    final nextY = _y + _vy;
    final collisionRow = _overlappingSolid(_x, nextY);
    if (collisionRow != null) {
      if (_vy > 0) {
        _y = collisionRow - _playerHeight;
        _grounded = true;
      } else {
        _y = collisionRow + 1;
      }
      _vy = 0;
    } else {
      _y = nextY;
      _grounded = false;
      _vy = math.min(.30, _vy + .014).toDouble();
    }

    if ((_x - _enemyX).abs() < .68 && (_y - 9.1).abs() < .75) {
      if (_vy > 0 && _y < 9.1) {
        _score += 25;
        _enemyX = -10;
        _vy = -.20;
      } else {
        _loseLife();
      }
    }
    if (_y > 13) _loseLife();
    if (_x >= 46.2) _won = true;
    _collectCoins();
  }

  void _loseLife() {
    _lives--;
    if (_lives <= 0) {
      _over = true;
      return;
    }
    _x = 1.2;
    _y = 8.9;
    _vy = 0;
    _grounded = true;
  }

  void _restart() => setState(() {
    _x = 1.2;
    _y = 8.9;
    _vy = 0;
    _enemyX = 22;
    _score = 0;
    _lives = 3;
    _direction = 1;
    _tickCount = 0;
    _grounded = true;
    _over = false;
    _won = false;
    _collectedCoins.clear();
  });

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ArcadeFrame(
    score: _won
        ? 'BÖLÜM TAMAM • $_score'
        : _over
        ? 'OYUN BİTTİ • $_score'
        : '$_score PTS  •  ♥ $_lives',
    controls: widget.showPad
        ? _VirtualGamepad(
            left: () => _move(-1),
            right: () => _move(1),
            up: _jump,
            a: _jump,
            b: _restart,
          )
        : null,
    child: GestureDetector(
      onTap: () {
        if (_over || _won) {
          _restart();
        } else {
          _jump();
        }
      },
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx.abs() > 3) _move(d.delta.dx > 0 ? 1 : -1);
      },
      child: CustomPaint(
        painter: _PlatformPainter(
          x: _x,
          y: _y,
          camera: (_x - 4).clamp(0.0, 36.0).toDouble(),
          enemyX: _enemyX,
          score: _score,
          coins: _collectedCoins,
          over: _over,
          won: _won,
          facing: _direction,
        ),
        size: Size.infinite,
      ),
    ),
  );
}

class _PlatformPainter extends CustomPainter {
  final double x, y, camera, enemyX;
  final int score, facing;
  final Set<int> coins;
  final bool over, won;
  const _PlatformPainter({
    required this.x,
    required this.y,
    required this.camera,
    required this.enemyX,
    required this.score,
    required this.coins,
    required this.over,
    required this.won,
    required this.facing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xff101a3d), Color(0xff2b3568), Color(0xff3f426e)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bg);
    final tile = size.width / 12;
    final cameraY = (y - 6).clamp(0.0, 1.0).toDouble();
    for (var col = camera.floor(); col < camera + 13; col++) {
      for (var row = 0; row <= 10; row++) {
        final floor = row == 10 && !_PlatformerState._gaps.contains(col);
        final platform = _PlatformerState._platforms.contains('$col:$row');
        if (!floor && !platform) continue;
        final rect = Rect.fromLTWH(
          (col - camera) * tile,
          (row - cameraY) * tile,
          tile,
          tile,
        );
        if (rect.bottom < 0 || rect.top > size.height) continue;
        canvas.drawRect(
          rect,
          Paint()
            ..color = floor ? const Color(0xff286443) : const Color(0xffaa774c),
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top, tile, 4),
          Paint()
            ..color = floor ? const Color(0xff75dd70) : const Color(0xffffc857),
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left + 3, rect.top + 9, tile - 6, 2),
          Paint()..color = Colors.black.withValues(alpha: .15),
        );
      }
    }
    for (var i = 0; i < _PlatformerState._coinSites.length; i++) {
      if (coins.contains(i)) continue;
      final point = _PlatformerState._coinSites[i];
      final center = Offset(
        (point.dx - camera) * tile,
        (point.dy - cameraY) * tile,
      );
      canvas.drawCircle(
        center,
        tile * .19,
        Paint()..color = const Color(0xffffc857),
      );
      canvas.drawCircle(
        center,
        tile * .12,
        Paint()..color = const Color(0xffffefad),
      );
    }
    if (enemyX >= camera - 1 && enemyX <= camera + 13) {
      final enemy = Rect.fromLTWH(
        (enemyX - camera) * tile,
        (9.15 - cameraY) * tile,
        tile * .72,
        tile * .7,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(enemy, const Radius.circular(5)),
        Paint()..color = const Color(0xffe95b67),
      );
      canvas.drawCircle(
        Offset(enemy.left + tile * .23, enemy.top + tile * .24),
        tile * .055,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        Offset(enemy.left + tile * .49, enemy.top + tile * .24),
        tile * .055,
        Paint()..color = Colors.white,
      );
    }
    final player = Rect.fromLTWH(
      (x - camera) * tile,
      (y - cameraY) * tile,
      tile * .72,
      tile * .86,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(player, const Radius.circular(5)),
      Paint()..color = const Color(0xff58b7ff),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        player.left,
        player.top + player.height * .58,
        player.width,
        player.height * .31,
      ),
      Paint()..color = const Color(0xffffca65),
    );
    final eyeX = facing > 0
        ? player.left + player.width * .58
        : player.left + player.width * .25;
    canvas.drawCircle(
      Offset(eyeX, player.top + player.height * .3),
      tile * .06,
      Paint()..color = Colors.white,
    );
    final flagX = (46.4 - camera) * tile;
    canvas.drawLine(
      Offset(flagX, 8.1 * tile),
      Offset(flagX, 10 * tile),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3,
    );
    canvas.drawRect(
      Rect.fromLTWH(flagX, 8.1 * tile, tile * .65, tile * .4),
      Paint()..color = const Color(0xff57e389),
    );
    if (over || won) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: .62),
      );
      _paintCenter(
        canvas,
        size,
        won ? 'BÖLÜM TAMAM' : 'OYUN BİTTİ',
        'Dokun ve yeniden dene',
      );
    }
  }

  void _paintCenter(Canvas canvas, Size size, String title, String subtitle) {
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
