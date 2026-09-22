import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

class StepRing extends StatelessWidget {
  final int steps;
  final int goal;
  final double size;

  const StepRing({
    super.key,
    required this.steps,
    required this.goal,
    this.size = 250,
  });

  @override
  Widget build(BuildContext context) {
    final progress = goal <= 0 ? 0.0 : (steps / goal).clamp(0.0, 1.0);
    final percent = (progress * 100).round();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, value, __) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(value),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_walk, color: AppColors.accent, size: 26),
              const SizedBox(height: 6),
              Text(
                Metrics.thousands(steps),
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                  height: 1.05,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'hedef ${Metrics.thousands(goal)}',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '%$percent',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  _RingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;

    final track = Paint()
      ..color = AppColors.surfaceAlt
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final arc = Paint()
      ..shader = SweepGradient(
        colors: [
          AppColors.pick(const Color(0xFF22C55E), const Color(0xFF15803D)),
          AppColors.accent,
          AppColors.pick(const Color(0xFFA3E635), const Color(0xFF65A30D)),
        ],
        startAngle: 0,
        endAngle: math.pi * 2,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    // Hedef tamamlaninca halkanin cevresinde hafif parlama (surekli degil).
    if (progress >= 0.999) {
      final glow = Paint()
        ..color = AppColors.accent
            .withValues(alpha: AppColors.isLight ? 0.28 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
      canvas.drawCircle(center, radius, glow);
    }
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}
