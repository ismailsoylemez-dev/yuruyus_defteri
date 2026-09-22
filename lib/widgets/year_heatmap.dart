import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

/// Yilin tamami: her sutun bir hafta, her kare bir gun. Acilista icinde
/// bulunulan ay ortada gelir (Ocak'tan baslamaz).
class YearHeatmap extends StatefulWidget {
  final int year;
  final Map<String, int> history;
  final int goal;

  const YearHeatmap({
    super.key,
    required this.year,
    required this.history,
    required this.goal,
  });

  @override
  State<YearHeatmap> createState() => _YearHeatmapState();
}

class _YearHeatmapState extends State<YearHeatmap> {
  static const _col = 13.0; // 10 kare + 3 bosluk
  static const _labelW = 26.0; // gun adlari sutunu + bosluk
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _center();
  }

  @override
  void didUpdateWidget(covariant YearHeatmap old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) _center();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bu yil: bugunun haftasi ortada. Gecmis yil: Aralik gorunur.
  void _center() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent <= 0) return;
      final now = DateTime.now();
      final start = Metrics.weekStart(DateTime(widget.year, 1, 1));
      final target = widget.year == now.year
          ? now
          : widget.year < now.year
              ? DateTime(widget.year, 12, 31)
              : DateTime(widget.year, 1, 1);
      final week = Metrics.daysBetween(start, target) ~/ 7;
      final x = _labelW + week * _col + _col / 2 - pos.viewportDimension / 2;
      _scroll.jumpTo(x.clamp(0.0, pos.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final year = widget.year;
    final history = widget.history;
    final goal = widget.goal;
    final start = Metrics.weekStart(DateTime(year, 1, 1));
    final end = DateTime(year, 12, 31);
    final weeks = (end.difference(start).inDays / 7).ceil() + 1;

    var maxVal = goal > 0 ? goal : 1;
    history.forEach((k, v) {
      if (Metrics.tryParseKey(k)?.year == year && v > maxVal) maxVal = v;
    });

    final today = DateTime.now();
    final activeDays = history.entries
        .where((e) => Metrics.tryParseKey(e.key)?.year == year && e.value > 0)
        .length;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$year takvimi',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '$activeDays aktif gün',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _labelW - 6,
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(height: 14),
                    ...List.generate(7, (i) {
                    return SizedBox(
                      height: 13,
                      child: i % 2 == 1
                          ? Text(
                              Metrics.weekdayShort[i],
                              style: TextStyle(
                                color: AppColors.textDim,
                                fontSize: 9.5,
                                height: 1.4,
                              ),
                            )
                          : null,
                    );
                  }),
                  ],
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  children: List.generate(weeks, (w) {
                    // Ayin ilk gunu bu haftadaysa ustte ay adi.
                    final weekStartDay = start.add(Duration(days: w * 7));
                    String? month;
                    for (var k = 0; k < 7; k++) {
                      final dd = weekStartDay.add(Duration(days: k));
                      if (dd.year == year && dd.day == 1) {
                        month = Metrics.monthName(dd.month).substring(0, 3);
                      }
                    }
                    final isNowWeek = today.year == year &&
                        !today.isBefore(weekStartDay) &&
                        today.isBefore(weekStartDay.add(const Duration(days: 7)));
                    return Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 14,
                            child: OverflowBox(
                              maxWidth: 30,
                              alignment: Alignment.topLeft,
                              child: Text(
                                month ?? '',
                                style: TextStyle(
                                  color: isNowWeek
                                      ? AppColors.accent
                                      : AppColors.textDim,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ),
                          ...List.generate(7, (d) {
                          final day = start.add(Duration(days: w * 7 + d));
                          if (day.year != year) {
                            return const SizedBox(width: 10, height: 13);
                          }

                          final value = history[Metrics.dayKey(day)] ?? 0;
                          final future = day.isAfter(today);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: future
                                    ? Colors.transparent
                                    : _shade(value, maxVal),
                                borderRadius: BorderRadius.circular(2.5),
                                border: future
                                    ? Border.all(
                                        color: AppColors.divider, width: 0.6)
                                    : null,
                              ),
                            ),
                          );
                        }),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'az',
                style: TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
              const SizedBox(width: 6),
              ...List.generate(5, (i) {
                return Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: _level(i),
                    borderRadius: BorderRadius.circular(2.5),
                  ),
                );
              }),
              const SizedBox(width: 3),
              Text(
                'çok',
                style: TextStyle(color: AppColors.textDim, fontSize: 11),
              ),
              const Spacer(),
              if (goal > 0)
                Text(
                  'hedef ${Metrics.compact(goal)}',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _shade(int value, int maxVal) {
    if (value <= 0) return AppColors.surfaceAlt;
    final ratio = (value / maxVal).clamp(0.0, 1.0);
    if (ratio < 0.25) return _level(1);
    if (ratio < 0.5) return _level(2);
    if (ratio < 0.8) return _level(3);
    return _level(4);
  }

  static Color _level(int i) => switch (i) {
        0 => AppColors.surfaceAlt,
        1 => AppColors.pick(const Color(0xFF1E4430), const Color(0xFFBBF7D0)),
        2 => AppColors.pick(const Color(0xFF2E7D4F), const Color(0xFF4ADE80)),
        3 => AppColors.pick(const Color(0xFF3FAF6B), const Color(0xFF22C55E)),
        _ => AppColors.accent,
      };
}
