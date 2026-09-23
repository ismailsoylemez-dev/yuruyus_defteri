import 'package:flutter/material.dart';
import '../utils/root_nav.dart';
import '../theme/app_theme.dart';
import '../utils/achievements.dart';
import '../utils/metrics.dart';

/// Basarilar ekraninin icerigi: ozet karti + kategori kategori rozetler.
class AchievementSection extends StatelessWidget {
  final AchievementStats stats;

  const AchievementSection({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = Achievements.evaluate(stats);
    final unlocked = items.where((e) => e.unlocked).length;
    final next = Achievements.next(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryCard(
          unlocked: unlocked,
          total: items.length,
          next: next,
          stats: stats,
        ),
        for (final c in Achievements.categories) ...[
          const SizedBox(height: 14),
          _CategoryCard(
            category: c,
            current: stats.valueFor(c.kind),
            items: items.where((e) => e.item.kind == c.kind).toList(),
          ),
        ],
      ],
    );
  }
}

String _format(AchievementKind kind, num v) => switch (kind) {
      AchievementKind.distance =>
        '${v.toStringAsFixed(v >= 100 ? 0 : 1).replaceAll('.', ',')} km',
      AchievementKind.calories => '${Metrics.thousands(v.round())} kcal',
      AchievementKind.totalSteps ||
      AchievementKind.single ||
      AchievementKind.bestWeek ||
      AchievementKind.bestMonth =>
        '${Metrics.thousands(v.toInt())} adım',
      AchievementKind.days ||
      AchievementKind.goalDays ||
      AchievementKind.streak =>
        '${v.toInt()} gün',
    };

String _short(AchievementKind kind, num v) => switch (kind) {
      AchievementKind.distance =>
        v.toStringAsFixed(v >= 100 ? 0 : 1).replaceAll('.', ','),
      AchievementKind.totalSteps ||
      AchievementKind.single ||
      AchievementKind.bestWeek ||
      AchievementKind.bestMonth ||
      AchievementKind.calories =>
        Metrics.compact(v.round()),
      _ => '${v.toInt()}',
    };

class _SummaryCard extends StatelessWidget {
  final int unlocked;
  final int total;
  final AchievementProgress? next;
  final AchievementStats stats;

