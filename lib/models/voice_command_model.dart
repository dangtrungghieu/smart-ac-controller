/// ========================================
/// VOICE COMMAND MODEL
/// ========================================
///
/// File này định nghĩa các model cho lệnh điều khiển giọng nói
library;

/// Loại hành động của lệnh giọng nói
enum VoiceCommandType {
  /// Bật/tắt máy lạnh
  powerControl,

  /// Tăng/giảm nhiệt độ
  temperatureControl,

  /// Lên lịch bật/tắt
  scheduleControl,

  /// Bật/tắt AutoOff
  autoOffControl,

  /// Không hiểu lệnh
  unknown,
}

/// Hành động bật/tắt
enum PowerAction {
  /// Bật máy lạnh
  turnOn,

  /// Tắt máy lạnh
  turnOff,
}

/// Hành động nhiệt độ
enum TemperatureAction {
  /// Tăng nhiệt độ (ấm hơn, bớt lạnh)
  increase,

  /// Giảm nhiệt độ (mát hơn, lạnh hơn)
  decrease,

  /// Đặt nhiệt độ cụ thể
  set,
}

/// Hành động AutoOff
enum AutoOffAction {
  /// Bật AutoOff
  enable,

  /// Tắt AutoOff
  disable,
}

/// Model chứa thông tin lệnh giọng nói đã phân tích
class VoiceCommand {
  /// Loại lệnh
  final VoiceCommandType type;

  /// Text gốc từ Speech-to-Text
  final String originalText;

  // ===== POWER CONTROL =====
  /// Hành động bật/tắt (nếu type = powerControl)
  final PowerAction? powerAction;

  // ===== TEMPERATURE CONTROL =====
  /// Hành động nhiệt độ (nếu type = temperatureControl)
  final TemperatureAction? temperatureAction;

  /// Số độ cần thay đổi (mặc định = 1)
  final int tempStep;

  /// Nhiệt độ mục tiêu (nếu action = set)
  final int? targetTemp;

  // ===== SCHEDULE CONTROL =====
  /// Lịch bật hay tắt (nếu type = scheduleControl)
  final bool? schedulePowerOn;

  /// Thứ trong tuần (1=Thứ 2, 2=Thứ 3, ..., 6=Thứ 7, 7=Chủ nhật)
  final int? scheduleDayOfWeek;

  /// Giờ (0-23)
  final int? scheduleHour;

  /// Phút (0-59)
  final int? scheduleMinute;

  // ===== AUTO OFF CONTROL =====
  /// Hành động AutoOff (nếu type = autoOffControl)
  final AutoOffAction? autoOffAction;

  /// Số phút AutoOff (tối đa 60 phút)
  final int? autoOffMinutes;

  /// Cảnh báo nếu thời gian > 60 phút
  final bool autoOffWarning;

  // ===== ERROR MESSAGE =====
  /// Thông báo lỗi (nếu type = unknown)
  final String? errorMessage;

  const VoiceCommand({
    required this.type,
    required this.originalText,
    this.powerAction,
    this.temperatureAction,
    this.tempStep = 1,
    this.targetTemp,
    this.schedulePowerOn,
    this.scheduleDayOfWeek,
    this.scheduleHour,
    this.scheduleMinute,
    this.autoOffAction,
    this.autoOffMinutes,
    this.autoOffWarning = false,
    this.errorMessage,
  });

  /// Tạo lệnh unknown
  factory VoiceCommand.unknown(String text, {String? error}) {
    return VoiceCommand(
      type: VoiceCommandType.unknown,
      originalText: text,
      errorMessage: error ?? 'Không hiểu lệnh: "$text" – vui lòng nói lại.',
    );
  }

  /// Tạo lệnh bật/tắt
  factory VoiceCommand.power({
    required String text,
    required PowerAction action,
  }) {
    return VoiceCommand(
      type: VoiceCommandType.powerControl,
      originalText: text,
      powerAction: action,
    );
  }

  /// Tạo lệnh nhiệt độ
  factory VoiceCommand.temperature({
    required String text,
    required TemperatureAction action,
    int step = 1,
  }) {
    return VoiceCommand(
      type: VoiceCommandType.temperatureControl,
      originalText: text,
      temperatureAction: action,
      tempStep: step,
    );
  }

  /// Tạo lệnh lịch
  factory VoiceCommand.schedule({
    required String text,
    required bool powerOn,
    required int dayOfWeek,
    required int hour,
    required int minute,
  }) {
    return VoiceCommand(
      type: VoiceCommandType.scheduleControl,
      originalText: text,
      schedulePowerOn: powerOn,
      scheduleDayOfWeek: dayOfWeek,
      scheduleHour: hour,
      scheduleMinute: minute,
    );
  }

  /// Tạo lệnh AutoOff
  factory VoiceCommand.autoOff({
    required String text,
    required AutoOffAction action,
    int? minutes,
    bool warning = false,
  }) {
    return VoiceCommand(
      type: VoiceCommandType.autoOffControl,
      originalText: text,
      autoOffAction: action,
      autoOffMinutes: minutes,
      autoOffWarning: warning,
    );
  }

  /// Lấy mô tả ngắn gọn của lệnh
  String getDescription() {
    switch (type) {
      case VoiceCommandType.powerControl:
        return powerAction == PowerAction.turnOn
            ? '🟢 Bật máy lạnh'
            : '🔴 Tắt máy lạnh';

      case VoiceCommandType.temperatureControl:
        if (temperatureAction == TemperatureAction.set) {
          return '🌡️ Đặt nhiệt độ ${targetTemp}°C';
        }
        final action = temperatureAction == TemperatureAction.increase
            ? 'Tăng'
            : 'Giảm';
        return '🌡️ $action nhiệt độ $tempStep°C';

      case VoiceCommandType.scheduleControl:
        final action = schedulePowerOn == true ? 'BẬT' : 'TẮT';
        final dayName = _getDayName(scheduleDayOfWeek!);
        final timeStr =
            '${scheduleHour!.toString().padLeft(2, '0')}:${scheduleMinute!.toString().padLeft(2, '0')}';
        return '⏰ Lịch $action máy lúc $timeStr $dayName';

      case VoiceCommandType.autoOffControl:
        if (autoOffAction == AutoOffAction.disable) {
          return '⏹️ Tắt AutoOff';
        }
        String warning = autoOffWarning ? ' ⚠️ Tốn điện!' : '';
        return '⏲️ Bật AutoOff sau ${autoOffMinutes}p$warning';

      case VoiceCommandType.unknown:
        return '❌ ${errorMessage ?? "Không hiểu lệnh"}';
    }
  }

  /// Lấy tên thứ trong tuần
  String _getDayName(int day) {
    switch (day) {
      case 1:
        return 'Thứ 2';
      case 2:
        return 'Thứ 3';
      case 3:
        return 'Thứ 4';
      case 4:
        return 'Thứ 5';
      case 5:
        return 'Thứ 6';
      case 6:
        return 'Thứ 7';
      case 7:
        return 'Chủ nhật';
      default:
        return 'Không xác định';
    }
  }

  @override
  String toString() {
    return 'VoiceCommand(type: $type, text: "$originalText", desc: "${getDescription()}")';
  }
}
