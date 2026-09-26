import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../providers/step_provider.dart';
import '../providers/water_provider.dart';
import '../services/route_service.dart';
import 'achievements_screen.dart';
import 'heatmap_screen.dart';
import 'insights_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'route_screen.dart';
import '../utils/root_nav.dart';
import '../widgets/celebration.dart';
import '../widgets/weekly_report_dialog.dart';

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int get _index => RootNav.tab.value;

  void _onTab() {
    if (mounted) setState(() {});
  }

  StepProvider? _step;

  /// Gunluk hedefe ulasildi: konfeti + titresim.
  void _celebrate() {
    if (!mounted) return;
    showCelebration(context, steps: context.read<StepProvider>().todaySteps);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final step = context.read<StepProvider>();
      step.refreshAll(force: true);
      // Arka plana alinirken bekleyen disk ve bulut yazmalari gonderilir.
      step.flushPersist();
      step.flushCloud();
      // Rotanin son 30 gunu (degistiyse) buluta yedeklenir.
      RouteService.syncRecent();
      RouteService.syncWorkouts();
    } else if (state == AppLifecycleState.resumed) {
      // Native servisin diske yazdigi degerleri tazele, gun gecisini
      // kontrol et ve servisin tuttugu kayitlari al.
      final water = context.read<WaterProvider>();
      context.read<StepProvider>().onResume().then((_) {
        // Widget'tan eklenen su (uygulama kapaliyken) belleğe alinir.
        water.reloadFromPrefs();
      });
      // Konum izni ayarlardan degistiyse servis tipi tazelenir.
      RouteService.refresh();
      RouteService.syncWorkouts();
      _handleLaunchAction();
      _calibrateStride();
    }
  }

  static const _pages = [
    HomeScreen(),
    HistoryScreen(),
    RouteScreen(embedded: true),
    AchievementsScreen(),
  ];

  /// Rota kayitlarindan adim boyu olculur; degistiyse tum km/kcal
  /// hesaplari (bildirim ve widget dahil) yeni degere gecer.
  Future<void> _calibrateStride() async {
    final r = await RouteService.measureStride();
    if (!mounted || r == null) return;
    final settings = context.read<SettingsProvider>();
    if (settings.strideCal == r.$1 && settings.strideCalCount == r.$2) return;
    final step = context.read<StepProvider>();
    await settings.setStrideCal(r.$1, r.$2);
    await step.refreshAll(force: true);
  }

  /// Uygulama kisayolu / Hizli Ayarlar kutucugu eylemleri.
  Future<void> _handleLaunchAction() async {
    final action = await RouteService.takeLaunchAction();
    if (!mounted || action == null) return;
    switch (action) {
      case 'workout':
        RootNav.go(RootNav.route);
        RootNav.startWorkout.value = true;
      case 'water':
        await context.read<WaterProvider>().addWater(250);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('+250 ml su eklendi 💧'),
        ));
      case 'heatmap':
        RootNav.go(RootNav.route);
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const HeatmapScreen()),
        );
      case 'weekly':
        RootNav.go(RootNav.home);
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const InsightsScreen(weekly: true)),
        );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    RootNav.tab.addListener(_onTab);
    _step = context.read<StepProvider>();
    _step!.goalReached.addListener(_celebrate);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _calibrateStride();
      RouteService.syncWorkouts(pull: true);
      RouteService.onLaunchAction(_handleLaunchAction);
      _handleLaunchAction();
      _step!.start().then((_) {
        // Kontrol et ve gerekirse haftalik raporu goster
        if (mounted) WeeklyReportDialog.checkAndShow(context);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RootNav.tab.removeListener(_onTab);
    _step?.goalReached.removeListener(_celebrate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: RootNav.go,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_walk_outlined),
            selectedIcon: Icon(Icons.directions_walk),
            label: 'Bugün',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Geçmiş',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_run_outlined),
            selectedIcon: Icon(Icons.directions_run),
            label: 'Antrenman',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Başarılar',
          ),
        ],
      ),
    );
  }
}
