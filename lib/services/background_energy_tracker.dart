import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'energy_monitoring_service.dart';
import '../utils/constants.dart';

/// Background service để tracking energy liên tục
/// Chạy độc lập với UI, không bị ảnh hưởng khi chuyển màn hình
class BackgroundEnergyTracker {
  // Singleton pattern
  static final BackgroundEnergyTracker _instance = BackgroundEnergyTracker._internal();

  factory BackgroundEnergyTracker() {
    return _instance;
  }

  BackgroundEnergyTracker._internal();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final EnergyMonitoringService _energyService = EnergyMonitoringService();

  // Map lưu timer cho từng device
  final Map<String, Timer?> _deviceTimers = {};

  // Map lưu stream subscription để lắng nghe Firebase
  final Map<String, StreamSubscription?> _deviceListeners = {};

  // Map lưu giá trị powerWatts mới nhất cho từng device
  final Map<String, double> _latestPowerWatts = {};

  // Map lưu giá trị electricityPrice mới nhất cho từng device
  final Map<String, int> _latestElectricityPrice = {};

  // Map lưu giá trị ratedPowerWatts mới nhất cho từng device
  final Map<String, int> _latestRatedPowerWatts = {};

  // Map để track xem có đang trong quá trình end session không (tránh gọi nhiều lần)
  final Map<String, bool> _isEndingSession = {};

  /// Bắt đầu tracking cho một device
  /// Tự động lắng nghe Firebase và cập nhật session mỗi 5 giây
  void startTracking(String deviceId) {
    print('🔋 [BG_TRACKER] Starting background energy tracking for $deviceId');

    // Nếu đã tracking rồi thì không làm gì
    if (_deviceTimers.containsKey(deviceId) && _deviceTimers[deviceId] != null) {
      print('⚠️ [BG_TRACKER] Already tracking $deviceId');
      return;
    }

    // Lắng nghe trạng thái AC và power từ Firebase
    _deviceListeners[deviceId] = _db
        .child('status/$deviceId')
        .onValue
        .listen((event) async {
      if (!event.snapshot.exists) return;

      try {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        // Lấy thông tin từ nested structure: status/{deviceId}/ac/...
        final acData = data['ac'] != null ? Map<String, dynamic>.from(data['ac']) : <String, dynamic>{};

        final powerWatts = (acData['power'] ?? 0).toDouble();
        final powerCurrent = (acData['current'] ?? 0).toDouble();

        // AC được xác định bật khi dòng điện > threshold (logic giống ControlScreen:257)
        final isAcOn = powerCurrent > AppConstants.acPowerOnThreshold;

        print('📊 [BG_TRACKER] Firebase event for $deviceId: Current=${powerCurrent}A, Power=${powerWatts}W, AC=${isAcOn ? "ON" : "OFF"}');

        final electricityPrice = data['electricityPrice'] ?? 3000;
        final ratedPowerWatts = data['ratedPowerWatts'] ?? 1100;

        // LƯU GIÁ TRỊ MỚI NHẤT VÀO MAP (để timer dùng giá trị realtime)
        _latestPowerWatts[deviceId] = powerWatts;
        _latestElectricityPrice[deviceId] = electricityPrice;
        _latestRatedPowerWatts[deviceId] = ratedPowerWatts;

        // Nếu máy đang bật và chưa có timer → bắt đầu timer
        if (isAcOn && (_deviceTimers[deviceId] == null || !_deviceTimers[deviceId]!.isActive)) {
          print('▶️ [BG_TRACKER] AC is ON, starting update timer for $deviceId');
          print('   Power: ${powerWatts}W, Current: ${powerCurrent}A');

          // Bắt đầu session
          await _energyService.startSession(
            deviceId: deviceId,
            electricityPrice: electricityPrice,
            ratedPowerWatts: ratedPowerWatts,
          );

          print('✅ [BG_TRACKER] Session started, creating periodic timer');

          // Tạo timer cập nhật mỗi 5 giây - ĐỌC GIÁ TRỊ TỪ MAP thay vì capture
          _deviceTimers[deviceId] = Timer.periodic(
            const Duration(seconds: 5),
            (_) async {
              // KIỂM TRA TIMER CÒN TỒN TẠI KHÔNG (có thể đã bị cancel)
              if (_deviceTimers[deviceId] == null) {
                print('⚠️ [BG_TRACKER] Timer was cancelled for $deviceId, stopping callback');
                return;
              }

              // Kiểm tra xem có đang end session không (tránh race condition)
              if (_isEndingSession[deviceId] == true) {
                print('⚠️ [BG_TRACKER] Already ending session for $deviceId, skipping');
                return;
              }

              // ĐỌC LẠI CURRENT TỪ FIREBASE để kiểm tra máy còn chạy không
              final snapshot = await _db.child('status/$deviceId/ac/current').get();
              final currentFromFirebase = snapshot.exists ? (snapshot.value as num).toDouble() : 0.0;

              final currentPower = _latestPowerWatts[deviceId] ?? 0;
              print('⏰ [BG_TRACKER] Timer fired for $deviceId (Current: ${currentFromFirebase}A, Power: ${currentPower}W)');

              // CHỈ update nếu current > threshold (máy đang chạy)
              if (currentFromFirebase > AppConstants.acPowerOnThreshold) {
                _updateSession(
                  deviceId,
                  currentPower,
                  _latestElectricityPrice[deviceId] ?? 3000,
                  _latestRatedPowerWatts[deviceId] ?? 1100,
                );
              } else {
                // Máy tắt → dừng timer và end session
                print('⚠️ [BG_TRACKER] Timer fired but current=${currentFromFirebase}A <= ${AppConstants.acPowerOnThreshold}A, stopping timer');
                print('   Note: Machine is in standby/idle mode with ${currentFromFirebase}A current');

                // Set flag để tránh gọi lại trong lúc đang process
                _isEndingSession[deviceId] = true;

                // HỦY TIMER NGAY LẬP TỨC (trước khi gọi endSession)
                final timer = _deviceTimers[deviceId];
                _deviceTimers[deviceId] = null;
                timer?.cancel();

                // Gọi endSession
                await _energyService.endSession(
                  deviceId: deviceId,
                  currentPowerWatts: currentPower,
                );

                // Cleanup
                _latestPowerWatts.remove(deviceId);
                _latestElectricityPrice.remove(deviceId);
                _latestRatedPowerWatts.remove(deviceId);
                _isEndingSession.remove(deviceId);

                print('✅ [BG_TRACKER] Timer stopped and session ended for $deviceId');
              }
            },
          );
          print('✅ [BG_TRACKER] Timer created successfully for $deviceId');
        }

        // Nếu máy tắt và đang có timer → dừng timer và kết thúc session
        if (!isAcOn && _deviceTimers[deviceId] != null && _deviceTimers[deviceId]!.isActive) {
          // Kiểm tra xem đã đang end session chưa
          if (_isEndingSession[deviceId] == true) {
            print('⚠️ [BG_TRACKER] Already ending session for $deviceId via Firebase listener, skipping');
            return;
          }

          print('⏹️ [BG_TRACKER] AC is OFF (Firebase listener), stopping timer for $deviceId');

          // Set flag
          _isEndingSession[deviceId] = true;

          // Hủy timer NGAY LẬP TỨC
          final timer = _deviceTimers[deviceId];
          _deviceTimers[deviceId] = null;
          timer?.cancel();

          // Kết thúc session
          await _energyService.endSession(
            deviceId: deviceId,
            currentPowerWatts: powerWatts,
          );

          // Xóa giá trị trong Map
          _latestPowerWatts.remove(deviceId);
          _latestElectricityPrice.remove(deviceId);
          _latestRatedPowerWatts.remove(deviceId);
          _isEndingSession.remove(deviceId);

          print('✅ [BG_TRACKER] Session ended via Firebase listener for $deviceId');
        }

        // Nếu máy đang chạy → update session ngay (với giá trị mới nhất)
        // CHÚ Ý: Chỉ update nếu có timer đang active (tránh update sau khi vừa stop)
        if (isAcOn && _deviceTimers[deviceId] != null && _deviceTimers[deviceId]!.isActive) {
          print('🔄 [BG_TRACKER] AC is running, updating session immediately');
          await _updateSession(deviceId, powerWatts, electricityPrice, ratedPowerWatts);
        }
      } catch (e) {
        print('❌ Error in background tracker listener: $e');
      }
    });
  }

