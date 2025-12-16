import '../utils/sensor_calibration.dart';

/// Enum định nghĩa các hành động gợi ý điều chỉnh nhiệt độ
enum TempSuggestionAction {
  /// Gợi ý tăng nhiệt độ (để tiết kiệm điện hoặc ấm hơn)
  increase,

  /// Gợi ý giảm nhiệt độ (để mát hơn)
  decrease,

  /// Nhiệt độ đang ổn, giữ nguyên
  keep,

  /// Gợi ý TẮT máy lạnh (không cần thiết)
  turnOff,
}

/// Model chứa thông tin gợi ý điều chỉnh nhiệt độ
class TempSuggestion {
  /// Hành động được gợi ý (tăng/giảm/giữ nguyên/tắt)
  final TempSuggestionAction action;

  /// Nhiệt độ hiện tại đang cài trên máy lạnh (°C)
  final int currentSetTemp;

  /// Nhiệt độ được gợi ý để cài (°C)
  final int suggestedTemp;

  /// Nhiệt độ thực tế (ngoài trời) (°C)
  final double realTemp;

  /// Nhiệt độ phòng hiện tại từ sensor (°C)
  final double roomTemp;

  /// Nội dung gợi ý hiển thị cho người dùng
  final String message;

  /// Icon hiển thị tương ứng với gợi ý
  final String icon;

  /// Lý do gợi ý (giải thích chi tiết)
  final String reason;

  /// Mức độ ưu tiên (1-5, càng cao càng quan trọng)
  final int priority;

  /// Tiết kiệm điện ước tính (%)
  final int energySaving;

  TempSuggestion({
    required this.action,
    required this.currentSetTemp,
    required this.suggestedTemp,
    required this.realTemp,
    required this.roomTemp,
    required this.message,
    required this.icon,
    required this.reason,
    this.priority = 3,
    this.energySaving = 0,
  });

  /// Kiểm tra xem có nên hiển thị gợi ý không
  bool get shouldShow => action != TempSuggestionAction.keep;

  /// Số độ thay đổi (âm = giảm, dương = tăng)
  int get tempDelta => suggestedTemp - currentSetTemp;
}

/// Service tính toán gợi ý điều chỉnh nhiệt độ dựa trên các mô hình khoa học
///
/// Sử dụng:
/// - Humidex (Canadian method) để tính cảm giác nhiệt độ trong phòng
/// - Vùng thoải mái cố định (ASHRAE 55 PMV-PPD) cho phòng có điều hòa
/// - Heuristics tiết kiệm điện (6-10% mỗi độ tăng setpoint)
class TempSuggestionService {
  // ========================================
  // CONSTANTS - THERMAL COMFORT (ASHRAE 55)
  // ========================================

  /// Vùng nhiệt độ thoải mái cho phòng có điều hòa (theo ASHRAE 55-2020)
  /// Đây là nhiệt độ CẢM GIÁC (Humidex), không phải nhiệt độ thực
  /// Phù hợp với khí hậu nhiệt đới Việt Nam và người Việt Nam
  ///
  /// Dưới 24°C = hơi lạnh, Trên 28°C = hơi nóng
  /// Vùng lý tưởng: 25-27°C
  static const double _minComfortFeelsLike = 24.0;
  static const double _maxComfortFeelsLike = 28.0;

  // ========================================
  // CONSTANTS - ENERGY SAVING
  // ========================================

  /// Tiết kiệm điện trung bình khi tăng setpoint 1°C (theo nghiên cứu: 6-10%)
  static const double _energySavingPerDegree = 8.0;
  static const double _maxEnergySaving = 30.0;

  // ========================================
  // HEAT INDEX (ROTHFUSZ REGRESSION)
  // ========================================

  /// Tính Heat Index (cảm giác nhiệt độ) sử dụng SensorCalibration
  ///
  /// Sử dụng hàm từ SensorCalibration.calculateHeatIndex() với Hệ số Trọng số K
  /// để đảm bảo cảm giác nhiệt độ chính xác hơn khi có thông tin nhiệt độ ngoài trời
  ///
  /// [tempC] Nhiệt độ trong phòng (°C)
  /// [humidity] Độ ẩm trong phòng (%)
  /// [outdoorTemp] Nhiệt độ ngoài trời (°C) - để tính hệ số K
  static double _calculateFeelsLike(double tempC, double humidity, {double? outdoorTemp}) {
    // Sử dụng hàm Heat Index từ SensorCalibration với outdoorTemp
    final heatIndex = SensorCalibration.calculateHeatIndex(tempC, humidity, outdoorTemp: outdoorTemp);
    return heatIndex ?? tempC;
  }

  // ========================================
  // THERMAL COMFORT ZONE (Fixed for Air-Conditioned Rooms)
  // ========================================

