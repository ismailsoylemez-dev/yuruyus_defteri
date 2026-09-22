import 'package:flutter/foundation.dart';
import '../services/foreground_service.dart';
import '../services/prefs_service.dart';
import '../utils/metrics.dart';

class SettingsProvider extends ChangeNotifier {
  final PrefsService _prefs;
  SettingsProvider(this._prefs) {
    applyStride();
  }

  int get goal => _prefs.goal;
  int get heightCm => _prefs.heightCm;
  double get weightKg => _prefs.weightKg;

  Future<void> setGoal(int v) async {
    await _prefs.setGoal(v.clamp(1000, 40000));
    notifyListeners();
  }

  Future<void> setHeight(int v) async {
    await _prefs.setHeight(v.clamp(120, 230));
    notifyListeners();
  }

  Future<void> setWeight(double v) async {
    await _prefs.setWeight(v.clamp(30.0, 250.0));
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Su takibi ac/kapat
  // ------------------------------------------------------------------

  /// Kapaliyken su ile ilgili her dugme, satir ve ikon gizlenir.
  bool get waterEnabled => _prefs.waterEnabled;

  Future<void> setWaterEnabled(bool v) async {
    await _prefs.setWaterEnabled(v);
    notifyListeners();
    await ForegroundService.waterChanged();
  }

  // ------------------------------------------------------------------
  // Kilo takibi
  // ------------------------------------------------------------------

  Map<String, double> get weightLog => _prefs.weightLog;

  /// Gunun kilosunu kaydeder. En yeni kayit profil kilosu olur (kalori
  /// hesabi guncel kiloyla yapilir).
  Future<void> addWeight(DateTime day, double kg) async {
    final v = double.parse(kg.clamp(30.0, 250.0).toStringAsFixed(1));
    final log = _prefs.weightLog..[Metrics.dayKey(day)] = v;
    await _prefs.setWeightLog(log);
    await _syncProfileWeight(log);
    notifyListeners();
  }

  Future<void> removeWeight(String dayKey) async {
    final log = _prefs.weightLog..remove(dayKey);
    await _prefs.setWeightLog(log);
    await _syncProfileWeight(log);
    notifyListeners();
  }

  /// Buluttan gelen kayitlarla birlestirir (ayni gunde yerel kalir).
  Future<void> mergeWeightLog(Map<String, double> incoming) async {
    if (incoming.isEmpty) return;
    final log = _prefs.weightLog;
    var changed = false;
    incoming.forEach((k, v) {
      if (!log.containsKey(k)) {
        log[k] = v;
        changed = true;
      }
    });
    if (!changed) return;
    await _prefs.setWeightLog(log);
    notifyListeners();
  }

  Future<void> _syncProfileWeight(Map<String, double> log) async {
    if (log.isEmpty) return;
    final last = (log.keys.toList()..sort()).last;
    await _prefs.setWeight(log[last]!);
  }

  // ------------------------------------------------------------------
  // GPS ile adim boyu kalibrasyonu
  // ------------------------------------------------------------------

  /// Olculen adim boyu (m) ve kac yuruyusten olculdugu.
  double? get strideCal => _prefs.strideCal;
  int get strideCalCount => _prefs.strideCalCount;
  bool get strideUseCal => _prefs.strideUseCal;

  /// Hesaplarda kullanilan adim boyu (m): kalibrasyon aciksa ve en az
  /// [minCalSamples] yuruyusten olculduyse o, degilse boydan tahmin.
  double get strideMeters => Metrics.strideMeters(heightCm);

  static const minCalSamples = 3;

  Future<void> setStrideUseCal(bool v) async {
    await _prefs.setStrideUseCal(v);
    applyStride();
    notifyListeners();
  }

  Future<void> setStrideCal(double m, int n) async {
    await _prefs.setStrideCal(m, n);
    applyStride();
    notifyListeners();
  }

  Future<void> resetStrideCal() async {
    await _prefs.clearStrideCal();
    applyStride();
    notifyListeners();
  }

  /// Metrics'teki genel adim boyu ayarini gunceller (tum km/kcal hesaplari).
  void applyStride() {
    final m = _prefs.strideCal;
    Metrics.strideOverrideM = _prefs.strideUseCal &&
            m != null &&
            _prefs.strideCalCount >= minCalSamples
        ? m
        : null;
    // Native servis (bildirim / kapaliyken widget) ayni degeri kullansin.
    ForegroundService.setStride(Metrics.strideOverrideM);
  }

  /// Gunluk su hedefi (ml): 1 - 6 L arasi.
  int get waterGoal => _prefs.waterGoal;

  Future<void> setWaterGoal(int ml) async {
    await _prefs.setWaterGoal(ml.clamp(1000, 6000));
    notifyListeners();
  }

  bool get notifyGoal => _prefs.notifyGoal;
  bool get notifyEvening => _prefs.notifyEvening;
  bool get notifyWeekly => _prefs.notifyWeekly;

  Future<void> setNotifyGoal(bool v) async {
    await _prefs.setNotifyGoal(v);
    notifyListeners();
  }

  Future<void> setNotifyEvening(bool v) async {
    await _prefs.setNotifyEvening(v);
    notifyListeners();
  }

  Future<void> setNotifyWeekly(bool v) async {
    await _prefs.setNotifyWeekly(v);
    notifyListeners();
  }

  Future<void> applyBackup({
    required int goal,
    required int heightCm,
    required double weightKg,
  }) async {
    await _prefs.setGoal(goal.clamp(1000, 40000));
    await _prefs.setHeight(heightCm.clamp(120, 230));
    await _prefs.setWeight(weightKg.clamp(30.0, 250.0));
    notifyListeners();
  }
}
