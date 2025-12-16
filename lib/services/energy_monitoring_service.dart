import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_database/firebase_database.dart';
import '../models/device_energy_status.dart';

/// Service quản lý giám sát và tính toán điện năng tiêu thụ
/// Tích hợp Firebase để lưu trữ persistent data
class EnergyMonitoringService {
  // Singleton pattern
  static final EnergyMonitoringService _instance = EnergyMonitoringService._internal();

  factory EnergyMonitoringService() {
    return _instance;
  }

  EnergyMonitoringService._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // Debounce timer để tránh ghi Firebase quá nhiều - mỗi device có timer riêng
  final Map<String, Timer?> _debounceTimers = {};
  static const Duration _debounceDelay = Duration(seconds: 5);

  // Cache để giảm đọc Firebase - mỗi device có cache riêng
  final Map<String, DeviceEnergyStatus?> _statusCache = {};

  /// Load trạng thái điện năng từ Firebase
  Future<DeviceEnergyStatus?> loadEnergyStatus(String deviceId) async {
    try {
      // Kiểm tra cache trước
      if (_statusCache.containsKey(deviceId)) {
        return _statusCache[deviceId];
      }

      final snapshot = await _db.child('status/$deviceId/energy').get();

      if (!snapshot.exists) {
        return null;
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final status = DeviceEnergyStatus.fromJson(data);

      // Lưu cache
      _statusCache[deviceId] = status;

      return status;
    } catch (e) {
      print('❌ Error loading energy status for $deviceId: $e');
      return null;
    }
  }

  /// Khởi tạo trạng thái khi thiết bị được thêm vào lần đầu
  Future<void> initializeStatus({
    required String deviceId,
    int electricityPrice = 3000,
    int ratedPowerWatts = 1100,
  }) async {
    try {
      final status = DeviceEnergyStatus.initial(
        electricityPrice: electricityPrice,
        ratedPowerWatts: ratedPowerWatts,
      );

      await _db.child('status/$deviceId/energy').set(status.toJson());

      // Cập nhật cache
      _statusCache[deviceId] = status;

      print('✅ Initialized energy status for $deviceId');
    } catch (e) {
      print('❌ Error initializing status for $deviceId: $e');
      rethrow;
    }
  }

  /// Bắt đầu session mới (khi máy lạnh bật)
  Future<DeviceEnergyStatus?> startSession({
    required String deviceId,
    int? electricityPrice,
    int? ratedPowerWatts,
  }) async {
    try {
      // Load status hiện tại (từ cache hoặc Firebase)
      DeviceEnergyStatus? status = _statusCache[deviceId] ?? await loadEnergyStatus(deviceId);

      // Nếu chưa có → khởi tạo
      if (status == null) {
        await initializeStatus(
          deviceId: deviceId,
          electricityPrice: electricityPrice ?? 3000,
          ratedPowerWatts: ratedPowerWatts ?? 1100,
        );
        status = _statusCache[deviceId];
      }

      // Kiểm tra xem đã sang tháng mới chưa → reset tháng
      if (status!.shouldResetForNewMonth()) {
        print('📅 Resetting monthly stats for new month: $deviceId');
        status = DeviceEnergyStatus.initial(
          electricityPrice: electricityPrice ?? status.electricityPrice,
          ratedPowerWatts: ratedPowerWatts ?? status.ratedPowerWatts,
        );
      }

      // Kiểm tra xem đã sang ngày mới chưa → reset daily stats
      if (status.shouldResetForNewDay()) {
        print('🌅 Resetting daily stats for new day: $deviceId');
        final today = DateTime.now();
        final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        status = status.copyWith(
          todayDate: todayStr,
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

      // Kiểm tra xem đã có session đang chạy chưa
      if (status.sessionStartTimestamp != null) {
        print('🔄 Resuming existing session for $deviceId');

        // Tính thời gian đã trôi qua từ lần update cuối (app có thể đã tắt)
        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceLastUpdate = (now - status.lastUpdated) / 1000; // seconds

        // Nếu app tắt quá lâu (>1 phút), kết thúc session cũ và bắt đầu session mới
        if (timeSinceLastUpdate > 60) {
          final missedMinutes = timeSinceLastUpdate / 60;
          print('⚠️ App was closed for ${missedMinutes.toStringAsFixed(1)} minutes');
          print('⚠️ Ending old session and starting new session to prevent incorrect runtime calculation');

          // Kết thúc session cũ (SỬ DỤNG lastUpdated thay vì now để không tính thời gian app tắt)
          final sessionEnergyKWh = status.currentSessionEnergyKWh;
          final sessionCost = sessionEnergyKWh * status.electricityPrice;

          // Cộng vào tổng tháng
          final newMonthlyEnergyKWh = status.estimatedMonthlyEnergyKWh + sessionEnergyKWh;
          final newMonthlyCost = status.estimatedMonthlyCost + sessionCost;

          // Cộng vào tổng ngày (KHÔNG cộng thêm runtime vì đã được cập nhật ở lần update cuối)
          final newDailyEnergyKWh = status.dailyEnergyKWh + sessionEnergyKWh;
          final newDailyCost = status.dailyCost + sessionCost;

          // Reset session và BẮT ĐẦU SESSION MỚI
          status = status.copyWith(
            estimatedMonthlyEnergyKWh: newMonthlyEnergyKWh,
            estimatedMonthlyCost: newMonthlyCost,
            dailyEnergyKWh: newDailyEnergyKWh,
            dailyCost: newDailyCost,
            currentSessionEnergyKWh: 0.0,
            sessionStartTimestamp: now, // Bắt đầu session mới TỪ BÂY GIỜ
            lastUpdated: now,
          );

          _statusCache[deviceId] = status;
          await forceSaveEnergyStatus(deviceId, status);

          print('✅ Old session ended, new session started from now');
          return status;
        }

        // Session đang chạy và app không tắt lâu → return status hiện tại
        return status;
      }

      // Bắt đầu session mới (chỉ khi chưa có session)
      final now = DateTime.now().millisecondsSinceEpoch;
      status = status.copyWith(
        currentSessionEnergyKWh: 0.0,
        sessionStartTimestamp: now,
        lastUpdated: now,
      );

      // Cập nhật cache
      _statusCache[deviceId] = status;

      // Ghi Firebase ngay lập tức
      await forceSaveEnergyStatus(deviceId, status);

      print('▶️ Started new session for $deviceId');
      return status;
    } catch (e) {
      print('❌ Error starting session for $deviceId: $e');
      return null;
    }
  }

  /// Cập nhật session hiện tại (được gọi định kỳ khi máy đang chạy)
  Future<DeviceEnergyStatus?> updateSession({
    required String deviceId,
    required double currentPowerWatts,
    int? electricityPrice,
    int? ratedPowerWatts,
  }) async {
    try {
      // Load status hiện tại (từ cache hoặc Firebase)
      DeviceEnergyStatus? status = _statusCache[deviceId] ?? await loadEnergyStatus(deviceId);

      if (status == null || status.sessionStartTimestamp == null) {
        print('⚠️ No active session for $deviceId, starting new one');
        return await startSession(
          deviceId: deviceId,
          electricityPrice: electricityPrice,
          ratedPowerWatts: ratedPowerWatts,
        );
      }

      // Tính điện năng tiêu thụ TÍCH LŨY (incremental)
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastUpdateSec = (now - status.lastUpdated) / 1000; // seconds (double)

      // Điện năng tiêu thụ trong khoảng thời gian vừa qua
      final incrementalEnergyKWh = (currentPowerWatts * timeSinceLastUpdateSec) / (3600 * 1000);

      // Cộng vào tổng session (thay vì tính lại toàn bộ)
      final sessionEnergyKWh = status.currentSessionEnergyKWh + incrementalEnergyKWh;

      // Cập nhật giá điện và công suất định mức nếu có thay đổi
      final finalElectricityPrice = electricityPrice ?? status.electricityPrice;
      final finalRatedPowerWatts = ratedPowerWatts ?? status.ratedPowerWatts;

      // === TRACKING LOAD ZONES ===
      // Tính % tải hiện tại
      final loadPercent = calculateLoadPercent(currentPowerWatts, finalRatedPowerWatts.toDouble());

      // Thời gian từ lần update trước cho load tracking (integer seconds)
      final timeSinceLastUpdateInt = timeSinceLastUpdateSec.toInt();

      // === TÍCH LŨY THỜI GIAN CHẠY (runtime) ===
      // Cộng dồn runtime theo từng đợt update thay vì tính lại toàn bộ ở endSession
      int newRuntimeTodaySeconds = status.runtimeTodaySeconds + timeSinceLastUpdateInt;

      // Tích lũy vào vùng tải tương ứng
      int newTimeLowSec = status.timeLowTodaySec;
      int newTimeMidSec = status.timeMidTodaySec;
      int newTimeHighSec = status.timeHighTodaySec;
      int newHighLoadStreak = status.highLoadCurrentStreakSec;
      int newLastWarningTimestamp = status.lastHighLoadWarningTimestamp;

      if (loadPercent < 30) {
        newTimeLowSec += timeSinceLastUpdateInt;
        newHighLoadStreak = 0; // Reset streak nếu không còn high load
      } else if (loadPercent >= 30 && loadPercent <= 70) {
        newTimeMidSec += timeSinceLastUpdateInt;
        newHighLoadStreak = 0; // Reset streak nếu không còn high load
      } else {
        newTimeHighSec += timeSinceLastUpdateInt;

        // Nếu tải > 80% → tích lũy streak
        if (loadPercent > 80) {
          newHighLoadStreak += timeSinceLastUpdateInt;

          // Kiểm tra cảnh báo: streak > 30 phút (1800s) và chưa cảnh báo trong 1 giờ
          const warningThreshold = 1800; // 30 phút
          const warningCooldown = 3600000; // 1 giờ (ms)

          if (newHighLoadStreak >= warningThreshold) {
            final timeSinceLastWarning = now - status.lastHighLoadWarningTimestamp;

            if (timeSinceLastWarning >= warningCooldown) {
              // Trigger cảnh báo (log hoặc callback)
              print('⚠️ HIGH LOAD WARNING: $deviceId running >80% for ${newHighLoadStreak}s');
              newLastWarningTimestamp = now;
            }
          }
        } else {
          newHighLoadStreak = 0; // Reset nếu tải < 80%
        }
      }

      status = status.copyWith(
        currentSessionEnergyKWh: sessionEnergyKWh,
        electricityPrice: finalElectricityPrice,
        ratedPowerWatts: finalRatedPowerWatts,
        lastUpdated: now,
        runtimeTodaySeconds: newRuntimeTodaySeconds,
        timeLowTodaySec: newTimeLowSec,
        timeMidTodaySec: newTimeMidSec,
        timeHighTodaySec: newTimeHighSec,
        highLoadCurrentStreakSec: newHighLoadStreak,
        lastHighLoadWarningTimestamp: newLastWarningTimestamp,
      );

      // Cập nhật cache
      _statusCache[deviceId] = status;

      // Ghi Firebase với debounce
      _debouncedFirebaseUpdate(deviceId, status);

      return status;
    } catch (e) {
      print('❌ Error updating session for $deviceId: $e');
      return null;
    }
  }

  /// Kết thúc session (khi máy lạnh tắt) - Lưu vào tổng tháng
  Future<DeviceEnergyStatus?> endSession({
    required String deviceId,
    required double currentPowerWatts,
  }) async {
    try {
      // Load status hiện tại (từ cache hoặc Firebase)
      DeviceEnergyStatus? status = _statusCache[deviceId] ?? await loadEnergyStatus(deviceId);

      if (status == null || status.sessionStartTimestamp == null) {
        print('⚠️ No active session to end for $deviceId');
        return status;
      }

      // Lấy năng lượng session đã tích lũy (không tính lại từ đầu)
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastUpdateSec = (now - status.lastUpdated) / 1000;

      // Tính năng lượng còn lại từ lần update cuối đến bây giờ
      final finalEnergyIncrement = (currentPowerWatts * timeSinceLastUpdateSec) / (3600 * 1000);
      final sessionEnergyKWh = status.currentSessionEnergyKWh + finalEnergyIncrement;
      final sessionCost = sessionEnergyKWh * status.electricityPrice;

      // Cộng vào tổng tháng
      final newMonthlyEnergyKWh = status.estimatedMonthlyEnergyKWh + sessionEnergyKWh;
      final newMonthlyCost = status.estimatedMonthlyCost + sessionCost;

      // Cộng vào tổng ngày hôm nay
      // KHÔNG tính lại từ sessionStartTimestamp, chỉ cộng thời gian còn lại
      final finalRuntimeIncrement = timeSinceLastUpdateSec.toInt();
      final newRuntimeTodaySeconds = status.runtimeTodaySeconds + finalRuntimeIncrement;
      final newDailyEnergyKWh = status.dailyEnergyKWh + sessionEnergyKWh;
      final newDailyCost = status.dailyCost + sessionCost;

      // Reset session
      status = status.copyWith(
        estimatedMonthlyEnergyKWh: newMonthlyEnergyKWh,
        estimatedMonthlyCost: newMonthlyCost,
        currentSessionEnergyKWh: 0.0,
        sessionStartTimestamp: null,
        lastUpdated: now,
        runtimeTodaySeconds: newRuntimeTodaySeconds,
        dailyEnergyKWh: newDailyEnergyKWh,
        dailyCost: newDailyCost,
      );

      // Cập nhật cache
      _statusCache[deviceId] = status;

      // Force save ngay lập tức
      await forceSaveEnergyStatus(deviceId, status);

      print('⏹️ Ended session for $deviceId: +${sessionEnergyKWh.toStringAsFixed(3)} kWh, +${sessionCost.toStringAsFixed(0)} VNĐ, runtime: ${(newRuntimeTodaySeconds / 3600).toStringAsFixed(2)}h today');
      return status;
    } catch (e) {
      print('❌ Error ending session for $deviceId: $e');
      return null;
    }
  }

  /// Ghi Firebase với debounce để tránh ghi quá nhiều
  void _debouncedFirebaseUpdate(String deviceId, DeviceEnergyStatus status) {
    // Hủy timer cũ nếu có
    _debounceTimers[deviceId]?.cancel();

    print('⏳ [ENERGY_SVC] Debounce timer scheduled for $deviceId (${_debounceDelay.inSeconds}s delay)');

    // Tạo timer mới
    _debounceTimers[deviceId] = Timer(_debounceDelay, () async {
      try {
        print('💾 [ENERGY_SVC] Writing to Firebase: $deviceId');
        print('   Session: ${status.currentSessionEnergyKWh.toStringAsFixed(4)} kWh');
        print('   Runtime today: ${status.runtimeTodaySeconds}s');
        print('   Last updated: ${status.lastUpdated}');

        await _db.child('status/$deviceId/energy').set(status.toJson());
        print('✅ [ENERGY_SVC] Firebase write completed for $deviceId');
      } catch (e, stackTrace) {
        print('❌ [ENERGY_SVC] Error saving to Firebase: $e');
        print('   Stack trace: $stackTrace');
      }
    });
  }

  /// Force save ngay lập tức (không debounce)
  /// Dùng khi user thay đổi cấu hình hoặc khi app closing
  Future<void> forceSaveEnergyStatus(String deviceId, DeviceEnergyStatus status) async {
    try {
      // Cancel debounce timer nếu có
      _debounceTimers[deviceId]?.cancel();
      _debounceTimers[deviceId] = null;

      // Ghi ngay
      await _db.child('status/$deviceId/energy').set(status.toJson());

      // Cập nhật cache
      _statusCache[deviceId] = status;

      print('💾 Force saved energy status to Firebase for $deviceId');
    } catch (e) {
      print('❌ Error force saving energy status: $e');
      rethrow;
    }
  }

  /// Reset tháng (khi user muốn reset lại tính toán)
  Future<void> resetMonth({
    required String deviceId,
  }) async {
    try {
      final status = _statusCache[deviceId] ?? await loadEnergyStatus(deviceId);

      if (status == null) {
        await initializeStatus(deviceId: deviceId);
        return;
      }

      final newStatus = DeviceEnergyStatus.initial(
        electricityPrice: status.electricityPrice,
        ratedPowerWatts: status.ratedPowerWatts,
      );

      await forceSaveEnergyStatus(deviceId, newStatus);

      print('🔄 Reset monthly stats for $deviceId');
    } catch (e) {
      print('❌ Error resetting month: $e');
      rethrow;
    }
  }

  /// Cập nhật cấu hình (giá điện, công suất định mức)
  Future<void> updateConfiguration({
    required String deviceId,
    int? electricityPrice,
    int? ratedPowerWatts,
  }) async {
    try {
      final status = _statusCache[deviceId] ?? await loadEnergyStatus(deviceId);

      if (status == null) {
        print('⚠️ Cannot update config: device not initialized');
        return;
      }

      final newStatus = status.copyWith(
        electricityPrice: electricityPrice,
        ratedPowerWatts: ratedPowerWatts,
        lastUpdated: DateTime.now().millisecondsSinceEpoch,
      );

      // Recalculate monthly cost with new price
      if (electricityPrice != null) {
        final newCost = newStatus.estimatedMonthlyEnergyKWh * electricityPrice.toDouble();
        final updatedStatus = newStatus.copyWith(estimatedMonthlyCost: newCost);
        await forceSaveEnergyStatus(deviceId, updatedStatus);
      } else {
        await forceSaveEnergyStatus(deviceId, newStatus);
      }

      print('⚙️ Updated configuration for $deviceId');
    } catch (e) {
      print('❌ Error updating configuration: $e');
      rethrow;
    }
  }

  /// Clear cache cho device cụ thể
  void clearCache(String deviceId) {
    _statusCache.remove(deviceId);
    _debounceTimers[deviceId]?.cancel();
    _debounceTimers.remove(deviceId);
  }

  /// Clear tất cả cache
  void clearAllCache() {
    _statusCache.clear();
    for (final timer in _debounceTimers.values) {
      timer?.cancel();
    }
    _debounceTimers.clear();
  }

  /// Dispose service
  void dispose() {
    clearAllCache();
  }
}

// ===== PURE FUNCTIONS: TÍNH TOÁN ĐIỆN NĂNG =====

/// Tính % tải của máy lạnh
double calculateLoadPercent(double currentPowerWatts, double ratedPowerWatts) {
  if (ratedPowerWatts <= 0) return 0;
  return (currentPowerWatts / ratedPowerWatts) * 100;
}

/// Tính tốc độ tiêu thụ tiền (VNĐ/giờ)
double calculateCostPerHour(double currentPowerWatts, int electricityPrice) {
  return (currentPowerWatts / 1000) * electricityPrice;
}

/// Tính điện năng tiêu thụ trong tháng (kWh)
double calculateMonthlyEnergyKWh(double currentEnergyKWh, double baselineEnergyKWh) {
  return math.max(0.0, currentEnergyKWh - baselineEnergyKWh).toDouble();
}

/// Tính chi phí tích lũy trong tháng (VNĐ)
double calculateMonthlyCost(double monthlyEnergyKWh, int electricityPrice) {
  return monthlyEnergyKWh * electricityPrice;
}

// ===== CÔNG SUẤT AC (POWER TRIANGLE) =====

/// Tính Real Power (P, W) - Công suất thực
/// Công thức: P = V × I × PF
double calculateRealPower(double voltage, double current, double powerFactor) {
  return voltage * current * powerFactor;
}

/// Tính Apparent Power (S, VA) - Công suất biểu kiến
/// Công thức: S = V × I
double calculateApparentPower(double voltage, double current) {
  return voltage * current;
}

/// Tính Reactive Power (Q, VAR) - Công suất phản kháng
/// Công thức: Q = S × sqrt(1 - PF²)
double calculateReactivePower(double voltage, double current, double powerFactor) {
  final apparentPower = calculateApparentPower(voltage, current);
  final pfSquared = powerFactor * powerFactor;

  if (pfSquared >= 1.0) return 0; // Tránh lỗi sqrt âm

  return apparentPower * math.sqrt(1 - pfSquared);
}
