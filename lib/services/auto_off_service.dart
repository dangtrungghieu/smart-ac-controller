import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import '../models/auto_off_settings.dart';
import '../utils/constants.dart';

/// Service để tự động tắt máy lạnh khi không có người trong phòng
/// Chạy background timer để kiểm tra hasPerson và settings
class AutoOffService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  Timer? _checkTimer;
  bool _isRunning = false;
  String? _currentUserId;

  // Callback để gửi logs về UI (optional)
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
      _log('👤 AutoOff User: $userId');
    }
  }

  /// Bắt đầu kiểm tra auto-off định kỳ (mỗi 10 giây)
  void startAutoOffMonitor() {
    if (_isRunning) return;

    _isRunning = true;
    final now = DateTime.now();
    _log('🔔 Bắt đầu auto-off monitor lúc ${now.hour}:${now.minute}:${now.second}');

    // Chạy ngay lần đầu
    _checkAutoOffDevices();

    // Sau đó chạy mỗi 10 giây
    _checkTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _checkAutoOffDevices();
    });
  }

  /// Dừng kiểm tra auto-off
  void stopAutoOffMonitor() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isRunning = false;
    _log('⏹️ Đã dừng auto-off monitor');
  }

  /// Kiểm tra tất cả thiết bị có bật auto-off
  Future<void> _checkAutoOffDevices() async {
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

      final now = DateTime.now().millisecondsSinceEpoch;

      // Duyệt qua devices của user hiện tại
      for (var deviceId in deviceIds) {
        try {
          await _checkDeviceAutoOff(deviceId, now);
        } catch (e) {
          _log('⚠️ Lỗi kiểm tra auto-off $deviceId: $e');
        }
      }
    } catch (e) {
      _log('❌ Lỗi: $e');
    }
  }

  /// Kiểm tra và xử lý auto-off cho một thiết bị cụ thể
  Future<void> _checkDeviceAutoOff(String deviceId, int currentTimestamp) async {
    // 1. Đọc settings auto-off
    final settingsSnapshot = await _db.child('settings/$deviceId/autoOff').get();

    if (!settingsSnapshot.exists) {
      return; // Không có settings → bỏ qua
    }

    final settings = AutoOffSettings.fromJson(
      Map<String, dynamic>.from(settingsSnapshot.value as Map),
    );

    if (!settings.enabled) {
      return; // Chức năng chưa bật → bỏ qua
    }

    // 2. Đọc trạng thái phòng và máy lạnh
    final statusSnapshot = await _db.child('status/$deviceId').get();

    if (!statusSnapshot.exists) {
      return; // Thiết bị offline → bỏ qua
    }

    final statusData = Map<String, dynamic>.from(statusSnapshot.value as Map);

    // Lấy thông tin phòng
    final roomData = statusData['room'] as Map<dynamic, dynamic>?;
    final hasPerson = roomData?['hasPerson'] ?? false;

    // Lấy thông tin máy lạnh
    final acData = statusData['ac'] as Map<dynamic, dynamic>?;
    final powerCurrent = (acData?['current'] ?? 0).toDouble();
    final isAcOn = powerCurrent > AppConstants.acPowerOnThreshold;

    // 3. Logic auto-off
    if (hasPerson) {
      // Có người → Reset lastPersonSeenAt
      if (settings.lastPersonSeenAt != null) {
        _log('👤 $deviceId: Phát hiện người → Reset timer');
        await _db.child('settings/$deviceId/autoOff/lastPersonSeenAt').remove();
      }
    } else {
      // Không có người
      if (settings.lastPersonSeenAt == null) {
        // Lần đầu phát hiện không có người → Lưu timestamp
        _log('👻 $deviceId: Không có người → Bắt đầu đếm ngược');
        await _db.child('settings/$deviceId/autoOff/lastPersonSeenAt').set(currentTimestamp);
      } else {
        // Đã đếm ngược → Kiểm tra đã đủ thời gian chưa
        final elapsed = currentTimestamp - settings.lastPersonSeenAt!;
        final elapsedMinutes = elapsed ~/ (60 * 1000);

        _log('⏳ $deviceId: Không có người ${elapsedMinutes}/${settings.delayMinutes} phút');

        if (elapsedMinutes >= settings.delayMinutes) {
          // Đã đủ thời gian → Tắt máy (nếu đang bật)
          if (isAcOn) {
            _log('🔌 $deviceId: Tắt máy tự động (không có người ${settings.delayMinutes} phút)');
            await _sendPowerOffCommand(deviceId);

            // Reset lastPersonSeenAt sau khi tắt
            await _db.child('settings/$deviceId/autoOff/lastPersonSeenAt').remove();
          } else {
            // Máy đã tắt rồi → Reset timer
            await _db.child('settings/$deviceId/autoOff/lastPersonSeenAt').remove();
          }
        }
      }
    }
  }

  /// Gửi lệnh tắt máy
  Future<void> _sendPowerOffCommand(String deviceId) async {
    final commandPath = 'commands/$deviceId';

    try {
      // Xóa lệnh cũ trước (nếu có)
      await _db.child(commandPath).remove();

      // Ghi lệnh power
      final commandData = {
        'action': 'power',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await _db.child(commandPath).set(commandData);

      _log('📤 Gửi lệnh tắt máy → $commandPath');
    } catch (e) {
      _log('❌ Lỗi gửi lệnh: $e');
    }
  }

  void dispose() {
    stopAutoOffMonitor();
  }
}
