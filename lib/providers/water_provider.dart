import 'package:flutter/foundation.dart';
import '../services/prefs_service.dart';
import '../utils/metrics.dart';
import '../services/cloud_service.dart';

class WaterProvider extends ChangeNotifier {
  final PrefsService prefs;
  Map<String, int> _water = {};
  CloudService? _cloud;

  WaterProvider(this.prefs) {
    _water = prefs.water;
  }

  void attachCloud(CloudService? cloud) {
    _cloud = cloud;
    notifyListeners();
  }

  void detachCloud(CloudService cloud) {
    if (!identical(_cloud, cloud)) return;
    _cloud = null;
    notifyListeners();
  }

  /// Widget'taki "su ekle" dugmesi uygulama kapaliyken ayni kayda yazar;
  /// uygulama one gelince (prefs.reload sonrasi) bellekteki kopya tazelenir.
  void reloadFromPrefs() {
    final fresh = prefs.water;
    var changed = fresh.length != _water.length;
    if (!changed) {
      for (final e in fresh.entries) {
        if (_water[e.key] != e.value) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) return;
    _water = fresh;
    pushToCloud();
    notifyListeners();
  }

  /// Tüm su verisi (ml)
  Map<String, int> get history => _water;

  /// Bugün içilen su miktarı (ml)
  int get todayWater {
    final today = Metrics.dayKey(DateTime.now());
    return _water[today] ?? 0;
  }

  /// Su ekleme (ml bazlı, e.g. 250ml)
  Future<void> addWater(int ml) async {
    final today = Metrics.dayKey(DateTime.now());
    final current = _water[today] ?? 0;
    final newValue = (current + ml).clamp(0, 20000); 
    
    _water[today] = newValue;
    await prefs.setWater(_water);
    pushToCloud();
    notifyListeners();
  }

  /// Geri alma (Yanlışlıkla basıldıysa)
  Future<void> removeWater(int ml) async {
    final today = Metrics.dayKey(DateTime.now());
    final current = _water[today] ?? 0;
    final newValue = (current - ml).clamp(0, 20000);
    
    _water[today] = newValue;
    await prefs.setWater(_water);
    pushToCloud();
    notifyListeners();
  }

  /// Sadece yerel verileri temizler. Çıkış yaparken kullanılır.
  Future<void> clearLocalDataOnly() async {
    _water = {};
    await prefs.setWater(_water);
    notifyListeners();
  }

  /// "Tum kayitlari sil": bellekteki ve diskteki su kaydi temizlenir.
  /// Buluttaki su verisi yil dokumanlarinda; onlar StepProvider.resetData
  /// icindeki clearRemote ile birlikte silinir.
  Future<void> resetData() async {
    _water = {};
    await prefs.setWater(_water);
    notifyListeners();
  }

  /// Toplam içilen su (Tüm zamanlar)
  int get totalWaterAllTime {
    return _water.values.fold<int>(0, (a, b) => a + b);
  }
  
  /// Icinde bulunulan hafta (Pazartesi -> Pazar).
  List<MapEntry<DateTime, int>> currentWeek() {
    final start = Metrics.weekStart(DateTime.now());
    final live = _water;
    return List.generate(7, (i) {
      final d = start.add(Duration(days: i));
      return MapEntry(d, live[Metrics.dayKey(d)] ?? 0);
    });
  }

  /// Mevcut veriyi bulut kuyruguna alir; gercek yazma gecikmeli yapilir.
  void pushToCloud() {
    _cloud?.scheduleWaterPush(_water);
  }

  /// Buluttan gelen veri ile yerel veriyi birleştirir (Büyük olan kazanır).
  Future<void> importHistory(Map<String, int> cloudHistory) async {
    bool changed = false;
    
    cloudHistory.forEach((day, ml) {
      final current = _water[day] ?? 0;
      if (ml > current) {
        _water[day] = ml;
        changed = true;
      }
    });

    if (changed) {
      await prefs.setWater(_water);
      notifyListeners();
    }
  }
}