  /// Lấy vùng thoải mái dựa trên NHIỆT ĐỘ CẢM GIÁC trong phòng
  ///
  /// Khác với Adaptive Comfort Model (dùng cho tòa nhà không điều hòa),
  /// phòng có điều hòa nên dùng vùng thoải mái CỐ ĐỊNH theo ASHRAE 55-2020
  /// cho không gian có điều hòa nhiệt độ.
  ///
  /// Vùng thoải mái: 24-28°C (Humidex/cảm giác nhiệt độ)
  /// Vùng lý tưởng: 25-27°C (Humidex/cảm giác nhiệt độ)
  ///
  /// Reference: ASHRAE Standard 55-2020, Section 5.3 (PMV-PPD Method for AC spaces)
  static ({double lower, double upper}) _getComfortBand() {
    return (
      lower: _minComfortFeelsLike,
      upper: _maxComfortFeelsLike,
    );
  }

  // ========================================
  // ENERGY SAVING ESTIMATION
  // ========================================

  /// Ước tính tiết kiệm điện khi tăng setpoint
  ///
  /// Nghiên cứu: Mỗi +1°C setpoint ≈ 6-10% tiết kiệm điện
  /// (DOE, ASHRAE, various studies on AC energy consumption)
  ///
  /// Công thức: saving% = (suggestedTemp - currentSetTemp) * 8%
  static int _estimateEnergySaving(int currentSetTemp, int suggestedTemp) {
    final delta = suggestedTemp - currentSetTemp;

    // Chỉ tính tiết kiệm khi TĂNG nhiệt độ (decrease energy use)
    if (delta <= 0) return 0;

    final saving = delta * _energySavingPerDegree;
    return saving.clamp(0, _maxEnergySaving).round();
  }

  // ========================================
  // TIME OF DAY
  // ========================================

