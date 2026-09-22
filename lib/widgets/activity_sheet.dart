import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/intensity.dart';
import '../utils/metrics.dart';

/// Tempo renkleri: tum ekranlarda ayni.
class ActivityColors {
  static Color get normal => AppColors.accent;
  static Color get brisk =>
      AppColors.pick(const Color(0xFFFFA726), const Color(0xFFF57C00));
  static Color get run =>
      AppColors.pick(const Color(0xFFEF5350), const Color(0xFFE53935));
}

/// Normal / tempolu / kosu kirilimini ekranin ortasinda yumusak bir kart
/// olarak gosterir: arka plan hafifce kararip bulaniklasir, kart kucuk bir
/// olcekle belirir. Sag ustteki carpi ya da kart disina dokunmak kapatir.
Future<void> showActivitySheet(
  BuildContext context, {
  required String title,
  required ActivityBreakdown breakdown,
  VoidCallback? onShowRoute,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withValues(alpha: AppColors.isLight ? 0.18 : 0.38),
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (ctx, _, __) => _ActivityCard(
      title: title,
      breakdown: breakdown,
      onShowRoute: onShowRoute,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      final blur = 5.0 * anim.value;
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class _ActivityCard extends StatelessWidget {
  final String title;
  final ActivityBreakdown breakdown;

  /// Verilirse kartin altinda "Rotayi gor" dugmesi cikar (tek gun).
  final VoidCallback? onShowRoute;

  const _ActivityCard({
    required this.title,
    required this.breakdown,
    this.onShowRoute,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.78;
    void close() => Navigator.of(context).maybePop();
    return Material(
      type: MaterialType.transparency,
      // Kart disina dokunmak kapatir; kartin kendisi dokunusu yutar.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              child: GestureDetector(
                onTap: () {},
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 340, maxHeight: maxH),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.pick(const Color(0xFF17221C), const Color(0xFFF1FAF4)),
                          AppColors.surface,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.accent
                            .withValues(alpha: AppColors.isLight ? 0.25 : 0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: AppColors.isLight ? 0.12 : 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 12, 8, 4),
                          child: Row(
                            children: [
                              Icon(Icons.insights_outlined,
                                  size: 17, color: AppColors.accent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _CloseButton(onTap: close),
                            ],
                          ),
                        ),
                        Flexible(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                                16, 6, 16, onShowRoute == null ? 14 : 4),
                            child: ActivityBreakdownView(breakdown: breakdown),
                          ),
                        ),
                        if (onShowRoute != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onShowRoute!();
                              },
                              icon: const Icon(Icons.route, size: 18),
                              label: const Text('Rotayı gör'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(42),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Kapat',
      child: Material(
        color: AppColors.surfaceAlt.withValues(alpha: 0.8),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
          ),
        ),
      ),
    );
  }
}

/// Kirilim: kalori payi cubugu + her tempo icin ayri blok + toplam.
///
/// Eski 5 sutunlu tablo dar ekranda sikisiyordu ("2 sa 32 dk" adim
/// sutununa dayaniyordu). Her tempo artik kendi satirinda; olculer
/// ikonlu ve renkli kutucuklarda (adim yesil, sure mor, km amber, kcal
/// turuncu).
class ActivityBreakdownView extends StatelessWidget {
  final ActivityBreakdown breakdown;

  const ActivityBreakdownView({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    if (b.steps <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Bu aralıkta adım kaydı yok.',
          style: TextStyle(color: AppColors.textDim, fontSize: 13),
        ),
      );
    }

    double share(double v) => b.kcal <= 0 ? 0 : v / b.kcal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShareBar(b: b),
        const SizedBox(height: 7),
        // Renklerin anlami: cubuk kalori payini gosterir.
        Row(
          children: [
            _Legend(color: ActivityColors.normal, text: 'Normal'),
            const SizedBox(width: 10),
            _Legend(color: ActivityColors.brisk, text: 'Tempolu'),
            const SizedBox(width: 10),
            _Legend(color: ActivityColors.run, text: 'Koşu'),
            const Spacer(),
            Text(
              'kalori payı',
              style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PartBlock(
          color: ActivityColors.normal,
          name: 'Normal yürüyüş',
          hint: '< ${Intensity.briskMinCadence} adım/dk',
          part: b.normal,
          share: share(b.normal.kcal),
        ),
        _PartBlock(
          color: ActivityColors.brisk,
          name: 'Tempolu yürüyüş',
          hint: '${Intensity.briskMinCadence}-${Intensity.runMinCadence - 1} adım/dk',
          part: b.brisk,
          share: share(b.brisk.kcal),
        ),
        _PartBlock(
          color: ActivityColors.run,
          name: 'Koşu',
          hint: '${Intensity.runMinCadence}+ adım/dk',
          part: b.run,
          share: share(b.run.kcal),
        ),
        // Toplamin uc kirilimin toplami oldugu ilk bakista anlasilsin.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
          child: Row(
            children: [
              const Expanded(child: Divider(height: 1, thickness: 1)),
              Flexible(
                flex: 4,
                child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final c in [
                      ActivityColors.normal,
                      ActivityColors.brisk,
                      ActivityColors.run,
                    ]) ...[
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration:
                            BoxDecoration(color: c, shape: BoxShape.circle),
                      ),
                    ],
                    const SizedBox(width: 5),
                    Text(
                      'normal + tempolu + koşu =',
                      style: TextStyle(
                        color: AppColors.textDim,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                ),
                ),
              ),
              const Expanded(child: Divider(height: 1, thickness: 1)),
            ],
          ),
        ),
        _PartBlock(
          color: AppColors.text,
          name: 'Toplam',
          hint: '',
          part: ActivityPart(
            steps: b.steps,
            minutes: b.minutes,
            km: b.km,
            kcal: b.kcal,
          ),
          total: true,
        ),
        if (!b.hasData) ...[
          const SizedBox(height: 4),
          Text(
            'Bu aralıkta tempo kaydı yok; tüm adımlar normal yürüyüş sayıldı. '
            'Tempo algılama arka plan servisi açıkken kendiliğinden çalışır.',
            style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
          ),
        ],
      ],
    );
  }
}

