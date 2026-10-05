// ignore_for_file: curly_braces_in_flow_control_structures
part of 'main.dart';

/// ZeroLog Retro: küçük, bağımsız ve offline oyunlar.
/// ROM, reklam, ağ bağlantısı veya üçüncü taraf oyun asset'i kullanmaz.
class RetroGame {
  final String id, title, subtitle, category;
  final IconData icon;
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
    'space_shooter',
    'Space Shooter',
    'Dalga dalga düşmanları temizle.',
    Icons.rocket_launch_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'breakout',
    'Breakout',
    'Tuğlaları kır, topu oyunda tut.',
    Icons.grid_4x4_rounded,
    'Arcade',
  ),
  RetroGame(
    'pong',
    'Pong',
    'Refleks düellosunda rakibini geç.',
    Icons.sports_tennis_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'snake',
    'Snake',
    'Yemleri topla, kuyruğa çarpma.',
    Icons.straighten_rounded,
    'Arcade',
    gamepad: true,
  ),
  RetroGame(
    'tetris',
    'Tetris',
    'Parçaları yerleştir, satırları temizle.',
    Icons.view_module_rounded,
    'Puzzle',
    gamepad: true,
  ),
  RetroGame(
    '2048',
    '2048',
    'Sayıları birleştir ve 2048’e ulaş.',
    Icons.exposure_plus_2_rounded,
    'Puzzle',
  ),
  RetroGame(
    'minesweeper',
    'Minesweeper',
    'Mayınları bul, güvenli alanı aç.',
    Icons.warning_amber_rounded,
    'Puzzle',
  ),
  RetroGame(
    'memory',
    'Memory',
    'Kart çiftlerini en az hamleyle bul.',
    Icons.flip_to_back_outlined,
    'Puzzle',
  ),
  RetroGame(
    'flappy',
    'Flappy',
    'Engellerin arasından geç.',
    Icons.flutter_dash_rounded,
    'Action / Casual',
  ),
];

class RetroArcadePage extends StatefulWidget {
  const RetroArcadePage({super.key});
  @override
  State<RetroArcadePage> createState() => _RetroArcadePageState();
}

