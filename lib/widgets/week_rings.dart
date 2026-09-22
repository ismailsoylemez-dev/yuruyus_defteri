import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';
import '../utils/intensity.dart';

/// Haftalik rapordaki bir gunun ozeti (dokunmadan gorunen satirlar).
class WeekDayDetail {
  final int steps;
  final double km;
  final double kcal;
  final int minutes;

  /// null: su takibi kapali, su satiri cikmaz.
  final int? waterMl;

  const WeekDayDetail({
    required this.steps,
    required this.km,
    required this.kcal,
    required this.minutes,
    this.waterMl,
  });

  factory WeekDayDetail.from({
    required int steps,
    required ActivityBreakdown breakdown,
    int? waterMl,
  }) =>
      WeekDayDetail(
        steps: steps,
        km: breakdown.km,
        kcal: breakdown.kcal,
        minutes: steps <= 0 ? 0 : breakdown.minutes,
        waterMl: waterMl,
      );
}

/// Haftanin gunleri icin mini ilerleme halkalari.
/// Hedefi tutan gun dolu + yildiz, 2 katini gecen gun "x2" rozeti alir.
/// [details] verilirse her gunun altinda ikonlu adim / km / kcal / sure / su
/// satirlari gorunur (dokunmadan).
class WeekRings extends StatelessWidget {
  final List<MapEntry<DateTime, int>> week;
  final int goal;
  final void Function(DateTime)? onDayTap;
  final List<WeekDayDetail>? details;

  const WeekRings({
    super.key,
    required this.week,
    required this.goal,
    this.onDayTap,
    this.details,
  });

  @override
  Widget build(BuildContext context) {
    final todayKey = Metrics.dayKey(DateTime.now());
    final d = details;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(week.length, (i) {
        final e = week[i];
        final ratio = goal <= 0 ? 0.0 : (e.value / goal).clamp(0.0, 1.0);
        final reached = goal > 0 && e.value >= goal;
        final doubled = goal > 0 && e.value >= goal * 2;
        final isToday = Metrics.dayKey(e.key) == todayKey;
        final detail = d != null && i < d.length ? d[i] : null;
        final future = e.key.isAfter(DateTime.now());

        return Expanded(
          child: GestureDetector(
            onTap: () => onDayTap?.call(e.key),
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: doubled
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppColors.best,
                            borderRadius: BorderRadius.circular(17),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'x2',
                            style: TextStyle(
                              color: Color(0xFF1A1206),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size.square(34),
                              painter: _MiniRing(ratio, reached),
                            ),
                            if (reached)
                              const Icon(Icons.star,
                                  size: 15, color: Color(0xFF07160E)),
                          ],
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  Metrics.shortLabel(e.key),
                  style: TextStyle(
                    fontSize: 11,
                    color: isToday ? AppColors.accent : AppColors.textDim,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                // Hedefin yuzde kaci tutuldu (detay acmadan gorunur).
                if (goal > 0) ...[
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 14,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        future ? '' : '%${(e.value / goal * 100).round()}',
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.2,
                          color: reached ? AppColors.accent : AppColors.textDim,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    padding: const EdgeInsets.fromLTRB(3, 5, 3, 5),
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppColors.accentSoft.withValues(alpha: 0.45)
                          : AppColors.surfaceAlt.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Opacity(
                      opacity: future || detail.steps <= 0 ? 0.35 : 1,
                      // Tek olcek + sola hizali: ikonlar deger uzunlugundan
                      // bagimsiz alt alta ayni hizada kalir.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Line(Icons.directions_walk, MetricColors.steps,
                              detail.steps <= 0 ? '–' : Metrics.compact(detail.steps)),
                          _Line(Icons.straighten, MetricColors.km,
                              detail.steps <= 0 ? '–' : detail.km.toStringAsFixed(1).replaceAll('.', ',')),
                          _Line(Icons.local_fire_department_outlined,
                              MetricColors.kcal,
                              detail.steps <= 0 ? '–' : detail.kcal.round().toString()),
                          _Line(Icons.timer_outlined, MetricColors.time,
                              detail.minutes <= 0 ? '–' : '${detail.minutes}dk'),
                          if (detail.waterMl != null)
                            _Line(Icons.water_drop_outlined, MetricColors.water,
                                detail.waterMl! <= 0
                                    ? '–'
                                    : (detail.waterMl! / 1000).toStringAsFixed(1).replaceAll('.', ',')),
                        ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Gun sutunundaki tek satir: kucuk ikon + deger (dar sutuna sigar).
class _Line extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _Line(this.icon, this.color, this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 17,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRing extends CustomPainter {
  final double ratio;
  final bool filled;
  _MiniRing(this.ratio, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2.5;

    if (filled) {
      canvas.drawCircle(center, radius + 2, Paint()..color = AppColors.accent);
      return;
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppColors.surfaceAlt
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * ratio,
        false,
        Paint()
          ..color = AppColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniRing old) =>
      old.ratio != ratio || old.filled != filled;
}
