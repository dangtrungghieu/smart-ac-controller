/// Model để quản lý trạng thái điện năng của thiết bị
/// Lưu trên Firebase tại: status/{deviceId}/energy/
class DeviceEnergyStatus {
  // Điện năng tích lũy trong tháng (tính theo session)
  final double estimatedMonthlyEnergyKWh;

  // Chi phí điện tích lũy trong tháng
  final double estimatedMonthlyCost;

  // Timestamp bắt đầu tháng (để reset đầu tháng)
  final int monthStartTimestamp;

  // Giá điện hiện tại (VNĐ/kWh)
  final int electricityPrice;

  // Công suất định mức của máy (W)
  final int ratedPowerWatts;

  // Timestamp cập nhật lần cuối
  final int lastUpdated;

  // Session hiện tại (khi máy đang bật)
  final double currentSessionEnergyKWh;
  final int? sessionStartTimestamp;

  // Thống kê theo ngày
  final String todayDate; // Format: YYYY-MM-DD
  final int runtimeTodaySeconds; // Tổng thời gian chạy trong ngày (giây)
  final double dailyEnergyKWh; // Điện năng tiêu thụ trong ngày
  final double dailyCost; // Chi phí trong ngày

  // Tracking theo vùng tải trong ngày
  final int timeLowTodaySec; // Thời gian chạy ở tải thấp (<30%)
  final int timeMidTodaySec; // Thời gian chạy ở tải trung (30-70%)
  final int timeHighTodaySec; // Thời gian chạy ở tải cao (>70%)

  // Cảnh báo tải cao
  final int highLoadCurrentStreakSec; // Thời gian liên tục chạy tải >80%
  final int lastHighLoadWarningTimestamp; // Timestamp cảnh báo tải cao lần cuối

  DeviceEnergyStatus({
    required this.estimatedMonthlyEnergyKWh,
    required this.estimatedMonthlyCost,
    required this.monthStartTimestamp,
    this.electricityPrice = 3000, // Mặc định 3000 VNĐ/kWh
    this.ratedPowerWatts = 1100, // Mặc định 1100W cho máy 1.5HP
    required this.lastUpdated,
    this.currentSessionEnergyKWh = 0.0,
    this.sessionStartTimestamp,
    required this.todayDate,
    this.runtimeTodaySeconds = 0,
    this.dailyEnergyKWh = 0.0,
    this.dailyCost = 0.0,
    this.timeLowTodaySec = 0,
    this.timeMidTodaySec = 0,
    this.timeHighTodaySec = 0,
    this.highLoadCurrentStreakSec = 0,
    this.lastHighLoadWarningTimestamp = 0,
  });

  /// Tạo instance mới với giá trị ban đầu
  factory DeviceEnergyStatus.initial({
    int electricityPrice = 3000,
    int ratedPowerWatts = 1100,
  }) {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final todayDate = _formatDate(now);

    return DeviceEnergyStatus(
      estimatedMonthlyEnergyKWh: 0,
      estimatedMonthlyCost: 0,
      monthStartTimestamp: nowMs,
      electricityPrice: electricityPrice,
      ratedPowerWatts: ratedPowerWatts,
      lastUpdated: nowMs,
      currentSessionEnergyKWh: 0.0,
      sessionStartTimestamp: null,
      todayDate: todayDate,
      runtimeTodaySeconds: 0,
      dailyEnergyKWh: 0.0,
      dailyCost: 0.0,
      timeLowTodaySec: 0,
      timeMidTodaySec: 0,
      timeHighTodaySec: 0,
      highLoadCurrentStreakSec: 0,
      lastHighLoadWarningTimestamp: 0,
    );
  }

