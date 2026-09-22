import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../widgets/home_widget_view.dart';

/// Ana ekran widget'ini Flutter gorunumunu PNG'ye render ederek gunceller.
class WidgetService {
  static const _providerName = 'StepWidgetProvider';
  static const _imageKey = 'stepWidgetImage';

  /// Cok sik render etmemek icin en az bu aralikla calisir.
  static const minGap = Duration(seconds: 20);

  static bool _busy = false;
  static DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  static bool enabled = false;
  static String? lastError;
  static int updateCount = 0;

  /// Cagiran taraf agir parametreleri (haftalik seri, gecmis kopyasi)
  /// hazirlamadan once kontrol edebilsin diye disari acildi.
  static bool canUpdate({bool force = false}) {
    if (_busy) return false;
    // enabled yalnizca gercek sensor akisi basladiginda (Android) true olur.
    if (!enabled && !force) return false;
    if (force) return true;
    return DateTime.now().difference(_last) >= minGap;
  }

  static Future<void> update({
    required int steps,
    required List<int> week,
    required int goal,
    // km / kcal / sure cagiran taraftan gelir (StepProvider.breakdownForDay):
    // uygulama, kalici bildirim ve widget ayni tempo kirilimli hesabi gosterir.
    required double km,
    required double kcal,
    required int minutes,
    /// null: su takibi kapali.
    int? waterMl,
    bool force = false,
  }) async {
    if (!canUpdate(force: force)) return;

    _busy = true;
    try {
      await HomeWidget.renderFlutterWidget(
        HomeWidgetView(
          steps: steps,
          goal: goal,
          km: km,
          kcal: kcal,
          minutes: minutes,
          week: week,
          todayIndex: DateTime.now().weekday - 1,
          waterMl: waterMl,
        ),
        key: _imageKey,
        logicalSize: const Size(360, 168),
        pixelRatio: 3,
      );

      await HomeWidget.updateWidget(
        name: _providerName,
        androidName: _providerName,
      );
      updateCount++;
      lastError = null;
    } catch (e) {
      lastError = '$e';
      debugPrint('Widget güncellenemedi: $e');
    } finally {
      // _last yalnizca basarida yazilirsa, render surekli hata veren bir
      // cihazda canUpdate hep true doner ve HER ADIM OLAYINDA yeniden
      // render denenir (saniyede ~2 PNG). Basarisiz deneme de ayni
      // araliga tabi olmali.
      _last = DateTime.now();
      _busy = false;
    }
  }
}
