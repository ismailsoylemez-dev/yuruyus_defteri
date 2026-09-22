import 'dart:math' as math;

/// Adim -> mesafe / kalori / sure donusumlerinin TEK kaynagi.
///
/// Tum km / kcal / MET formulleri burada. Tempo kirilimi
/// ([ActivityBreakdown]), widget, veri dokumu ve grafikler yalnizca bu
/// fonksiyonlari kullanir. Native taraf (uygulama kapaliyken bildirim ve
/// widget) ayni formulleri android/.../Formulas.kt icinde birebir tasir;
/// birini degistirirsen digerini de degistir (test/formulas_test.dart
/// ortak referans degerleri tutar).
class Metrics {
  /// GPS ile olculen adim boyu (m). Doluysa boydan tahminin yerine gecer;
  /// SettingsProvider.applyStride yazar. Native taraf ayni degeri
  /// Formulas.strideOverrideM ile kullanir.
  static double? strideOverrideM;

  /// Ortalama adim uzunlugu (metre): olculmusse o, degilse boy cm * 0.415.
  static double strideMeters(int heightCm) =>
      strideOverrideM ?? heightCm * 0.415 / 100;

  /// Boydan tahmin (kalibrasyon karsilastirmasi icin).
  static double estimatedStrideMeters(int heightCm) => heightCm * 0.415 / 100;

  static double distanceKm(int steps, int heightCm) =>
      steps * strideMeters(heightCm) / 1000;

  /// Normal yurume temposu. Tahmini ve saatlik hesap ayni sabiti kullanir;
  /// aksi halde ayni gun icin iki ekran farkli sure gosterir.
  static const stepsPerMinute = 110;

  /// Bir saati "aktif" saymak icin gereken en az adim. Daha azi cihazin
  /// cebe konup cikarilmasi gibi gurultudur; sayilirsa 24 saat boyunca
  /// 1'er adim = 24 dakika aktif sure gibi sacma sonuclar cikar.
  static const minHourSteps = 20;

  /// Kalori hesabinda kullanilan hizin makul siniri (km/sa). Saatlik kayit
  /// eksik kalirsa sure kuculur, hiz firlar ve MET katsayisi kaloriyi
  /// katlar; bu sinir o sapmayi engeller.
  ///
  /// Ust sinir bilerek 8.0 degil 7.5: [metForSpeed] tablosunda 8.0 ve
  /// uzeri kosu kademesi (9.8 MET) ve boy tabanli adim uzunlugu modeli o
  /// hizlarda zaten gecerli degil. 8.0'a kirpmak hicbir sey degistirmezdi.
  static const minSpeedKmh = 1.5;
  static const maxSpeedKmh = 7.5;

  /// Ortalama tempo kabulu ile aktif sure.
  static int activeMinutes(int steps) => (steps / stepsPerMinute).round();

  /// Saatlik kayittan gercek aktif sureyi tahmin eder.
  /// Bir saatte atilan adim normal tempoda kac dakika surerdi sorusunun
  /// cevabi; saat basina 60 dakika ile sinirlanir.
  static int activeMinutesFromHours(List<int> hours) {
    if (hours.isEmpty) return 0;
    var total = 0;
    for (final h in hours) {
      if (h < minHourSteps) continue;
      total += (h / stepsPerMinute).ceil().clamp(1, 60);
    }
    return total;
  }

  /// Yurume hizina karsilik gelen MET katsayisi (Compendium of
  /// Physical Activities degerlerine yakin kademeler).
  static double metForSpeed(double kmh) {
    if (kmh <= 0) return 0;
    if (kmh < 3.2) return 2.8;
    if (kmh < 4.0) return 3.0;
    if (kmh < 4.8) return 3.5;
    if (kmh < 5.6) return 4.3;
    if (kmh < 6.4) return 5.0;
    if (kmh < 8.0) return 7.0;
    return 9.8;
  }

  // ---- Tempo esikleri ve MET (tempolu yuruyus / kosu) ----

  /// Dakika kadansi esikleri (adim/dk), StepService.kt ile ayni.
  static const briskMinCadence = 100;
  static const runMinCadence = 140;

  /// Kosu adim uzunlugu yurumenin ~%50 fazlasi: boy * 0.62.
  static double runStrideMeters(int heightCm) => heightCm * 0.62 / 100;

