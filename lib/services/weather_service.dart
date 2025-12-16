import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service lấy thông tin thời tiết từ API
/// Hỗ trợ OpenWeatherMap API (có thể thay bằng API khác)
class WeatherService {
  // ===== THAY ĐỔI CẤU HÌNH API Ở ĐÂY =====

  static const String _apiKey = 'a87fe1394765bcf38b8ebf26654608cf';

  // TODO: Thay đổi tọa độ theo vị trí
  static const double _defaultLat = 10.8231; // Vĩ độ HCM
  static const double _defaultLon = 106.6297; // Kinh độ HCM

  // Base URL của OpenWeatherMap API
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  // ===== KẾT THÚC CẤU HÌNH =====

  /// Lấy nhiệt độ ngoài trời từ API thời tiết
  ///
  /// Trả về nhiệt độ (°C) hoặc null nếu có lỗi
  ///
  /// Sử dụng:
  /// ```dart
  /// final temp = await WeatherService.fetchOutdoorTemperature();
  /// if (temp != null) {
  ///   print('Nhiệt độ ngoài trời: $temp°C');
  /// }
  /// ```
  static Future<double?> fetchOutdoorTemperature({
    double? lat,
    double? lon,
  }) async {
    try {
      // Sử dụng tọa độ mặc định nếu không truyền vào
      final latitude = lat ?? _defaultLat;
      final longitude = lon ?? _defaultLon;

      // Tạo URL với query parameters
      final url = Uri.parse(
        '$_baseUrl?lat=$latitude&lon=$longitude&appid=$_apiKey&units=metric&lang=vi',
      );

      print('>>> Đang gọi Weather API: $url');

      // Gọi API (timeout 10 giây)
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout khi gọi Weather API');
        },
      );

      print('>>> Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Lấy nhiệt độ từ response
        final temp = (data['main']['temp'] as num).toDouble();

        print('>>> Nhiệt độ ngoài trời: $temp°C');
        return temp;
      } else {
        print('>>> Lỗi API: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('>>> Lỗi khi lấy nhiệt độ: $e');
      return null;
    }
  }

  /// Lấy nhiệt độ MOCK (dùng khi chưa có API key thật)
  ///
  /// Hàm này trả về nhiệt độ giả lập ngẫu nhiên từ 25-35°C
  /// để test chức năng mà không cần API key
  ///
  /// **LƯU Ý**: Chỉ dùng để test, production nên dùng fetchOutdoorTemperature()
  static Future<double> fetchMockTemperature() async {
    // Giả lập delay khi gọi API
    await Future.delayed(const Duration(milliseconds: 500));

    // Trả về nhiệt độ ngẫu nhiên từ 25-35°C
    final mockTemp = 25.0 + (DateTime.now().millisecondsSinceEpoch % 10);
    print('>>> MOCK nhiệt độ ngoài trời: $mockTemp°C');

    return mockTemp;
  }

  /// Kiểm tra API key đã được cấu hình chưa
  static bool isApiConfigured() {
    return _apiKey != 'YOUR_API_KEY_HERE' && _apiKey.isNotEmpty && _apiKey.length > 10;
  }
}
