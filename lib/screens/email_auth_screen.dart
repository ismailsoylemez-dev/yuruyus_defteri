import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class EmailAuthScreen extends StatefulWidget {
  final bool isLinking;
  final VoidCallback? onSuccess;

  const EmailAuthScreen({
    super.key,
    this.isLinking = false,
    this.onSuccess,
  });

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isLogin = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    if (mounted) setState(() => _busy = value);
  }

  void _setError(String? err) {
    if (mounted) setState(() => _error = err);
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+");
    return regex.hasMatch(email);
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || !_isValidEmail(email)) {
      _setError('Geçerli bir e-posta adresi giriniz.');
      return;
    }

    if (password.length < 6) {
      _setError('Şifre en az 6 karakter olmalıdır.');
      return;
    }

    _setBusy(true);
    _setError(null);

    try {
      if (widget.isLinking) {
        await AuthService.instance.linkWithEmailAndPassword(email, password);
      } else if (_isLogin) {
        await AuthService.instance.signInWithEmailAndPassword(email, password);
      } else {
        await AuthService.instance.registerWithEmailAndPassword(email, password);
      }
      
      if (mounted) {
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } on AuthFailure catch (e) {
      _setError(e.message);
    } catch (e) {
      _setError('Beklenmeyen bir hata oluştu: $e');
    } finally {
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.isLinking
              ? 'Hesabı Bağla'
              : (_isLogin ? 'Giriş Yap' : 'Kayıt Ol'),
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.isLinking) ...[
                // Toggle
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (!_isLogin) {
                              setState(() {
                                _isLogin = true;
                                _error = null;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: _isLogin ? AppColors.accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Giriş Yap',
                              style: TextStyle(
                                color: _isLogin ? AppColors.onAccent : AppColors.textDim,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            if (_isLogin) {
                              setState(() {
                                _isLogin = false;
                                _error = null;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !_isLogin ? AppColors.accent : Colors.transparent,
                              borderRadius: BorderRadius.circular(11),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'Kayıt Ol',
                              style: TextStyle(
                                color: !_isLogin ? AppColors.onAccent : AppColors.textDim,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                widget.isLinking
                    ? 'Hesabı Bağla'
                    : (_isLogin ? 'Hoş Geldiniz' : 'Hesap Oluşturun'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.isLinking
                    ? 'Adımlarınızı güvenle buluta yedeklemek için e-posta ile hesabınızı bağlayın.'
                    : (_isLogin
                        ? 'Yürüyüş Defteri\'ne tekrar bağlanın.'
                        : 'Yürüyüş hedeflerinizi kaydetmeye başlayın.'),
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textDim,
                ),
              ),
              const SizedBox(height: 32),

              TextField(
                controller: _emailCtrl,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: 'ornek@eposta.com',
                  filled: true,
                  fillColor: AppColors.pick(Colors.white, const Color(0xFF1E1E1E)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.accent, width: 2),
                  ),
                  prefixIcon: Icon(Icons.email_outlined, color: AppColors.textDim),
                ),
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordCtrl,
                enabled: !_busy,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Şifreniz (En az 6 karakter)',
                  filled: true,
                  fillColor: AppColors.pick(Colors.white, const Color(0xFF1E1E1E)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.accent, width: 2),
                  ),
                  prefixIcon: Icon(Icons.lock_outline, color: AppColors.textDim),
                ),
              ),

              const SizedBox(height: 24),

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
                    children: [
                      const Icon(Icons.error_outline,
                          color: Color(0xFFEF5350), size: 18),
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

              ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onAccent,
                        ),
                      )
                    : Text(
                        _isLogin ? 'Giriş Yap' : 'Kayıt Ol',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
