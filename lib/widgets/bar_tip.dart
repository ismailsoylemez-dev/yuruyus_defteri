import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dokunulan sutunun ustunde gorunen kucuk bilgi kutusu.
///
/// Sabit yukseklikte yer ayirir; secim yokken bos kalir, boylece dokununca
/// kart ziplamaz. Kutu sutunun ortasina hizalanir, kenarlarda karttan
/// tasmaz ([Align] cocugu her zaman sinirlar icinde tutar).
class BarTip extends StatelessWidget {
  static const height = 20.0;

  final int? index;
  final int count;
  final String text;
  final Color color;

  const BarTip({
    super.key,
    required this.index,
    required this.count,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final i = index;
    if (i == null || count <= 0) return const SizedBox(height: height);
    final x = count == 1 ? 0.0 : -1 + 2 * i / (count - 1);

    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment(x, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.7)),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