  const _SummaryCard({
    required this.unlocked,
    required this.total,
    required this.next,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final n = next;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.pick(const Color(0xFF2A2212), const Color(0xFFFDF4DC)),
            AppColors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$unlocked',
                style: TextStyle(
                  color: AppColors.best,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(
                  '/ $total rozet',
                  style: TextStyle(
                    color: AppColors.textDim,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${stats.currentStreak} gün',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'güncel seri',
                    style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : unlocked / total,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(AppColors.best),
            ),
          ),
          if (n != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(n.item.icon, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Sıradaki: ',
                          style: TextStyle(color: AppColors.textDim),
                        ),
                        TextSpan(
                          text: '${n.item.title} ${n.item.unit}',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: '  -  %${(n.ratio * 100).floor()}, '
                              '${_format(n.item.kind, (n.item.threshold - n.current).clamp(0, n.item.threshold))} kaldı',
                          style: TextStyle(color: AppColors.textDim),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontSize: 12.5),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final AchievementCategory category;
  final num current;
  final List<AchievementProgress> items;

  const _CategoryCard({
    required this.category,
    required this.current,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final done = items.where((e) => e.unlocked).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
              Icon(category.icon, size: 17, color: AppColors.accent),
              const SizedBox(width: 7),
              Text(
                category.title,
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$done/${items.length}',
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  _format(category.kind, current),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.best,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 12,
              // Sabit yukseklik: dar ekranda oranla kuculup tasmasin.
              mainAxisExtent: 112,
            ),
            itemBuilder: (_, i) => _Badge(item: items[i]),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final AchievementProgress item;
  const _Badge({required this.item});

  List<Color> _getBadgeColors(String title) {
    final tierColors = [
      // Orange / Gold
      [const Color(0xFFFFD700), const Color(0xFFFFA500), const Color(0xFFB8860B)],
      // Blue / Diamond
      [const Color(0xFF00FFFF), const Color(0xFF1E90FF), const Color(0xFF00008B)],
      // Purple / Amethyst
      [const Color(0xFFDDA0DD), const Color(0xFF8A2BE2), const Color(0xFF4B0082)],
      // Pink / Ruby
      [const Color(0xFFFF69B4), const Color(0xFFDC143C), const Color(0xFF8B0000)],
      // Green / Emerald
      [const Color(0xFF00FF7F), const Color(0xFF32CD32), const Color(0xFF006400)],
    ];
    // Hash tabanli renk secimi
    return tierColors[title.hashCode % tierColors.length];
  }

  void _showDetails(BuildContext context) {
    showBadgeDialog(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final on = item.unlocked;

    return GestureDetector(
      onTap: () => _showDetails(context),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: on
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _getBadgeColors(item.item.title),
                      stops: const [0.1, 0.5, 0.9],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.surfaceAlt,
                        AppColors.surfaceAlt.withValues(alpha: 0.5),
                      ],
                    ),
              boxShadow: on
                  ? [
                      BoxShadow(
                        color: _getBadgeColors(item.item.title)[1].withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 0,
                        offset: const Offset(-2, -2), // Highlight
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: -2,
                        offset: const Offset(4, 4), // Inner Shadow effect pseudo
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(2, 2),
                      ),
                    ],
              border: Border.all(
                color: on ? Colors.white.withValues(alpha: 0.5) : AppColors.divider,
                width: on ? 2 : 1,
              ),
            ),
            child: Icon(
              item.item.icon,
              size: 28,
              color: on ? Colors.white : AppColors.textDim.withValues(alpha: 0.3),
            ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            item.item.title,
            style: TextStyle(
              color: on ? AppColors.text : AppColors.textDim,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            item.item.unit,
            style: TextStyle(
              color: on ? AppColors.best : AppColors.textDim,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 3),
        if (!on)
          SizedBox(
            width: 42,
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: item.ratio,
                    minHeight: 3,
                    backgroundColor: AppColors.divider,
                    valueColor:
                        AlwaysStoppedAnimation(AppColors.textDim),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '%${(item.ratio * 100).floor()} • ${_short(item.item.kind, item.current)}/'
                    '${_short(item.item.kind, item.item.threshold)}',
                    style: TextStyle(
                      color: AppColors.textDim,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
    );
  }
}

/// Rozet karti: kategoriye uygun arka plan gorseli, buyuk rozet, hedef
/// ve ilerleme. Sag ustteki dugme Basarilar sekmesine goturur.
void showBadgeDialog(BuildContext context, AchievementProgress item) {
  final on = item.unlocked;
  final category = Achievements.categories
      .where((c) => c.kind == item.item.kind)
      .map((c) => c.title)
      .firstOrNull;
  final theme = _BadgeTheme.of(item.item.kind);
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          Positioned.fill(child: _BadgeBackdrop(theme: theme, active: on)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 30, 22, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: on
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.pick(const Color(0xFF65A30D), const Color(0xFF22C55E)),
                              AppColors.best,
                              AppColors.pick(const Color(0xFF15803D), const Color(0xFF166534)),
                            ],
                          )
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.surfaceAlt,
                              AppColors.surfaceAlt.withValues(alpha: 0.8),
                            ],
                          ),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: AppColors.best.withValues(alpha: 0.5),
                              blurRadius: 24,
                              spreadRadius: 4,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.3),
                              blurRadius: 4,
                              offset: const Offset(-2, -2),
                            ),
                          ]
                        : null,
                    border: Border.all(
                      color: on ? Colors.white.withValues(alpha: 0.4) : AppColors.divider,
                      width: on ? 2 : 1,
                    ),
                  ),
                  child: Icon(
                    item.item.icon,
                    size: 48,
                    color: on ? Colors.white : AppColors.textDim.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.item.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  [if (category != null) category, item.item.unit].join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: on ? AppColors.best : AppColors.textDim,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hedef: ${_format(item.item.kind, item.item.threshold)}',
                        style: TextStyle(
                            color: AppColors.text, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Şu an: ${_format(item.item.kind, item.current)}',
                        style: TextStyle(
                            color: AppColors.textDim, fontSize: 12.5),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: item.ratio,
                          minHeight: 6,
                          backgroundColor: AppColors.divider,
                          valueColor: AlwaysStoppedAnimation(
                            on ? AppColors.best : AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        on
                            ? 'Kazanıldı 🎉'
                            : '%${(item.ratio * 100).floor()} tamamlandı',
                        style: TextStyle(
                          color: on ? AppColors.best : AppColors.textDim,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Kapat sagda.
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Kapat'),
                  ),
                ),
              ],
            ),
          ),
          // Sag ust: Basarilar sekmesine git.
          Positioned(
            top: 6,
            right: 6,
            child: IconButton(
              tooltip: 'Başarılar',
              style: IconButton.styleFrom(
                backgroundColor: AppColors.bg.withValues(alpha: 0.55),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                RootNav.go(RootNav.achievements);
              },
              icon: Icon(Icons.emoji_events_outlined,
                  color: AppColors.best, size: 20),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Kategoriye gore arka plan: renk gecisi + temaya uygun silik ikonlar.
class _BadgeTheme {
  final List<Color> colors;
  final List<IconData> motifs;
  final IconData hero;

  const _BadgeTheme(this.colors, this.motifs, this.hero);

  static _BadgeTheme of(AchievementKind kind) => switch (kind) {
        AchievementKind.distance => const _BadgeTheme(
            [Color(0xFF0F3B4A), Color(0xFF0E1A26)],
            [Icons.straighten, Icons.map_outlined, Icons.terrain, Icons.flag_outlined],
            Icons.landscape),
        AchievementKind.totalSteps => const _BadgeTheme(
            [Color(0xFF12402B), Color(0xFF0D1A14)],
            [Icons.directions_walk, Icons.hiking, Icons.directions_run],
            Icons.directions_walk),
        AchievementKind.calories => const _BadgeTheme(
            [Color(0xFF4A1E12), Color(0xFF1C0F0C)],
            [Icons.local_fire_department, Icons.whatshot, Icons.fitness_center],
            Icons.local_fire_department),
        AchievementKind.streak => const _BadgeTheme(
            [Color(0xFF4A2C0E), Color(0xFF1C140A)],
            [Icons.whatshot, Icons.bolt, Icons.local_fire_department],
            Icons.whatshot),
        AchievementKind.goalDays => const _BadgeTheme(
            [Color(0xFF1F3F1F), Color(0xFF0F1A0F)],
            [Icons.flag, Icons.check_circle_outline, Icons.emoji_events_outlined],
            Icons.flag),
        AchievementKind.days => const _BadgeTheme(
            [Color(0xFF1E2C4E), Color(0xFF0E1322)],
            [Icons.calendar_month, Icons.event_available, Icons.today],
            Icons.calendar_month),
        AchievementKind.single => const _BadgeTheme(
            [Color(0xFF3C1F4E), Color(0xFF160E1E)],
            [Icons.bolt, Icons.speed, Icons.rocket_launch],
            Icons.bolt),
        AchievementKind.bestWeek => const _BadgeTheme(
            [Color(0xFF123C3C), Color(0xFF0B1A1A)],
            [Icons.date_range, Icons.trending_up, Icons.show_chart],
            Icons.trending_up),
        AchievementKind.bestMonth => const _BadgeTheme(
            [Color(0xFF2C2C50), Color(0xFF12121F)],
            [Icons.calendar_view_month, Icons.stars, Icons.auto_graph],
            Icons.stars),
      };
}

class _BadgeBackdrop extends StatelessWidget {
  final _BadgeTheme theme;
  final bool active;

  const _BadgeBackdrop({required this.theme, required this.active});

  // Sabit dagilim (x, y, boyut, aci): her acilista ayni, titremez.
  static const _spots = [
    (0.08, 0.10, 34.0, -0.3), (0.78, 0.06, 26.0, 0.4), (0.60, 0.30, 22.0, 0.2),
    (0.12, 0.42, 28.0, 0.5), (0.86, 0.46, 36.0, -0.4), (0.30, 0.70, 24.0, -0.2),
    (0.70, 0.78, 30.0, 0.3), (0.05, 0.86, 22.0, 0.1), (0.45, 0.92, 20.0, -0.5),
  ];

  @override
  Widget build(BuildContext context) {
    final alpha = active ? 1.0 : 0.55;
    return Opacity(
      opacity: alpha,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Acik temada ayni renklerin pastel tonu (yazi okunur kalsin).
            colors: AppColors.isLight
                ? [
                    for (final c in theme.colors)
                      Color.lerp(c, Colors.white, 0.8)!,
                  ]
                : theme.colors,
          ),
        ),
        child: LayoutBuilder(
          builder: (_, c) => Stack(
            children: [
              Positioned(
                right: -30,
                bottom: -20,
                child: Icon(
                  theme.hero,
                  size: 190,
                  color: AppColors.pick(Colors.white, Colors.black)
                      .withValues(alpha: 0.06),
                ),
              ),
              for (var i = 0; i < _spots.length; i++)
                Positioned(
                  left: c.maxWidth * _spots[i].$1,
                  top: c.maxHeight * _spots[i].$2,
                  child: Transform.rotate(
                    angle: _spots[i].$4,
                    child: Icon(
                      theme.motifs[i % theme.motifs.length],
                      size: _spots[i].$3,
                      color: AppColors.pick(Colors.white, Colors.black)
                          .withValues(alpha: 0.07),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
