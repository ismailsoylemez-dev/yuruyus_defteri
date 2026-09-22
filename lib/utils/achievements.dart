import 'package:flutter/material.dart';

import 'aggregate.dart';
import 'metrics.dart';

enum AchievementKind {
  totalSteps,
  distance,
  calories,
  days,
  goalDays,
  streak,
  single,
  bestWeek,
  bestMonth,
}

class Achievement {
  final AchievementKind kind;
  final num threshold;
  final String title;

  /// Rozetin altindaki kisa aciklama (or. "Maraton").
  final String unit;
  final IconData icon;

  const Achievement({
    required this.kind,
    required this.threshold,
    required this.title,
    required this.unit,
    required this.icon,
  });
}

class AchievementProgress {
  final Achievement item;
  final num current;

  const AchievementProgress(this.item, this.current);

  bool get unlocked => current >= item.threshold;
  double get ratio =>
      item.threshold <= 0 ? 1.0 : (current / item.threshold).clamp(0.0, 1.0);
}

/// Rozet kategorisi (ekranda ayri baslik altinda listelenir).
class AchievementCategory {
  final AchievementKind kind;
  final String title;
  final IconData icon;

  const AchievementCategory(this.kind, this.title, this.icon);
}

/// Rozetlerin hesaplandigi toplu degerler; kayitlardan tek geciste cikar.
class AchievementStats {
  final int totalSteps;
  final double totalKm;
  final double totalKcal;
  final int recordedDays;
  final int goalDays;
  final int bestStreak;
  final int currentStreak;
  final int bestDay;
  final int bestWeek;
  final int bestMonth;

  const AchievementStats({
    required this.totalSteps,
    required this.totalKm,
    required this.totalKcal,
    required this.recordedDays,
    required this.goalDays,
    required this.bestStreak,
    required this.currentStreak,
    required this.bestDay,
    required this.bestWeek,
    required this.bestMonth,
  });

  /// [totalKcal] disaridan gelir: Istatistik ekranindaki "Tum zamanlar"
  /// karti ile ayni deger (gercek aktif sure varsa onunla) kullanilsin.
  factory AchievementStats.from({
    required Map<String, int> history,
    required int goal,
    required int heightCm,
    required double totalKcal,
    double? totalKm,
  }) {
    var total = 0;
    var recorded = 0;
    var goalDays = 0;
    var bestDay = 0;
    final weeks = <String, int>{};
    final months = <String, int>{};

    history.forEach((k, v) {
      if (v <= 0) return;
      final d = Metrics.tryParseKey(k);
      if (d == null) return;
      total += v;
      recorded++;
      if (goal > 0 && v >= goal) goalDays++;
      if (v > bestDay) bestDay = v;
      final w = Metrics.dayKey(Metrics.weekStart(d));
      weeks[w] = (weeks[w] ?? 0) + v;
      final m = '${d.year}-${d.month}';
      months[m] = (months[m] ?? 0) + v;
    });

    int maxOf(Map<String, int> m) =>
        m.values.fold<int>(0, (a, b) => b > a ? b : a);

    return AchievementStats(
      totalSteps: total,
      totalKm: totalKm ?? Metrics.distanceKm(total, heightCm),
      totalKcal: totalKcal,
      recordedDays: recorded,
      goalDays: goalDays,
      bestStreak: Aggregate.bestStreak(history, goal),
      currentStreak: Aggregate.currentStreak(history, goal),
      bestDay: bestDay,
      bestWeek: maxOf(weeks),
      bestMonth: maxOf(months),
    );
  }

  num valueFor(AchievementKind kind) => switch (kind) {
        AchievementKind.totalSteps => totalSteps,
        AchievementKind.distance => totalKm,
        AchievementKind.calories => totalKcal,
        AchievementKind.days => recordedDays,
        AchievementKind.goalDays => goalDays,
        AchievementKind.streak => bestStreak,
        AchievementKind.single => bestDay,
        AchievementKind.bestWeek => bestWeek,
        AchievementKind.bestMonth => bestMonth,
      };
}