  /// Format date to YYYY-MM-DD
  static String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parse từ Firebase JSON
  factory DeviceEnergyStatus.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return DeviceEnergyStatus(
      estimatedMonthlyEnergyKWh: (json['estimatedMonthlyEnergyKWh'] ?? 0).toDouble(),
      estimatedMonthlyCost: (json['estimatedMonthlyCost'] ?? 0).toDouble(),
      monthStartTimestamp: json['monthStartTimestamp'] ?? now.millisecondsSinceEpoch,
      electricityPrice: json['electricityPrice'] ?? 3000,
      ratedPowerWatts: json['ratedPowerWatts'] ?? 1100,
      lastUpdated: json['lastUpdated'] ?? now.millisecondsSinceEpoch,
      currentSessionEnergyKWh: (json['currentSessionEnergyKWh'] ?? 0).toDouble(),
      sessionStartTimestamp: json['sessionStartTimestamp'],
      todayDate: json['todayDate'] ?? _formatDate(now),
      runtimeTodaySeconds: json['runtimeTodaySeconds'] ?? 0,
      dailyEnergyKWh: (json['dailyEnergyKWh'] ?? 0).toDouble(),
      dailyCost: (json['dailyCost'] ?? 0).toDouble(),
      timeLowTodaySec: json['timeLowTodaySec'] ?? 0,
      timeMidTodaySec: json['timeMidTodaySec'] ?? 0,
      timeHighTodaySec: json['timeHighTodaySec'] ?? 0,
      highLoadCurrentStreakSec: json['highLoadCurrentStreakSec'] ?? 0,
      lastHighLoadWarningTimestamp: json['lastHighLoadWarningTimestamp'] ?? 0,
    );
  }

  /// Convert sang JSON để lưu Firebase
  Map<String, dynamic> toJson() {
    return {
      'estimatedMonthlyEnergyKWh': estimatedMonthlyEnergyKWh,
      'estimatedMonthlyCost': estimatedMonthlyCost,
      'monthStartTimestamp': monthStartTimestamp,
      'electricityPrice': electricityPrice,
      'ratedPowerWatts': ratedPowerWatts,
      'lastUpdated': lastUpdated,
      'currentSessionEnergyKWh': currentSessionEnergyKWh,
      'sessionStartTimestamp': sessionStartTimestamp,
      'todayDate': todayDate,
      'runtimeTodaySeconds': runtimeTodaySeconds,
      'dailyEnergyKWh': dailyEnergyKWh,
      'dailyCost': dailyCost,
      'timeLowTodaySec': timeLowTodaySec,
      'timeMidTodaySec': timeMidTodaySec,
      'timeHighTodaySec': timeHighTodaySec,
      'highLoadCurrentStreakSec': highLoadCurrentStreakSec,
      'lastHighLoadWarningTimestamp': lastHighLoadWarningTimestamp,
    };
  }

  /// Copy với các giá trị mới
  DeviceEnergyStatus copyWith({
    double? estimatedMonthlyEnergyKWh,
    double? estimatedMonthlyCost,
    int? monthStartTimestamp,
    int? electricityPrice,
    int? ratedPowerWatts,
    int? lastUpdated,
    double? currentSessionEnergyKWh,
    int? sessionStartTimestamp,
    String? todayDate,
    int? runtimeTodaySeconds,
    double? dailyEnergyKWh,
    double? dailyCost,
    int? timeLowTodaySec,
    int? timeMidTodaySec,
    int? timeHighTodaySec,
    int? highLoadCurrentStreakSec,
    int? lastHighLoadWarningTimestamp,
  }) {
    return DeviceEnergyStatus(
      estimatedMonthlyEnergyKWh: estimatedMonthlyEnergyKWh ?? this.estimatedMonthlyEnergyKWh,
      estimatedMonthlyCost: estimatedMonthlyCost ?? this.estimatedMonthlyCost,
      monthStartTimestamp: monthStartTimestamp ?? this.monthStartTimestamp,
      electricityPrice: electricityPrice ?? this.electricityPrice,
      ratedPowerWatts: ratedPowerWatts ?? this.ratedPowerWatts,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      currentSessionEnergyKWh: currentSessionEnergyKWh ?? this.currentSessionEnergyKWh,
      sessionStartTimestamp: sessionStartTimestamp ?? this.sessionStartTimestamp,
      todayDate: todayDate ?? this.todayDate,
      runtimeTodaySeconds: runtimeTodaySeconds ?? this.runtimeTodaySeconds,
      dailyEnergyKWh: dailyEnergyKWh ?? this.dailyEnergyKWh,
      dailyCost: dailyCost ?? this.dailyCost,
      timeLowTodaySec: timeLowTodaySec ?? this.timeLowTodaySec,
      timeMidTodaySec: timeMidTodaySec ?? this.timeMidTodaySec,
      timeHighTodaySec: timeHighTodaySec ?? this.timeHighTodaySec,
      highLoadCurrentStreakSec: highLoadCurrentStreakSec ?? this.highLoadCurrentStreakSec,
      lastHighLoadWarningTimestamp: lastHighLoadWarningTimestamp ?? this.lastHighLoadWarningTimestamp,
    );
  }

  /// Kiểm tra xem đã sang tháng mới chưa
  bool shouldResetForNewMonth() {
    final monthStart = DateTime.fromMillisecondsSinceEpoch(monthStartTimestamp);
    final now = DateTime.now();

    return now.year != monthStart.year || now.month != monthStart.month;
  }

  /// Kiểm tra xem đã sang ngày mới chưa
  bool shouldResetForNewDay() {
    final today = DeviceEnergyStatus._formatDate(DateTime.now());
    return today != todayDate;
  }

  @override
  String toString() {
    return 'DeviceEnergyStatus('
        'monthly: ${estimatedMonthlyEnergyKWh.toStringAsFixed(2)} kWh, '
        'daily: ${dailyEnergyKWh.toStringAsFixed(2)} kWh, '
        'runtime: ${(runtimeTodaySeconds / 3600).toStringAsFixed(1)} h)';
  }
}
