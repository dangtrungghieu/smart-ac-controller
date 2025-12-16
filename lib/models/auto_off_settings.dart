class AutoOffSettings {
  final bool enabled;
  final int delayMinutes; // 1-30 phút
  final int? lastPersonSeenAt; // Timestamp lần cuối thấy người

  AutoOffSettings({
    this.enabled = false,
    this.delayMinutes = 10,
    this.lastPersonSeenAt,
  });

  factory AutoOffSettings.fromJson(Map<String, dynamic> json) {
    return AutoOffSettings(
      enabled: json['enabled'] ?? false,
      delayMinutes: (json['delayMinutes'] ?? 10).clamp(1, 30),
      lastPersonSeenAt: json['lastPersonSeenAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'delayMinutes': delayMinutes,
      if (lastPersonSeenAt != null) 'lastPersonSeenAt': lastPersonSeenAt,
    };
  }

  AutoOffSettings copyWith({
    bool? enabled,
    int? delayMinutes,
    int? lastPersonSeenAt,
  }) {
    return AutoOffSettings(
      enabled: enabled ?? this.enabled,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      lastPersonSeenAt: lastPersonSeenAt ?? this.lastPersonSeenAt,
    );
  }

  // Helper: Kiểm tra đã đủ thời gian chờ chưa
  bool shouldTurnOff(int currentTimestamp) {
    if (!enabled || lastPersonSeenAt == null) return false;

    final elapsed = currentTimestamp - lastPersonSeenAt!;
    final elapsedMinutes = elapsed ~/ (60 * 1000); // Convert ms to minutes

    return elapsedMinutes >= delayMinutes;
  }
}
