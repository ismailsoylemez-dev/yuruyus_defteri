import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Hedef kutlamasi, aksam hatirlatmasi ve haftalik ozet bildirimleri.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'adim_sayar_reminders';
  static const _idGoal = 1001;
  static const _idEvening = 1002;
  static const _idWeekly = 1003;

  static bool _ready = false;
  static String? lastError;

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Istanbul'));

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        const InitializationSettings(android: android),
      );
      _ready = true;
    } catch (e) {
      lastError = '$e';
      debugPrint('Bildirim servisi baslatilamadi: $e');
    }
  }

  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  static NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Hatirlatmalar',
          channelDescription: 'Hedef ve yurume hatirlatmalari',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          color: Color(0xFF4ADE80),
        ),
      );

  static Future<void> showGoalReached(int steps) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        _idGoal,
        'Günlük hedef tamamlandı',
        'Bugün $steps adım attın. Devam et!',
        _details,
      );
    } catch (e) {
      lastError = '$e';
    }
  }

  /// Aksam hatirlatmasi artik native serviste (StepService.onEvening):
  /// her gun 20:00'de, Ayarlar'daki anahtar aciksa ve hedef tutulmadiysa
  /// kalan adimla birlikte gonderilir; hedef tutulduysa hic gelmez.
  ///
  /// Burada yalnizca eski surumden kalan, her gun sabit metinle tekrar eden
  /// planli bildirim (varsa) iptal edilir. Ekranda duran bildirime dokunulmaz.
  static Future<void> scheduleEvening() async {
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((p) => p.id == _idEvening)) {
        await _plugin.cancel(_idEvening);
      }
    } catch (e) {
      lastError = '$e';
    }
  }

  /// Haftalik ozet artik native serviste (StepService.onWeekly): her Pazar
  /// 20:30'da gercek sayilarla (adim, km, hedef tutulan gun, gecen haftaya
  /// gore degisim). Burada yalnizca eski surumun sabit metinli planli
  /// bildirimi (varsa) iptal edilir.
  static Future<void> scheduleWeekly() async {
    if (!_ready) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      if (pending.any((p) => p.id == _idWeekly)) {
        await _plugin.cancel(_idWeekly);
      }
    } catch (e) {
      lastError = '$e';
    }
  }

  static Future<void> cancelEvening() => _safeCancel(_idEvening);
  static Future<void> cancelWeekly() => _safeCancel(_idWeekly);

  static Future<void> _safeCancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

}