class Achievements {
  static const categories = <AchievementCategory>[
    AchievementCategory(
        AchievementKind.distance, 'Mesafe', Icons.straighten),
    AchievementCategory(
        AchievementKind.totalSteps, 'Toplam adım', Icons.directions_walk),
    AchievementCategory(AchievementKind.calories, 'Yakılan enerji',
        Icons.local_fire_department_outlined),
    AchievementCategory(
        AchievementKind.streak, 'Hedef serisi', Icons.whatshot_outlined),
    AchievementCategory(
        AchievementKind.goalDays, 'Hedefi tutan gün', Icons.flag_outlined),
    AchievementCategory(
        AchievementKind.days, 'Kayıtlı gün', Icons.calendar_month_outlined),
    AchievementCategory(AchievementKind.single, 'Tek günde', Icons.bolt),
    AchievementCategory(
        AchievementKind.bestWeek, 'Tek haftada', Icons.date_range_outlined),
    AchievementCategory(
        AchievementKind.bestMonth, 'Tek ayda', Icons.calendar_view_month),
  ];

  static const all = <Achievement>[
    // Mesafe (km)
    Achievement(kind: AchievementKind.distance, threshold: 5, title: '5 KM', unit: 'başlangıç', icon: Icons.straighten),
    Achievement(kind: AchievementKind.distance, threshold: 10, title: '10 KM', unit: 'ilk adımlar', icon: Icons.straighten),
    Achievement(kind: AchievementKind.distance, threshold: 20, title: '20 KM', unit: 'yarı maraton', icon: Icons.straighten),
    Achievement(kind: AchievementKind.distance, threshold: 42.2, title: '42 KM', unit: 'maraton', icon: Icons.directions_run),
    Achievement(kind: AchievementKind.distance, threshold: 75, title: '75 KM', unit: 'uzun yol', icon: Icons.straighten),
    Achievement(kind: AchievementKind.distance, threshold: 100, title: '100 KM', unit: 'ultra', icon: Icons.straighten),
    Achievement(kind: AchievementKind.distance, threshold: 200, title: '200 KM', unit: 'şehirlerarası', icon: Icons.directions_car),
    Achievement(kind: AchievementKind.distance, threshold: 450, title: '450 KM', unit: 'İst - Ank', icon: Icons.signpost_outlined),
    Achievement(kind: AchievementKind.distance, threshold: 750, title: '750 KM', unit: 'uzak mesafe', icon: Icons.terrain),
    Achievement(kind: AchievementKind.distance, threshold: 1000, title: '1000 KM', unit: 'bin km', icon: Icons.terrain),
    Achievement(kind: AchievementKind.distance, threshold: 1600, title: '1600 KM', unit: 'Edirne - Kars', icon: Icons.map_outlined),
    Achievement(kind: AchievementKind.distance, threshold: 3000, title: '3000 KM', unit: 'kısa kıta', icon: Icons.flight_takeoff),
    Achievement(kind: AchievementKind.distance, threshold: 5000, title: '5000 KM', unit: 'kıta', icon: Icons.flight_takeoff),
    Achievement(kind: AchievementKind.distance, threshold: 10000, title: '10.000 KM', unit: 'okyanus', icon: Icons.waves),
    Achievement(kind: AchievementKind.distance, threshold: 40075, title: 'DÜNYA', unit: 'ekvator turu', icon: Icons.public),
    // Toplam adim
    Achievement(kind: AchievementKind.totalSteps, threshold: 10000, title: '10B', unit: 'adım', icon: Icons.directions_walk),
    Achievement(kind: AchievementKind.totalSteps, threshold: 50000, title: '50B', unit: 'adım', icon: Icons.directions_walk),
    Achievement(kind: AchievementKind.totalSteps, threshold: 100000, title: '100B', unit: 'adım', icon: Icons.directions_walk),
    Achievement(kind: AchievementKind.totalSteps, threshold: 250000, title: '250B', unit: 'adım', icon: Icons.directions_walk),
    Achievement(kind: AchievementKind.totalSteps, threshold: 500000, title: '500B', unit: 'adım', icon: Icons.directions_walk),
    Achievement(kind: AchievementKind.totalSteps, threshold: 750000, title: '750B', unit: 'adım', icon: Icons.military_tech),
    Achievement(kind: AchievementKind.totalSteps, threshold: 1000000, title: '1 MİLYON', unit: 'adım', icon: Icons.military_tech),
    Achievement(kind: AchievementKind.totalSteps, threshold: 2000000, title: '2 MİLYON', unit: 'adım', icon: Icons.military_tech),
    Achievement(kind: AchievementKind.totalSteps, threshold: 3000000, title: '3 MİLYON', unit: 'adım', icon: Icons.military_tech),
    Achievement(kind: AchievementKind.totalSteps, threshold: 5000000, title: '5 MİLYON', unit: 'adım', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.totalSteps, threshold: 7500000, title: '7,5 MİLYON', unit: 'adım', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.totalSteps, threshold: 10000000, title: '10 MİLYON', unit: 'adım', icon: Icons.diamond_outlined),
    Achievement(kind: AchievementKind.totalSteps, threshold: 20000000, title: '20 MİLYON', unit: 'adım', icon: Icons.diamond),
    Achievement(kind: AchievementKind.totalSteps, threshold: 50000000, title: '50 MİLYON', unit: 'adım', icon: Icons.diamond),
    // Kalori (7.700 kcal ~ 1 kg yag)
    Achievement(kind: AchievementKind.calories, threshold: 1500, title: 'İLK YAKIM', unit: '1.500 kcal', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.calories, threshold: 3850, title: 'Yarım KG', unit: '3.850 kcal', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.calories, threshold: 7700, title: '1 KG', unit: '7.700 kcal', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.calories, threshold: 15400, title: '2 KG', unit: '15.400 kcal', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.calories, threshold: 38500, title: '5 KG', unit: '38.500 kcal', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.calories, threshold: 77000, title: '10 KG', unit: '77.000 kcal', icon: Icons.whatshot),
    Achievement(kind: AchievementKind.calories, threshold: 115500, title: '15 KG', unit: '115.500 kcal', icon: Icons.whatshot),
    Achievement(kind: AchievementKind.calories, threshold: 154000, title: '20 KG', unit: '154.000 kcal', icon: Icons.whatshot),
    Achievement(kind: AchievementKind.calories, threshold: 231000, title: '30 KG', unit: '231.000 kcal', icon: Icons.whatshot_outlined),
    Achievement(kind: AchievementKind.calories, threshold: 385000, title: '50 KG', unit: '385.000 kcal', icon: Icons.whatshot_outlined),
    Achievement(kind: AchievementKind.calories, threshold: 770000, title: '100 KG', unit: '770.000 kcal', icon: Icons.whatshot_outlined),
    // Seri (ust uste hedef)
    Achievement(kind: AchievementKind.streak, threshold: 3, title: '3 GÜN', unit: 'üst üste', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.streak, threshold: 7, title: '7 GÜN', unit: 'üst üste', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.streak, threshold: 14, title: '14 GÜN', unit: 'üst üste', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.streak, threshold: 21, title: '21 GÜN', unit: 'üst üste', icon: Icons.local_fire_department),
    Achievement(kind: AchievementKind.streak, threshold: 30, title: '30 GÜN', unit: 'üst üste', icon: Icons.whatshot),
    Achievement(kind: AchievementKind.streak, threshold: 45, title: '45 GÜN', unit: 'üst üste', icon: Icons.whatshot),
    Achievement(kind: AchievementKind.streak, threshold: 60, title: '60 GÜN', unit: 'üst üste', icon: Icons.whatshot),
    Achievement(kind: AchievementKind.streak, threshold: 75, title: '75 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 100, title: '100 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 150, title: '150 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 200, title: '200 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 250, title: '250 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 300, title: '300 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 365, title: '365 GÜN', unit: 'üst üste', icon: Icons.emoji_events),
    Achievement(kind: AchievementKind.streak, threshold: 500, title: '500 GÜN', unit: 'üst üste', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.streak, threshold: 730, title: '2 YIL', unit: 'üst üste', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.streak, threshold: 1000, title: '1000 GÜN', unit: 'üst üste', icon: Icons.diamond_outlined),
    // Hedefi tutan gun (toplam)
    Achievement(kind: AchievementKind.goalDays, threshold: 5, title: '5 GÜN', unit: 'hedef', icon: Icons.flag),
    Achievement(kind: AchievementKind.goalDays, threshold: 10, title: '10 GÜN', unit: 'hedef', icon: Icons.flag),
    Achievement(kind: AchievementKind.goalDays, threshold: 25, title: '25 GÜN', unit: 'hedef', icon: Icons.flag),
    Achievement(kind: AchievementKind.goalDays, threshold: 50, title: '50 GÜN', unit: 'hedef', icon: Icons.flag),
    Achievement(kind: AchievementKind.goalDays, threshold: 75, title: '75 GÜN', unit: 'hedef', icon: Icons.flag),
    Achievement(kind: AchievementKind.goalDays, threshold: 100, title: '100 GÜN', unit: 'hedef', icon: Icons.flag_circle),
    Achievement(kind: AchievementKind.goalDays, threshold: 150, title: '150 GÜN', unit: 'hedef', icon: Icons.flag_circle),
    Achievement(kind: AchievementKind.goalDays, threshold: 200, title: '200 GÜN', unit: 'hedef', icon: Icons.flag_circle),
    Achievement(kind: AchievementKind.goalDays, threshold: 250, title: '250 GÜN', unit: 'hedef', icon: Icons.flag_circle),
    Achievement(kind: AchievementKind.goalDays, threshold: 365, title: '1 YIL', unit: 'hedef', icon: Icons.verified),
    Achievement(kind: AchievementKind.goalDays, threshold: 500, title: '500 GÜN', unit: 'hedef', icon: Icons.verified),
    Achievement(kind: AchievementKind.goalDays, threshold: 750, title: '750 GÜN', unit: 'hedef', icon: Icons.verified),
    Achievement(kind: AchievementKind.goalDays, threshold: 1000, title: '1000 GÜN', unit: 'hedef', icon: Icons.verified_user),
    // Kayitli gun
    Achievement(kind: AchievementKind.days, threshold: 3, title: '3 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 7, title: '7 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 14, title: '14 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 30, title: '30 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 60, title: '60 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 100, title: '100 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 200, title: '200 GÜN', unit: 'kayıt', icon: Icons.calendar_month),
    Achievement(kind: AchievementKind.days, threshold: 365, title: '1 YIL', unit: 'kayıt', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.days, threshold: 500, title: '500 GÜN', unit: 'kayıt', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.days, threshold: 730, title: '2 YIL', unit: 'kayıt', icon: Icons.workspace_premium),
    Achievement(kind: AchievementKind.days, threshold: 1000, title: '1000 GÜN', unit: 'kayıt', icon: Icons.diamond_outlined),
    // Tek gun
    Achievement(kind: AchievementKind.single, threshold: 5000, title: '5B', unit: 'tek gün', icon: Icons.bolt),
    Achievement(kind: AchievementKind.single, threshold: 7500, title: '7,5B', unit: 'tek gün', icon: Icons.bolt),
    Achievement(kind: AchievementKind.single, threshold: 10000, title: '10B', unit: 'tek gün', icon: Icons.bolt),
    Achievement(kind: AchievementKind.single, threshold: 15000, title: '15B', unit: 'tek gün', icon: Icons.bolt),
    Achievement(kind: AchievementKind.single, threshold: 20000, title: '20B', unit: 'tek gün', icon: Icons.bolt),
    Achievement(kind: AchievementKind.single, threshold: 25000, title: '25B', unit: 'tek gün', icon: Icons.rocket_launch),
    Achievement(kind: AchievementKind.single, threshold: 30000, title: '30B', unit: 'tek gün', icon: Icons.rocket_launch),
    Achievement(kind: AchievementKind.single, threshold: 40000, title: '40B', unit: 'tek gün', icon: Icons.rocket_launch),
    Achievement(kind: AchievementKind.single, threshold: 50000, title: '50B', unit: 'tek gün', icon: Icons.rocket_launch),
    Achievement(kind: AchievementKind.single, threshold: 75000, title: '75B', unit: 'tek gün', icon: Icons.rocket_launch),
    Achievement(kind: AchievementKind.single, threshold: 100000, title: '100B', unit: 'tek gün', icon: Icons.diamond),
    // Tek hafta
    Achievement(kind: AchievementKind.bestWeek, threshold: 25000, title: '25B', unit: 'tek hafta', icon: Icons.date_range),
    Achievement(kind: AchievementKind.bestWeek, threshold: 40000, title: '40B', unit: 'tek hafta', icon: Icons.date_range),
    Achievement(kind: AchievementKind.bestWeek, threshold: 50000, title: '50B', unit: 'tek hafta', icon: Icons.date_range),
    Achievement(kind: AchievementKind.bestWeek, threshold: 70000, title: '70B', unit: 'tek hafta', icon: Icons.date_range),
    Achievement(kind: AchievementKind.bestWeek, threshold: 100000, title: '100B', unit: 'tek hafta', icon: Icons.date_range),
    Achievement(kind: AchievementKind.bestWeek, threshold: 150000, title: '150B', unit: 'tek hafta', icon: Icons.stars),
    Achievement(kind: AchievementKind.bestWeek, threshold: 200000, title: '200B', unit: 'tek hafta', icon: Icons.stars),
    Achievement(kind: AchievementKind.bestWeek, threshold: 300000, title: '300B', unit: 'tek hafta', icon: Icons.stars),
    Achievement(kind: AchievementKind.bestWeek, threshold: 500000, title: '500B', unit: 'tek hafta', icon: Icons.diamond),
    // Tek ay
    Achievement(kind: AchievementKind.bestMonth, threshold: 100000, title: '100B', unit: 'tek ay', icon: Icons.calendar_view_month),
    Achievement(kind: AchievementKind.bestMonth, threshold: 150000, title: '150B', unit: 'tek ay', icon: Icons.calendar_view_month),
    Achievement(kind: AchievementKind.bestMonth, threshold: 200000, title: '200B', unit: 'tek ay', icon: Icons.calendar_view_month),
    Achievement(kind: AchievementKind.bestMonth, threshold: 300000, title: '300B', unit: 'tek ay', icon: Icons.calendar_view_month),
    Achievement(kind: AchievementKind.bestMonth, threshold: 400000, title: '400B', unit: 'tek ay', icon: Icons.stars),
    Achievement(kind: AchievementKind.bestMonth, threshold: 500000, title: '500B', unit: 'tek ay', icon: Icons.stars),
    Achievement(kind: AchievementKind.bestMonth, threshold: 750000, title: '750B', unit: 'tek ay', icon: Icons.stars),
    Achievement(kind: AchievementKind.bestMonth, threshold: 1000000, title: '1 MİLYON', unit: 'tek ay', icon: Icons.diamond),
    Achievement(kind: AchievementKind.bestMonth, threshold: 1500000, title: '1,5 MİLYON', unit: 'tek ay', icon: Icons.diamond),
  ];


  /// Kategoriler arasinda benzersiz kimlik (basliklar tekrar ediyor).
  static String idOf(Achievement a) => '${a.kind.name}:${a.threshold}';

  static List<AchievementProgress> evaluate(AchievementStats s) => all
      .map((a) => AchievementProgress(a, s.valueFor(a.kind)))
      .toList();

  /// Acilmamislar icinde tamamlanmaya en yakin olan (yoksa null).
  static AchievementProgress? next(List<AchievementProgress> items) {
    AchievementProgress? best;
    for (final p in items) {
      if (p.unlocked) continue;
      if (best == null || p.ratio > best.ratio) best = p;
    }
    return best;
  }
}