class _PartBlock extends StatelessWidget {
  final Color color;
  final String name;
  final String hint;
  final ActivityPart part;
  final double share;
  final bool total;

  const _PartBlock({
    required this.color,
    required this.name,
    required this.hint,
    required this.part,
    this.share = 0,
    this.total = false,
  });

  @override
  Widget build(BuildContext context) {
    final empty = part.steps <= 0 && !total;
    return Opacity(
      opacity: empty ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: total ? AppColors.surfaceAlt : AppColors.bg.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border(
            left: BorderSide(color: color, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Ad + esik tek satirda; dar ekranda esik kisalir, tasmaz.
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: TextStyle(
                            color: total ? AppColors.text : color,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hint.isNotEmpty)
                          TextSpan(
                            text: '  $hint',
                            style: TextStyle(
                              color: AppColors.textDim,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!total && share > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    '%${(share * 100).round()} kcal',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.directions_walk,
                    color: MetricColors.steps,
                    value: Metrics.thousands(part.steps),
                    unit: 'adım',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.timer_outlined,
                    color: MetricColors.time,
                    value: Metrics.duration(part.minutes),
                    unit: 'süre',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.straighten,
                    color: MetricColors.km,
                    value: part.km.toStringAsFixed(2).replaceAll('.', ','),
                    unit: 'km',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.local_fire_department_outlined,
                    color: MetricColors.kcal,
                    value: part.kcal.round().toString(),
                    unit: 'kcal',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String unit;

  const _Metric({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                unit,
                style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bugun kartindaki ince ozet: renkli cubuk + dakikalar.
class ActivityStrip extends StatelessWidget {
  final ActivityBreakdown breakdown;

  const ActivityStrip({super.key, required this.breakdown});

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShareBar(b: b, height: 16),
        const SizedBox(height: 8),
        Row(
          children: [
            _Legend(
              color: ActivityColors.normal,
              text: 'Normal ${Metrics.duration(b.normal.minutes)}',
            ),
            const SizedBox(width: 10),
            _Legend(
              color: ActivityColors.brisk,
              text: 'Tempolu ${Metrics.duration(b.brisk.minutes)}',
            ),
            const SizedBox(width: 10),
            _Legend(
              color: ActivityColors.run,
              text: 'Koşu ${Metrics.duration(b.run.minutes)}',
            ),
            const Spacer(),
            Icon(Icons.chevron_right, size: 18, color: AppColors.textDim),
          ],
        ),
      ],
    );
  }
}

class _ShareBar extends StatelessWidget {
  final ActivityBreakdown b;
  final double height;

  const _ShareBar({required this.b, this.height = 20});

  @override
  Widget build(BuildContext context) {
    final total = b.kcal;
    int flex(double v) => total <= 0 ? 0 : (v / total * 1000).round();
    final parts = [
      (flex(b.normal.kcal), ActivityColors.normal),
      (flex(b.brisk.kcal), ActivityColors.brisk),
      (flex(b.run.kcal), ActivityColors.run),
    ].where((e) => e.$1 > 0).toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: parts.isEmpty
            ? Container(color: AppColors.surfaceAlt)
            : Row(
                children: [
                  for (final p in parts)
                    Expanded(
                      flex: p.$1,
                      child: Container(
                        color: p.$2,
                        alignment: Alignment.center,
                        // Dilim yeterince genisse yuzdesi icinde yazilir.
                        child: p.$1 >= 100
                            ? Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '%${(p.$1 / 10).round()}',
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: ThemeData.estimateBrightnessForColor(
                                                  p.$2) ==
                                              Brightness.dark
                                          ? Colors.white
                                          : const Color(0xFF0B1A10),
                                      fontSize: height >= 20 ? 12 : 11,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;

  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
