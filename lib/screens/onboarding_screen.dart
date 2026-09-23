import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_theme.dart';
import '../services/prefs_service.dart';
import 'auth_gate.dart';
import 'root_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final PrefsService prefs;
  final bool firebaseReady;
  
  const OnboardingScreen({
    super.key,
    required this.prefs,
    required this.firebaseReady,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _pages = [
    {
      'title': 'Adım Sayar\'a Hoş Geldiniz',
      'desc': 'Sağlıklı bir yaşama adım atın. Sadece yürüyün, gerisini bize bırakın.',
      'lottie': 'https://lottie.host/801bf7b0-7539-4cd0-9ed4-7cbfeb7ab86f/Z5V6Q9N7x3.json', // temp
    },
    {
      'title': 'Batarya Dostu Takip',
      'desc': 'Arka planda çok düşük güç tüketerek adımlarınızı eksiksiz sayıyoruz. Pil optimizasyonunu kapatmanız takibin durmamasını sağlar.',
      'lottie': 'https://lottie.host/801bf7b0-7539-4cd0-9ed4-7cbfeb7ab86f/Z5V6Q9N7x3.json', // temp
    },
    {
      'title': 'Hedeflerinizi Belirleyin',
      'desc': 'Günlük adım, kalori ve süre hedeflerinize ulaşarak eğlenceli 3D rozetler kazanın!',
      'lottie': 'https://lottie.host/801bf7b0-7539-4cd0-9ed4-7cbfeb7ab86f/Z5V6Q9N7x3.json', // temp
    },
    {
      'title': 'İzinleri Verin ve Başlayın',
      'desc': 'Doğru sayım için fiziksel aktivite (sensör) ve harita rotası için konum izni gereklidir.',
      'lottie': 'https://lottie.host/801bf7b0-7539-4cd0-9ed4-7cbfeb7ab86f/Z5V6Q9N7x3.json', // temp
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              final page = _pages[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 280,
                      child: Lottie.network(
                        page['lottie'],
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) => Icon(
                          index == 0 ? Icons.directions_walk : index == 1 ? Icons.battery_charging_full : index == 2 ? Icons.emoji_events : Icons.security,
                          size: 100,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Text(
                      page['title'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      page['desc'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textDim,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: _currentPage == index ? 24 : 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index ? AppColors.best : AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: _currentPage == _pages.length - 1
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.best,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    onPressed: _finishOnboarding,
                    child: const Text(
                      'İzin Ver ve Başla',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          _pageController.animateToPage(
                            _pages.length - 1,
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Text(
                          'Atla',
                          style: TextStyle(color: AppColors.textDim, fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                      FloatingActionButton(
                        backgroundColor: AppColors.accent,
                        elevation: 2,
                        onPressed: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _finishOnboarding() async {
    await Permission.activityRecognition.request();
    await Permission.locationWhenInUse.request();
    await Permission.ignoreBatteryOptimizations.request();
    
    await widget.prefs.setIntroShown(true);
    
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => widget.firebaseReady 
            ? AuthGate(prefs: widget.prefs) 
            : const RootScreen(),
      ),
    );
  }
}
