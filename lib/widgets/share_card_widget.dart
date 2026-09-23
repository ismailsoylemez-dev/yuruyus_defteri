import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

class ShareCardWidget extends StatelessWidget {
  final Uint8List mapImage;
  final double distance;
  final int minutes;
  final int kcal;
  final DateTime date;
  
  const ShareCardWidget({
    super.key,
    required this.mapImage,
    required this.distance,
    required this.minutes,
    required this.kcal,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 1920,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Arka plan harita goruntusu (Bulanik veya koyulastirilmis olabilir)
          Image.memory(
            mapImage,
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.4),
            colorBlendMode: BlendMode.darken,
          ),
          
          // Uste binen gradyan (Metinlerin okunabilirligi icin)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.8),
                ],
                stops: const [0.4, 0.7, 1.0],
              ),
            ),
          ),
          
          // Icerik Paneli (Glassmorphism)
          Positioned(
            left: 60,
            right: 60,
            bottom: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(48),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.all(60.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(48),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tarih

                      Text(
                        '${Metrics.numericDate(date)} ${Metrics.longLabel(date)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 42,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: const Offset(0, 4),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // Mesafe
                      Text(
                        distance.toStringAsFixed(2),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 260,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          letterSpacing: -12,
                          shadows: [
                            Shadow(
                              color: AppColors.best.withValues(alpha: 0.5),
                              blurRadius: 40,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'KİLOMETRE',
                        style: TextStyle(
                          color: AppColors.best,
                          fontSize: 48,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 12,
                          shadows: [
                            Shadow(
                              color: AppColors.best.withValues(alpha: 0.8),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 80),
                      
                      // Alt istatistikler
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _StatColumn(label: 'SÜRE', value: Metrics.duration(minutes)),
                          _StatColumn(label: 'KALORİ', value: '$kcal kcal'),
                          _StatColumn(label: 'TEMPO', value: '${(minutes / (distance > 0 ? distance : 1)).toStringAsFixed(2)} /km'),
                        ],
                      ),
                      
                      const SizedBox(height: 80),
                      
                      // Logo veya Uygulama ismi
                      Row(
                        children: [
                          Icon(Icons.directions_walk, color: AppColors.best, size: 56),
                          const SizedBox(width: 24),
                          const Text(
                            'YÜRÜYÜŞ DEFTERİ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 6,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}
