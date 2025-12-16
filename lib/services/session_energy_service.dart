/// Service to manage session energy consumption per device
/// Keeps track of energy usage across screen navigation
/// Resets only when AC is turned off

class SessionEnergyService {
  // Singleton instance
  static final SessionEnergyService _instance = SessionEnergyService._internal();

  factory SessionEnergyService() {
    return _instance;
  }

  SessionEnergyService._internal();

  // Map to store session energy per device
  // Key: deviceId, Value: sessionEnergyKWh
  final Map<String, double> _sessionEnergyMap = {};

  // Map to store last power value per device (for calculating delta)
  final Map<String, double> _lastPowerWattMap = {};

  // Map to store last calculation time per device
  final Map<String, DateTime> _lastCalculationTimeMap = {};

  /// Get current session energy for a device
  double getSessionEnergy(String deviceId) {
    return _sessionEnergyMap[deviceId] ?? 0.0;
  }

  /// Update session energy for a device
  /// Returns updated energy value
  double updateSessionEnergy(String deviceId, double currentPowerWatts) {
    // Initialize if not exists
    if (!_sessionEnergyMap.containsKey(deviceId)) {
      _sessionEnergyMap[deviceId] = 0.0;
      _lastPowerWattMap[deviceId] = currentPowerWatts;
      _lastCalculationTimeMap[deviceId] = DateTime.now();
      return 0.0;
    }

    final now = DateTime.now();
    final lastTime = _lastCalculationTimeMap[deviceId] ?? now;

    // Calculate time difference in seconds
    final timeDiffSeconds = now.difference(lastTime).inMilliseconds / 1000;

    if (timeDiffSeconds > 0 && currentPowerWatts > 0) {
      // Energy = Power (kW) × Time (hours)
      final energyKWh = (currentPowerWatts / 1000) * (timeDiffSeconds / 3600);
      _sessionEnergyMap[deviceId] = (_sessionEnergyMap[deviceId] ?? 0.0) + energyKWh;
    }

    // Update last values
    _lastPowerWattMap[deviceId] = currentPowerWatts;
    _lastCalculationTimeMap[deviceId] = now;

    return _sessionEnergyMap[deviceId] ?? 0.0;
  }

  /// Reset session energy for a device (when AC is turned off)
  void resetSessionEnergy(String deviceId) {
    _sessionEnergyMap[deviceId] = 0.0;
    _lastPowerWattMap[deviceId] = 0.0;
    _lastCalculationTimeMap[deviceId] = DateTime.now();
  }

  /// Reset all sessions (rarely used)
  void resetAllSessions() {
    _sessionEnergyMap.clear();
    _lastPowerWattMap.clear();
    _lastCalculationTimeMap.clear();
  }

  /// Check if device has active session
  bool hasActiveSession(String deviceId) {
    return _sessionEnergyMap.containsKey(deviceId) && (_sessionEnergyMap[deviceId] ?? 0.0) > 0.0;
  }

  /// Get debug info
  Map<String, dynamic> getDebugInfo(String deviceId) {
    return {
      'deviceId': deviceId,
      'sessionEnergyKWh': getSessionEnergy(deviceId),
      'lastPowerWatt': _lastPowerWattMap[deviceId] ?? 0.0,
      'lastCalculationTime': _lastCalculationTimeMap[deviceId]?.toString() ?? 'N/A',
    };
  }
}