  /// Cập nhật session
  Future<void> _updateSession(
    String deviceId,
    double powerWatts,
    int electricityPrice,
    int ratedPowerWatts,
  ) async {
    try {
      print('⏱️ [BG_TRACKER] Timer tick for $deviceId');
      print('   Power: ${powerWatts}W, Price: $electricityPrice, Rated: ${ratedPowerWatts}W');

      final result = await _energyService.updateSession(
        deviceId: deviceId,
        currentPowerWatts: powerWatts,
        electricityPrice: electricityPrice,
        ratedPowerWatts: ratedPowerWatts,
      );

      if (result != null) {
        print('✅ [BG_TRACKER] Session updated: ${result.currentSessionEnergyKWh.toStringAsFixed(4)} kWh, runtime: ${result.runtimeTodaySeconds}s');
      } else {
        print('⚠️ [BG_TRACKER] Session update returned null for $deviceId');
      }
    } catch (e, stackTrace) {
      print('❌ [BG_TRACKER] Error updating session: $e');
      print('   Stack trace: $stackTrace');
    }
  }

  /// Dừng tracking cho một device
  void stopTracking(String deviceId) {
    print('🛑 Stopping background energy tracking for $deviceId');

    // Hủy timer
    _deviceTimers[deviceId]?.cancel();
    _deviceTimers.remove(deviceId);

    // Hủy listener
    _deviceListeners[deviceId]?.cancel();
    _deviceListeners.remove(deviceId);

    // Xóa cached values
    _latestPowerWatts.remove(deviceId);
    _latestElectricityPrice.remove(deviceId);
    _latestRatedPowerWatts.remove(deviceId);
  }

  /// Dừng tất cả tracking
  void stopAllTracking() {
    print('🛑 Stopping all background energy tracking');

    // Hủy tất cả timer
    for (final timer in _deviceTimers.values) {
      timer?.cancel();
    }
    _deviceTimers.clear();

    // Hủy tất cả listener
    for (final listener in _deviceListeners.values) {
      listener?.cancel();
    }
    _deviceListeners.clear();

    // Xóa tất cả cached values
    _latestPowerWatts.clear();
    _latestElectricityPrice.clear();
    _latestRatedPowerWatts.clear();
  }

  /// Kiểm tra xem device có đang được track không
  bool isTracking(String deviceId) {
    return _deviceTimers.containsKey(deviceId) &&
           _deviceTimers[deviceId] != null &&
           _deviceTimers[deviceId]!.isActive;
  }

  /// Dispose service
  void dispose() {
    stopAllTracking();
  }
}
