import 'dart:convert';
import 'dart:io';

/// A single weather reading destined for the clock face.
///
/// [temp] is a whole degree already in the requested unit (°C or °F). [code] is
/// the compact 0..6 condition bucket the firmware knows how to draw (see
/// [WeatherDatasource._bucketForWmo] and `BlePayloads.weather`).
class WeatherReading {
  final int temp;
  final int code;
  const WeatherReading({required this.temp, required this.code});
}

/// Fetches current weather for the phone's approximate location so the app can
/// push it to the (network-less) clock over BLE.
///
/// Deliberately dependency-free: it uses `dart:io`'s [HttpClient] rather than
/// pulling in `package:http`, and derives an approximate location from the
/// phone's IP (ipapi.co) rather than adding a geolocation plugin + a new runtime
/// permission. City-level accuracy is plenty for a temperature + condition. Both
/// calls are best-effort; any failure returns null and the caller simply skips
/// the weather push (the clock keeps its last value or shows nothing).
class WeatherDatasource {
  const WeatherDatasource();

  Future<WeatherReading?> fetch({required bool fahrenheit}) async {
    try {
      final loc = await _approxLocation();
      if (loc == null) return null;
      return await _currentWeather(
        lat: loc.$1,
        lon: loc.$2,
        fahrenheit: fahrenheit,
      );
    } catch (_) {
      return null; // network down, offline, timeout — weather is non-critical
    }
  }

  /// Approximate (lat, lon) from the phone's public IP. No permission prompt.
  Future<(double, double)?> _approxLocation() async {
    final json = await _getJson(Uri.parse('https://ipapi.co/json/'));
    if (json == null) return null;
    final lat = (json['latitude'] as num?)?.toDouble();
    final lon = (json['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  Future<WeatherReading?> _currentWeather({
    required double lat,
    required double lon,
    required bool fahrenheit,
  }) async {
    final unit = fahrenheit ? 'fahrenheit' : 'celsius';
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=${lat.toStringAsFixed(3)}'
      '&longitude=${lon.toStringAsFixed(3)}'
      '&current=temperature_2m,weather_code'
      '&temperature_unit=$unit',
    );
    final json = await _getJson(uri);
    final current = json?['current'] as Map<String, dynamic>?;
    if (current == null) return null;
    final tempNum = current['temperature_2m'] as num?;
    final wmo = (current['weather_code'] as num?)?.toInt();
    if (tempNum == null || wmo == null) return null;
    return WeatherReading(
      temp: tempNum.round(),
      code: _bucketForWmo(wmo),
    );
  }

  /// Collapse Open-Meteo's WMO weather code (0..99) into the firmware's 0..6
  /// icon buckets. Anything unrecognised falls back to "cloudy".
  static int _bucketForWmo(int wmo) {
    if (wmo == 0) return 0; // clear
    if (wmo == 1 || wmo == 2) return 1; // mainly clear / partly cloudy
    if (wmo == 3) return 2; // overcast
    if (wmo == 45 || wmo == 48) return 6; // fog
    if (wmo >= 95) return 5; // thunderstorm
    // Snow: 71-77 snowfall/grains, 85-86 snow showers.
    if ((wmo >= 71 && wmo <= 77) || wmo == 85 || wmo == 86) return 4;
    // Rain / drizzle / freezing / showers: 51-67, 80-82.
    if ((wmo >= 51 && wmo <= 67) || (wmo >= 80 && wmo <= 82)) return 3;
    return 2; // default: cloudy
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'WakeGuard/0.1');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } finally {
      client.close(force: true);
    }
  }
}
