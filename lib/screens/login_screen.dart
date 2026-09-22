import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  /// Hesapsiz devam secildiginde cagrilir.
  final VoidCallback onSkip;

  const LoginScreen({super.key, required this.onSkip});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signInWithGoogle();
      // Basarili ise AuthGate stream uzerinden ekrani degistirir.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Beklenmeyen hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 96,
                  width: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_walk,
                    color: AppColors.accent,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Yürüyüş Defteri',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Google hesabınla giriş yap; adım geçmişin buluta yedeklensin '
                  've telefon değiştirdiğinde kaybolmasın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 36),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.pick(const Color(0xFF3A1A1A), const Color(0xFFFDECEC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.pick(const Color(0xFF5B2626), const Color(0xFFF5C2C2))),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Color(0xFFEF5350),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: AppColors.pick(const Color(0xFFFFCDD2), const Color(0xFFB71C1C)),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                FilledButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: _busy
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: AppColors.onAccent,
                          ),
                        )
                      : const Icon(Icons.login, size: 20),
                  label: Text(
                    _busy ? 'Giriş yapılıyor…' : 'Google ile devam et',
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : widget.onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textDim,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('Hesapsız devam et'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Hesapsız kullanımda veriler yalnızca bu cihazda tutulur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
