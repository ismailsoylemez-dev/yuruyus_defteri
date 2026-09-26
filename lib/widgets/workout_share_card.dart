import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../utils/metrics.dart';

/// Tek antrenmanin paylasim karti (1080x1350, Instagram 4:5).
/// Harita karosu gerektirmez: rota, noktalarin kendisinden cizilir.
class WorkoutShareCard extends StatelessWidget {
  final List<LatLng> points;
  final String title;
  final DateTime date;
  final double km;
  final int durationSec;
  final String pace;
  final int steps;
  final int kcal;

  /// Kartin ustundeki vurgular (or. "Hedef tamam", "En uzun yürüyüş").
  final List<String> highlights;

  const WorkoutShareCard({
    super.key,
    required this.points,
    required this.title,
    required this.date,
    required this.km,
    required this.durationSec,
    required this.pace,
    required this.steps,
    required this.kcal,
    this.highlights = const [],
  });

  static const _green = Color(0xFF4ADE80);
  static const _yellow = Color(0xFFFACC15);

  String _clock(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 1350,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1F17), Color(0xFF0D0F14), Color(0xFF1A1433)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(80, 72, 80, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(Icons.directions_walk_rounded, color: _green, size: 48),
              ),
              const SizedBox(width: 24),
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
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${Metrics.numericDate(date)} ${Metrics.longLabel(date)} · '
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (highlights.isNotEmpty) ...[
            const SizedBox(height: 28),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                for (final h in highlights)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                    decoration: BoxDecoration(
                      color: _yellow.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: _yellow.withValues(alpha: 0.5), width: 2),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: _yellow, size: 30),
                        const SizedBox(width: 10),
                        Text(
                          h,
                          style: const TextStyle(
                            color: _yellow,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 2),
              ),
              padding: const EdgeInsets.all(48),
              child: points.length >= 2
                  ? CustomPaint(painter: _RoutePainter(points))
                  : Center(
                      child: Icon(
                        Icons.route_rounded,
                        size: 180,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 36),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                km.toStringAsFixed(2).replaceAll('.', ','),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 150,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -6,
                ),
              ),
              const SizedBox(width: 18),
              const Padding(
                padding: EdgeInsets.only(bottom: 18),
                child: Text(
                  'KM',
                  style: TextStyle(
                    color: _green,
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _Stat(icon: Icons.timer_outlined, color: const Color(0xFFA78BFA), value: _clock(durationSec), label: 'SÜRE'),
              _Stat(icon: Icons.speed_rounded, color: const Color(0xFFFF7043), value: pace, label: 'TEMPO /KM'),
              _Stat(icon: Icons.directions_walk_rounded, color: _green, value: Metrics.thousands(steps), label: 'ADIM'),
              _Stat(icon: Icons.local_fire_department_rounded, color: const Color(0xFFFFA726), value: '$kcal', label: 'KCAL'),
            ],
          ),
          const SizedBox(height: 40),
          Row(
            children: [
              Text(
                'YÜRÜYÜŞ DEFTERİ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                ),
              ),
              const Spacer(),
              Text(
                '#YürüyüşDefteri',
                style: TextStyle(
                  color: _green.withValues(alpha: 0.8),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  const _Stat({required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 44),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rota: enlem/boylam esit-aci izdusumuyle alana sigdirilir, parlak cizgi.
class _RoutePainter extends CustomPainter {
  final List<LatLng> points;
  _RoutePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    final lat0 = points.first.latitude * math.pi / 180;
    final k = math.cos(lat0);
    final xy = <Offset>[];
    for (final p in points) {
      final x = p.longitude * k;
      final y = -p.latitude;
      xy.add(Offset(x, y));
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final w = math.max(maxX - minX, 1e-6);
    final h = math.max(maxY - minY, 1e-6);
    final scale = math.min(size.width / w, size.height / h);
    final dx = (size.width - w * scale) / 2;
    final dy = (size.height - h * scale) / 2;
    final pts = [
      for (final o in xy) Offset(dx + (o.dx - minX) * scale, dy + (o.dy - minY) * scale),
    ];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final o in pts.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF4ADE80).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF4ADE80), Color(0xFF38BDF8), Color(0xFFFACC15)],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(pts.first, 18, Paint()..color = const Color(0xFF4ADE80));
    canvas.drawCircle(pts.first, 8, Paint()..color = Colors.white);
    canvas.drawCircle(pts.last, 18, Paint()..color = const Color(0xFFEF4444));
    canvas.drawCircle(pts.last, 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) => old.points != points;
}
