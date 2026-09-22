import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/metrics.dart';

/// Ana ekran widget'ina goruntu olarak basilan gorunum.
/// Flutter agaci disinda render edildigi icin kendi Directionality/MediaQuery
/// sarmalayicilarini tasir.
class HomeWidgetView extends StatelessWidget {
  final int steps;
  final int goal;
  final double km;
  final double kcal;
  final int minutes;
  final List<int> week;
  final int todayIndex;

  /// null: su takibi kapali, su hucresi cizilmez (3 hucre esit yayilir).
  final int? waterMl;

  const HomeWidgetView({
    super.key,
    required this.steps,
    required this.goal,
    required this.km,
    required this.kcal,
    required this.minutes,
    required this.week,
    required this.todayIndex,
    this.waterMl,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal <= 0 ? 0.0 : (steps / goal).clamp(0.0, 1.0);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: 360,
        height: 168,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: DarkColors.bg,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: DarkColors.divider, width: 1.2),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size.square(104),
                    painter: _WidgetRing(progress),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_walk,
                          color: DarkColors.accent, size: 17),
                      const SizedBox(height: 2),
                      Text(
                        Metrics.thousands(steps),
                        style: const TextStyle(
                          color: DarkColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '/ ${Metrics.compact(goal)}',
                        style: const TextStyle(
                          color: DarkColors.textDim,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 58,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(week.length, (i) {
                        final maxVal = week.fold<int>(
                            goal, (m, v) => v > m ? v : m);
                        final ratio = maxVal == 0 ? 0.0 : week[i] / maxVal;
                        final isToday = i == todayIndex;
                        final reached = goal > 0 && week[i] >= goal;

                        return Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 3.5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  height:
                                      (40 * ratio).clamp(3.0, 40.0).toDouble(),
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? DarkColors.accent
                                        : reached
                                            ? DarkColors.accent
                                                .withValues(alpha: 0.75)
                                            : week[i] > 0
                                                ? DarkColors.accent
                                                    .withValues(alpha: 0.32)
                                                : DarkColors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  Metrics.weekdayShort[i],
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    height: 1,
                                    color: isToday
                                        ? DarkColors.accent
                                        : DarkColors.textDim,
                                    fontWeight: isToday
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _Cell(
                        icon: Icons.straighten,
                        color: DarkColors.km,
                        value: km.toStringAsFixed(2),
                        label: 'Km',
                      ),
                      _Cell(
                        icon: Icons.local_fire_department,
                        color: DarkColors.kcal,
                        value: kcal.toStringAsFixed(0),
                        label: 'Kcal',
                      ),
                      if (waterMl != null)
                        _Cell(
                          icon: Icons.water_drop,
                          color: DarkColors.water,
                          value: waterMl! >= 1000
                              ? '${(waterMl! / 1000).toStringAsFixed(1)}L'
                              : '${waterMl}ml',
                          label: 'Su',
                        ),
                      _Cell(
                        icon: Icons.schedule,
                        color: DarkColors.time,
                        value: Metrics.duration(minutes),
                        label: 'Süre',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _Cell({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: DarkColors.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: DarkColors.textDim, fontSize: 9),
        ),
      ],
    );
  }
}

class _WidgetRing extends CustomPainter {
  final double progress;
  _WidgetRing(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = DarkColors.surfaceAlt
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = DarkColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_WidgetRing old) => old.progress != progress;
}
