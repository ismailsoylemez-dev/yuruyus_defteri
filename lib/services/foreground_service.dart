import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/intensity.dart';

/// Servisten okunan kayit.
class ServiceSnapshot {
  final bool running;
  final String date;
  final int today;
  final Map<String, int> history;

  /// Servisin olcum anina gore tuttugu saatlik dagilim (uygulama kapaliyken
  /// de dolar).
  final Map<String, List<int>> hourly;

  /// Servisin dakika kadansindan cikardigi tempo kirilimi.
  final Map<String, List<int>> intensity;

  const ServiceSnapshot({
    required this.running,
    required this.date,
    required this.today,
    required this.history,
    this.hourly = const {},
    this.intensity = const {},
  });
}

/// Native arka plan servisinin (StepService.kt) kontrolu.
///
/// Eski surumde bu is flutter_foreground_task ile yapiliyordu; o eklenti
/// servisin icinde ikinci bir Dart isolate baslatip el sikismayi bekledigi
/// icin bazi cihazlarda ServiceTimeoutException atiyordu. Bu servis Dart
/// calistirmaz, dolayisiyla beklenecek bir cevap da yoktur.
class ForegroundService {
  static const _channel = MethodChannel('adim_sayar/service');

  static bool running = false;
  static String? lastError;

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Servisi baslatir. Sistem reddederse false doner, istisna firlatmaz.
  static Future<bool> start({
    required int goal,
    int? heightCm,
    double? weightKg,
  }) async {
    if (!supported) return false;
    try {
      await _channel.invokeMethod<bool>(
        'start',
        _profile(goal, heightCm, weightKg),
      );
      // Servis onCreate icinde running=true yapar; hemen sorulur.
      await syncRunningState();
      lastError = running ? null : 'Servis baslatilamadi.';
      return running;
    } on PlatformException catch (e) {
      lastError = e.message ?? e.code;
      running = false;
      debugPrint('StepService baslatilamadi: $e');
      return false;
    } catch (e) {
      lastError = '$e';
      running = false;
      return false;
    }
  }

  /// Hedef degistiginde kalici bildirim eski degerde kalmasin.
  ///
  /// Native tarafta ayri bir 'updateGoal' islemi yoksa servis ayni hedefle
  /// yeniden baslatilir; zaten calisan bir servis icin bu da bildirimi
  /// tazeler ve ikinci bir servis olusturmaz.
  static Future<void> updateGoal(
    int goal, {
    int? heightCm,
    double? weightKg,
  }) async {
    if (!supported || !running) return;
    final args = _profile(goal, heightCm, weightKg);
    try {
      await _channel.invokeMethod<bool>('updateGoal', args);
    } catch (e) {
      debugPrint('updateGoal yok, servis ayni hedefle tazeleniyor: $e');
      try {
        await _channel.invokeMethod<bool>('start', args);
      } catch (e2) {
        debugPrint('Servis hedefi guncellenemedi: $e2');
      }
    }
  }

  /// Servis bildirimde hedefi, widget'ta km/kcal icin boy ve kiloyu kullanir.
  static Map<String, Object> _profile(int goal, int? heightCm, double? weightKg) => {
        'goal': goal,
        if (heightCm != null) 'heightCm': heightCm,
        if (weightKg != null) 'weightKg': weightKg,
      };

  /// Uygulamadaki bugunku adimi servise iletir; servis kucukse benimser
  /// (kalici bildirim / widget uygulamayla ayni sayiyi gosterir). Eski
  /// native surumde yontem yoksa sessizce yok sayilir.
  static Future<void> syncToday(String date, int steps) async {
    if (!supported || !running || steps <= 0) return;
    try {
      await _channel.invokeMethod<bool>('syncToday', {
        'date': date,
        'steps': steps,
      });
    } catch (e) {
      debugPrint('syncToday desteklenmiyor: $e');
    }
  }

  /// GPS ile olculen adim boyu (m). null: boydan tahmine don. Kalici
  /// bildirim ve uygulama kapaliyken cizilen widget ayni degeri kullanir.
  static Future<void> setStride(double? meters) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('setStride', {'strideM': meters ?? -1.0});
    } catch (e) {
      debugPrint('setStride desteklenmiyor: $e');
    }
  }

  /// Su ayari degisti ya da su eklendi: bildirim ve widget (su seridi dahil)
  /// yeniden cizilsin.
  static Future<void> waterChanged() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('waterChanged');
    } catch (e) {
      debugPrint('waterChanged desteklenmiyor: $e');
    }
  }

  /// Pil optimizasyonu kapali mi (native, MainActivity).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Pil optimizasyonu ayar ekranini acar (native, MainActivity).
  static Future<void> openBatterySettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('openBatterySettings');
    } catch (e) {
      debugPrint('Pil ayarlari acilamadi: $e');
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (e) {
      lastError = '$e';
    }
    running = false;
  }

  /// Gercek durumu isletim sisteminden okur.
  static Future<bool> syncRunningState() async {
    if (!supported) {
      running = false;
      return false;
    }
    try {
      running = await _channel.invokeMethod<bool>('isRunning') ?? false;
    } catch (_) {
      running = false;
    }
    return running;
  }

  /// Servisin uygulama kapaliyken biriktirdigi kayitlari getirir.
  static Future<ServiceSnapshot?> pull() async {
    if (!supported) return null;
    try {
      final raw = await _channel.invokeMethod<String>('pull');
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;

      final history = <String, int>{};
      final rawHistory = jsonDecode(map['history'] as String? ?? '{}');
      if (rawHistory is Map) {
        rawHistory.forEach((k, v) {
          final key = k.toString();
          final value = v is num ? v.toInt() : int.tryParse(v.toString());
          if (value != null && value >= 0 && _validKey(key)) {
            history[key] = value;
          }
        });
      }

      final hourly = <String, List<int>>{};
      final rawHourly = jsonDecode(map['hourly'] as String? ?? '{}');
      if (rawHourly is Map) {
        rawHourly.forEach((k, v) {
          final key = k.toString();
          if (!_validKey(key) || v is! List || v.length != 24) return;
          final hours = <int>[];
          for (final e in v) {
            if (e is! num) return;
            final n = e.toInt();
            hours.add(n < 0 ? 0 : n);
          }
          hourly[key] = hours;
        });
      }

      // Eski native surumde alan yoktur: bos kalir, her sey normal sayilir.
      var intensity = <String, List<int>>{};
      try {
        intensity = Intensity.decodeMap(
          jsonDecode(map['intensity'] as String? ?? '{}'),
        );
      } catch (_) {}

      running = map['running'] == true;
      return ServiceSnapshot(
        running: running,
        date: map['date'] as String? ?? '',
        today: (map['today'] as num?)?.toInt() ?? 0,
        history: history,
        hourly: hourly,
        intensity: intensity,
      );
    } catch (e) {
      debugPrint('StepService okunamadi: $e');
      return null;
    }
  }

  /// "Tum kayitlari sil" servisin kendi kopyasini da temizlemeli.
  static Future<void> clear() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<bool>('clear');
    } catch (e) {
      debugPrint('StepService temizlenemedi: $e');
    }
  }

  static bool _validKey(String k) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k);
}
