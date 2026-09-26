import 'package:flutter/material.dart';
import '../services/weather_service.dart';

class WeatherSuggestionCard extends StatefulWidget {
  const WeatherSuggestionCard({super.key});

  @override
  State<WeatherSuggestionCard> createState() => _WeatherSuggestionCardState();
}

class _WeatherSuggestionCardState extends State<WeatherSuggestionCard> {
  WeatherForecast? _forecast = WeatherService.cached;
  late bool _isLoading = _forecast == null;

  /// Secili gun sayfa kaydirilip kart yeniden kurulsa da korunur.
  static int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    final data = await WeatherService.getForecast();
    if (mounted) {
      setState(() {
        _forecast = data;
        _isLoading = false;
      });
    }
  }

  String _getDayName(DateTime date) {
    final now = DateTime.now();
    if (now.year == date.year && now.month == date.month && now.day == date.day) return "Bugün";
    final tomorrow = now.add(const Duration(days: 1));
    if (tomorrow.year == date.year && tomorrow.month == date.month && tomorrow.day == date.day) return "Yarın";
    
    const days = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"];
    return days[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Yukleme gostergesi yok (ilk acilista "yenileme" gibi gorunuyordu):
      // kartin yerini tutan sade bir iskelet.
      return Container(
        height: 104,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).primaryColor.withValues(alpha: 0.18),
        ),
      );
    }

    if (_forecast == null || _forecast!.daily.isEmpty) {
      return const SizedBox.shrink(); 
    }

    if (_currentIndex >= _forecast!.daily.length) _currentIndex = 0;
    final daily = _forecast!.daily[_currentIndex];
    
    // Eğer geçmiş saatse (Bugün için) soluklaştırmak veya göstermemek için
    final now = DateTime.now();
    final hourlyList = daily.hourly.where((h) {
      // Eğer seçili gün bugünse, geçmiş saatleri de gösterebiliriz ama listeyi şu anki saate kaydırmak iyi olur.
      // Basitlik adına tüm günün saatlerini gösteriyoruz.
      return true;
    }).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık: Oklar ve Tarih
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: _currentIndex > 0 
                      ? () => setState(() => _currentIndex--) 
                      : null,
                ),
                Text(
                  _getDayName(daily.date),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: _currentIndex < _forecast!.daily.length - 1 
                      ? () => setState(() => _currentIndex++) 
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // İçerik (Sol: Genel Durum, Sağ: Saatlik)
            Row(
              children: [
                Column(
                  children: [
                    Text(
                      daily.iconEmoji,
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${daily.maxTemp.round()}° / ${daily.minTemp.round()}°',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: hourlyList.length,
                      itemBuilder: (context, index) {
                        final h = hourlyList[index];
                        final isPast = h.time.isBefore(now.subtract(const Duration(hours: 1)));
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Opacity(
                            opacity: isPast ? 0.5 : 1.0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "${h.time.hour.toString().padLeft(2, '0')}:00", 
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                                const SizedBox(height: 2),
                                Text(h.iconEmoji, style: const TextStyle(fontSize: 18)),
                                const SizedBox(height: 2),
                                Text(
                                  "${h.temperature.round()}°", 
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            if ((_currentIndex == 0 && _forecast!.humidity != null) || _forecast!.elevation != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_currentIndex == 0 && _forecast!.humidity != null)
                    _InfoPill(icon: Icons.water_drop_rounded, text: 'Nem %${_forecast!.humidity}'),
                  if (_currentIndex == 0 && _forecast!.humidity != null && _forecast!.elevation != null)
                    const SizedBox(width: 8),
                  if (_forecast!.elevation != null)
                    _InfoPill(icon: Icons.terrain_rounded, text: 'Rakım ${_forecast!.elevation!.round()} m'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