class _RetroArcadePageState extends State<RetroArcadePage> {
  String filter = 'Tümü';
  final filters = const ['Tümü', 'Arcade', 'Puzzle', 'Action / Casual'];
  @override
  Widget build(BuildContext context) {
    final t = ThemeController.instance.data;
    final games = _retroGames
        .where((g) => filter == 'Tümü' || g.category == filter)
        .toList();
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Retro Arcade',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.sports_esports_rounded, color: t.primary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                colors: [t.primary.withValues(alpha: .24), t.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: t.primary.withValues(alpha: .18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.videogame_asset_rounded,
                        color: t.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        'ZeroLog Retro',
                        style: TextStyle(
                          color: t.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${_retroGames.length} oyun • tamamen offline • reklam yok',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: t.text.withValues(alpha: .58),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final x = filters[i];
                return ChoiceChip(
                  label: Text(x),
                  selected: x == filter,
                  onSelected: (_) => setState(() => filter = x),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: games.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 11,
              mainAxisSpacing: 11,
              childAspectRatio: 1.03,
            ),
            itemBuilder: (_, i) {
              final g = games[i];
              return _RetroCard(
                game: g,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RetroGamePage(game: g)),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RetroCard extends StatelessWidget {
  final RetroGame game;
  final VoidCallback onTap;
  const _RetroCard({required this.game, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = ThemeController.instance.data;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        borderRadius: BorderRadius.circular(21),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [
                        t.primary.withValues(alpha: .22),
                        t.text.withValues(alpha: .025),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Icon(game.icon, size: 42, color: t.primary),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                game.title,
                style: TextStyle(
                  color: t.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                game.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.text.withValues(alpha: .45),
                  fontSize: 10.5,
                ),
              ),
              if (game.gamepad) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(Icons.gamepad_rounded, size: 13, color: t.primary),
                    const SizedBox(width: 4),
                    Text(
                      'Sanal gamepad',
                      style: TextStyle(fontSize: 9.5, color: t.primary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RetroGamePage extends StatefulWidget {
  final RetroGame game;
  const RetroGamePage({super.key, required this.game});
  @override
  State<RetroGamePage> createState() => _RetroGamePageState();
}

class _RetroGamePageState extends State<RetroGamePage> {
  int _nonce = 0;
  bool showPad = true;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(
        widget.game.title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        if (widget.game.gamepad)
          IconButton(
            tooltip: showPad ? 'Gamepadı gizle' : 'Gamepadı göster',
            onPressed: () => setState(() => showPad = !showPad),
            icon: Icon(
              showPad ? Icons.gamepad_rounded : Icons.gamepad_outlined,
            ),
          ),
        IconButton(
          tooltip: 'Yeniden başlat',
          onPressed: () => setState(() => _nonce++),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: KeyedSubtree(key: ValueKey(_nonce), child: _game(widget.game.id)),
    ),
  );
  Widget _game(String id) {
    switch (id) {
      case 'space_shooter':
        return _SpaceGame(showPad: showPad);
      case 'breakout':
        return const _BreakoutGame();
      case 'pong':
        return _PongGame(showPad: showPad);
      case 'snake':
        return _SnakeGame(showPad: showPad);
      case 'tetris':
        return _TetrisGame(showPad: showPad);
      case '2048':
        return const _Twenty48Game();
      case 'minesweeper':
        return const _MinesGame();
      case 'memory':
        return const _MemoryGame();
      case 'flappy':
        return const _FlappyGame();
      default:
        return const SizedBox.shrink();
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
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 8, color: Color(0xff48ff9b)),
                const SizedBox(width: 7),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Text(
                  score,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
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
                color: const Color(0xff070a10),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .45),
                    blurRadius: 25,
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  if (controls != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: controls!,
                    ),
                ],
              ),
            ),
          ),
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
  Widget _btn(IconData icon, VoidCallback? on, String label) => Semantics(
    button: true,
    enabled: on != null,
    label: label,
    child: SizedBox(
      width: 54,
      height: 54,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: on == null ? .035 : .12),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: on == null ? Colors.white10 : Colors.white24,
            ),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Icon(
            icon,
            color: on == null ? Colors.white24 : Colors.white,
            size: 25,
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
          _btn(Icons.keyboard_arrow_up_rounded, up, 'Yukarı'),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _btn(Icons.keyboard_arrow_left_rounded, left, 'Sol'),
              const SizedBox(width: 5),
              _btn(Icons.keyboard_arrow_down_rounded, down, 'Aşağı'),
              const SizedBox(width: 5),
              _btn(Icons.keyboard_arrow_right_rounded, right, 'Sağ'),
            ],
          ),
        ],
      ),
      const Spacer(),
      Row(
        children: [
          if (b != null) _btn(Icons.close_rounded, b, 'B'),
          if (b != null && a != null) const SizedBox(width: 9),
          if (a != null) _btn(Icons.circle_rounded, a, 'A'),
        ],
      ),
    ],
  );
}

class _SnakeGame extends StatefulWidget {
  final bool showPad;
  const _SnakeGame({required this.showPad});
  @override
  State<_SnakeGame> createState() => _SnakeState();
}

class _SnakeState extends State<_SnakeGame> {
  final r = math.Random();
  List<math.Point<int>> snake = [];
  math.Point<int> dir = const math.Point(1, 0);
  math.Point<int> food = const math.Point(5, 5);
  Timer? timer;
  int score = 0;
  bool over = false;
  @override
  void initState() {
    super.initState();
    _reset();
    timer = Timer.periodic(const Duration(milliseconds: 125), (_) {
      if (mounted && !over) setState(_tick);
    });
  }

  void _reset() {
    snake = [
      const math.Point(5, 8),
      const math.Point(4, 8),
      const math.Point(3, 8),
    ];
    dir = const math.Point(1, 0);
    score = 0;
    over = false;
    _food();
  }

  void _food() {
    final occupied = snake.toSet();
    final available = <math.Point<int>>[
      for (var y = 0; y < 19; y++)
        for (var x = 0; x < 15; x++) math.Point(x, y),
    ].where((point) => !occupied.contains(point)).toList();

    if (available.isEmpty) {
      over = true;
      return;
    }

    food = available[r.nextInt(available.length)];
  }

  void turn(math.Point<int> d) {
    if (d.x == -dir.x && d.y == -dir.y) return;
    dir = d;
  }

