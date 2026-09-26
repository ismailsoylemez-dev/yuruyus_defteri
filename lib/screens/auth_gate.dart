import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../services/auth_service.dart';
import '../services/cloud_service.dart';
import '../services/prefs_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'root_screen.dart';

/// Oturum durumuna gore giris ekranini veya uygulamayi gosterir.
///
/// Firebase oturumu cihazda kalici oldugundan, bir kez giris yapildiktan
/// sonra [FirebaseAuth.authStateChanges] ilk karede kullaniciyi dondurur ve
/// giris ekrani hic gorunmez.
class AuthGate extends StatefulWidget {
  final PrefsService prefs;
  const AuthGate({super.key, required this.prefs});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late bool _skipped = widget.prefs.skipLogin;

  @override
  void initState() {
    super.initState();
    // Otomatik sessiz giris kaldirildi. 
    // Sadece daha onceden basarili giris yapilmissa authStateChanges
    // uzerinden dogrudan iceri alinacak.
  }

  Future<void> _skip() async {
    await widget.prefs.setSkipLogin(true);
    if (mounted) setState(() => _skipped = true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _Splash(label: 'Yükleniyor…');
        }

        final user = snapshot.data;
        if (user == null) {
          // Hesapsiz baslayip sonra Ayarlar'dan giris yapan kullanici cikis
          // yapinca giris ekranini gormeli; bayrak prefs'ten canli okunur.
          if (_skipped && widget.prefs.skipLogin) return const RootScreen();
          return LoginScreen(onSkip: _skip);
        }

        return _CloudGate(
          key: ValueKey(user.uid),
          user: user,
          prefs: widget.prefs,
        );
      },
    );
  }
}

/// Giris yapildiktan sonra buluttaki veriyi cihazdakiyle birlestirir.
class _CloudGate extends StatefulWidget {
  final User user;
  final PrefsService prefs;

  const _CloudGate({super.key, required this.user, required this.prefs});

  @override
  State<_CloudGate> createState() => _CloudGateState();
}

class _CloudGateState extends State<_CloudGate> {
  bool _ready = false;
  CloudService? _cloud;

  /// dispose() sirasinda context okunmamasi icin saglayici burada tutulur.
  StepProvider? _step;
  WaterProvider? _water;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  Future<void> _sync() async {
    if (!mounted) return;
    final cloud = CloudService(widget.user.uid);
    _cloud = cloud;

    final step = context.read<StepProvider>();
    final water = context.read<WaterProvider>();
    final settings = context.read<SettingsProvider>();
    _step = step;
    _water = water;
    final prefs = widget.prefs;

    // Buluttan gelen veriyi yerel veriyle birlestirir. Hem ilk giriste hem
    // okuma gecikip sonradan tamamlandiginda ayni yol kullanilir.
    cloud.onRemoteLoaded = (snapshot) async {
      if (snapshot.isEmpty) return;
      if (snapshot.goal != null) {
        await settings.applyBackup(
          goal: snapshot.goal!,
          heightCm: snapshot.heightCm ?? prefs.heightCm,
          weightKg: snapshot.weightKg ?? prefs.weightKg,
          smartGoalEnabled: snapshot.smartGoalEnabled,
          unlockedBadges: snapshot.unlockedBadges,
        );
      }
      // Ayni gunde buyuk olan deger korunur; elle duzeltilen gunler haric.
      await step.importHistory(
        step.withoutOverrides(snapshot.history),
        hourly: step.hourlyWithoutOverrides(snapshot.hourly),
        intensity: step.hourlyWithoutOverrides(snapshot.intensity),
      );
      await settings.mergeWeightLog(snapshot.weightLog);
      if (snapshot.waterHistory.isNotEmpty) {
        await water.importHistory(snapshot.waterHistory);
      }
      // Hedef/boy/kilo buluttan gelmis olabilir; widget ve kalici bildirim
      // eski degerde kalmasin.
      await step.refreshAll(force: true);
    };
    step.attachCloud(cloud);
    water.attachCloud(cloud);

    try {
      await cloud.saveProfile(
        email: widget.user.email,
        displayName: widget.user.displayName,
      );

      // Baglanti yavassa uygulama acilisini kilitlememek icin sure siniri.
      // Okuma sure icinde bitmezse arka planda surer, bitince
      // onRemoteLoaded ile birlestirilir; o zamana kadar buluta yazilmaz.
      await cloud.pullAndApply().timeout(
            const Duration(seconds: 12),
            onTimeout: () => false,
          );

      // Birlesmis hali hemen geri yaz (yeni hesapta ilk yukleme de budur).
      step.pushToCloud();
      water.pushToCloud();
      await cloud.flush();
    } catch (e) {
      debugPrint('Bulut esitleme hatasi: $e');
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  void dispose() {
    // Oturum degisiminde saglayici, dispose edilmis CloudService'i tutmaya
    // devam ediyor ve "bulut acik" gorunuyordu.
    final step = _step;
    final water = _water;
    final cloud = _cloud;
    if (step != null && cloud != null) {
      // Widget agaci sokulurken notifyListeners cagirmamak icin kare
      // bittikten sonra cozulur.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        step.detachCloud(cloud);
        water?.detachCloud(cloud);
      });
    }
    _step = null;
    _water = null;
    cloud?.dispose();
    _cloud = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const _Splash(label: 'Veriler eşitleniyor…');
    return const RootScreen();
  }
}

class _Splash extends StatelessWidget {
  final String label;
  const _Splash({required this.label});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 34,
              width: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              label,
              style: TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
