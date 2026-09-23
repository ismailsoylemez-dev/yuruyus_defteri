import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/intensity.dart';

/// SharedPreferences anahtarlari.
///
/// Arka plan isolate'i ile UI ayni anahtarlari kullanmak zorundadir; bu yuzden
/// anahtarlar tek yerde tanimlanir. Deger degistirilirse mevcut kayitlar
/// okunamaz hale gelir.
class PrefsKeys {
  static const goal = 'goal';
  static const smartGoal = 'smart_goal';

  /// Su takibi acik mi (Ayarlar). Native servis de okur: flutter.water_enabled
  static const waterEnabled = 'water_enabled';

  /// Kilo kaydi: { "2026-09-22": 92.4 }
  static const weightLog = 'weight_log_json';

  /// GPS ile olculen adim boyu (m), ornek sayisi ve kullanilsin mi.
  static const strideCal = 'stride_cal_m';
  static const strideCalCount = 'stride_cal_n';
  static const strideUseCal = 'stride_use_cal';
  static const height = 'height_cm';
  static const weight = 'weight_kg';
  static const history = 'history_json';
  static const savedToday = 'saved_today';
  static const baseline = 'sensor_baseline';
  static const lastDate = 'last_date';
  static const hourly = 'hourly_json';

  /// Tempo kirilimi: { gun: [normalDk, tempoluAdim, tempoluDk, kosuAdim, kosuDk] }
  static const intensity = 'intensity_json';
  static const background = 'background_service';
  static const notifyGoal = 'notify_goal';
  static const notifyEvening = 'notify_evening';
  static const notifyWeekly = 'notify_weekly';
  static const notifyStandup = 'notify_standup';
  static const goalNotifiedOn = 'goal_notified_on';
  static const skipLogin = 'skip_login';

  /// Android 13+ POST_NOTIFICATIONS izni bir kez istendi mi.
  static const notificationAsked = 'notification_asked';

  /// Elle duzeltilen gecmis gunler (servis/bulut bunlarin uzerine yazmaz).
  static const overriddenDays = 'overridden_days';

  /// Yeni Ozellikler: Su Takibi, Oyunlastirma ve Raporlar
  static const water = 'water_json';
  static const unlockedBadges = 'unlocked_badges';
  static const lastBadge = 'last_badge';

  /// Hedef kutlamasi bugun gosterildi mi (gun anahtari).
  static const goalCelebratedOn = 'goal_celebrated_on';

  /// Ilk acilis izin aciklamasi gosterildi mi.
  static const introShown = 'intro_shown';

  /// Acik tema secili mi (varsayilan koyu).
  static const lightTheme = 'light_theme';

  /// Tema: dark / amoled / light (eski light_theme kaydindan tasinir).
  static const themeMode = 'theme_mode';

  /// Gunluk su hedefi (ml).
  static const waterGoal = 'water_goal_ml';
  static const defaultWaterGoal = 2500;
  static const lastWeeklyReport = 'last_weekly_report';
  
  /// Sanal Rotalar


  /// Varsayilanlar da paylasilir; arka plan ile UI farkli deger kullanmamali.
  static const defaultGoal = 8000;
  static const defaultHeight = 172;
  static const defaultWeight = 70.0;
}

class PrefsService {
  final SharedPreferences _p;
  PrefsService(this._p);

  static Future<PrefsService> create() async =>
      PrefsService(await SharedPreferences.getInstance());

  /// Arka plan isolate'i disk uzerinde degisiklik yaptiysa bellekteki
  /// kopyayi tazeler.
  Future<void> reload() => _p.reload();

  int get goal => _p.getInt(PrefsKeys.goal) ?? PrefsKeys.defaultGoal;
  Future<void> setGoal(int v) => _p.setInt(PrefsKeys.goal, v);

  bool get smartGoal => _p.getBool(PrefsKeys.smartGoal) ?? false;
  Future<void> setSmartGoal(bool v) => _p.setBool(PrefsKeys.smartGoal, v);

  int get heightCm => _p.getInt(PrefsKeys.height) ?? PrefsKeys.defaultHeight;
  Future<void> setHeight(int v) => _p.setInt(PrefsKeys.height, v);

  double get weightKg =>
      _p.getDouble(PrefsKeys.weight) ?? PrefsKeys.defaultWeight;
  Future<void> setWeight(double v) => _p.setDouble(PrefsKeys.weight, v);

  int get savedToday => _p.getInt(PrefsKeys.savedToday) ?? 0;
  int get baseline => _p.getInt(PrefsKeys.baseline) ?? -1;
  String get lastDate => _p.getString(PrefsKeys.lastDate) ?? '';

