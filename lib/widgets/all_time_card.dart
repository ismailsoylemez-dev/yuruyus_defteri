import 'package:flutter/material.dart';

import '../providers/step_provider.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';

/// "Tum zamanlar" vitrin karti (Basarilar sayfasinin en ustu).
class AllTimeCard extends StatelessWidget {
  final StepProvider step;
  final int heightCm;
  final double weightKg;

  const AllTimeCard({
    super.key,
    required this.step,
    required this.heightCm,
    required this.weightKg,
  });

  @override
  Widget build(BuildContext context) {
    final total = step.totalSteps;
    // Normal + tempolu + kosu toplami (tempo kaydi yoksa eski hesap).
    final bd = step.breakdownAllTime;
    final km = bd.km;
    final kcal = bd.kcal;
    final minutes = bd.minutes;

    // Diger kartlardan ayrisan "vitrin" karti: koyu lacivert-turkuaz zemin,
    // arka planda soluk kupa, ust etikette rozet, 2x2 bilgi karolari.
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.isLight
                ? const [Color(0xFFD5F5EE), Color(0xFFE3EEFC), Color(0xFFEDE7FB)]
                : const [Color(0xFF0E3B3A), Color(0xFF14203A), Color(0xFF1A1530)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2DD4BF).withValues(alpha: 0.35)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -18,
              top: -14,
              child: Icon(
                Icons.emoji_events,
                size: 130,
                color: AppColors.pick(Colors.white, Colors.black)
                    .withValues(alpha: 0.05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2DD4BF).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.all_inclusive,
                                size: 14, color: AppColors.pick(const Color(0xFF5EEAD4), const Color(0xFF0F766E))),
                            const SizedBox(width: 6),
                            Text(
                              'TÜM ZAMANLAR',
                              style: TextStyle(
                                color: AppColors.pick(const Color(0xFF5EEAD4), const Color(0xFF0F766E)),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${step.recordedDays} gün kayıt',
                        style: TextStyle(
                            color: AppColors.textDim, fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      Metrics.thousands(total),
                      style: TextStyle(
                        color: AppColors.pick(Colors.white, LightColors.text),
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.4,
                        height: 1,
                      ),
                    ),
                  ),
                  Text(
                    'toplam adım',
                    style: TextStyle(color: AppColors.pick(const Color(0xFF5EEAD4), const Color(0xFF0F766E)), fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.straighten,
                          value: '${km.toStringAsFixed(1)} km',
                          label: 'mesafe',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Tile(
                          icon: Icons.local_fire_department_outlined,
                          value: '${Metrics.thousands(kcal.round())} kcal',
                          label: 'kalori',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          icon: Icons.timer_outlined,
                          value: Metrics.duration(minutes),
                          label: 'yürüme süresi',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Tile(
                          icon: Icons.whatshot_outlined,
                          value: '${step.bestStreak} gün',
                          label: 'en uzun seri',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FatLoss(kg: Metrics.fatKg(kcal)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tum zamanlar kartindaki yari saydam bilgi karosu.
class _Tile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _Tile({required this.icon, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: AppColors.isLight ? 0.6 : 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.pick(const Color(0xFF5EEAD4), const Color(0xFF0F766E))),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: AppColors.pick(Colors.white, LightColors.text),
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Toplam kalorinin yag karsiligi: 7.700 kcal ~ 1 kg.
class _FatLoss extends StatelessWidget {
  final double kg;
  const _FatLoss({required this.kg});

  @override
  Widget build(BuildContext context) {
    final text = kg < 0.1
        ? '< 0,1 kg'
        : '≈ ${kg.toStringAsFixed(kg >= 10 ? 0 : 1).replaceAll('.', ',')} kg';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bestSoft.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.monitor_weight_outlined,
              size: 20, color: AppColors.best),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: text,
                        style: TextStyle(
                          color: AppColors.best,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' yağ yakımına denk',
                        style: TextStyle(color: AppColors.text),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'Yürüyüşle yakılan toplam kaloriye göre (7.700 kcal ≈ 1 kg)',
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
