import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class PhoneAuthScreen extends StatefulWidget {
  final bool isLinking;
  final VoidCallback? onSuccess;

  const PhoneAuthScreen({
    super.key,
    this.isLinking = false,
    this.onSuccess,
  });

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  bool _isCodeSent = false;
  bool _busy = false;
  String? _error;
  String? _verificationId;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _setBusy(bool val) {
    if (mounted) setState(() => _busy = val);
  }

  void _setError(String? msg) {
    if (mounted) setState(() => _error = msg);
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _setError('Lütfen telefon numaranızı girin.');
      return;
    }
    // Basit bir +90 kontrolü veya format düzeltmesi eklenebilir.
    // Kullanıcıya +90 eklemesi gerektiği söyleniyor.
    if (!phone.startsWith('+')) {
      _setError('Lütfen ülke koduyla başlayın (Örn: +90555...)');
      return;
    }

    _setBusy(true);
    _setError(null);

    try {
      await AuthService.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android cihazlarda bazen SMS kodu otomatik okunup bu metod tetiklenir.
          try {
            if (widget.isLinking) {
              await AuthService.instance.linkWithPhoneCredential(credential.verificationId!, credential.smsCode!);
            } else {
              await FirebaseAuth.instance.signInWithCredential(credential);
            }
            if (mounted) {
              if (widget.onSuccess != null) {
                widget.onSuccess!();
              } else {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            }
          } catch (e) {
            _setError('Otomatik doğrulama başarısız: $e');
            _setBusy(false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          _setError(e.message ?? 'Doğrulama başarısız oldu (${e.code})');
          _setBusy(false);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isCodeSent = true;
              _busy = false;
            });
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      _setError(e.toString());
      _setBusy(false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _setError('Lütfen SMS kodunu girin.');
      return;
    }
    if (_verificationId == null) {
      _setError('Doğrulama ID\'si bulunamadı. Lütfen tekrar kod isteyin.');
      return;
    }

    _setBusy(true);
    _setError(null);

    try {
      if (widget.isLinking) {
        await AuthService.instance.linkWithPhoneCredential(_verificationId!, code);
      } else {
        await AuthService.instance.signInWithPhoneCredential(_verificationId!, code);
      }
      if (mounted) {
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } on AuthFailure catch (e) {
      _setError(e.message);
      _setBusy(false);
    } catch (e) {
      _setError('Beklenmeyen hata: $e');
      _setBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pick(Colors.white, const Color(0xFF121212)),
      appBar: AppBar(
        title: Text(widget.isLinking ? 'Hesabı Bağla' : 'Telefon ile Giriş'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.phone_android_rounded,
                size: 64,
                color: AppColors.accent,
              ),
              const SizedBox(height: 24),
              Text(
                _isCodeSent ? 'SMS Kodunu Girin' : 'Telefon Numaranız',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _isCodeSent
                    ? 'Telefonunuza gönderilen 6 haneli kodu girin.'
                    : 'Lütfen ülke kodu ile birlikte girin (Örn: +90 555 555 5555)',
                style: TextStyle(
                  color: AppColors.pick(Colors.black54, Colors.white60),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_isCodeSent) ...[
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(
                    color: AppColors.pick(Colors.black, Colors.white),
                  ),
                  decoration: InputDecoration(
                    hintText: '+90 555 555 5555',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onFieldSubmitted: (_) => _sendCode(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _busy ? null : _sendCode,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Kodu Gönder',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ] else ...[
                TextFormField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                    color: AppColors.pick(Colors.black, Colors.white),
                  ),
                  decoration: InputDecoration(
                    hintText: '000000',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLength: 6,
                  onFieldSubmitted: (_) => _verifyCode(),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _busy ? null : _verifyCode,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Doğrula ve Giriş Yap',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _isCodeSent = false;
                            _codeController.clear();
                            _error = null;
                          });
                        },
                  child: const Text('Numarayı Değiştir'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
