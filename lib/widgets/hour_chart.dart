import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/metrics.dart';
import 'bar_tip.dart';

/// Secili gunun 24 saatlik adim dagilimi. Bir saate dokununca o saatte
/// atilan adim sutunun ustunde gosterilir; tekrar dokunmak kapatir.
class HourChart extends StatefulWidget {
  final List<int> hours;

  /// Gosterilen gun; degisince secim sifirlanir.
  final DateTime? day;

  const HourChart({super.key, required this.hours, this.day});

  @override
  State<HourChart> createState() => _HourChartState();
}

class _HourChartState extends State<HourChart> {
  int? _selected;

  @override
  void didUpdateWidget(covariant HourChart old) {
    super.didUpdateWidget(old);
    // Baska gune gecildiyse eski secim kalmasin.
    if (old.day != widget.day) _selected = null;
  }

  static String _hh(int h) => h.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final hours = widget.hours;
    final maxVal = hours.fold<int>(1, (m, v) => v > m ? v : m);
    final total = hours.fold<int>(0, (a, b) => a + b);
    final bestHour = hours.indexOf(hours.fold<int>(0, (m, v) => v > m ? v : m));
    final sel = _selected;
    const h = 140.0;
    final now = DateTime.now();
    final day = widget.day;
    final nowHour = day != null && DateUtils.isSameDay(day, now) ? now.hour : -1;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
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
                'Saatlik dağılım',
                style: TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (total > 0)
                Text(
                  'en yoğun ${_hh(bestHour)}:00',
                  style: TextStyle(
                    color: AppColors.best,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (total == 0)
            SizedBox(
              height: h + BarTip.height + 4,
              child: Center(
                child: Text(
                  'Bu gün için saatlik kayıt yok.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(right: 26),
              child: BarTip(
              index: sel,
              count: 24,
              text: sel == null
                  ? ''
                  : '${_hh(sel)}:00-${_hh((sel + 1) % 24)}:00 · '
                      '${Metrics.thousands(hours[sel])} adım',
              color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: h,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Olcek cizgileri: ust = en yogun saat, orta = onun 1/4'u,
                  // alt ceyrek = 1/16'si (karekok olcek).
                  for (final g in const [1.0, 0.5, 0.25])
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: h * g - 0.5,
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: AppColors.divider.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            Metrics.compact((maxVal * g * g).round()),
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 11.5,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 26),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(24, (i) {
                        final v = hours[i];
                        // Karekok olcek: 10 ile 200 adim arasindaki fark
                        // dogrusal olcekte (en yogun saat 1.500 iken) ayni
                        // 4 piksele dusuyordu. sqrt ile 10 -> %8, 100 ->
                        // %26, 200 -> %37 yukseklik; siralama bozulmaz.
                        final ratio = v <= 0 ? 0.0 : math.sqrt(v / maxVal);
                        final isBest = v == maxVal && maxVal > 0;
                        final isSel = sel == i;
                        return Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                setState(() => _selected = isSel ? null : i),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 1),
                                child: Container(
                                  height:
                                      v <= 0 ? 2.0 : math.max(3.0, h * ratio),
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? AppColors.text
                                        : v <= 0
                                            ? AppColors.surfaceAlt
                                            : isBest
                                                ? AppColors.best
                                                : AppColors.accent.withValues(
                                                    alpha: 0.35 + 0.65 * ratio),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          // Her sutunun altinda saat: 0 1 2 ... 23
          SizedBox(
            height: 13,
            child: Padding(
              padding: EdgeInsets.only(right: total == 0 ? 0 : 26),
              child: Row(
              children: List.generate(24, (i) {
                return Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      // Eksen etiketi basinda sifir olmadan: 0 1 2 ... 23
                      '$i',
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        // Bugunun su anki saati vurgu renginde.
                        color: sel == i
                            ? AppColors.text
                            : i == nowHour
                                ? AppColors.accent
                                : AppColors.textDim,
                        fontSize: 11.5,
                        fontWeight: sel == i || i == nowHour
                            ? FontWeight.w700
                            : FontWeight.normal,
                        height: 1.2,
                      ),
                    ),
                  ),
                );
              }),
            ),
            ),
          ),
          if (total > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Kayıtlı saatlik toplam: ${Metrics.thousands(total)} adım',
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
