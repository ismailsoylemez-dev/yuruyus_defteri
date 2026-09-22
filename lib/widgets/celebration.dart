import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../utils/metrics.dart';

/// Gunluk hedefe ulasilinca: titresim + kisa konfeti + ortada kutlama.
/// Ekrani kapatmaz; 2,8 sn sonra kendiliginden kaybolur, dokunmalar
/// alttaki sayfaya gecer.
void showCelebration(BuildContext context, {required int steps}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  HapticFeedback.heavyImpact();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _Celebration(
        steps: steps,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    ),
  );
  overlay.insert(entry);
}

class _Celebration extends StatefulWidget {
  final int steps;
  final VoidCallback onDone;
  const _Celebration({required this.steps, required this.onDone});

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward().whenComplete(widget.onDone);

  // Sabit tohum: parcaciklar her seferinde ayni dagilir (titremez).
  final _parts = List.generate(70, (i) {
    final r = math.Random(i * 7919);
    return _Part(
      x: r.nextDouble(),
      delay: r.nextDouble() * 0.35,
      speed: 0.6 + r.nextDouble() * 0.6,
      drift: (r.nextDouble() - 0.5) * 0.25,
      size: 5 + r.nextDouble() * 6,
      spin: r.nextDouble() * math.pi,
      color: [
        AppColors.accent,
        AppColors.best,
        MetricColors.kcal,
        MetricColors.km,
        MetricColors.time,
      ][i % 5],
    );
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        // Kutlama karti: ilk %15'te buyur, son %20'de solar.
        final cardOpacity = t < 0.15
            ? t / 0.15
            : t > 0.8
                ? (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0)
                : 1.0;
        final scale = 0.8 + 0.2 * Curves.easeOutBack.transform((t / 0.15).clamp(0.0, 1.0));
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _ConfettiPainter(_parts, t)),
            ),
            Center(
              child: Opacity(
                opacity: cardOpacity,
                child: Transform.scale(
                  scale: scale,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 18),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accent, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.35),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🎉', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 6),
                          Text(
                            'Günlük hedef tamam!',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${Metrics.thousands(widget.steps)} adım',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Part {
  final double x, delay, speed, drift, size, spin;
  final Color color;
  const _Part({
    required this.x,
    required this.delay,
    required this.speed,
    required this.drift,
    required this.size,
    required this.spin,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Part> parts;
  final double t;
  _ConfettiPainter(this.parts, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in parts) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + local * p.speed * (size.height + 40);
      final x = (p.x + p.drift * local) * size.width;
      paint.color = p.color.withValues(alpha: (1 - local * 0.7).clamp(0.0, 1.0));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin + local * 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
