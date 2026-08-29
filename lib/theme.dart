part of 'main.dart';

class ZeroLogThemeData {
  final String name;
  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color text;
  final Color bubbleMine;
  final Color bubbleOther;

  const ZeroLogThemeData({
    required this.name,
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.text,
    required this.bubbleMine,
    required this.bubbleOther,
  });
}

const Map<ZeroLogTheme, ZeroLogThemeData> zeroLogThemes = {
  ZeroLogTheme.black: ZeroLogThemeData(
    name: 'Black & White',
    background: Color(0xFF0B0B0B),
    surface: Color(0xFF171717),
    primary: Color(0xFFE5E5E5),
    secondary: Color(0xFF9E9E9E),
    text: Color(0xFFFFFFFF),
    bubbleMine: Color(0xFF303030),
    bubbleOther: Color(0xFF1E1E1E),
  ),
  ZeroLogTheme.matrix: ZeroLogThemeData(
    name: 'Matrix',
    background: Color(0xFF000000),
    surface: Color(0xFF071407),
    primary: Color(0xFF00FF41),
    secondary: Color(0xFF00B52D),
    text: Color(0xFF00FF41),
    bubbleMine: Color(0xFF123D18),
    bubbleOther: Color(0xFF0A210E),
  ),
  ZeroLogTheme.whatsapp: ZeroLogThemeData(
    name: 'WhatsApp',
    background: Color(0xFFECE5DD),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF075E54),
    secondary: Color(0xFF25D366),
    text: Color(0xFF111111),
    bubbleMine: Color(0xFFD9FDD3),
    bubbleOther: Color(0xFFFFFFFF),
  ),
  ZeroLogTheme.pink: ZeroLogThemeData(
    name: 'Pink',
    background: Color(0xFFFFEAF2),
    surface: Color(0xFFFFF5F8),
    primary: Color(0xFFE91E63),
    secondary: Color(0xFFFF80AB),
    text: Color(0xFF171717),
    bubbleMine: Color(0xFFFFB6CF),
    bubbleOther: Color(0xFFFFD9E5),
  ),
  ZeroLogTheme.grey: ZeroLogThemeData(
    name: 'Grey / GPT',
    background: Color(0xFF212121),
    surface: Color(0xFF2F2F2F),
    primary: Color(0xFF10A37F),
    secondary: Color(0xFF8E8E8E),
    text: Color(0xFFF5F5F5),
    bubbleMine: Color(0xFF3A3A3A),
    bubbleOther: Color(0xFF2B2B2B),
  ),
  ZeroLogTheme.midnight: ZeroLogThemeData(
    name: 'Midnight',
    background: Color(0xFF08111F),
    surface: Color(0xFF101D30),
    primary: Color(0xFF64B5F6),
    secondary: Color(0xFF42A5F5),
    text: Color(0xFFF3F7FF),
    bubbleMine: Color(0xFF183B5C),
    bubbleOther: Color(0xFF12263D),
  ),
  ZeroLogTheme.mivi: ZeroLogThemeData(
    name: 'Mivi',
    // Mivi: Türk bayrağından ilham alan beyaz/kırmızı
    // zemin ve güçlü lacivert tipografi.
    background: Color(0xFFFFF8F8),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFFD90429),
    secondary: Color(0xFF174A7E),
    text: Color(0xFF12365A),
    bubbleMine: Color(0xFFFFE8EC),
    bubbleOther: Color(0xFFF2F6FA),
  ),
  ZeroLogTheme.obsidianGold: ZeroLogThemeData(
    name: 'Varsayılan',
    background: Color(0xFF07111F),
    surface: Color(0xFF0E1A2B),
    primary: Color(0xFF62D6C7),
    secondary: Color(0xFF5B8DEF),
    text: Color(0xFFF2F7FF),
    bubbleMine: Color(0xFF163B4A),
    bubbleOther: Color(0xFF111F31),
  ),
  ZeroLogTheme.platinum: ZeroLogThemeData(
    name: 'Platinum',
    background: Color(0xFF0D1014),
    surface: Color(0xFF171B21),
    primary: Color(0xFFD8DDE5),
    secondary: Color(0xFF8F98A6),
    text: Color(0xFFF3F5F8),
    bubbleMine: Color(0xFF252B33),
    bubbleOther: Color(0xFF171B21),
  ),
  ZeroLogTheme.emerald: ZeroLogThemeData(
    name: 'Emerald Dark',
    background: Color(0xFF07100C),
    surface: Color(0xFF0F1B15),
    primary: Color(0xFF5FE0A0),
    secondary: Color(0xFF2D8D61),
    text: Color(0xFFEAF7F0),
    bubbleMine: Color(0xFF153526),
    bubbleOther: Color(0xFF0D1813),
  ),
};

class ZeroLogPrivacyIntro {
  static const String _shownKey = 'zerolog.privacy_intro.v2';

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_shownKey) ?? false);
  }

  static Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_shownKey, true);
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'zerolog_theme';

  ZeroLogTheme current = ZeroLogTheme.obsidianGold;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final index = prefs.getInt(_key);

    if (index != null && index >= 0 && index < ZeroLogTheme.values.length) {
      current = ZeroLogTheme.values[index];
    }
  }

  Future<void> setTheme(ZeroLogTheme theme) async {
    current = theme;

    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_key, theme.index);

    notifyListeners();
  }

  ZeroLogThemeData get data => zeroLogThemes[current]!;
}

// ============================================================
// MIVI DESIGN SYSTEM
// ============================================================

class MiviThemeFrame extends StatelessWidget {
  final Widget child;

  const MiviThemeFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isMivi = ThemeController.instance.current == ZeroLogTheme.mivi;

    if (!isMivi) {
      return child;
    }

    return Column(
      children: [
        const MiviFlagBar(),
        Expanded(child: child),
      ],
    );
  }
}

class MiviFlagBar extends StatelessWidget {
  const MiviFlagBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      width: double.infinity,
      child: CustomPaint(painter: _MiviFlagPainter()),
    );
  }
}

class _MiviFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final red = Paint()
      ..color = const Color(0xFFD90429)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Offset.zero & size, red);

    final center = Offset(size.width * 0.50, size.height * 0.50);

    final radius = size.height * 0.34;

    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Crescent.
    canvas.drawCircle(center, radius, white);

    final cutout = Paint()
      ..color = const Color(0xFFD90429)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(center.dx + radius * 0.38, center.dy - radius * 0.04),
      radius * 0.82,
      cutout,
    );

    // Minimal five-point star.
    final starCenter = Offset(center.dx + radius * 1.55, center.dy);

    final path = Path();

    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + (math.pi * i / 5);
      final r = i.isEven ? radius * 0.43 : radius * 0.18;

      final point = Offset(
        starCenter.dx + math.cos(angle) * r,
        starCenter.dy + math.sin(angle) * r,
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    path.close();
    canvas.drawPath(path, white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
// APP
// ============================================================
