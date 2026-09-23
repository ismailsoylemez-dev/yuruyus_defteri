import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'email_auth_screen.dart';
import 'phone_auth_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Hesapsiz devam secildiginde cagrilir.
  final VoidCallback onSkip;
  final bool isLinking;

  const LoginScreen({
    super.key,
    required this.onSkip,
    this.isLinking = false,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  void _setError(String? err) {
    if (mounted) setState(() => _error = err);
  }

  Future<void> _signInWithGoogle() async {
    _setBusy(true);
    _setError(null);
    try {
      if (widget.isLinking) {
        await AuthService.instance.linkWithGoogle();
        // Basarili baglama sonrasi ayarlara doner
        if (mounted) widget.onSkip();
      } else {
        await AuthService.instance.signInWithGoogle();
        // Basarili ise AuthGate stream uzerinden ekrani degistirir.
      }
    } on AuthFailure catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('Beklenmeyen hata: $e');
    } finally {
      _setBusy(false);
    }
  }

  void _goToPhoneAuth() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PhoneAuthScreen(
          isLinking: widget.isLinking,
          onSuccess: widget.isLinking ? widget.onSkip : null,
        ),
      ),
    );
  }

  void _goToEmailAuth() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EmailAuthScreen(
          isLinking: widget.isLinking,
          onSuccess: widget.isLinking ? widget.onSkip : null,
        ),
      ),
    );
  }

  Widget _buildAuthButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color fgColor,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        elevation: 0,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: bgColor == AppColors.bg
              ? BorderSide(color: AppColors.divider)
              : BorderSide.none,
        ),
      ),
      icon: Icon(icon, size: 22),
      label: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
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
                  widget.isLinking ? 'Hesabı Bağla/Yedekle' : 'Yürüyüş Defteri',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isLinking
                      ? 'Hesabınızı bağlayarak verilerinizi bulutta güvenle saklayın.'
                      : 'Adımlarınızı ve hedeflerinizi bulutta güvenle saklamak için giriş yapın.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 36),
                
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.pick(
                          const Color(0xFF3A1A1A), const Color(0xFFFDECEC)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.pick(
                              const Color(0xFF5B2626), const Color(0xFFF5C2C2))),
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
                              color: AppColors.pick(
                                  const Color(0xFFFFCDD2), const Color(0xFFB71C1C)),
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

                if (_busy)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: CircularProgressIndicator(),
                    ),
                  ),

                _buildAuthButton(
                  label: 'Telefon ile Devam Et',
                  icon: Icons.phone_android_rounded,
                  bgColor: AppColors.pick(Colors.white, const Color(0xFFF1F3F4)),
                  fgColor: Colors.black87,
                  onPressed: _goToPhoneAuth,
                ),
                const SizedBox(height: 12),

                _buildAuthButton(
                  label: 'Google ile Devam Et',
                  icon: Icons.g_mobiledata_rounded,
                  bgColor: AppColors.pick(Colors.white, const Color(0xFFF1F3F4)),
                  fgColor: Colors.black87,
                  onPressed: _signInWithGoogle,
                ),
                const SizedBox(height: 12),
                
                _buildAuthButton(
                  label: 'E-posta ile Devam Et',
                  icon: Icons.email_outlined,
                  bgColor: AppColors.accent,
                  fgColor: AppColors.onAccent,
                  onPressed: _goToEmailAuth,
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.divider)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'VEYA',
                        style: TextStyle(
                          color: AppColors.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: AppColors.divider)),
                  ],
                ),
                const SizedBox(height: 24),

                TextButton(
                  onPressed: _busy ? null : widget.onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.text,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.divider),
                    ),
                  ),
                  child: Text(
                    widget.isLinking ? 'İptal' : 'Hesapsız devam et (Misafir)',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 16),
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
