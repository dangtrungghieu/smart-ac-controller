import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/schedule_model.dart';
import '../utils/constants.dart';

/// Service để kiểm tra và thực thi lịch tự động
/// Chạy background timer để kiểm tra các lịch đã đến giờ
class ScheduleExecutor {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  Timer? _checkTimer;
  bool _isRunning = false;
  String? _currentUserId;

  // Callback để gửi logs về UI
  Function(String)? onLog;

  void setLogCallback(Function(String) callback) {
    onLog = callback;
  }

  void _log(String message) {
    print(message);
    onLog?.call(message);
  }

  // Đăng ký userId để tự động load devices
  void setUserId(String userId) {
    if (_currentUserId != userId) {
      _currentUserId = userId;
      _log('👤 User: $userId');
    }
  }

  /// Bắt đầu kiểm tra lịch định kỳ (mỗi 10 giây)
  void startScheduleChecker() {
    if (_isRunning) return;

    _isRunning = true;
    final now = DateTime.now();
    _log('🔔 Bắt đầu kiểm tra lịch lúc ${now.hour}:${now.minute}:${now.second}');

    // Chạy ngay lần đầu
    _checkAndExecuteSchedules();

    // Sau đó chạy mỗi 10 giây (nhanh hơn để test)
    _checkTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkAndExecuteSchedules();
    });
  }

  /// Dừng kiểm tra lịch
  void stopScheduleChecker() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRunning = false;
    _log('⏹️ Đã dừng kiểm tra lịch');
  }

  /// Kiểm tra và thực thi tất cả lịch đã đến giờ
  Future<void> _checkAndExecuteSchedules() async {
    try {
      // Nếu không có userId, bỏ qua
      if (_currentUserId == null) {
        return;
      }

      // Load devices của user từ user_devices/{userId}
      final userDevicesSnapshot = await _db.child('user_devices/$_currentUserId').get();

      if (!userDevicesSnapshot.exists) {
        return;
      }

      final userDevices = userDevicesSnapshot.value as Map<dynamic, dynamic>;
      final deviceIds = userDevices.keys.toList();

      if (deviceIds.isEmpty) {
        return;
      }

      final now = DateTime.now();
      final currentDay = now.weekday % 7; // 0 = CN, 1-6 = T2-T7
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      _log('⏰ $currentTime | ${_getDayName(currentDay)}');

      int totalSchedules = 0;
      int executedSchedules = 0;

      // Duyệt qua devices của user hiện tại
      for (var deviceId in deviceIds) {
        try {
          final schedulesSnapshot = await _db.child('schedules/$deviceId').get();

          if (!schedulesSnapshot.exists) {
            continue;
          }

          final deviceSchedules = schedulesSnapshot.value as Map<dynamic, dynamic>;

          // Duyệt qua từng lịch của thiết bị
          for (var scheduleEntry in deviceSchedules.entries) {
            totalSchedules++;
            final scheduleData = scheduleEntry.value as Map<dynamic, dynamic>;
            final schedule = ScheduleModel.fromMap(
              scheduleEntry.key as String,
              Map<String, dynamic>.from(scheduleData),
            );

            // Kiểm tra xem lịch có cần thực thi không
            if (_shouldExecuteSchedule(schedule, currentDay, currentTime, now)) {
              executedSchedules++;
              _log('✅ Thực thi: "${schedule.name}" - ${schedule.actionName}');
              await _executeSchedule(schedule, deviceId, currentTime);
            }
          }
        } catch (e) {
          _log('⚠️ Lỗi đọc lịch $deviceId: $e');
        }
      }

      if (executedSchedules > 0) {
        _log('📊 Đã thực thi $executedSchedules/$totalSchedules lịch');
      }
    } catch (e) {
      _log('❌ Lỗi: $e');
    }
  }

  String _getDayName(int day) {
    const days = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    return days[day];
  }

  /// Kiểm tra xem lịch có nên được thực thi không
  bool _shouldExecuteSchedule(
    ScheduleModel schedule,
    int currentDay,
    String currentTime,
    DateTime now,
  ) {
    // Kiểm tra lịch có được bật không
    if (!schedule.enabled) return false;

    // Kiểm tra ngày trong tuần có khớp không
    if (!schedule.daysOfWeek.contains(currentDay)) return false;

    // Kiểm tra thời gian có khớp không
    if (schedule.time != currentTime) return false;

    // Kiểm tra xem đã thực thi trong phút này chưa (tránh thực thi nhiều lần)
    if (schedule.lastExecuted != null) {
      final lastExecutedTime = DateTime.fromMillisecondsSinceEpoch(schedule.lastExecuted!);
      final diff = now.difference(lastExecutedTime);

      // Nếu đã thực thi trong vòng 1 phút thì bỏ qua
      if (diff.inMinutes < 1) {
        return false;
      }
    }

    return true;
  }

  /// Thực thi một lịch cụ thể
  Future<void> _executeSchedule(ScheduleModel schedule, String deviceId, String currentTime) async {
    try {
      // Đánh dấu lastExecuted NGAY để tránh thực thi lại trong cùng phút
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.child('schedules/$deviceId/${schedule.scheduleId}/lastExecuted').set(now);

      // 1. Kiểm tra thiết bị có online không
      final deviceSnapshot = await _db.child('status/$deviceId/ac').get();
      if (!deviceSnapshot.exists) {
        _log('⚠️ Thiết bị offline');
        await _markScheduleIncomplete(schedule.scheduleId, deviceId, 'Thiết bị offline');
        return;
      }

      final deviceData = deviceSnapshot.value as Map<dynamic, dynamic>;
      // Tính trạng thái máy từ dòng điện (> threshold = máy đang chạy)
      final powerCurrent = (deviceData['current'] ?? 0).toDouble();
      var currentPowerOn = powerCurrent > AppConstants.acPowerOnThreshold;
      var currentTemp = deviceData['setTemp'] as int? ?? 24;

      // 2. Thực thi action
      if (schedule.action == 'powerOn' || schedule.action == 'powerOff') {
        await _executePowerSchedule(schedule, deviceId, currentPowerOn);
      } else if (schedule.action == 'tempUp' || schedule.action == 'tempDown') {
        await _executeTemperatureSchedule(schedule, deviceId, currentPowerOn, currentTemp);
      }

      // Đánh dấu đã hoàn thành
      await _markScheduleComplete(schedule.scheduleId, deviceId);

    } catch (e) {
      _log('❌ Lỗi thực thi: $e');
      await _markScheduleIncomplete(schedule.scheduleId, deviceId, 'Lỗi: $e');
    }
  }

  /// Thực thi lịch bật/tắt máy
  Future<void> _executePowerSchedule(
    ScheduleModel schedule,
    String deviceId,
    bool currentPowerOn,
  ) async {
    final shouldBePowerOn = schedule.action == 'powerOn';

    _log('  📋 Trạng thái hiện tại: ${currentPowerOn ? "BẬT" : "TẮT"}, Mục tiêu: ${shouldBePowerOn ? "BẬT" : "TẮT"}');

    if (currentPowerOn == shouldBePowerOn) {
      _log('  ⏭️ Máy đã ${shouldBePowerOn ? "bật" : "tắt"}');
      return;
    }

    // Máy chưa đúng trạng thái → Gửi lệnh power
    _log('  🎯 Gửi lệnh ${shouldBePowerOn ? "BẬT" : "TẮT"} máy');
    await _sendCommand(deviceId, 'power', null);
    // Delay đủ lâu để ESP32 đọc command trước khi bị xóa bởi lệnh tiếp theo
      // (vì _sendCommand xóa command cũ trước khi ghi mới)
    await Future.delayed(const Duration(milliseconds: 2500));
  }

  /// Gửi lệnh đến ESP32 qua Firebase
  Future<void> _sendCommand(String deviceId, String action, int? value) async {
    final commandPath = 'commands/$deviceId';

    try {
      // Xóa lệnh cũ trước (nếu có)
      await _db.child(commandPath).remove();

      // Ghi lệnh mới theo format của ESP32
      final commandData = {
        'action': action,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      if (value != null) {
        commandData['value'] = value;
      }

      await _db.child(commandPath).set(commandData);

      _log('📤 Gửi: $action${value != null ? " ($value°C)" : ""} → $commandPath');
    } catch (e) {
      _log('❌ Lỗi gửi lệnh: $e');
    }
  }

  /// Kịch bản 2: Thực thi lịch tăng/giảm nhiệt độ
  Future<void> _executeTemperatureSchedule(
    ScheduleModel schedule,
    String deviceId,
    bool currentPowerOn,
    int currentTemp,
  ) async {
    final targetTemp = schedule.value ?? 24;

    // Nếu máy chưa bật → Bật máy trước
    if (!currentPowerOn) {
      _log('  🔌 Bật máy trước');
      await _sendCommand(deviceId, 'power', null);

      // Đợi 10 giây để máy lạnh khởi động hoàn toàn
      _log('  ⏳ Đợi 20 giây để máy khởi động...');
      await Future.delayed(const Duration(seconds: 20));

      // Đọc lại setTemp từ database sau khi bật máy
      final snapshot = await _db.child('status/$deviceId/ac/setTemp').get();
      if (snapshot.exists) {
        currentTemp = snapshot.value as int? ?? 24;
        _log('  📖 Nhiệt độ sau khi bật: $currentTemp°C');
      }
    }

    // Nếu máy đã ở nhiệt độ mục tiêu → Không cần làm gì
    if (currentTemp == targetTemp) {
      _log('  ⏭️ Đã ở $targetTemp°C');
      return;
    }

    // Gửi lệnh tăng/giảm nhiệt độ theo từng bước
    final action = schedule.action == 'tempUp' ? 'tempUp' : 'tempDown';
    final steps = (targetTemp - currentTemp).abs();

    _log('  🌡️ Đặt nhiệt độ: $currentTemp°C → $targetTemp°C ($steps bước)');

    // Gửi lệnh nhiều lần theo khoảng cách nhiệt độ
    for (int i = 0; i < steps; i++) {
      // Gửi lệnh đến ESP32
      await _sendCommand(deviceId, action, null);
      _log('  📤 Bước ${i + 1}/$steps: $action');

      // Delay đủ lâu để ESP32 đọc command trước khi bị xóa bởi lệnh tiếp theo
      // (vì _sendCommand xóa command cũ trước khi ghi mới)
      await Future.delayed(const Duration(milliseconds: 2500));
    }

    _log('  ✅ Đã gửi $steps lệnh $action');
  }

  /// Đánh dấu lịch đã hoàn thành
  Future<void> _markScheduleComplete(String scheduleId, String deviceId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.child('schedules/$deviceId/$scheduleId/lastExecuted').set(now);
    await _db.child('schedules/$deviceId/$scheduleId/lastStatus').set('completed');
  }

  /// Đánh dấu lịch chưa hoàn thành (do offline hoặc lỗi)
  Future<void> _markScheduleIncomplete(String scheduleId, String deviceId, String reason) async {
    await _db.child('schedules/$deviceId/$scheduleId/lastStatus').set('failed');
    await _db.child('schedules/$deviceId/$scheduleId/lastError').set(reason);
  }

  void dispose() {
    stopScheduleChecker();
  }
}