  /// Kullanici "Hesapsiz devam et" dediyse giris ekrani bir daha acilmaz.
  bool get skipLogin => _p.getBool(PrefsKeys.skipLogin) ?? false;
  Future<void> setSkipLogin(bool v) => _p.setBool(PrefsKeys.skipLogin, v);

  Future<void> saveCounterState({
    required int savedToday,
    required int baseline,
    required String date,
  }) async {
    await _p.setInt(PrefsKeys.savedToday, savedToday);
    await _p.setInt(PrefsKeys.baseline, baseline);
    await _p.setString(PrefsKeys.lastDate, date);
  }

  Map<String, int> get history => decodeHistory(_p.getString(PrefsKeys.history));

  Future<void> setHistory(Map<String, int> h) =>
      _p.setString(PrefsKeys.history, jsonEncode(h));

  bool get backgroundService => _p.getBool(PrefsKeys.background) ?? false;
  Future<void> setBackgroundService(bool v) =>
      _p.setBool(PrefsKeys.background, v);

  bool get notifyGoal => _p.getBool(PrefsKeys.notifyGoal) ?? true;
  Future<void> setNotifyGoal(bool v) => _p.setBool(PrefsKeys.notifyGoal, v);

  bool get notifyEvening => _p.getBool(PrefsKeys.notifyEvening) ?? false;
  Future<void> setNotifyEvening(bool v) =>
      _p.setBool(PrefsKeys.notifyEvening, v);

  bool get notifyWeekly => _p.getBool(PrefsKeys.notifyWeekly) ?? false;
  Future<void> setNotifyWeekly(bool v) => _p.setBool(PrefsKeys.notifyWeekly, v);

  bool get notifyStandup => _p.getBool(PrefsKeys.notifyStandup) ?? true;
  Future<void> setNotifyStandup(bool v) => _p.setBool(PrefsKeys.notifyStandup, v);

  String get goalNotifiedOn => _p.getString(PrefsKeys.goalNotifiedOn) ?? '';
  Future<void> setGoalNotifiedOn(String v) =>
      _p.setString(PrefsKeys.goalNotifiedOn, v);

  /// Hedef bildirimi varsayilan olarak acik oldugu halde izin hicbir yerde
  /// istenmiyordu; ilk sensor baslatmada bir kez istenir ve bu bayrak
  /// yazilir, boylece kullaniciya her acilista sorulmaz.
  bool get notificationAsked =>
      _p.getBool(PrefsKeys.notificationAsked) ?? false;
  Future<void> setNotificationAsked(bool v) =>
      _p.setBool(PrefsKeys.notificationAsked, v);

  Set<String> get overriddenDays =>
      (_p.getStringList(PrefsKeys.overriddenDays) ?? const <String>[]).toSet();
  Future<void> setOverriddenDays(Set<String> v) =>
      _p.setStringList(PrefsKeys.overriddenDays, v.toList()..sort());

  /// { "2026-09-20": [24 saatlik adim dizisi] }
  Map<String, List<int>> get hourly => decodeHourly(_p.getString(PrefsKeys.hourly));

  Future<void> setHourly(Map<String, List<int>> h) =>
      _p.setString(PrefsKeys.hourly, jsonEncode(h));

