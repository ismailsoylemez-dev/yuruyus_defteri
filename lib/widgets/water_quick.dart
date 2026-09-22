import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../theme/app_theme.dart';

/// Su dugmesine uzun basinca acilan kucuk kart: bugunku litre, hedef
/// cubugu ve sayfaya girmeden - / + 250 ml. Tempo karti ile ayni yumusak
/// acilis; carpiyla ya da kart disina dokunarak kapanir.
Future<void> showWaterQuick(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.black.withValues(alpha: AppColors.isLight ? 0.18 : 0.38),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => const _WaterQuickCard(),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
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

class _WaterQuickCard extends StatefulWidget {
  const _WaterQuickCard();

  @override
  State<_WaterQuickCard> createState() => _WaterQuickCardState();
}

class _WaterQuickCardState extends State<_WaterQuickCard> {
  static const _step = 250;
  Timer? _refresh;

  @override
  void dispose() {
    // Bekleyen tazeleme varsa kapanirken hemen yapilir (widget ve kalici
    // bildirim son degeri gostersin).
    final pending = _refresh != null;
    _refresh?.cancel();
    _refresh = null;
    if (pending) _stepProvider?.refreshAll(force: true);
    super.dispose();
  }

  StepProvider? _stepProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stepProvider = context.read<StepProvider>();
  }

  Future<void> _change(int ml) async {
    HapticFeedback.lightImpact();
    final water = context.read<WaterProvider>();
    if (ml > 0) {
      await water.addWater(ml);
    } else {
      await water.removeWater(-ml);
    }
    // Arka arkaya dokunuslarda widget her seferinde cizilmesin: son
    // dokunustan 1,5 sn sonra (ya da kart kapaninca) bir kez tazelenir.
    _refresh?.cancel();
    _refresh = Timer(const Duration(milliseconds: 1500), () {
      _refresh = null;
      _stepProvider?.refreshAll(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final today = context.watch<WaterProvider>().todayWater;
    final goal = context.watch<SettingsProvider>().waterGoal;
    final progress = goal <= 0 ? 0.0 : (today / goal).clamp(0.0, 1.0);
    String l(int ml) => (ml / 1000).toStringAsFixed(2).replaceAll('.', ',');
    void close() => Navigator.of(context).maybePop();

    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 300,
                padding: const EdgeInsets.fromLTRB(18, 10, 10, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.waterSoft, AppColors.surface],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.water.withValues(alpha: 0.35),
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
                  children: [
                    Row(
                      children: [
                        Icon(Icons.water_drop, size: 18, color: AppColors.water),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bugünkü su',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Material(
                          color: AppColors.surfaceAlt.withValues(alpha: 0.8),
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: close,
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: Icon(Icons.close_rounded,
                                  size: 18, color: AppColors.textDim),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${l(today)} L',
                      style: TextStyle(
                        color: AppColors.water,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    Text(
                      'hedef ${l(goal)} L · %${(progress * 100).round()}',
                      style: TextStyle(color: AppColors.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          color: AppColors.water,
                          backgroundColor: AppColors.surfaceAlt,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _QuickButton(
                              icon: Icons.remove_rounded,
                              label: '$_step ml',
                              filled: false,
                              onTap: today <= 0 ? null : () => _change(-_step),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _QuickButton(
                              icon: Icons.add_rounded,
                              label: '$_step ml',
                              filled: true,
                              onTap: () => _change(_step),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  const _QuickButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.water;
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: filled ? color : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: filled ? 0 : 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: filled ? Colors.white : color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.white : color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