  /// Kadansa gore tempolu yuruyus MET degeri.
  ///
  /// CADENCE-Adults (Tudor-Locke ve ark.): 100 adim/dk ~ 3 MET, 130 adim/dk
  /// ~ 6 MET; arasi yaklasik dogrusal (+0,1 MET / adim/dk). Hiz tablosundan
  /// ([metForSpeed]) dusuk cikmamasi icin ikisinin buyugu alinir.
  static double briskMet(double cadence, int heightCm) {
    final byCadence = 3.0 + (cadence - briskMinCadence) * 0.1;
    final kmh = cadence * strideMeters(heightCm) * 60 / 1000;
    return math.max(byCadence, metForSpeed(kmh)).clamp(3.0, 8.0);
  }

  /// Kosu MET: ACSM kosu denklemi VO2 = 0.2 * hiz(m/dk) + 3.5 (duz zemin),
  /// MET = VO2 / 3.5. Hiz = kadans * kosu adim uzunlugu.
  static double runMet(double cadence, int heightCm) {
    final speed = (cadence * runStrideMeters(heightCm)).clamp(100.0, 300.0);
    return (0.2 * speed + 3.5) / 3.5;
  }

  /// kcal = MET * kilo(kg) * sure(saat)
  /// [activeMin] verilirse gercek tempo kullanilir; verilmezse
  /// [stepsPerMinute] (110 adim/dk) varsayimiyla hesaplanir.
  ///
  /// Hiz [minSpeedKmh] - [maxSpeedKmh] araligina kirpilir: eksik saatlik
  /// kayit yuzunden sure oldugundan kisa cikarsa kalori katlanmasin.
  static double kcal(
    int steps,
    int heightCm,
    double weightKg, {
    int? activeMin,
  }) {
    if (steps <= 0) return 0;
    final minutes =
        (activeMin != null && activeMin > 0) ? activeMin : activeMinutes(steps);
    if (minutes <= 0) return 0;

    final hours = minutes / 60;
    final speed =
        (distanceKm(steps, heightCm) / hours).clamp(minSpeedKmh, maxSpeedKmh);
    return metForSpeed(speed) * weightKg * hours;
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static final RegExp _keyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Kayit anahtari "yyyy-MM-dd" bicimine uyuyor mu.
  static bool isValidKey(String k) => _keyPattern.hasMatch(k);

  static DateTime parseKey(String key) {
    final p = key.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// Bozuk anahtarda istisna atmak yerine null doner.
  static DateTime? tryParseKey(String key) {
    if (!isValidKey(key)) return null;
    final p = key.split('-');
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final parsed = DateTime(y, m, d);
    // 2026-02-31 gibi tasan tarihler DateTime tarafindan kaydirilir.
    if (parsed.year != y || parsed.month != m || parsed.day != d) return null;
    return parsed;
  }

  /// Iki tarih arasindaki tam gun farki. [Duration.inDays] yaz saati
  /// gecislerinde 23/25 saatlik gunlerde yanilabildigi icin gun bilesenleri
  /// uzerinden sayilir.
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// Takvimde [days] gun ileri/geri gider (DST'den etkilenmez).
  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static const weekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  static const weekdayLong = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'
  ];

  static const months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
  ];

  static String shortLabel(DateTime d) => weekdayShort[d.weekday - 1];

  static String longLabel(DateTime d) => weekdayLong[d.weekday - 1];

  static String monthName(int m) => months[m - 1];

  static String fullLabel(DateTime d) => '${d.day} ${months[d.month - 1]}';

  /// 21.09.2026
  static String numericDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// 1 kg vucut yagi ~ 7.700 kcal. Bu, yag dokusunun enerji icerigidir;
  /// kisinin boyuna/kilosuna gore degismez (kilo ve boy zaten harcanan
  /// kaloriyi hesaplarken kullaniliyor, burada ikinci kez carpilmamali).
  static const kcalPerKgFat = 7700.0;

  /// Yuruyusle harcanan kalorinin yag karsiligi (kg). [weightKg] ve [heightCm]
  /// eski cagrilarla uyum icin durur; sonuca etkisi yoktur.
  static double fatKg(double kcal, [double? weightKg, int? heightCm]) {
    if (kcal <= 0) return 0;
    return kcal / kcalPerKgFat;
  }

  /// Dakikayi "2 sa 14 dk" bicimine cevirir.
  static String duration(int minutes) {
    if (minutes < 60) return '$minutes dk';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h sa' : '$h sa $m dk';
  }

  /// Buyuk sayilari kisaltir: 8240 -> 8,2b
  static String compact(int v) {
    if (v < 1000) return v.toString();
    final k = v / 1000;
    return '${k.toStringAsFixed(k >= 10 ? 0 : 1).replaceAll('.', ',')}b';
  }

  /// Haftanin pazartesi gunu (DST'den etkilenmeyen takvim aritmetigi).
  static DateTime weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  static String thousands(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
}