  void _tick() {
    final h = snake.first;
    final n = math.Point(h.x + dir.x, h.y + dir.y);
    if (n.x < 0 || n.x >= 15 || n.y < 0 || n.y >= 19 || snake.contains(n)) {
      over = true;
      return;
    }
    snake.insert(0, n);
    if (n == food) {
      score += 10;
      _food();
    } else {
      snake.removeLast();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: over ? 'OYUN BİTTİ • $score' : '$score PTS',
    controls: widget.showPad
        ? _VirtualGamepad(
            up: () => setState(() => turn(const math.Point(0, -1))),
            down: () => setState(() => turn(const math.Point(0, 1))),
            left: () => setState(() => turn(const math.Point(-1, 0))),
            right: () => setState(() => turn(const math.Point(1, 0))),
            a: () => setState(() {
              if (over) _reset();
            }),
            b: () => setState(_reset),
          )
        : null,
    child: GestureDetector(
      onPanEnd: (d) {
        final v = d.velocity.pixelsPerSecond;
        if (v.dx.abs() > v.dy.abs()) {
          turn(math.Point(v.dx > 0 ? 1 : -1, 0));
        } else {
          turn(math.Point(0, v.dy > 0 ? 1 : -1));
        }
      },
      child: CustomPaint(
        painter: _SnakePainter(snake, food, over),
        size: Size.infinite,
      ),
    ),
  );
}

class _BreakoutGame extends StatefulWidget {
  const _BreakoutGame();
  @override
  State<_BreakoutGame> createState() => _BreakoutState();
}

class _BreakoutState extends State<_BreakoutGame> {
  double x = .5, y = .72, vx = .012, vy = -.015, paddle = .5;
  int score = 0, lives = 3;
  final List<bool> bricks = List<bool>.filled(30, true);
  Timer? tm;

  @override
  void initState() {
    super.initState();
    tm = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) setState(_tick);
    });
  }

  void _resetBall() {
    x = .5;
    y = .72;
    vx = .012;
    vy = -.015;
  }

  void _resetBricks() {
    for (var i = 0; i < bricks.length; i++) {
      bricks[i] = true;
    }
  }

  void _tick() {
    x += vx;
    y += vy;

    if (x < .03 || x > .97) {
      vx = -vx;
      x = x.clamp(.03, .97).toDouble();
    }

    if (y < .04) {
      vy = vy.abs();
      y = .04;
    }

    // 6 columns × 5 rows of real Breakout bricks.
    for (var row = 0; row < 5; row++) {
      for (var col = 0; col < 6; col++) {
        final index = row * 6 + col;
        if (!bricks[index]) continue;

        final left = .015 + col / 6;
        final right = .985 - (5 - col) / 6;
        final top = .025 + row * .045;
        final bottom = top + .035;

        if (x >= left && x <= right && y >= top && y <= bottom && vy < 0) {
          bricks[index] = false;
          vy = vy.abs();
          score += 10;
          break;
        }
      }
    }

    if (y > .86 && y < .95 && (x - paddle).abs() < .16 && vy > 0) {
      vy = -vy.abs();

      // Give the paddle some influence over the horizontal direction.
      final offset = (x - paddle) / .16;
      vx = (vx + offset * .004).clamp(-.018, .018).toDouble();
      if (vx.abs() < .004) {
        vx = vx < 0 ? -.004 : .004;
      }
    }

    if (bricks.every((brick) => !brick)) {
      _resetBricks();
      _resetBall();
      vx *= 1.08;
      vy *= 1.08;
    }

    if (y > 1) {
      lives--;
      if (lives <= 0) {
        lives = 3;
        score = 0;
        _resetBricks();
      }
      _resetBall();
    }
  }

  @override
  void dispose() {
    tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: '$score  •  ♥ $lives',
    child: GestureDetector(
      onHorizontalDragUpdate: (d) => setState(
        () => paddle = (paddle + d.primaryDelta! / 300)
            .clamp(.12, .88)
            .toDouble(),
      ),
      onTapDown: (d) => setState(
        () => paddle = (d.localPosition.dx / MediaQuery.sizeOf(c).width)
            .clamp(.12, .88)
            .toDouble(),
      ),
      child: CustomPaint(
        painter: _BreakPainter(x, y, paddle, bricks),
        size: Size.infinite,
      ),
    ),
  );
}

class _PongGame extends StatefulWidget {
  final bool showPad;
  const _PongGame({required this.showPad});
  @override
  State<_PongGame> createState() => _PongState();
}

class _PongState extends State<_PongGame> {
  double bx = .5, by = .5, vx = .012, vy = .008, me = .5, ai = .5;
  int score = 0;
  Timer? tm;
  @override
  void initState() {
    super.initState();
    tm = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) setState(_tick);
    });
  }

  void _tick() {
    bx += vx;
    by += vy;
    if (by < .04 || by > .96) {
      vy = -vy;
      by = by.clamp(.04, .96).toDouble();
    }
    ai += (by - ai) * .035;
    if (bx < .08 && (by - me).abs() < .15) vx = vx.abs();
    if (bx > .92 && (by - ai).abs() < .15) {
      vx = -vx.abs();
      score++;
    }
    if (bx < -.03 || bx > 1.03) {
      final servedFromLeft = bx < 0;
      bx = .5;
      by = .5;
      vx = servedFromLeft ? .012 : -.012;
    }
  }

  void move(double d) =>
      setState(() => me = (me + d).clamp(.12, .88).toDouble());
  @override
  void dispose() {
    tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: '$score PTS',
    controls: widget.showPad
        ? _VirtualGamepad(
            up: () => move(-.08),
            down: () => move(.08),
            a: () => move(-.12),
            b: () => move(.12),
          )
        : null,
    child: GestureDetector(
      onVerticalDragUpdate: (d) => move(d.primaryDelta! / 300),
      child: CustomPaint(
        painter: _PongPainter(bx, by, me, ai),
        size: Size.infinite,
      ),
    ),
  );
}

