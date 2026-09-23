import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../theme/app_theme.dart';
import '../utils/achievements.dart';
import '../utils/root_nav.dart';
import '../widgets/achievement_section.dart';
import '../widgets/all_time_card.dart';

/// Alt menudeki "Basarilar" sekmesi: en ustte Tum zamanlar karti.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<StepProvider>();
    final settings = context.watch<SettingsProvider>();
    final h = settings.heightCm;

    // Tum zamanlar karti ile ayni kalori ve mesafe (normal + tempolu + kosu).
    final all = step.breakdownAllTime;
    final stats = AchievementStats.from(
      history: step.history,
      goal: settings.goal,
      heightCm: h,
      totalKcal: all.kcal,
      totalKm: all.km,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Başarılar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: IconButton(
              tooltip: 'Ayarlar',
              onPressed: () => RootNav.openSettings(),
              icon: Icon(Icons.settings_outlined, color: AppColors.textDim),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          AllTimeCard(step: step, heightCm: h, weightKg: settings.weightKg),
          const SizedBox(height: 14),
          AchievementSection(stats: stats),
        ],
      ),
    );
  }
}
