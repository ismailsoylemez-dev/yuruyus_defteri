import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android TYPE_STEP_COUNTER kanali (MainActivity.kt).
///
/// Deger cihaz acilisindan beri toplam adimdir ve her adimda gelir;
/// pedometer eklentisinin toplu raporlamasinin aksine gecikme yoktur.
/// Kanal calismazsa cagiran taraf pedometer akisina duser.
class StepSensorService {
  static const _channel = EventChannel('adim_sayar/step_counter');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Kumulatif ham sayac degeri.
  static Stream<int> get counterStream => _channel
      .receiveBroadcastStream()
      .map((e) => (e as num).toInt())
      .where((v) => v >= 0);
}
