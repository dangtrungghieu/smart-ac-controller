/// Utility class để hiệu chỉnh dữ liệu cảm biến DHT22
/// DHT22 có sai số:
/// - Nhiệt độ: ±0.5°C đến ±2°C (thường thấp hơn thực tế)
/// - Độ ẩm: ±2% đến ±5% (có thể cao hoặc thấp hơn thực tế)
class SensorCalibration {
  // ===== CẤU HÌNH HIỆU CHỈNH =====
  // Bạn có thể điều chỉnh các giá trị này dựa trên phép đo thực tế

  /// Độ lệch nhiệt độ (temperature offset)
  /// - Giá trị dương: cảm biến đo thấp hơn thực tế
  /// - Giá trị âm: cảm biến đo cao hơn thực tế
  static const double temperatureOffset = -3.0;

  /// Hệ số nhân nhiệt độ (temperature scale factor)
  /// Mặc định = 1.0 (không scale)
  static const double temperatureScale = 1.0;

  /// Độ lệch độ ẩm (humidity offset)
  /// - Giá trị dương: cảm biến đo thấp hơn thực tế
  /// - Giá trị âm: cảm biến đo cao hơn thực tế
  static const double humidityOffset = 10.0;

  /// Hệ số nhân độ ẩm (humidity scale factor)
  /// Mặc định = 1.0 (không scale)
  static const double humidityScale = 1.0;

  /// Giới hạn nhiệt độ hợp lệ (°C)
  static const double minValidTemp = -10.0;
  static const double maxValidTemp = 60.0;

  /// Giới hạn độ ẩm hợp lệ (%)
  static const double minValidHumidity = 0.0;
  static const double maxValidHumidity = 100.0;

  // ===== PHƯƠNG THỨC HIỆU CHỈNH =====

  /// Hiệu chỉnh giá trị nhiệt độ từ cảm biến DHT22
  ///
  /// Công thức: correctedTemp = (rawTemp * scale) + offset
  ///
  /// [rawTemp] Giá trị nhiệt độ thô từ cảm biến
  /// Returns nhiệt độ đã hiệu chỉnh, hoặc null nếu giá trị không hợp lệ
  static double? calibrateTemperature(double? rawTemp) {
    if (rawTemp == null || rawTemp == 0) return null;

    // Áp dụng công thức hiệu chỉnh
    double corrected = (rawTemp * temperatureScale) + temperatureOffset;

    // Kiểm tra giới hạn hợp lệ
    if (corrected < minValidTemp || corrected > maxValidTemp) {
      return null; // Giá trị ngoài phạm vi hợp lý
    }

    return corrected;
  }

  /// Hiệu chỉnh giá trị độ ẩm từ cảm biến DHT22
  ///
  /// Công thức: correctedHumidity = (rawHumidity * scale) + offset
  ///
  /// [rawHumidity] Giá trị độ ẩm thô từ cảm biến
  /// Returns độ ẩm đã hiệu chỉnh, hoặc null nếu giá trị không hợp lệ
  static double? calibrateHumidity(double? rawHumidity) {
    if (rawHumidity == null || rawHumidity == 0) return null;

    // Áp dụng công thức hiệu chỉnh
    double corrected = (rawHumidity * humidityScale) + humidityOffset;

    // Giới hạn trong khoảng 0-100%
    corrected = corrected.clamp(minValidHumidity, maxValidHumidity);

    return corrected;
  }

  // ===== PHƯƠNG THỨC TRỢ GIÚP =====

  /// Kiểm tra xem giá trị nhiệt độ có hợp lệ không
  static bool isValidTemperature(double? temp) {
    if (temp == null) return false;
    return temp >= minValidTemp && temp <= maxValidTemp;
  }

  /// Kiểm tra xem giá trị độ ẩm có hợp lệ không
  static bool isValidHumidity(double? humidity) {
    if (humidity == null) return false;
    return humidity >= minValidHumidity && humidity <= maxValidHumidity;
  }

  /// Format nhiệt độ để hiển thị
  /// [temp] Nhiệt độ đã hiệu chỉnh
  /// [decimals] Số chữ số thập phân (mặc định 1)
  /// Returns chuỗi định dạng, ví dụ: "27.5°C" hoặc "--" nếu không hợp lệ
  static String formatTemperature(double? temp, {int decimals = 1}) {
    if (temp == null || !isValidTemperature(temp)) return '--';
    return '${temp.toStringAsFixed(decimals)}°C';
  }

  /// Format độ ẩm để hiển thị
  /// [humidity] Độ ẩm đã hiệu chỉnh
  /// [decimals] Số chữ số thập phân (mặc định 0)
  /// Returns chuỗi định dạng, ví dụ: "65%" hoặc "--" nếu không hợp lệ
  static String formatHumidity(double? humidity, {int decimals = 0}) {
    if (humidity == null || !isValidHumidity(humidity)) return '--';
    return '${humidity.toStringAsFixed(decimals)}%';
  }

  // ===== PHƯƠNG THỨC NÂNG CAO =====

