import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../theme/app_theme.dart';
import '../utils/achievements.dart';
import '../utils/aggregate.dart';
import '../utils/metrics.dart';

/// Haftalik / aylik paylasilabilir ozet karti.
class InsightsScreen extends StatefulWidget {
  /// true: Haftalik sekmesiyle acilir.
  final bool weekly;
  const InsightsScreen({super.key, this.weekly = false});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _shot = ScreenshotController();
  bool _isSharing = false;
  late bool _weekly = widget.weekly;
  int _offset = 0;

  Period get _period => _weekly ? Period.week : Period.month;

  Future<void> _share(String title) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final image = await _shot.capture(
        delay: const Duration(milliseconds: 20),
        pixelRatio: 3.0,
      );
      if (image == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ozet_${_weekly ? 'hafta' : 'ay'}.png');
      await file.writeAsBytes(image);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '$title 🚶 #YürüyüşDefteri',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşım sırasında bir hata oluştu.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();
    final data = PeriodSummary.compute(
      step: step,
      goal: settings.goal,
      heightCm: settings.heightCm,
      period: _period,
      offset: _offset,
    );
    final title = _weekly ? 'Haftalık Özet' : '${Metrics.monthName(data.range.start.month)} Özeti';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Görsel Özet'),
        actions: [
          _isSharing
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  icon: Icon(Icons.ios_share_rounded, color: AppColors.accent),
                  tooltip: 'Paylaş',
                  onPressed: () => _share(title),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Haftalık'), icon: Icon(Icons.view_week_rounded)),
              ButtonSegment(value: false, label: Text('Aylık'), icon: Icon(Icons.calendar_month_rounded)),
            ],
            selected: {_weekly},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _weekly = s.first;
              _offset = 0;
            }),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _offset--),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  data.range.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                onPressed: _offset < 0 ? () => setState(() => _offset++) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Screenshot(
            controller: _shot,
            child: SummaryShareCard(title: title, data: data, weekly: _weekly),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isSharing ? null : () => _share(title),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Kartı paylaş', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Bir haftanin/ayin ozet verisi (kart ve Bugun sayfasindaki girisler icin).
class PeriodSummary {
  final PeriodRange range;
  final int steps;
  final double km;
  final double kcal;
  final int minutes;
  final int activeDays;
  final int goalDays;

  /// Donemdeki gecen gun sayisi (bugunden sonrasi sayilmaz).
  final int elapsedDays;
  final int bestDaySteps;
  final DateTime? bestDay;

  /// Onceki doneme gore adim degisimi (%); onceki donem bossa null.
  final int? changePct;

  /// Gunluk adimlar (grafik).
  final List<MapEntry<DateTime, int>> days;

  /// Bu donemde acilan rozetler.
  final List<Achievement> newBadges;
  final int totalBadges;

  const PeriodSummary({
    required this.range,
    required this.steps,
    required this.km,
    required this.kcal,
    required this.minutes,
    required this.activeDays,
    required this.goalDays,
    required this.elapsedDays,
    required this.bestDaySteps,
    required this.bestDay,
    required this.changePct,
    required this.days,
    required this.newBadges,
    required this.totalBadges,
  });

  int get avgSteps => elapsedDays == 0 ? 0 : (steps / elapsedDays).round();

  static PeriodSummary compute({
    required StepProvider step,
    required int goal,
    required int heightCm,
    required Period period,
    int offset = 0,
  }) {
    final history = step.history;
    final r = Aggregate.range(period, offset);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = r.end.isAfter(today) ? today : r.end;

    var steps = 0;
    var active = 0;
    var goalDays = 0;
    var best = 0;
    DateTime? bestDay;
    final days = <MapEntry<DateTime, int>>[];
    for (var d = r.start; !d.isAfter(r.end); d = Metrics.addDays(d, 1)) {
      final v = d.isAfter(last) ? 0 : history[Metrics.dayKey(d)] ?? 0;
      days.add(MapEntry(d, v));
      steps += v;
      if (v > 0) active++;
      if (goal > 0 && v >= goal) goalDays++;
      if (v > best) {
        best = v;
        bestDay = d;
      }
    }
    final elapsed = last.isBefore(r.start) ? 0 : Metrics.daysBetween(r.start, last) + 1;

    // Onceki donemin ayni uzunluktaki kismiyla karsilastirma.
    final prev = Aggregate.range(period, offset - 1);
    final prevEnd = Metrics.addDays(prev.start, elapsed - 1);
    final prevSteps = elapsed == 0
        ? 0
        : Aggregate.totalBetween(
            history, prev.start, prevEnd.isAfter(prev.end) ? prev.end : prevEnd);
    final change = prevSteps > 0 ? (((steps - prevSteps) / prevSteps) * 100).round() : null;

    final bd = step.breakdownBetween(r.start, last);

    // Donemde acilan rozetler: donem sonuna kadarki kayitla acik olup
    // donem basindan onceki kayitla kapali olanlar.
    final newBadges = <Achievement>[];
    var totalBadges = 0;
    DateTime? first;
    for (final k in history.keys) {
      final d = Metrics.tryParseKey(k);
      if (d != null && (first == null || d.isBefore(first))) first = d;
    }
    final firstDay = first;
    if (firstDay != null) {
      Map<String, int> upTo(DateTime end) => {
            for (final e in history.entries)
              if ((Metrics.tryParseKey(e.key)?.isAfter(end) ?? true) == false) e.key: e.value,
          };
      AchievementStats stats(DateTime end) {
        final h = upTo(end);
        final all = end.isBefore(firstDay) ? null : step.breakdownBetween(firstDay, end);
        return AchievementStats.from(
          history: h,
          goal: goal,
          heightCm: heightCm,
          totalKcal: all?.kcal ?? 0,
          totalKm: all?.km ?? 0,
        );
      }

      final after = Achievements.evaluate(stats(last)).where((p) => p.unlocked).toList();
      final before = Achievements.evaluate(stats(Metrics.addDays(r.start, -1)))
          .where((p) => p.unlocked)
          .map((p) => Achievements.idOf(p.item))
          .toSet();
      totalBadges = after.length;
      for (final p in after) {
        if (!before.contains(Achievements.idOf(p.item))) newBadges.add(p.item);
      }
    }

    return PeriodSummary(
      range: r,
      steps: steps,
      km: bd.km,
      kcal: bd.kcal,
      minutes: bd.minutes,
      activeDays: active,
      goalDays: goalDays,
      elapsedDays: elapsed,
      bestDaySteps: best,
      bestDay: bestDay,
      changePct: change,
      days: days,
      newBadges: newBadges,
      totalBadges: totalBadges,
    );
  }
}

/// Paylasilan kartin kendisi.
class SummaryShareCard extends StatelessWidget {
  final String title;
  final PeriodSummary data;
  final bool weekly;

  const SummaryShareCard({
    super.key,
    required this.title,
    required this.data,
    required this.weekly,
  });

  static const _green = Color(0xFF4ADE80);
  static const _yellow = Color(0xFFFACC15);

  @override
  Widget build(BuildContext context) {
    final colors = weekly
        ? const [Color(0xFF0F766E), Color(0xFF0B3B5C), Color(0xFF1E1B4B)]
        : const [Color(0xFF7C2D12), Color(0xFF581C87), Color(0xFF1E1B4B)];
    final change = data.changePct;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baslik
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  weekly ? Icons.view_week_rounded : Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${Metrics.numericDate(data.range.start)} – ${Metrics.numericDate(data.range.end)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.auto_awesome_rounded, color: _yellow, size: 26),
            ],
          ),
          const SizedBox(height: 18),
          // Ana rakam
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Metrics.thousands(data.steps),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 5),
                child: Text(
                  'adım',
                  style: TextStyle(color: _green, fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              if (change != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: (change >= 0 ? _green : const Color(0xFFF87171)).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        change >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        size: 16,
                        color: change >= 0 ? _green : const Color(0xFFF87171),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${change >= 0 ? '+' : ''}%$change',
                        style: TextStyle(
                          color: change >= 0 ? _green : const Color(0xFFF87171),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _MiniBars(days: data.days, weekly: weekly),
          const SizedBox(height: 14),
          // Olcu izgarasi (2 sutun)
          Row(
            children: [
              Expanded(child: _Tile(Icons.route_rounded, const Color(0xFF38BDF8), '${data.km.toStringAsFixed(1).replaceAll('.', ',')} km', 'mesafe')),
              const SizedBox(width: 8),
              Expanded(child: _Tile(Icons.local_fire_department_rounded, const Color(0xFFFF7043), '${data.kcal.round()} kcal', 'kalori')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Tile(Icons.timer_rounded, const Color(0xFFA78BFA), Metrics.duration(data.minutes), 'aktif süre')),
              const SizedBox(width: 8),
              Expanded(child: _Tile(Icons.flag_rounded, _green, '${data.goalDays}/${data.elapsedDays} gün', 'hedef tuttu')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Tile(Icons.show_chart_rounded, const Color(0xFF2DD4BF), Metrics.thousands(data.avgSteps), 'günlük ort.')),
              const SizedBox(width: 8),
              Expanded(
                child: _Tile(
                  Icons.star_rounded,
                  _yellow,
                  Metrics.thousands(data.bestDaySteps),
                  data.bestDay == null ? 'en iyi gün' : 'en iyi · ${Metrics.shortLabel(data.bestDay!)} ${data.bestDay!.day}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Rozetler
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded, color: _yellow, size: 20),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        data.newBadges.isEmpty
                            ? 'Kazanılan rozetler'
                            : 'Kazanılan rozetler (${data.newBadges.length})',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                    ),
                    Text(
                      'toplam ${data.totalBadges}',
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (data.newBadges.isEmpty)
                  Text(
                    weekly ? 'Bu hafta yeni rozet yok — sıradaki yakında!' : 'Bu ay yeni rozet yok — sıradaki yakında!',
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final b in data.newBadges.take(8))
                        Container(
                          padding: const EdgeInsets.fromLTRB(6, 5, 10, 5),
                          decoration: BoxDecoration(
                            color: _yellow.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _yellow.withValues(alpha: 0.45)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(b.icon, size: 16, color: _yellow),
                              const SizedBox(width: 5),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(
                                  b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (data.newBadges.length > 8)
                        Text('+${data.newBadges.length - 8}',
                            style: const TextStyle(color: _yellow, fontWeight: FontWeight.w800)),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.directions_walk_rounded, color: _green, size: 18),
              const SizedBox(width: 6),
              const Text(
                'YÜRÜYÜŞ DEFTERİ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                '${data.activeDays} aktif gün',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Tile(this.icon, this.color, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Donemin gunluk adim cubuklari.
class _MiniBars extends StatelessWidget {
  final List<MapEntry<DateTime, int>> days;
  final bool weekly;
  const _MiniBars({required this.days, required this.weekly});

  @override
  Widget build(BuildContext context) {
    final max = days.fold<int>(0, (a, e) => e.value > a ? e.value : a);
    return SizedBox(
      height: weekly ? 70 : 54,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final e in days)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: weekly ? 4 : 1.2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: FractionallySizedBox(
                        heightFactor: max == 0 ? 0.04 : (e.value / max).clamp(0.04, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xFF4ADE80), Color(0xFFFACC15)],
                            ),
                            borderRadius: BorderRadius.circular(weekly ? 6 : 2),
                          ),
                        ),
                      ),
                    ),
                    if (weekly) ...[
                      const SizedBox(height: 4),
                      Text(
                        Metrics.shortLabel(e.key),
                        style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