  Map<String, List<int>> get intensity {
    final raw = _p.getString(PrefsKeys.intensity);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Intensity.decodeMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> setIntensity(Map<String, List<int>> v) =>
      _p.setString(PrefsKeys.intensity, jsonEncode(v));

  // --- Su Takibi ---
  Map<String, int> get water {
    final raw = _p.getString(PrefsKeys.water);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, int>{};
      m.forEach((k, v) {
        if (!_validKey(k) || v is! num) return;
        final value = v.toInt();
        if (value < 0) return;
        out[k] = value;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> setWater(Map<String, int> v) =>
      _p.setString(PrefsKeys.water, jsonEncode(v));

  // --- Oyunlastirma (Acilan Rozetler) ---
  Set<String> get unlockedBadges =>
      (_p.getStringList(PrefsKeys.unlockedBadges) ?? const <String>[]).toSet();
      
  Future<void> setUnlockedBadges(Set<String> v) =>
      _p.setStringList(PrefsKeys.unlockedBadges, v.toList()..sort());



  String get goalCelebratedOn => _p.getString(PrefsKeys.goalCelebratedOn) ?? '';
  Future<void> setGoalCelebratedOn(String v) =>
      _p.setString(PrefsKeys.goalCelebratedOn, v);

  bool get introShown => _p.getBool(PrefsKeys.introShown) ?? false;

  Future<void> setIntroShown(bool v) => _p.setBool(PrefsKeys.introShown, v);
  
  bool get lightTheme => _p.getBool(PrefsKeys.lightTheme) ?? false;
  Future<void> setLightTheme(bool v) => _p.setBool(PrefsKeys.lightTheme, v);

  String get themeMode =>
      _p.getString(PrefsKeys.themeMode) ?? (lightTheme ? 'light' : 'dark');
  Future<void> setThemeMode(String v) async {
    await _p.setString(PrefsKeys.themeMode, v);
    await _p.setBool(PrefsKeys.lightTheme, v == 'light');
  }

  bool get waterEnabled => _p.getBool(PrefsKeys.waterEnabled) ?? true;
  Future<void> setWaterEnabled(bool v) => _p.setBool(PrefsKeys.waterEnabled, v);

  // --- Kilo takibi ---
  Map<String, double> get weightLog {
    final raw = _p.getString(PrefsKeys.weightLog);
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, double>{};
      m.forEach((k, v) {
        if (!_validKey(k) || v is! num) return;
        final kg = v.toDouble();
        if (kg < 30 || kg > 250) return;
        out[k] = kg;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> setWeightLog(Map<String, double> v) =>
      _p.setString(PrefsKeys.weightLog, jsonEncode(v));

  // --- GPS adim boyu kalibrasyonu ---
  double? get strideCal => _p.getDouble(PrefsKeys.strideCal);
  int get strideCalCount => _p.getInt(PrefsKeys.strideCalCount) ?? 0;
  bool get strideUseCal => _p.getBool(PrefsKeys.strideUseCal) ?? true;
  Future<void> setStrideUseCal(bool v) => _p.setBool(PrefsKeys.strideUseCal, v);
  Future<void> setStrideCal(double m, int n) async {
    await _p.setDouble(PrefsKeys.strideCal, m);
    await _p.setInt(PrefsKeys.strideCalCount, n);
  }

  Future<void> clearStrideCal() async {
    await _p.remove(PrefsKeys.strideCal);
    await _p.remove(PrefsKeys.strideCalCount);
  }

  int get waterGoal => _p.getInt(PrefsKeys.waterGoal) ?? PrefsKeys.defaultWaterGoal;
  Future<void> setWaterGoal(int v) => _p.setInt(PrefsKeys.waterGoal, v);

  /// En son acilan rozetin kimligi ("tur:esik").
  String get lastBadge => _p.getString(PrefsKeys.lastBadge) ?? '';
  Future<void> setLastBadge(String v) => _p.setString(PrefsKeys.lastBadge, v);

  // --- Haftalik Rapor ---
  String get lastWeeklyReport => _p.getString(PrefsKeys.lastWeeklyReport) ?? '';
  Future<void> setLastWeeklyReport(String v) =>
      _p.setString(PrefsKeys.lastWeeklyReport, v);

  Future<void> clearAll() async {
    await _p.remove(PrefsKeys.hourly);
    await _p.remove(PrefsKeys.intensity);
    await _p.remove(PrefsKeys.goalNotifiedOn);
    await _p.remove(PrefsKeys.history);
    await _p.remove(PrefsKeys.savedToday);
    await _p.remove(PrefsKeys.baseline);
    await _p.remove(PrefsKeys.lastDate);
    await _p.remove(PrefsKeys.overriddenDays);
    await _p.remove(PrefsKeys.water);
    await _p.remove(PrefsKeys.unlockedBadges);
    await _p.remove(PrefsKeys.lastBadge);
    await _p.remove(PrefsKeys.lastWeeklyReport);
  }

  static final RegExp _dayKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Bozuk bir anahtar ilerideki `Metrics.parseKey` cagrilarinda istisna
  /// atiyordu; okuma asamasinda elenir.
  static bool _validKey(String k) => _dayKeyPattern.hasMatch(k);

  /// Arka plan isolate'i de ayni cozumlemeyi kullanir.
  static Map<String, int> decodeHistory(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, int>{};
      m.forEach((k, v) {
        if (!_validKey(k) || v is! num) return;
        final value = v.toInt();
        if (value < 0) return;
        out[k] = value;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Map<String, List<int>> decodeHourly(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final out = <String, List<int>>{};
      m.forEach((k, v) {
        if (!_validKey(k) || v is! List || v.length != 24) return;
        final hours = <int>[];
        var ok = true;
        for (final e in v) {
          if (e is! num) {
            ok = false;
            break;
          }
          final value = e.toInt();
          hours.add(value < 0 ? 0 : value);
        }
        if (ok) out[k] = hours;
      });
      return out;
    } catch (_) {
      return {};
    }
  }
}
