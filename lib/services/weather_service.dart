import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class HourlyWeather {
  final DateTime time;
  final double temperature;
  final int weatherCode;
  final String iconEmoji;

  HourlyWeather({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.iconEmoji,
  });
}

class DailyWeather {
  final DateTime date;
  final double maxTemp;
  final double minTemp;
  final int weatherCode;
  final String description;
  final String iconEmoji;
  final List<HourlyWeather> hourly;

  DailyWeather({
    required this.date,
    required this.maxTemp,
    required this.minTemp,
    required this.weatherCode,
    required this.description,
    required this.iconEmoji,
    required this.hourly,
  });
}

class WeatherForecast {
  final List<DailyWeather> daily;

  /// Anlik bagil nem (%) ve bulunulan yerin deniz seviyesinden yuksekligi (m).
  /// Rakim Open-Meteo'nun sayisal yukseklik modelinden gelir (GPS rakimindan
  /// cok daha tutarli, ek izin/sensor gerekmez).
  final int? humidity;
  final double? elevation;

  WeatherForecast({required this.daily, this.humidity, this.elevation});
}

class WeatherService {
  static WeatherForecast? _cache;
  static DateTime? _cacheAt;
  static Future<WeatherForecast?>? _inflight;
  static const _ttl = Duration(minutes: 30);

  /// Son alinan tahmin (30 dk icinde); yoksa null. Kart yeniden
  /// kuruldugunda yukleme gostermeden bununla cizilir.
  static WeatherForecast? get cached {
    final at = _cacheAt;
    if (_cache == null || at == null) return null;
    return DateTime.now().difference(at) < _ttl ? _cache : null;
  }

  /// Onbellekli tahmin: 30 dk icinde tekrar konum/ag istegi yapilmaz,
  /// ayni anda gelen cagrilar tek istegi paylasir.
  static Future<WeatherForecast?> getForecast() {
    final c = cached;
    if (c != null) return Future.value(c);
    return _inflight ??= _fetch().then((f) {
      if (f != null) {
        _cache = f;
        _cacheAt = DateTime.now();
      }
      return f ?? _cache;
    }).whenComplete(() => _inflight = null);
  }

  static Future<WeatherForecast?> _fetch() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&hourly=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&current=relative_humidity_2m&timezone=auto');
      
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final hourlyTimes = data['hourly']['time'] as List;
        final hourlyTemps = data['hourly']['temperature_2m'] as List;
        final hourlyCodes = data['hourly']['weather_code'] as List;

        final dailyTimes = data['daily']['time'] as List;
        final dailyMaxTemps = data['daily']['temperature_2m_max'] as List;
        final dailyMinTemps = data['daily']['temperature_2m_min'] as List;
        final dailyCodes = data['daily']['weather_code'] as List;

        List<DailyWeather> dailyList = [];

        for (int i = 0; i < dailyTimes.length; i++) {
          final date = DateTime.parse(dailyTimes[i]);
          final maxT = (dailyMaxTemps[i] as num).toDouble();
          final minT = (dailyMinTemps[i] as num).toDouble();
          final dCode = dailyCodes[i] as int;
          final dWmo = _mapWmoCode(dCode);

          // O güne ait saatlik verileri filtrele
          List<HourlyWeather> dayHourly = [];
          for (int j = 0; j < hourlyTimes.length; j++) {
            final hTime = DateTime.parse(hourlyTimes[j]);
            if (hTime.year == date.year && hTime.month == date.month && hTime.day == date.day) {
              final hCode = hourlyCodes[j] as int;
              dayHourly.add(HourlyWeather(
                time: hTime,
                temperature: (hourlyTemps[j] as num).toDouble(),
                weatherCode: hCode,
                iconEmoji: _mapWmoCode(hCode)['icon']!,
              ));
            }
          }

          dailyList.add(DailyWeather(
            date: date,
            maxTemp: maxT,
            minTemp: minT,
            weatherCode: dCode,
            description: dWmo['description']!,
            iconEmoji: dWmo['icon']!,
            hourly: dayHourly,
          ));
        }

        final current = data['current'];
        final hum = current is Map ? current['relative_humidity_2m'] : null;
        final elev = data['elevation'];
        return WeatherForecast(
          daily: dailyList,
          humidity: hum is num ? hum.round() : null,
          elevation: elev is num ? elev.toDouble() : null,
        );
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
    }
    return null;
  }

  static Map<String, String> _mapWmoCode(int code) {
    if (code == 0) {
      return {'description': 'Açık', 'icon': '☀️'};
    } else if (code == 1 || code == 2 || code == 3) {
      return {'description': 'Parçalı Bulutlu', 'icon': '⛅'};
    } else if (code == 45 || code == 48) {
      return {'description': 'Sisli', 'icon': '🌫️'};
    } else if (code >= 51 && code <= 67) {
      return {'description': 'Yağmurlu', 'icon': '🌧️'};
    } else if (code >= 71 && code <= 77) {
      return {'description': 'Karlı', 'icon': '❄️'};
    } else if (code >= 80 && code <= 82) {
      return {'description': 'Sağanak Yağış', 'icon': '🌦️'};
    } else if (code >= 85 && code <= 86) {
      return {'description': 'Kar Fırtınası', 'icon': '🌨️'};
    } else if (code >= 95 && code <= 99) {
      return {'description': 'Fırtına', 'icon': '⛈️'};
    }
    return {'description': 'Bilinmiyor', 'icon': '🌡️'};
  }
}