  /// Lấy thời gian trong ngày
  static String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 11) return 'morning'; // Sáng
    if (hour >= 11 && hour < 14) return 'noon'; // Trưa
    if (hour >= 14 && hour < 18) return 'afternoon'; // Chiều
    if (hour >= 18 && hour < 22) return 'evening'; // Tối
    return 'night'; // Đêm (22h-6h)
  }

  // ========================================
  // PUBLIC API
  // ========================================

  /// Tính toán gợi ý điều chỉnh nhiệt độ dựa trên các mô hình khoa học
  ///
  /// Input:
  /// - realTemp: Nhiệt độ ngoài trời (°C) từ API
  /// - roomTemp: Nhiệt độ phòng (°C) từ sensor
  /// - roomHumidity: Độ ẩm phòng (%) từ sensor
  /// - acSetTemp: Nhiệt độ đang cài trên máy lạnh (°C)
  /// - isAcOn: Trạng thái máy lạnh (true = đang bật)
  ///
  /// Output: TempSuggestion với action, suggestedTemp, message, reason, energySaving
  static TempSuggestion calculateSuggestion({
    required double realTemp,
    required double roomTemp,
    required int acSetTemp,
    required bool isAcOn,
    double roomHumidity = 0,
  }) {
    // Tính toán các chỉ số
    // Truyền realTemp (nhiệt độ ngoài trời) vào để tính hệ số K
    final feelsLikeTemp = _calculateFeelsLike(roomTemp, roomHumidity, outdoorTemp: realTemp);
    final comfortBand = _getComfortBand();  // Dùng vùng thoải mái cố định cho phòng có điều hòa
    final timeOfDay = _getTimeOfDay();
    final isNight = timeOfDay == 'night';
    final isNoon = timeOfDay == 'noon';

    // Phân nhánh xử lý
    if (!isAcOn) {
      return _suggestForAcOff(
        roomTemp: roomTemp,
        realTemp: realTemp,
        feelsLikeTemp: feelsLikeTemp,
        acSetTemp: acSetTemp,
        comfortBand: comfortBand,
      );
    }

    return _suggestForAcOn(
      roomTemp: roomTemp,
      realTemp: realTemp,
      feelsLikeTemp: feelsLikeTemp,
      acSetTemp: acSetTemp,
      roomHumidity: roomHumidity,
      comfortBand: comfortBand,
      isNight: isNight,
      isNoon: isNoon,
    );
  }

  // ========================================
  // LOGIC: AC OFF
  // ========================================

  /// Gợi ý khi máy lạnh ĐANG TẮT
  static TempSuggestion _suggestForAcOff({
    required double roomTemp,
    required double realTemp,
    required double feelsLikeTemp,
    required int acSetTemp,
    required ({double lower, double upper}) comfortBand,
  }) {
    // Case 1: Phòng RẤT NÓNG (feels-like vượt comfort band nhiều)
    // → Gợi ý BẬT máy ngay
    if (feelsLikeTemp > comfortBand.upper + 3.0) {
      return TempSuggestion(
        action: TempSuggestionAction.decrease,
        currentSetTemp: acSetTemp,
        suggestedTemp: 25,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng rất nóng (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🔥',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C vượt vùng thoải mái. Gợi ý BẬT máy lạnh và cài 25°C',
        priority: 5,
        energySaving: 0,
      );
    }

    // Case 2: Phòng HƠI NÓNG (feels-like vượt comfort band vừa phải)
    // → Gợi ý BẬT máy
    if (feelsLikeTemp > comfortBand.upper + 1.5) {
      return TempSuggestion(
        action: TempSuggestionAction.decrease,
        currentSetTemp: acSetTemp,
        suggestedTemp: 26,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng hơi nóng (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🌡️',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C cao hơn vùng thoải mái. Gợi ý BẬT máy lạnh và cài 26°C',
        priority: 4,
        energySaving: 0,
      );
    }

    // Case 3: Phòng THOẢI MÁI
    // → Không cần bật máy
    return TempSuggestion(
      action: TempSuggestionAction.keep,
      currentSetTemp: acSetTemp,
      suggestedTemp: acSetTemp,
      realTemp: realTemp,
      roomTemp: roomTemp,
      message: 'Nhiệt độ phòng thoải mái',
      icon: '😊',
      reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C trong vùng thoải mái. Không cần bật máy lạnh',
      priority: 1,
      energySaving: 100,
    );
  }

  // ========================================
  // LOGIC: AC ON
  // ========================================

  /// Gợi ý khi máy lạnh ĐANG BẬT
  static TempSuggestion _suggestForAcOn({
    required double roomTemp,
    required double realTemp,
    required double feelsLikeTemp,
    required int acSetTemp,
    required double roomHumidity,
    required ({double lower, double upper}) comfortBand,
    required bool isNight,
    required bool isNoon,
  }) {
    // ========================================
    // PRIORITY 1: SPECIAL CASES (SAFETY & ENERGY)
    // ========================================

    // Case 1A: Phòng QUÁ LẠNH (< 22°C) - nguy cơ sức khỏe
    // → Gợi ý TẮT hoặc TĂNG mạnh
    if (roomTemp < 22.0) {
      if (acSetTemp < 24) {
        return TempSuggestion(
          action: TempSuggestionAction.turnOff,
          currentSetTemp: acSetTemp,
          suggestedTemp: 0,
          realTemp: realTemp,
          roomTemp: roomTemp,
          message: 'Phòng quá lạnh (${feelsLikeTemp.toStringAsFixed(1)}°C)',
          icon: '❄️',
          reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C thấp hơn ngưỡng an toàn. Gợi ý TẮT máy lạnh',
          priority: 5,
          energySaving: 100,
        );
      }


      final newTemp = (acSetTemp + 2).clamp(24, 30);
      return TempSuggestion(
        action: TempSuggestionAction.increase,
        currentSetTemp: acSetTemp,
        suggestedTemp: newTemp,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng lạnh (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🧊',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C quá thấp. Gợi ý TĂNG 2°C (lên $newTemp°C) để ấm hơn và tiết kiệm điện',
        priority: 4,
        energySaving: _estimateEnergySaving(acSetTemp, newTemp),
      );
    }

    // Case 1B: ĐÊM KHUYA + Phòng đã MÁT (< 24°C)
    // → Gợi ý TẮT để tiết kiệm điện
    if (isNight && roomTemp < 24.0 && feelsLikeTemp <= comfortBand.upper) {
      return TempSuggestion(
        action: TempSuggestionAction.turnOff,
        currentSetTemp: acSetTemp,
        suggestedTemp: 0,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Đêm khuya và phòng đã mát (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🌙',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C đủ mát để ngủ. Gợi ý TẮT máy lạnh để tiết kiệm điện',
        priority: 4,
        energySaving: 100,
      );
    }

    // Case 1C: NGOÀI TRỜI MÁT (< 26°C) + Phòng đã MÁT (< 25°C) + KHÔNG PHẢI TRƯA
    // → Gợi ý TẮT, có thể mở cửa sổ
    if (realTemp > 0 && realTemp < 26.0 && roomTemp < 25.0 && !isNoon) {
      return TempSuggestion(
        action: TempSuggestionAction.turnOff,
        currentSetTemp: acSetTemp,
        suggestedTemp: 0,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Trời mát (${realTemp.toStringAsFixed(1)}°C), phòng mát rồi',
        icon: '🌤️',
        reason: 'Ngoài trời và trong phòng đều mát. Gợi ý TẮT máy lạnh và mở cửa sổ để tiết kiệm điện',
        priority: 3,
        energySaving: 100,
      );
    }

    // ========================================
    // PRIORITY 2: ADAPTIVE COMFORT MODEL
    // ========================================

    // Case 2A: Feels-like VƯỢT COMFORT BAND (quá nóng)
    // → Gợi ý GIẢM nhiệt độ
    if (feelsLikeTemp > comfortBand.upper + 2.0) {
      // Quá nóng → Giảm mạnh
      final newTemp = (acSetTemp - 3).clamp(20, 28);
      return TempSuggestion(
        action: TempSuggestionAction.decrease,
        currentSetTemp: acSetTemp,
        suggestedTemp: newTemp,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng rất nóng (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🔥',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C vượt vùng thoải mái ${comfortBand.upper.toStringAsFixed(1)}°C. Gợi ý GIẢM MẠNH xuống $newTemp°C',
        priority: 5,
        energySaving: 0,
      );
    }

    if (feelsLikeTemp > comfortBand.upper + 0.5 && acSetTemp > 23) {
      // Hơi nóng → Giảm vừa
      final newTemp = (acSetTemp - 2).clamp(20, 28);
      return TempSuggestion(
        action: TempSuggestionAction.decrease,
        currentSetTemp: acSetTemp,
        suggestedTemp: newTemp,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng nóng (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🌡️',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C cao hơn vùng thoải mái. Gợi ý GIẢM 2°C xuống $newTemp°C',
        priority: 4,
        energySaving: 0,
      );
    }

    // Case 2B: Feels-like DƯỚI COMFORT BAND (quá lạnh/mát)
    // → Gợi ý TĂNG nhiệt độ (tiết kiệm điện)
    if (feelsLikeTemp < comfortBand.lower - 1.0 && acSetTemp < 28) {
      // Quá mát → Tăng nhiều
      final newTemp = (acSetTemp + 2).clamp(20, 28);
      final saving = _estimateEnergySaving(acSetTemp, newTemp);
      return TempSuggestion(
        action: TempSuggestionAction.increase,
        currentSetTemp: acSetTemp,
        suggestedTemp: newTemp,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng đã mát (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '💡',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C thấp hơn vùng thoải mái. Gợi ý TĂNG 2°C lên $newTemp°C để tiết kiệm ~$saving% điện',
        priority: 3,
        energySaving: saving,
      );
    }

    if (feelsLikeTemp < comfortBand.lower && acSetTemp < 27) {
      // Hơi mát → Tăng nhẹ
      final newTemp = (acSetTemp + 1).clamp(20, 28);
      final saving = _estimateEnergySaving(acSetTemp, newTemp);
      return TempSuggestion(
        action: TempSuggestionAction.increase,
        currentSetTemp: acSetTemp,
        suggestedTemp: newTemp,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Phòng mát vừa (${feelsLikeTemp.toStringAsFixed(1)}°C)',
        icon: '🌙',
        reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C. Gợi ý TĂNG 1°C lên $newTemp°C để tiết kiệm ~$saving% điện mà vẫn thoải mái',
        priority: 2,
        energySaving: saving,
      );
    }

    // ========================================
    // PRIORITY 3: TRONG VÙNG THOẢI MÁI
    // ========================================

    // Case 3A: Trong comfort band nhưng TRƯA NẮNG NÓNG + setpoint cao
    // → Gợi ý giảm nhẹ để thoải mái hơn
    if (isNoon && realTemp > 33.0 && acSetTemp > 26) {
      return TempSuggestion(
        action: TempSuggestionAction.decrease,
        currentSetTemp: acSetTemp,
        suggestedTemp: 25,
        realTemp: realTemp,
        roomTemp: roomTemp,
        message: 'Trưa nắng nóng (${realTemp.toStringAsFixed(1)}°C ngoài trời)',
        icon: '☀️',
        reason: 'Trời nắng gắt. Gợi ý GIẢM xuống 25°C để thoải mái hơn',
        priority: 3,
        energySaving: 0,
      );
    }

    // Case 3B: NHIỆT ĐỘ TỐI ƯU - giữ nguyên
    return TempSuggestion(
      action: TempSuggestionAction.keep,
      currentSetTemp: acSetTemp,
      suggestedTemp: acSetTemp,
      realTemp: realTemp,
      roomTemp: roomTemp,
      message: 'Nhiệt độ lý tưởng',
      icon: '✅',
      reason: 'Cảm giác nhiệt độ ${feelsLikeTemp.toStringAsFixed(1)}°C nằm trong vùng thoải mái (${comfortBand.lower.toStringAsFixed(1)}-${comfortBand.upper.toStringAsFixed(1)}°C). Không cần điều chỉnh',
      priority: 1,
      energySaving: 0,
    );
  }
}