  /// Hiệu chỉnh cả nhiệt độ và độ ẩm cùng lúc
  ///
  /// Returns Map với keys: 'temperature' và 'humidity'
  static Map<String, double?> calibrateBoth({
    required double? rawTemp,
    required double? rawHumidity,
  }) {
    return {
      'temperature': calibrateTemperature(rawTemp),
      'humidity': calibrateHumidity(rawHumidity),
    };
  }

  /// Tính Humidex (Chỉ số cảm giác nhiệt độ) với Hệ số Trọng số K
  ///
  /// Sử dụng phương pháp lai (Weighted Factor Method) để tránh giá trị quá cao
  /// khi nhiệt độ ngoài trời mát nhưng trong phòng nóng.
  ///
  /// Công thức: T_feel = T_in + (Humidex_in - T_in) × K
  /// Trong đó:
  /// - T_in: Nhiệt độ trong phòng (°C)
  /// - Humidex_in: Chỉ số Humidex tính toán
  /// - K: Hệ số ảnh hưởng của độ ẩm (0.0 - 1.0), phụ thuộc nhiệt độ ngoài trời
  ///
  /// Hệ số K (ĐÃ ĐIỀU CHỈNH để sát thực tế hơn):
  /// - Ngoài trời MÁT (< 28°C): K = 0.2 (chỉ 20% ảnh hưởng độ ẩm)
  /// - Ngoài trời VỪA (28-32°C): K = 0.4-0.7 (ảnh hưởng trung bình)
  /// - Ngoài trời NÓNG (> 32°C): K = 0.9 (90% ảnh hưởng - nguy cơ sốc nhiệt cao)
  ///
  /// [temp] Nhiệt độ trong phòng đã hiệu chỉnh (°C)
  /// [humidity] Độ ẩm trong phòng đã hiệu chỉnh (%)
  /// [outdoorTemp] Nhiệt độ ngoài trời (°C) - mặc định null (không có thông tin)
  /// Returns Cảm giác nhiệt độ (°C), hoặc null nếu không áp dụng được
  static double? calculateHeatIndex(double? temp, double? humidity, {double? outdoorTemp}) {
    if (temp == null || humidity == null) return null;
    if (!isValidTemperature(temp) || !isValidHumidity(humidity)) return null;

    // Bước 1: Tính Humidex thuần túy (không điều chỉnh)
    // Tính điểm sương (dewpoint) sử dụng công thức Magnus-Tetens
    // e = áp suất hơi nước bão hòa (kPa)
    double e = 6.112 * _pow10(7.5 * temp / (237.7 + temp)) * (humidity / 100);

    // Công thức Humidex
    // Khi e < 10 kPa, Humidex không áp dụng
    double rawHumidex;
    if (e < 10) {
      rawHumidex = temp;
    } else {
      rawHumidex = temp + 0.5555 * (e - 10);
      // Giới hạn Humidex để tránh giá trị bất thường
      rawHumidex = rawHumidex.clamp(temp, temp + 15.0);
    }

    // Bước 2: Xác định hệ số K dựa trên nhiệt độ ngoài trời
    // ĐÃ ĐIỀU CHỈNH: Giảm hệ số K để T_feel sát thực tế hơn
    double k;

    if (outdoorTemp == null || outdoorTemp <= 0) {
      // Không có thông tin nhiệt độ ngoài trời
      // Sử dụng heuristic: Nếu temp < 26°C thì K = 0.2, ngược lại K = 0.6
      k = temp < 26.0 ? 0.2 : 0.6;
    } else if (outdoorTemp < 28.0) {
      // Ngoài trời MÁT (< 28°C)
      // Độ ẩm ít ảnh hưởng đến cảm giác nhiệt độ
      k = 0.2;
    } else if (outdoorTemp < 32.0) {
      // Ngoài trời VỪA PHẢI (28-32°C)
      // Tăng dần ảnh hưởng của độ ẩm theo nhiệt độ ngoài trời
      // K tăng tuyến tính từ 0.4 (tại 28°C) đến 0.7 (tại 32°C)
      k = 0.4 + (outdoorTemp - 28.0) / 4.0 * 0.3;
    } else {
      // Ngoài trời NÓNG (>= 32°C)
      // Độ ẩm ảnh hưởng rất lớn, nguy cơ sốc nhiệt
      k = 0.9;
    }

    // Bước 3: Tính cảm giác nhiệt độ cuối cùng với hệ số K
    // T_feel = T_in + (Humidex_in - T_in) × K
    double feelsLike = temp + (rawHumidex - temp) * k;

    return feelsLike;
  }

  /// Hàm hỗ trợ: Tính 10^x
  static double _pow10(double x) {
    return _exp(x * 2.302585093); // ln(10) ≈ 2.302585093
  }

  /// Hàm hỗ trợ: Tính e^x (xấp xỉ bằng chuỗi Taylor)
  static double _exp(double x) {
    // Sử dụng chuỗi Taylor: e^x = 1 + x + x²/2! + x³/3! + ...
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
      if (term.abs() < 1e-10) break; // Dừng khi số hạng đủ nhỏ
    }
    return result;
  }
}
