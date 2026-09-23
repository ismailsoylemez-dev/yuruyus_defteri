import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

class FitnessRings extends StatelessWidget {
  final int steps;
  final int goal;
  final int kcal;
  final int minutes;
  final double km;
  final double size;

  const FitnessRings({
    super.key,
    required this.steps,
    required this.goal,
    required this.kcal,
    required this.minutes,
    required this.km,
    this.size = 290,
  });

  @override
  Widget build(BuildContext context) {
    final stepProgress = goal <= 0 ? 0.0 : (steps / goal).clamp(0.0, 1.0);
    // Hardcoded goals for calories and minutes for visual representation
    // Or we could calculate them based on step goal if we want (e.g. goal * 0.04 for kcal, goal * 0.01 for minutes)
    final kcalGoal = goal <= 0 ? 500 : (goal * 0.04).round(); 
    final minGoal = goal <= 0 ? 30 : (goal * 0.01).round();
    
    final kcalProgress = (kcal / (kcalGoal > 0 ? kcalGoal : 1)).clamp(0.0, 1.0);
    final minProgress = (minutes / (minGoal > 0 ? minGoal : 1)).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (_, anim, __) => CustomPaint(
              size: Size.square(size),
              painter: _FitnessRingsPainter(
                stepProgress: stepProgress * anim,
                kcalProgress: kcalProgress * anim,
                minProgress: minProgress * anim,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.directions_walk, color: AppColors.accent, size: 28),
              const SizedBox(height: 6),
              Text(
                Metrics.thousands(steps),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: AppColors.text,
                  height: 1.05,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'hedef ${Metrics.thousands(goal)}',
                style: TextStyle(
                  color: AppColors.textDim, 
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LegendItem(color: Color(0xFF22C55E), icon: Icons.directions_walk, label: 'Adım'),
                  const SizedBox(width: 12),
                  _LegendItem(color: MetricColors.kcal, icon: Icons.local_fire_department, label: 'Kalori'),
                  const SizedBox(width: 12),
                  _LegendItem(color: MetricColors.time, icon: Icons.timer, label: 'Süre'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${km.toStringAsFixed(2).replaceAll('.', ',')} km • $kcal kcal • $minutes dk',
                style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _LegendItem({required this.color, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _FitnessRingsPainter extends CustomPainter {
  final double stepProgress;
  final double kcalProgress;
  final double minProgress;
  
  _FitnessRingsPainter({
    required this.stepProgress,
    required this.kcalProgress,
    required this.minProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Ring configs
    const stroke = 12.0;
    const spacing = 4.0;
    
    final stepRadius = (size.width - stroke) / 2;
    final kcalRadius = stepRadius - stroke - spacing;
    final minRadius = kcalRadius - stroke - spacing;

    // Draw Tracks
    _drawRing(canvas, center, stepRadius, stroke, AppColors.surfaceAlt, 1.0);
    _drawRing(canvas, center, kcalRadius, stroke, AppColors.surfaceAlt, 1.0);
    _drawRing(canvas, center, minRadius, stroke, AppColors.surfaceAlt, 1.0);

    // Draw Progress
    final stepGradient = SweepGradient(
      colors: [
        const Color(0xFF22C55E).withValues(alpha: 0.6), 
        const Color(0xFF22C55E), 
        const Color(0xFF22C55E).withValues(alpha: 0.8),
      ],
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
    );
    
    final kcalGradient = SweepGradient(
      colors: [MetricColors.kcal.withValues(alpha: 0.6), MetricColors.kcal, MetricColors.kcal.withValues(alpha: 0.8)],
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
    );

    final minGradient = SweepGradient(
      colors: [MetricColors.time.withValues(alpha: 0.6), MetricColors.time, MetricColors.time.withValues(alpha: 0.8)],
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
    );

    if (stepProgress > 0) _drawRing(canvas, center, stepRadius, stroke, null, stepProgress, shader: stepGradient);
    if (kcalProgress > 0) _drawRing(canvas, center, kcalRadius, stroke, null, kcalProgress, shader: kcalGradient);
    if (minProgress > 0) _drawRing(canvas, center, minRadius, stroke, null, minProgress, shader: minGradient);
    
    // Add glowing effect to finished rings
    if (stepProgress >= 0.999) _drawGlow(canvas, center, stepRadius, stroke, AppColors.accent);
    if (kcalProgress >= 0.999) _drawGlow(canvas, center, kcalRadius, stroke, MetricColors.kcal);
    if (minProgress >= 0.999) _drawGlow(canvas, center, minRadius, stroke, MetricColors.time);
  }

  void _drawRing(Canvas canvas, Offset center, double radius, double stroke, Color? color, double progress, {Gradient? shader}) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
      
    if (color != null) paint.color = color;
    if (shader != null) {
      paint.shader = shader.createShader(Rect.fromCircle(center: center, radius: radius));
    }
    
    if (progress >= 1.0) {
      canvas.drawCircle(center, radius, paint);
    } else {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint,
      );
    }
  }

  void _drawGlow(Canvas canvas, Offset center, double radius, double stroke, Color color) {
    final glow = Paint()
      ..color = color.withValues(alpha: AppColors.isLight ? 0.28 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11);
    canvas.drawCircle(center, radius, glow);
  }

  @override
  bool shouldRepaint(_FitnessRingsPainter old) => 
    old.stepProgress != stepProgress || old.kcalProgress != kcalProgress || old.minProgress != minProgress;
}
