import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'cloud_service.dart';

/// Giris hatalarinin kullaniciya gosterilebilir hali.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);
  @override
  String toString() => message;
}

/// Google hesabi ile Firebase Authentication.
///
/// Oturum Firebase tarafindan cihazda kalici saklanir; uygulama her acildiginda
/// tekrar giris istenmez. Sadece uygulama silinir veya cihaz degisirse
/// bir kez hesap secimi gerekir.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// Firebase konsolunda Google saglayicisi acilinca olusan "Web client ID".
  /// Bos birakilirsa eklenti google-services.json'dan uretilen
  /// `default_web_client_id` kaynagini kullanir; normalde bos kalmali.
  static const String serverClientId = '';

  /// [Firebase.initializeApp] basarili oldu mu. main() tarafindan yazilir.
  /// false iken FirebaseAuth'a dokunmak [core/no-app] firlatir, bu yuzden
  /// asagidaki erisimlerin hepsi bu bayragi kontrol eder.
  static bool available = false;

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _initialized = true;
  }

  Stream<User?> get authState {
    if (!available) return Stream<User?>.value(null);
    return FirebaseAuth.instance.authStateChanges();
  }

  User? get currentUser {
    if (!available) return null;
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  /// Ekran acmadan, daha once verilmis izinle sessiz giris dener.
  /// Basarisiz olursa sessizce gecilir; kullanici butonla girer.
  Future<void> trySilentSignIn() async {
    if (!available || currentUser != null) return;
    try {
      await _ensureInit();
      final account =
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account != null) await _linkToFirebase(account);
    } catch (_) {
      // Yoksay.
    }
  }

  /// Kullanici butona bastiginda calisir. Iptal edilirse null doner.
  Future<User?> signInWithGoogle() async {
    if (!available) {
      throw const AuthFailure(
        'Bulut yedekleme bu platformda kullanılamıyor.',
      );
    }
    try {
      await _ensureInit();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const AuthFailure(
          'Bu platformda Google ile giris desteklenmiyor.',
        );
      }
      final account = await GoogleSignIn.instance.authenticate();
      return await _linkToFirebase(account);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthFailure(_mapGoogleError(e));
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  Future<User?> _linkToFirebase(GoogleSignInAccount account) async {
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthFailure(
        'Kimlik dogrulanamadi. Firebase konsolunda SHA-1 parmak izinin '
        'ekli oldugundan emin ol.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    final result =
        await FirebaseAuth.instance.signInWithCredential(credential);
    return result.user;
  }

  /// Misafir hesabi Google hesabina baglar.
  Future<User?> linkWithGoogle() async {
    if (!available) {
      throw const AuthFailure('Bulut yedekleme bu platformda kullanılamıyor.');
    }
    GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw AuthFailure(_mapGoogleError(e));
    }

    final auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthFailure('Kimlik dogrulanamadi.');
    }
    
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    try {
      final result = await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
      return result?.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  /// Telefon numarasi ile dogrulama kodu gonderir
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(PhoneAuthCredential) verificationCompleted,
    required void Function(FirebaseAuthException) verificationFailed,
    required void Function(String, int?) codeSent,
    required void Function(String) codeAutoRetrievalTimeout,
  }) async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  /// Gelen SMS koduyla telefon oturumunu tamamlar
  Future<User?> signInWithPhoneCredential(String verificationId, String smsCode) async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  /// Mevcut anonim hesabi SMS koduyla baglar
  Future<User?> linkWithPhoneCredential(String verificationId, String smsCode) async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    final user = currentUser;
    if (user == null) throw const AuthFailure('Oturum açık değil.');
    
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final result = await user.linkWithCredential(credential);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  /// Misafir olarak giris (Anonim)
  Future<User?> signInAnonymously() async {
    if (!available) return null;
    try {
      final result = await FirebaseAuth.instance.signInAnonymously();
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }



  /// Email ve Sifre ile giris
  Future<User?> signInWithEmailAndPassword(String email, String password) async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    try {
      final result = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  /// Mevcut anonim hesabi Email ve Sifre ile baglar
  Future<User?> linkWithEmailAndPassword(String email, String password) async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    final user = currentUser;
    if (user == null) throw const AuthFailure('Oturum açık değil.');
    
    try {
      final credential = EmailAuthProvider.credential(email: email, password: password);
      final result = await user.linkWithCredential(credential);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  /// Email ve Sifre ile kayit
  Future<User?> registerWithEmailAndPassword(String email, String password) async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    try {
      final result = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_mapFirebaseError(e));
    }
  }

  Future<void> signOut() async {
    if (!available) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google tarafi temizlenemese de Firebase oturumu kapatilir.
    }
    await FirebaseAuth.instance.signOut();
  }

  /// Hesabı ve buluttaki verileri kalıcı olarak siler
  Future<void> deleteAccount() async {
    if (!available) throw const AuthFailure('Bulut yedekleme kullanılamıyor.');
    final user = currentUser;
    if (user == null) throw const AuthFailure('Oturum açık değil.');

    try {
      // 1. Önce buluttaki verileri temizle
      final cloud = CloudService(user.uid);
      await cloud.deleteUserData();

      // 2. Google Session'ı temizle (Varsa)
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}

      // 3. Hesabı sil
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw const AuthFailure('Güvenlik nedeniyle hesabı silmek için lütfen çıkış yapıp tekrar giriş yapın.');
      }
      throw AuthFailure(_mapFirebaseError(e));
    } catch (e) {
      throw AuthFailure('Hesap silinemedi: $e');
    }
  }

  String _mapGoogleError(GoogleSignInException e) {
    return switch (e.code) {
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Firebase yapilandirmasi eksik: google-services.json ve SHA-1 kontrol et.',
      GoogleSignInExceptionCode.clientConfigurationError =>
        'Istemci yapilandirmasi hatali. Paket adi ve Web client ID uyusmuyor.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Giris ekrani acilamadi. Google Play Hizmetleri guncel mi?',
      _ => 'Google girisi basarisiz oldu (${e.code.name}).',
    };
  }

  String _mapFirebaseError(FirebaseAuthException e) {
    return switch (e.code) {
      'network-request-failed' => 'Internet baglantisi yok.',
      'account-exists-with-different-credential' =>
        'Bu e-posta baska bir yontemle kayitli.',
      'operation-not-allowed' =>
        'Google saglayicisi Firebase konsolunda acik degil.',
      'invalid-credential' => 'Kimlik bilgisi gecersiz veya suresi dolmus.',
      'invalid-verification-code' => 'Doğrulama kodu hatalı.',
      'invalid-phone-number' => 'Telefon numarası geçersiz. Lütfen ülke koduyla birlikte girin (+90...)',
      _ => 'Giris basarisiz oldu (${e.code}).',
    };
  }
}
