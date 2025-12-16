class ScheduleModel {
  final String scheduleId;
  final String deviceId;
  final String name;
  final String action; // 'powerOn', 'powerOff', 'tempUp', 'tempDown'
  final int? value; // Giá trị nhiệt độ cho tempUp/tempDown
  final String time; // Format: "HH:mm"
  final List<int> daysOfWeek; // 0 = CN, 1 = T2, ..., 6 = T7
  final bool enabled;
  final int? lastExecuted; // Timestamp lần thực hiện cuối
  final int createdAt;
  final int lastModified;

  ScheduleModel({
    required this.scheduleId,
    required this.deviceId,
    required this.name,
    required this.action,
    this.value,
    required this.time,
    required this.daysOfWeek,
    this.enabled = true,
    this.lastExecuted,
    required this.createdAt,
    required this.lastModified,
  });

  factory ScheduleModel.fromJson(String scheduleId, Map<String, dynamic> json) {
    return ScheduleModel(
      scheduleId: scheduleId,
      deviceId: json['deviceId'] ?? '',
      name: json['name'] ?? '',
      action: json['action'] ?? '',
      value: json['value'],
      time: json['time'] ?? '',
      daysOfWeek: json['daysOfWeek'] != null
          ? List<int>.from(json['daysOfWeek'])
          : [],
      enabled: json['enabled'] ?? true,
      lastExecuted: json['lastExecuted'],
      createdAt: json['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      lastModified: json['lastModified'] ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  // Alias cho fromJson
  factory ScheduleModel.fromMap(String scheduleId, Map<String, dynamic> map) {
    return ScheduleModel.fromJson(scheduleId, map);
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'name': name,
      'action': action,
      if (value != null) 'value': value,
      'time': time,
      'daysOfWeek': daysOfWeek,
      'enabled': enabled,
      if (lastExecuted != null) 'lastExecuted': lastExecuted,
      'createdAt': createdAt,
      'lastModified': lastModified,
    };
  }

  // Helper để lấy tên action
  String get actionName {
    switch (action) {
      case 'powerOn':
        return 'Bật máy';
      case 'powerOff':
        return 'Tắt máy';
      case 'tempUp':
        return 'Tăng nhiệt độ';
      case 'tempDown':
        return 'Giảm nhiệt độ';
      // Backward compatibility
      case 'power':
        return 'Bật/Tắt';
      default:
        return action;
    }
  }

  // Helper để format days
  String get daysText {
    if (daysOfWeek.length == 7) return 'Hàng ngày';
    if (daysOfWeek.isEmpty) return 'Không lặp lại';

    final dayNames = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    return daysOfWeek.map((day) => dayNames[day]).join(', ');
  }

  ScheduleModel copyWith({
    String? scheduleId,
    String? deviceId,
    String? name,
    String? action,
    int? value,
    String? time,
    List<int>? daysOfWeek,
    bool? enabled,
    int? lastExecuted,
    int? createdAt,
    int? lastModified,
  }) {
    return ScheduleModel(
      scheduleId: scheduleId ?? this.scheduleId,
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      action: action ?? this.action,
      value: value ?? this.value,
      time: time ?? this.time,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      enabled: enabled ?? this.enabled,
      lastExecuted: lastExecuted ?? this.lastExecuted,
      createdAt: createdAt ?? this.createdAt,
      lastModified: lastModified ?? this.lastModified,
    );
  }
}
