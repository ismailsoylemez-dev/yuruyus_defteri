import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temperature;
  final int weatherCode;
  final String description;
  final String message;
  final String iconEmoji;

  WeatherData({
    required this.temperature,
    required this.weatherCode,
    required this.description,
    required this.message,
    required this.iconEmoji,
  });
}

class WeatherService {
  static Future<WeatherData?> getCurrentWeather() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null; // Location services are disabled
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

      // Get location
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${position.latitude}&longitude=${position.longitude}&current=temperature_2m,weather_code');
      
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        final temp = (current['temperature_2m'] as num).toDouble();
        final code = current['weather_code'] as int;

        final wmo = _mapWmoCode(code);
        
        return WeatherData(
          temperature: temp,
          weatherCode: code,
          description: wmo['description']!,
          message: wmo['message']!,
          iconEmoji: wmo['icon']!,
        );
      }
    } catch (e) {
      debugPrint('Weather fetch error: $e');
    }
    return null;
  }

  static Map<String, String> _mapWmoCode(int code) {
    if (code == 0) {
      return {'description': 'Açık', 'icon': '☀️', 'message': 'Hava açık ve yürüyüş için harika! 👟'};
    } else if (code == 1 || code == 2 || code == 3) {
      return {'description': 'Parçalı Bulutlu', 'icon': '⛅', 'message': 'Yürüyüş için çok güzel bir gün! 🚶'};
    } else if (code == 45 || code == 48) {
      return {'description': 'Sisli', 'icon': '🌫️', 'message': 'Sisli havanın mistik atmosferinde yürümek gibisi yok.'};
    } else if (code >= 51 && code <= 67) {
      return {'description': 'Yağmurlu', 'icon': '🌧️', 'message': 'Yağmurluğunu al, yağmurda yürümek tazelendirir! 🌂'};
    } else if (code >= 71 && code <= 77) {
      return {'description': 'Karlı', 'icon': '❄️', 'message': 'Kar altında sıcacık giyinip dışarı çıkmanın tam vakti! 🧣'};
    } else if (code >= 80 && code <= 82) {
      return {'description': 'Sağanak Yağış', 'icon': '🌦️', 'message': 'Sağanak yağışa dikkat, adımlarını sağlam at! ☔'};
    } else if (code >= 85 && code <= 86) {
      return {'description': 'Kar Fırtınası', 'icon': '🌨️', 'message': 'Zorlu şartlarda sadece en güçlüler yürür! 🎿'};
    } else if (code >= 95 && code <= 99) {
      return {'description': 'Fırtına', 'icon': '⛈️', 'message': 'Fırtınalı hava! Belki bugün evde biraz egzersiz yapabilirsin. 🏠'};
    }
    return {'description': 'Bilinmiyor', 'icon': '🌡️', 'message': 'Hava nasıl olursa olsun, adımlarını atmaya devam et!'};
  }
}
