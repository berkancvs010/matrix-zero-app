part of 'main.dart';

class ZeroLogReferenceLogin extends StatefulWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool loading;
  final bool obscurePassword;
  final bool registerMode;
  final VoidCallback onSubmit;
  final VoidCallback onTogglePassword;
  final VoidCallback onRegister;

  const ZeroLogReferenceLogin({
    super.key,
    required this.usernameController,
    required this.passwordController,
    required this.loading,
    required this.obscurePassword,
    required this.registerMode,
    required this.onSubmit,
    required this.onTogglePassword,
    required this.onRegister,
  });

  @override
  State<ZeroLogReferenceLogin> createState() => _ZeroLogReferenceLoginState();
}

class _ZeroLogReferenceLoginState extends State<ZeroLogReferenceLogin>
    with SingleTickerProviderStateMixin {
  static const green = Color(0xFF35E57F);

  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  static const greenBright = Color(0xFF39FF88);
  static const fieldBg = Color(0xFF0D1410);

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF777D79),
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: greenBright, size: 30),
      suffixIcon: suffix,
      filled: true,
      fillColor: fieldBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 21),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: Color(0xFF244F38), width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: greenBright, width: 1.5),
      ),
    );
  }

  Widget _usernameField() {
    return TextField(
      controller: widget.usernameController,
      enabled: !widget.loading,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      keyboardType: TextInputType.text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: greenBright,
      decoration: _decoration(
        hint: 'Kullanıcı adı',
        icon: Icons.person_outline_rounded,
      ),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: widget.passwordController,
      enabled: !widget.loading,
      obscureText: widget.obscurePassword,
      autocorrect: false,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => widget.onSubmit(),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: greenBright,
      decoration: _decoration(
        hint: 'Şifre',
        icon: Icons.lock_outline_rounded,
        suffix: IconButton(
          onPressed: widget.loading ? null : widget.onTogglePassword,
          icon: Icon(
            widget.obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: Colors.white70,
            size: 30,
          ),
        ),
      ),
    );
  }

  Future<void> _showForgotDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111613),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2DFF82), width: 1),
          ),
          title: const Text(
            'UNUTMASAYDIN 🤣',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'TAMAM',
                style: TextStyle(
                  color: greenBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _primaryButton() {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton(
        onPressed: widget.loading ? null : widget.onSubmit,
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: widget.loading
            ? const SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.registerMode ? 'HESAP OLUŞTUR' : 'GİRİŞ',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: widget.registerMode ? 18 : 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: widget.registerMode ? 1.2 : 1.8,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _registerButton() {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: OutlinedButton(
        onPressed: widget.loading ? null : widget.onRegister,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: greenBright, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.registerMode
                  ? Icons.login_rounded
                  : Icons.person_add_alt_1_rounded,
              size: 28,
              color: Colors.white,
            ),
            const SizedBox(width: 14),
            Text(
              widget.registerMode ? 'Giriş ekranına dön' : 'Yeni hesap oluştur',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(42, 30, 42, 28),
                  child: Column(
                    children: [
                      // LOGO
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(27),
                          border: Border.all(color: greenBright, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: greenBright.withValues(alpha: 0.18),
                              blurRadius: 35,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Z',
                          style: TextStyle(
                            color: greenBright,
                            fontSize: 58,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      // BRAND
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 46,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.5,
                          ),
                          children: [
                            TextSpan(
                              text: 'Zero',
                              style: TextStyle(color: Colors.white),
                            ),
                            TextSpan(
                              text: 'Log',
                              style: TextStyle(color: greenBright),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Gizlilik odaklı iletişim',
                        style: TextStyle(
                          color: Color(0xFF8B918D),
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 12),

                      AnimatedBuilder(
                        animation: _waveController,
                        builder: (context, child) {
                          return SizedBox(
                            width: 190,
                            height: 48,
                            child: CustomPaint(
                              painter: _ZeroLogWavePainter(
                                progress: _waveController.value,
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 34),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          widget.registerMode
                              ? 'Yeni hesabınızı oluşturun'
                              : '',
                          key: ValueKey(widget.registerMode),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ),

                      if (widget.registerMode) const SizedBox(height: 16),

                      _usernameField(),

                      const SizedBox(height: 16),

                      _passwordField(),

                      if (!widget.registerMode) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: widget.loading
                                ? null
                                : _showForgotDialog,
                            child: const Text(
                              'Şifremi Unuttum?',
                              style: TextStyle(
                                color: greenBright,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      _primaryButton(),

                      const SizedBox(height: 16),

                      _registerButton(),

                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            color: greenBright,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Verileriniz uçtan uca şifrelenir.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