class _SpaceGame extends StatefulWidget {
  final bool showPad;
  const _SpaceGame({required this.showPad});
  @override
  State<_SpaceGame> createState() => _SpaceState();
}

class _SpaceState extends State<_SpaceGame> {
  double ship = .5;
  List<Offset> shots = [], enemies = [];
  int score = 0;
  Timer? tm;
  final r = math.Random();
  @override
  void initState() {
    super.initState();
    _reset();
    tm = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (mounted) setState(_tick);
    });
  }

  void _reset() {
    ship = .5;
    score = 0;
    shots = [];
    enemies = [
      for (int i = 0; i < 8; i++) Offset(.1 + i * .11, .10 + (i % 2) * .11),
    ];
  }

  void fire() {
    shots.add(Offset(ship, .88));
  }

  void _tick() {
    shots = [
      for (final s in shots)
        if (s.dy > .02) Offset(s.dx, s.dy - .025),
    ];
    if (r.nextDouble() < .035) {
      enemies.add(Offset(.08 + r.nextDouble() * .84, .03));
    }
    final hitEnemies = <Offset>{};
    final hitShots = <Offset>{};

    for (final s in shots) {
      for (final e in enemies) {
        if (hitEnemies.contains(e)) continue;
        if ((s.dx - e.dx).abs() < .045 && (s.dy - e.dy).abs() < .045) {
          hitEnemies.add(e);
          hitShots.add(s);
          break;
        }
      }
    }

    shots = [
      for (final s in shots)
        if (!hitShots.contains(s)) s,
    ];

    for (final e in hitEnemies) {
      enemies.remove(e);
      score += 10;
    }
    enemies = [for (final e in enemies) Offset(e.dx, e.dy + .0028)];
    if (enemies.any((e) => e.dy > .91)) _reset();
  }

  void move(double d) =>
      setState(() => ship = (ship + d).clamp(.05, .95).toDouble());
  @override
  void dispose() {
    tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: '$score PTS',
    controls: widget.showPad
        ? _VirtualGamepad(
            left: () => move(-.07),
            right: () => move(.07),
            a: () => fire(),
            b: () => setState(_reset),
          )
        : null,
    child: GestureDetector(
      onHorizontalDragUpdate: (d) => move(d.primaryDelta! / 300),
      onTap: fire,
      child: CustomPaint(
        painter: _SpacePainter(ship, shots, enemies),
        size: Size.infinite,
      ),
    ),
  );
}

class _TetrisGame extends StatefulWidget {
  final bool showPad;
  const _TetrisGame({required this.showPad});
  @override
  State<_TetrisGame> createState() => _TetrisState();
}

