part of 'main.dart';

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  late final AnimationController _geometryController;

  bool _loading = false;
  bool _registerMode = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();

    _geometryController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.length < 3) {
      _show('Kullanıcı adı en az 3 karakter olmalı.');
      return;
    }

    if (password.length < 8) {
      _show('Şifre en az 8 karakter olmalı.');
      return;
    }

    setState(() {
      _loading = true;
    });

    if (_registerMode) {
      await _register(username, password);
    } else {
      await _login(username, password);
    }
  }

  Future<void> _register(String username, String password) async {
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      final subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw.toString());

            if (decoded is! Map) return;

            final data = Map<String, dynamic>.from(decoded);

            if (!mounted) return;

            if (data['type'] == 'accountRegistered') {
              channel.sink.close();
              setState(() {
                _loading = false;
                _registerMode = false;
              });

              _show('Hesap oluşturuldu. Şimdi giriş yapabilirsiniz.');
            }

            if (data['type'] == 'authError') {
              channel.sink.close();

              setState(() {
                _loading = false;
              });

              _show((data['message'] ?? 'Kayıt başarısız.').toString());
            }
          } catch (_) {}
        },
        onError: (_) {
          if (!mounted) return;

          setState(() {
            _loading = false;
          });

          _show('Sunucuya bağlanılamadı.');
        },
      );

      await channel.ready;

      channel.sink.add(
        jsonEncode({
          'type': 'registerAccount',
          'username': username,
          'password': password,
        }),
      );

      Future.delayed(const Duration(seconds: 10), () {
        subscription.cancel();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _show('Sunucuya bağlanılamadı.');
    }
  }

  Future<void> _login(String username, String password) async {
    setState(() {
      _loading = true;
    });

    final ok = await WsClient.instance.connect(username, password);

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (!ok) {
      _show(
        'Giriş başarısız. Kullanıcı adı, şifre veya hesap durumu kontrol edilmeli.',
      );
      return;
    }

    await SecureSession.save(username: username, password: password);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            MainScreen(nickname: WsClient.instance.nickname ?? username),
      ),
    );
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _geometryController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ZeroLogReferenceLogin(
      usernameController: _usernameController,
      passwordController: _passwordController,
      loading: _loading,
      obscurePassword: _obscurePassword,
      registerMode: _registerMode,
      onSubmit: _submit,
      onTogglePassword: () {
        setState(() {
          _obscurePassword = !_obscurePassword;
        });
      },
      onRegister: () {
        setState(() {
          _registerMode = !_registerMode;
        });
      },
    );
  }
}

// ============================================================
// ZEROLOG LOGIN WAVE
// ============================================================

// ============================================================
// MAIN
// ============================================================

// ============================================================
