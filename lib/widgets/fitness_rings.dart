import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

class FitnessRings extends StatefulWidget {
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
  State<FitnessRings> createState() => _FitnessRingsState();
}

class _FitnessRingsState extends State<FitnessRings> {
  int _activeRing = 0; // 0: None, 1: Step, 2: Kcal, 3: Min

  void _handleTap(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final distance = (localPosition - center).distance;
    
    const stroke = 12.0;
    const spacing = 4.0;
    
    final stepRadius = (widget.size - stroke) / 2;
    final kcalRadius = stepRadius - stroke - spacing;
    final minRadius = kcalRadius - stroke - spacing;

    // Tolerance
    const t = stroke / 2 + 6;

    if ((distance - stepRadius).abs() < t) {
      setState(() => _activeRing = 1);
    } else if ((distance - kcalRadius).abs() < t) {
      setState(() => _activeRing = 2);
    } else if ((distance - minRadius).abs() < t) {
      setState(() => _activeRing = 3);
    }
  }

  void _handleTapUp() {
    if (_activeRing != 0) {
      setState(() => _activeRing = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stepProgress = widget.goal <= 0 ? 0.0 : (widget.steps / widget.goal).clamp(0.0, 1.0);
    
    // Adjusted goals so they don't fill up too fast compared to steps
    final kcalGoal = widget.goal <= 0 ? 500 : (widget.goal * 0.06).round(); 
    final minGoal = widget.goal <= 0 ? 45 : (widget.goal * 0.02).round();
    
    final kcalProgress = (widget.kcal / (kcalGoal > 0 ? kcalGoal : 1)).clamp(0.0, 1.0);
    final minProgress = (widget.minutes / (minGoal > 0 ? minGoal : 1)).clamp(0.0, 1.0);

    Widget centerContent;
    if (_activeRing == 1) {
      centerContent = _buildCenterInfo(Icons.directions_walk, const Color(0xFF22C55E), '${widget.km.toStringAsFixed(2).replaceAll('.', ',')} km', 'Adım Mesafesi');
    } else if (_activeRing == 2) {
      centerContent = _buildCenterInfo(Icons.local_fire_department, MetricColors.kcal, '${widget.kcal}', 'Yakılan Kalori');
    } else if (_activeRing == 3) {
      centerContent = _buildCenterInfo(Icons.timer, MetricColors.time, '${widget.minutes}', 'Aktif Süre (dk)');
    } else {
      centerContent = Column(
        key: const ValueKey('default'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_walk, color: AppColors.accent, size: 28),
          const SizedBox(height: 6),
          Text(
            Metrics.thousands(widget.steps),
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
            'hedef ${Metrics.thousands(widget.goal)}',
            style: TextStyle(
              color: AppColors.textDim, 
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              const _LegendItem(color: Color(0xFF22C55E), icon: Icons.directions_walk, label: 'Adım'),
              _LegendItem(color: MetricColors.kcal, icon: Icons.local_fire_department, label: 'Kalori'),
              _LegendItem(color: MetricColors.time, icon: Icons.timer, label: 'Süre'),
            ],
          ),
        ],
      );
    }

    return GestureDetector(
      onPanDown: (details) => _handleTap(details.localPosition),
      onPanEnd: (_) => _handleTapUp(),
      onPanCancel: () => _handleTapUp(),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1.0),
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              builder: (_, anim, __) => CustomPaint(
                size: Size.square(widget.size),
                painter: _FitnessRingsPainter(
                  stepProgress: stepProgress * anim,
                  kcalProgress: kcalProgress * anim,
                  minProgress: minProgress * anim,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: centerContent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterInfo(IconData icon, Color color, String val, String label) {
    return Column(
      key: ValueKey(label),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 36),
        const SizedBox(height: 8),
        Text(
          val,
          style: TextStyle(
            fontSize: 42,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.05,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textDim, 
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