class _TetrisState extends State<_TetrisGame> {
  List<List<int>> board = List.generate(20, (_) => List.filled(10, 0));
  int x = 4, y = 0, kind = 0, score = 0, rotation = 0;
  Timer? timer;
  final r = math.Random();
  final shapes = const [
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
  ];
  @override
  void initState() {
    super.initState();
    _spawn();
    timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (mounted) setState(_drop);
    });
  }

  List<List<int>> get s {
    var out = shapes[kind].map((row) => List<int>.from(row)).toList();
    for (var n = 0; n < rotation; n++) {
      final h = out.length, w = out.first.length;
      out = List.generate(
        w,
        (yy) => List.generate(h, (xx) => out[h - 1 - xx][yy]),
      );
    }
    return out;
  }

  bool can(int nx, int ny) {
    for (int yy = 0; yy < s.length; yy++)
      for (int xx = 0; xx < s[yy].length; xx++) {
        if (s[yy][xx] == 1) {
          final bx = nx + xx, by = ny + yy;
          if (bx < 0 ||
              bx >= 10 ||
              by >= 20 ||
              (by >= 0 && board[by][bx] != 0)) {
            return false;
          }
        }
      }
    return true;
  }

  void _spawn() {
    kind = r.nextInt(shapes.length);
    rotation = 0;
    x = 4;
    y = 0;
    if (!can(x, y)) {
      board = List.generate(20, (_) => List.filled(10, 0));
      score = 0;
    }
  }

  void _drop() {
    if (can(x, y + 1)) {
      y++;
      return;
    }
    for (int yy = 0; yy < s.length; yy++)
      for (int xx = 0; xx < s[yy].length; xx++) {
        if (s[yy][xx] == 1 && y + yy >= 0) board[y + yy][x + xx] = kind + 1;
      }
    final before = board.length;
    board.removeWhere((row) => row.every((v) => v != 0));
    score += (before - board.length) * 100;
    while (board.length < 20) {
      board.insert(0, List.filled(10, 0));
    }
    _spawn();
  }

  void _resetGame() {
    setState(() {
      board = List.generate(20, (_) => List.filled(10, 0));
      x = 4;
      y = 0;
      score = 0;
      rotation = 0;
      kind = r.nextInt(shapes.length);
    });
  }

  void move(int d) {
    if (can(x + d, y)) setState(() => x += d);
  }

  void rotate() {
    final next = (rotation + 1) % 4;
    final old = rotation;
    setState(() {
      rotation = next;
      if (!can(x, y)) rotation = old;
    });
  }

  void hard() {
    setState(() {
      while (can(x, y + 1)) {
        y++;
      }
      _drop();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: '$score',
    controls: widget.showPad
        ? _VirtualGamepad(
            left: () => move(-1),
            right: () => move(1),
            down: () => setState(_drop),
            up: hard,
            a: rotate,
            b: _resetGame,
          )
        : null,
    child: GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx.abs() > 7) move(d.delta.dx > 0 ? 1 : -1);
      },
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 0) hard();
      },
      child: CustomPaint(
        painter: _TetrisPainter(board, s, x, y, kind),
        size: Size.infinite,
      ),
    ),
  );
}

class _Twenty48Game extends StatefulWidget {
  const _Twenty48Game();
  @override
  State<_Twenty48Game> createState() => _Twenty48State();
}

class _Twenty48State extends State<_Twenty48Game> {
  List<int> b = List.filled(16, 0);
  int score = 0;
  bool over = false, won = false;
  final r = math.Random();
  @override
  void initState() {
    super.initState();
    _new();
  }

  void _new() {
    b = List.filled(16, 0);
    score = 0;
    over = false;
    won = false;
    _add();
    _add();
  }

  void _add() {
    final e = [
      for (int i = 0; i < 16; i++)
        if (b[i] == 0) i,
    ];
    if (e.isNotEmpty) b[e[r.nextInt(e.length)]] = r.nextDouble() < .9 ? 2 : 4;
  }

  void swipe(int d) {
    if (over || won) return;
    final old = List<int>.from(b), nb = List.filled(16, 0);
    bool moved = false;
    for (int line = 0; line < 4; line++) {
      var a = [
        for (int i = 0; i < 4; i++)
          d <= 2 ? old[line * 4 + i] : old[i * 4 + line],
      ];
      if (d == 1 || d == 4) a = a.reversed.toList();
      var compact = a.where((v) => v > 0).toList();
      for (int j = 0; j < compact.length - 1; j++) {
        if (compact[j] == compact[j + 1]) {
          compact[j] *= 2;
          score += compact[j];
          compact.removeAt(j + 1);
        }
      }
      while (compact.length < 4) {
        compact.add(0);
      }
      if (d == 1 || d == 4) compact = compact.reversed.toList();
      for (int i = 0; i < 4; i++) {
        final idx = d <= 2 ? line * 4 + i : i * 4 + line;
        if (nb[idx] != compact[i]) moved = true;
        nb[idx] = compact[i];
      }
    }
    if (moved) {
      b = nb;
      _add();
      won = b.contains(2048);
      if (!won && !_movesAvailable()) over = true;
      setState(() {});
    }
  }

  bool _movesAvailable() {
    for (var i = 0; i < 16; i++) {
      if (b[i] == 0) return true;
      final x = i % 4, y = i ~/ 4;
      if (x < 3 && b[i] == b[i + 1]) return true;
      if (y < 3 && b[i] == b[i + 4]) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: won
        ? '2048! • $score'
        : over
        ? 'OYUN BİTTİ • $score'
        : '$score',
    child: GestureDetector(
      onVerticalDragEnd: (d) => swipe((d.primaryVelocity ?? 0) > 0 ? 3 : 4),
      onHorizontalDragEnd: (d) => swipe((d.primaryVelocity ?? 0) > 0 ? 2 : 1),
      child: GridView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: 16,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 9,
          mainAxisSpacing: 9,
        ),
        itemBuilder: (_, i) => Container(
          decoration: BoxDecoration(
            color: _tile(b[i]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: Text(
              b[i] == 0 ? '' : '${b[i]}',
              style: TextStyle(
                color: b[i] > 4 ? Colors.black : Colors.white,
                fontSize: b[i] > 999 ? 20 : 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Color _tile(int v) {
    if (v == 0) return const Color(0xff151b27);
    final k = (math.log(v) / math.log(2)).round();
    return [
      const Color(0xff334155),
      const Color(0xff3b82f6),
      const Color(0xff8b5cf6),
      const Color(0xffec4899),
      const Color(0xfff59e0b),
      const Color(0xff22c55e),
    ][k.clamp(0, 5).toInt()];
  }
}

class _MinesGame extends StatefulWidget {
  const _MinesGame();
  @override
  State<_MinesGame> createState() => _MinesState();
}

class _MinesState extends State<_MinesGame> {
  late List<bool> mines, open, flags;
  final r = math.Random();
  bool over = false, won = false;
  @override
  void initState() {
    super.initState();
    _new();
  }

  void _new() {
    mines = List.filled(36, false);
    open = List.filled(36, false);
    flags = List.filled(36, false);
    over = false;
    won = false;
    final ids = <int>{};
    while (ids.length < 6) {
      ids.add(r.nextInt(36));
    }
    for (final i in ids) {
      mines[i] = true;
    }
  }

  int around(int i) {
    final x = i % 6, y = i ~/ 6;
    var n = 0;
    for (final dx in [-1, 0, 1])
      for (final dy in [-1, 0, 1]) {
        final xx = x + dx, yy = y + dy;
        if (xx >= 0 && xx < 6 && yy >= 0 && yy < 6 && mines[yy * 6 + xx]) n++;
      }
    return n;
  }

  void tap(int i) {
    if (over || flags[i] || open[i]) return;
    if (mines[i]) {
      setState(() {
        open = List.filled(36, true);
        over = true;
      });
      return;
    }
    final q = [i];
    while (q.isNotEmpty) {
      final n = q.removeLast();
      if (open[n] || flags[n] || mines[n]) continue;
      open[n] = true;
      if (around(n) == 0) {
        final x = n % 6, y = n ~/ 6;
        for (final dx in [-1, 0, 1])
          for (final dy in [-1, 0, 1]) {
            final xx = x + dx, yy = y + dy;
            if (xx >= 0 && xx < 6 && yy >= 0 && yy < 6) q.add(yy * 6 + xx);
          }
      }
    }
    if (open.where((x) => x).length >= 30) won = true;
    setState(() {});
  }

  void flag(int i) {
    if (over || open[i]) return;
    setState(() => flags[i] = !flags[i]);
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: won
        ? 'KAZANDIN'
        : over
        ? 'PATLADI'
        : '💣 ${flags.where((x) => x).length}/6',
    child: GridView.builder(
      padding: const EdgeInsets.all(18),
      itemCount: 36,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemBuilder: (_, i) => GestureDetector(
        onLongPress: () => flag(i),
        onTap: () => tap(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: BoxDecoration(
            color: open[i] ? const Color(0xff1f2937) : const Color(0xff334155),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: open[i]
                ? Text(
                    mines[i]
                        ? '💥'
                        : around(i) == 0
                        ? ''
                        : '${around(i)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  )
                : Icon(
                    flags[i] ? Icons.flag_rounded : Icons.help_outline_rounded,
                    color: flags[i] ? const Color(0xffffc857) : Colors.white38,
                    size: 18,
                  ),
          ),
        ),
      ),
    ),
  );
}

class _MemoryGame extends StatefulWidget {
  const _MemoryGame();
  @override
  State<_MemoryGame> createState() => _MemoryState();
}

class _MemoryState extends State<_MemoryGame> {
  late List<int> cards;
  List<int> open = [];
  Set<int> matched = {};
  int moves = 0;
  bool locked = false;
  @override
  void initState() {
    super.initState();
    _new();
  }

  void _new() {
    cards = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]..shuffle();
    open = [];
    matched = {};
    moves = 0;
    locked = false;
  }

  void tap(int i) {
    if (locked || open.contains(i) || matched.contains(i)) return;
    setState(() => open.add(i));
    if (open.length == 2) {
      moves++;
      if (cards[open[0]] == cards[open[1]]) {
        setState(() => matched.addAll(open));
        open = [];
      } else {
        locked = true;
        final a = List<int>.from(open);
        Future.delayed(const Duration(milliseconds: 650), () {
          if (!mounted) return;
          setState(() {
            open.removeWhere(a.contains);
            locked = false;
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: '$moves HAMLE',
    child: GridView.builder(
      padding: const EdgeInsets.all(18),
      itemCount: 16,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
      ),
      itemBuilder: (_, i) {
        final show = open.contains(i) || matched.contains(i);
        return GestureDetector(
          onTap: () => tap(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: show ? const Color(0xff48ff9b) : const Color(0xff202838),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(
                show ? ['★', '◆', '●', '▲', '✦', '♥', '☀', '♣'][cards[i]] : '?',
                style: TextStyle(
                  color: show ? Colors.black : Colors.white54,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _FlappyGame extends StatefulWidget {
  const _FlappyGame();
  @override
  State<_FlappyGame> createState() => _FlappyState();
}

class _FlappyState extends State<_FlappyGame> {
  double y = .5, vy = 0, pipe = .8, gap = .48;
  int score = 0;
  bool over = false;
  Timer? tm;
  final r = math.Random();
  @override
  void initState() {
    super.initState();
    tm = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (mounted && !over) setState(_tick);
    });
  }

  void flap() {
    if (over) {
      setState(() {
        y = .5;
        vy = 0;
        pipe = .8;
        score = 0;
        over = false;
      });
      return;
    }
    vy = -.022;
  }

  void _tick() {
    vy += .0018;
    y += vy;
    pipe -= .008;
    if (pipe < -.1) {
      pipe = 1.05;
      gap = .25 + r.nextDouble() * .5;
      score++;
    }
    if (y < .04 ||
        y > .96 ||
        (pipe < .34 && pipe > .05 && (y < gap - .15 || y > gap + .15))) {
      over = true;
    }
  }

  @override
  void dispose() {
    tm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => _ArcadeFrame(
    score: over ? 'GAME OVER • $score' : '$score PTS',
    child: GestureDetector(
      onTap: flap,
      child: CustomPaint(
        painter: _FlappyPainter(y, pipe, gap, over),
        size: Size.infinite,
      ),
    ),
  );
}

class _SnakePainter extends CustomPainter {
  final List<math.Point<int>> s;
  final math.Point<int> f;
  final bool over;
  _SnakePainter(this.s, this.f, this.over);
  @override
  void paint(Canvas c, Size z) {
    final p = Paint();
    final cw = z.width / 15, ch = z.height / 19;
    p.color = const Color(0xff0c1220);
    c.drawRect(Offset.zero & z, p);
    p.color = const Color(0xff48ff9b);
    for (final q in s) {
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(q.x * cw + 2, q.y * ch + 2, cw - 4, ch - 4),
          const Radius.circular(6),
        ),
        p,
      );
    }
    p.color = const Color(0xffff4f8b);
    c.drawCircle(
      Offset((f.x + .5) * cw, (f.y + .5) * ch),
      math.min(cw, ch) * .32,
      p,
    );
    if (over) {
      p.color = Colors.black54;
      c.drawRect(Offset.zero & z, p);
      _center(c, z, 'GAME OVER');
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter o) => true;
}

class _BreakPainter extends CustomPainter {
  final double x, y, p;
  final List<bool> bricks;

  _BreakPainter(this.x, this.y, this.p, this.bricks);

  @override
  void paint(Canvas c, Size z) {
    final q = Paint()..color = const Color(0xff48ff9b);

    for (var j = 0; j < 5; j++) {
      for (var i = 0; i < 6; i++) {
        final index = j * 6 + i;
        if (!bricks[index]) continue;

        q.color = Color.lerp(
          const Color(0xff55b7ff),
          const Color(0xffff4f8b),
          j / 4,
        )!;

        c.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              10 + i * z.width / 6,
              18 + j * 27,
              z.width / 6 - 14,
              21,
            ),
            const Radius.circular(7),
          ),
          q,
        );
      }
    }

    q.color = Colors.white;
    c.drawCircle(Offset(x * z.width, y * z.height), 7, q);

    q.color = const Color(0xff48ff9b);
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(p * z.width - 48, z.height - 34, 96, 14),
        const Radius.circular(8),
      ),
      q,
    );
  }

  @override
  bool shouldRepaint(covariant _BreakPainter o) => true;
}

class _PongPainter extends CustomPainter {
  final double x, y, m, a;
  _PongPainter(this.x, this.y, this.m, this.a);
  @override
  void paint(Canvas c, Size z) {
    final p = Paint()..color = Colors.white;
    final h = z.height * .16;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, m * z.height - h / 2, 10, h),
        const Radius.circular(5),
      ),
      p,
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(z.width - 22, a * z.height - h / 2, 10, h),
        const Radius.circular(5),
      ),
      p,
    );
    c.drawCircle(Offset(x * z.width, y * z.height), 8, p);
    p.color = Colors.white12;
    for (double yy = 0; yy < z.height; yy += 28) {
      c.drawRect(Rect.fromLTWH(z.width / 2 - 1, yy, 2, 14), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PongPainter o) => true;
}

class _SpacePainter extends CustomPainter {
  final double ship;
  final List<Offset> shots, enemies;
  _SpacePainter(this.ship, this.shots, this.enemies);
  @override
  void paint(Canvas c, Size z) {
    final p = Paint();
    p.color = const Color(0xff070a10);
    c.drawRect(Offset.zero & z, p);
    p.color = Colors.white24;
    for (int i = 0; i < 40; i++) {
      c.drawCircle(
        Offset(
          (i * 73 % 100) / 100 * z.width,
          (i * 137 % 100) / 100 * z.height,
        ),
        1.2,
        p,
      );
    }
    p.color = const Color(0xff48ff9b);
    final sx = ship * z.width;
    final sy = z.height * .9;
    c.drawPath(
      Path()
        ..moveTo(sx, sy - 22)
        ..lineTo(sx - 16, sy + 16)
        ..lineTo(sx, sy + 9)
        ..lineTo(sx + 16, sy + 16)
        ..close(),
      p,
    );
    p.color = Colors.white;
    for (final s in shots) {
      c.drawRect(
        Rect.fromCenter(
          center: Offset(s.dx * z.width, s.dy * z.height),
          width: 3,
          height: 12,
        ),
        p,
      );
    }
    p.color = const Color(0xffff4f8b);
    for (final e in enemies) {
      c.drawCircle(Offset(e.dx * z.width, e.dy * z.height), 12, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SpacePainter o) => true;
}

class _TetrisPainter extends CustomPainter {
  final List<List<int>> b, s;
  final int x, y, k;
  _TetrisPainter(this.b, this.s, this.x, this.y, this.k);
  @override
  void paint(Canvas c, Size z) {
    final p = Paint();
    final cw = z.width / 10, ch = z.height / 20;
    p.color = const Color(0xff0c1220);
    c.drawRect(Offset.zero & z, p);
    for (int yy = 0; yy < 20; yy++)
      for (int xx = 0; xx < 10; xx++) {
        if (b[yy][xx] != 0) {
          p.color = Colors.primaries[(b[yy][xx] - 1) % Colors.primaries.length]
              .withAlpha(210);
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(xx * cw + 1, yy * ch + 1, cw - 2, ch - 2),
              const Radius.circular(4),
            ),
            p,
          );
        }
      }
    p.color = Colors.white;
    for (int yy = 0; yy < s.length; yy++)
      for (int xx = 0; xx < s[yy].length; xx++) {
        if (s[yy][xx] == 1) {
          c.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                (x + xx) * cw + 1,
                (y + yy) * ch + 1,
                cw - 2,
                ch - 2,
              ),
              const Radius.circular(4),
            ),
            p,
          );
        }
      }
  }

  @override
  bool shouldRepaint(covariant _TetrisPainter o) => true;
}

class _FlappyPainter extends CustomPainter {
  final double y, pipe, gap;
  final bool over;
  _FlappyPainter(this.y, this.pipe, this.gap, this.over);
  @override
  void paint(Canvas c, Size z) {
    final p = Paint()..color = const Color(0xff55b7ff);
    c.drawRect(Offset.zero & z, p);
    p.color = const Color(0xff48ff9b);
    final px = pipe * z.width;
    final top = (gap - .15) * z.height;
    final bot = (gap + .15) * z.height;
    c.drawRect(Rect.fromLTWH(px - 28, 0, 56, top), p);
    c.drawRect(Rect.fromLTWH(px - 28, bot, 56, z.height - bot), p);
    p.color = const Color(0xffffc857);
    c.drawCircle(Offset(z.width * .32, y * z.height), 17, p);
    if (over) {
      p.color = Colors.black54;
      c.drawRect(Offset.zero & z, p);
      _center(c, z, 'DOKUN VE TEKRARLA');
    }
  }

  @override
  bool shouldRepaint(covariant _FlappyPainter o) => true;
}

void _center(Canvas c, Size z, String s) {
  final tp = TextPainter(
    text: TextSpan(
      text: s,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w900,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(c, Offset((z.width - tp.width) / 2, (z.height - tp.height) / 2));
}
