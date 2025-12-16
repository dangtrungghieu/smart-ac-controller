import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../models/device_model.dart';
import '../../models/auto_off_settings.dart';
import '../../services/device_service.dart';
import '../../services/device_heartbeat_service.dart';
import '../../services/auth_service.dart';
import '../../services/background_energy_tracker.dart';
import '../../utils/theme.dart';
import '../../utils/sensor_calibration.dart'; // THÊM: Import sensor calibration
import '../../utils/constants.dart';
import 'package:provider/provider.dart';
import '../schedule/schedule_list_screen.dart';
import '../../widgets/smart_temp_suggestion_widget.dart';
import '../../widgets/power_consumption_widget.dart';

// ===== THÊM: VOICE CONTROL IMPORTS =====
import '../../models/voice_command_model.dart';
import '../../widgets/voice_control_button.dart';
import '../../widgets/voice_command_guide.dart';

class ControlScreen extends StatefulWidget {
  final DeviceModel device;

  const ControlScreen({
    super.key,
    required this.device,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final DeviceHeartbeatService _heartbeatService = DeviceHeartbeatService();
  final BackgroundEnergyTracker _energyTracker = BackgroundEnergyTracker();
  Timer? _statusCheckTimer;
  StreamSubscription? _claimedListener;

  bool _acPowerOn = false;
  int _currentTemp = 24;
  double _roomTemp = 0;
  double _roomHumidity = 0;
  bool _hasPerson = false;
  double _powerWatt = 0;
  double _powerCurrent = 0;
  bool _isOnline = false;
  bool _offlineDialogShown = false; // Đảm bảo chỉ hiện dialog 1 lần
  bool _resetDialogShown = false; // Đảm bảo chỉ hiện dialog reset 1 lần

  // PZEM-004T additional data
  double _voltage = 220.0;
  double _energyKWh = 0.0;
  double _powerFactor = 0.9;

  // Auto-off settings
  AutoOffSettings _autoOffSettings = AutoOffSettings();
  StreamSubscription? _autoOffListener;

  @override
  void initState() {
    super.initState();

    // Kiểm tra xem thiết bị đã có heartbeat chưa (từ DeviceList)
    final hasHeartbeat = _heartbeatService.getLastSeen(widget.device.deviceId) != null;
    if (hasHeartbeat) {
      // Đã có heartbeat → kiểm tra online ngay từ heartbeat service
      _isOnline = _heartbeatService.isDeviceOnline(widget.device.deviceId);
    } else {
      // Chưa có heartbeat → mặc định offline, đợi Firebase listener cập nhật
      _isOnline = false;
    }

    // Chỉ cần listen, không cần load initial data vì StreamBuilder sẽ tự động cập nhật
    _listenToStatus();

    // ===== THÊM: LISTEN CLAIMED STATUS =====
    _listenToDeviceReset();

    // ===== THÊM: LOAD VÀ LISTEN AUTO-OFF SETTINGS =====
    _loadAutoOffSettings();
    _listenToAutoOffSettings();

    // ===== THÊM: BẮT ĐẦU BACKGROUND ENERGY TRACKING =====
    _energyTracker.startTracking(widget.device.deviceId);

    // Timer kiểm tra trạng thái mỗi 1 giây để cập nhật UI ngay lập tức
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        final currentOnline = _heartbeatService.isDeviceOnline(widget.device.deviceId);

        // Chỉ rebuild nếu trạng thái thay đổi
        if (_isOnline != currentOnline) {
          setState(() {
            _isOnline = currentOnline;
          });

          // Nếu thiết bị vừa chuyển sang offline, hiển thị dialog
          if (!currentOnline && !_offlineDialogShown) {
            _offlineDialogShown = true;
            _showOfflineDialog();
          }
        }

      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _claimedListener?.cancel();
    _autoOffListener?.cancel();
    // KHÔNG dừng _energyTracker vì nó cần chạy background ngay cả khi chuyển màn hình
    // Energy tracking chỉ dừng khi AC tắt hoặc user logout
    super.dispose();
  }

  // ===== THÊM: LISTEN DEVICE RESET =====
  void _listenToDeviceReset() {
    _claimedListener = _db
        .child('devices/${widget.device.deviceId}/info/claimed')
        .onValue
        .listen((event) {
      if (mounted && event.snapshot.exists) {
        final claimed = event.snapshot.value as bool?;

        // Nếu thiết bị bị reset (claimed = false)
        if (claimed == false && !_resetDialogShown) {
          _resetDialogShown = true;
          print('⚠️ Phat hien device ${widget.device.deviceId} bi reset!');
          _showDeviceResetDialog();
        }
      }
    });
  }

  // ===== THÊM: DIALOG THIẾT BỊ BỊ RESET =====
  void _showDeviceResetDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Thiết bị đã được reset',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Thiết bị "${widget.device.name}" đã được reset từ nút cứng hoặc từ nơi khác.\n\nThiết bị đã được xóa khỏi danh sách của bạn.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Đóng dialog
              Navigator.of(context).pop(); // Quay lại Device List
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  void _showOfflineDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // Người dùng phải nhấn nút để đóng
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.errorColor, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Thiết bị mất kết nối',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          'Thiết bị "${widget.device.name}" đã offline. Vui lòng kiểm tra lại kết nối.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Đóng dialog
              Navigator.of(context).pop(); // Quay lại Device List
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Chấp nhận'),
          ),
        ],
      ),
    );
  }
//Đọc dữ liệu cap nhật từ Firebase Realtime Database
  void _listenToStatus() {
    _db.child('status/${widget.device.deviceId}').onValue.listen((event) {
      if (event.snapshot.exists && mounted) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          // Đọc lastSeen từ root level (ESP32 gửi lên)
          int? lastSeen = data['lastSeen'];

          // Cập nhật heartbeat service
          if (lastSeen != null) {
            _heartbeatService.updateLastSeen(widget.device.deviceId, lastSeen);
            _isOnline = _heartbeatService.isDeviceOnline(widget.device.deviceId);
          }

          // Room status - Áp dụng hiệu chỉnh cho cảm biến DHT22
          if (data['room'] != null) {
            final room = Map<String, dynamic>.from(data['room']);
            final double rawTemp = (room['temp'] ?? 0).toDouble();
            final double rawHumidity = (room['humidity'] ?? 0).toDouble();

            // Hiệu chỉnh dữ liệu cảm biến DHT22
            _roomTemp = SensorCalibration.calibrateTemperature(rawTemp) ?? 0.0;
            _roomHumidity = SensorCalibration.calibrateHumidity(rawHumidity) ?? 0.0;
            _hasPerson = room['hasPerson'] ?? false;
          }

          // AC status
          if (data['ac'] != null) {
            final ac = Map<String, dynamic>.from(data['ac']);
            _currentTemp = ac['setTemp'] ?? 24;
            _powerWatt = (ac['power'] ?? 0).toDouble();
            _powerCurrent = (ac['current'] ?? 0).toDouble();

            // PZEM-004T additional data
            _voltage = (ac['voltage'] ?? 220.0).toDouble();
            _energyKWh = (ac['energy'] ?? 0.0).toDouble();
            _powerFactor = (ac['powerFactor'] ?? 0.9).toDouble();

            _acPowerOn = _powerCurrent > AppConstants.acPowerOnThreshold; // set current > threshold nghĩa là AC đang bật
          }
        });
      }
    });
  }

  // ===== AUTO-OFF SETTINGS =====
  Future<void> _loadAutoOffSettings() async {
    try {
      final snapshot = await _db.child('settings/${widget.device.deviceId}/autoOff').get();
      if (snapshot.exists && mounted) {
        setState(() {
          _autoOffSettings = AutoOffSettings.fromJson(
            Map<String, dynamic>.from(snapshot.value as Map),
          );
        });
      }
    } catch (e) {
      print('Error loading auto-off settings: $e');
    }
  }

  void _listenToAutoOffSettings() {
    _autoOffListener = _db
        .child('settings/${widget.device.deviceId}/autoOff')
        .onValue
        .listen((event) {
      if (event.snapshot.exists && mounted) {
        setState(() {
          _autoOffSettings = AutoOffSettings.fromJson(
            Map<String, dynamic>.from(event.snapshot.value as Map),
          );
        });
      }
    });
  }

  Future<void> _updateAutoOffSettings(AutoOffSettings settings) async {
    try {
      await _db.child('settings/${widget.device.deviceId}/autoOff').set(settings.toJson());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi cập nhật cài đặt: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _sendCommand(String action, {int? value}) async {
    final deviceService = Provider.of<DeviceService>(context, listen: false);
    
    final success = await deviceService.sendCommand(
      deviceId: widget.device.deviceId,
      action: action,
      value: value,
    );

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lỗi gửi lệnh'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _togglePower() async {
    await _sendCommand('power');
  }

  Future<void> _increaseTemp() async {
    if (_currentTemp < 30) {
      await _sendCommand('tempUp');
    }
  }

  Future<void> _decreaseTemp() async {
    if (_currentTemp > 16) {
      await _sendCommand('tempDown');
    }
  }

  Future<void> _setTemp(int temp) async {
    if (temp >= 16 && temp <= 30) {
      await _sendCommand('setTemp', value: temp);
    }
  }

  // ===== THÊM: XỬ LÝ VOICE COMMAND =====
  /// Xử lý lệnh giọng nói đã được phân tích
  Future<void> _handleVoiceCommand(VoiceCommand command) async {
    print('🎤 Processing voice command: ${command.type}');

    // Kiểm tra thiết bị online
    if (!_isOnline) {
      _showSnackBar('Thiết bị đang offline, không thể thực hiện lệnh', isError: true);
      return;
    }

    // Xử lý theo loại lệnh
    switch (command.type) {
      case VoiceCommandType.powerControl:
        await _handlePowerControl(command);
        break;

      case VoiceCommandType.temperatureControl:
        await _handleTemperatureControl(command);
        break;

      case VoiceCommandType.scheduleControl:
        await _handleScheduleControl(command);
        break;

      case VoiceCommandType.autoOffControl:
        await _handleAutoOffControl(command);
        break;

      case VoiceCommandType.unknown:
        _showSnackBar(command.errorMessage ?? 'Không hiểu lệnh', isError: true);
        break;
    }
  }

  /// Xử lý lệnh bật/tắt
  Future<void> _handlePowerControl(VoiceCommand command) async {
    if (command.powerAction == PowerAction.turnOn) {
      if (!_acPowerOn) {
        await _togglePower();
        _showSnackBar('✅ Đã bật máy lạnh', isError: false);
      } else {
        _showSnackBar('Máy lạnh đang bật rồi', isError: false);
      }
    } else if (command.powerAction == PowerAction.turnOff) {
      if (_acPowerOn) {
        await _togglePower();
        _showSnackBar('✅ Đã tắt máy lạnh', isError: false);
      } else {
        _showSnackBar('Máy lạnh đang tắt rồi', isError: false);
      }
    }
  }

  /// Xử lý lệnh nhiệt độ
  Future<void> _handleTemperatureControl(VoiceCommand command) async {
    // Bật máy nếu đang tắt
    if (!_acPowerOn) {
      await _togglePower();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    int newTemp = _currentTemp;

    // Xử lý theo action
    if (command.temperatureAction == TemperatureAction.set) {
      // ĐẶT NHIỆT ĐỘ CỤ THỂ (mới - từ Smart Parser)
      newTemp = (command.targetTemp ?? 24).clamp(16, 30);
    } else if (command.temperatureAction == TemperatureAction.decrease) {
      // GIẢM nhiệt độ = phòng mát hơn
      final step = command.tempStep;
      newTemp = (_currentTemp - step).clamp(16, 30);
    } else if (command.temperatureAction == TemperatureAction.increase) {
      // TĂNG nhiệt độ = phòng ấm hơn
      final step = command.tempStep;
      newTemp = (_currentTemp + step).clamp(16, 30);
    }

    await _setTemp(newTemp);
    _showSnackBar('✅ Đã đặt nhiệt độ $newTemp°C', isError: false);
  }

  /// Xử lý lệnh lịch
  Future<void> _handleScheduleControl(VoiceCommand command) async {
    // Lấy userId
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid ?? '';

    if (userId.isEmpty) {
      _showSnackBar('Không thể tạo lịch: Chưa đăng nhập', isError: true);
      return;
    }

    // Tạo thông tin lịch
    final dayName = _getDayName(command.scheduleDayOfWeek!);
    final timeStr = '${command.scheduleHour!.toString().padLeft(2, '0')}:${command.scheduleMinute!.toString().padLeft(2, '0')}';
    final action = command.schedulePowerOn! ? 'BẬT' : 'TẮT';

    // TODO: Tích hợp với schedule service để tạo lịch
    // Hiện tại chỉ show thông báo và mở màn hình lịch
    _showSnackBar(
      '📅 Lịch $action máy vào $timeStr $dayName\nVui lòng kiểm tra màn hình Lịch',
      isError: false,
    );

    // Mở màn hình lịch
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScheduleListScreen(
            device: widget.device,
            userId: userId,
          ),
        ),
      );
    }
  }

  /// Xử lý lệnh AutoOff
  Future<void> _handleAutoOffControl(VoiceCommand command) async {
    if (command.autoOffAction == AutoOffAction.disable) {
      // Tắt AutoOff
      final newSettings = _autoOffSettings.copyWith(enabled: false);
      await _updateAutoOffSettings(newSettings);
      _showSnackBar('✅ Đã tắt Auto Off', isError: false);
    } else if (command.autoOffAction == AutoOffAction.enable) {
      // Bật AutoOff
      final minutes = command.autoOffMinutes ?? 30;
      final warning = command.autoOffWarning;

      if (warning) {
        _showSnackBar(
          '⚠️ Thời gian > 60 phút sẽ tốn nhiều điện!\nĐã đặt Auto Off $minutes phút',
          isError: true,
        );
      }

      final newSettings = _autoOffSettings.copyWith(
        enabled: true,
        delayMinutes: minutes,
      );
      await _updateAutoOffSettings(newSettings);
      _showSnackBar('✅ Đã bật Auto Off sau $minutes phút', isError: false);
    }
  }

  /// Hiển thị SnackBar thông báo
  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Lấy tên thứ
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
        return '';
    }
  }
  // ===== KẾT THÚC XỬ LÝ VOICE COMMAND =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.device.name,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isOnline ? AppTheme.successColor : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isOnline ? AppTheme.successColor : Colors.grey,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // ===== THÊM: NÚT HELP CHO VOICE CONTROL =====
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              VoiceCommandGuide.show(context);
            },
            tooltip: 'Hướng dẫn lệnh giọng nói',
          ),
          // ===== KẾT THÚC THÊM =====

          IconButton(
            icon: const Icon(Icons.schedule),
            onPressed: () {
              // Lấy userId từ AuthService
              final authService = Provider.of<AuthService>(context, listen: false);
              final userId = authService.currentUser?.uid ?? '';

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScheduleListScreen(
                    device: widget.device,
                    userId: userId,
                  ),
                ),
              );
            },
            tooltip: 'Lịch điều khiển',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Power Button
            _buildPowerButton(),

            const SizedBox(height: 16),

            // Temperature Control
            if (_acPowerOn) _buildTemperatureControl(),

            if (_acPowerOn) const SizedBox(height: 16),

            // Room Info
            _buildRoomInfo(),

            const SizedBox(height: 16),

            // ===== THÊM: WIDGET GỢI Ý THÔNG MINH V2 =====
            // Chỉ hiển thị khi thiết bị online
            if (_isOnline)
              SmartTempSuggestionWidget(
                roomTemp: _roomTemp,
                roomHumidity: _roomHumidity, // THÊM ĐỘ ẨM
                acSetTemp: _currentTemp,
                isAcOn: _acPowerOn,
                isOnline: _isOnline,
                onApplySuggestion: (newTemp) async {
                  // Áp dụng nhiệt độ mới
                  await _setTemp(newTemp);
                },
                onTurnOnAc: () async {
                  // Bật máy lạnh nếu đang tắt
                  await _togglePower();
                },
              ),

            if (_isOnline) const SizedBox(height: 16),
            // ===== KẾT THÚC WIDGET GỢI Ý =====

            // Auto-off settings
            _buildAutoOffSettings(),

            const SizedBox(height: 16),

            // Power Consumption
            _buildPowerInfo(),

            // Thêm padding dưới cùng để tránh bị che bởi floating button
            const SizedBox(height: 80),
          ],
        ),
      ),
      // ===== THÊM: FLOATING VOICE CONTROL BUTTON =====
      floatingActionButton: _isOnline ? _buildFloatingVoiceButton() : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // ===== KẾT THÚC THÊM =====
    );
  }

  Widget _buildPowerButton() {
    return Card(
      child: InkWell(
        onTap: _isOnline ? _togglePower : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: _acPowerOn
                      ? AppTheme.successColor.withOpacity(0.2)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.power_settings_new,
                  size: 32,
                  color: _acPowerOn ? AppTheme.successColor : Colors.grey[600],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _acPowerOn ? 'Đang bật' : 'Đang tắt',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isOnline
                          ? (_acPowerOn
                              ? 'Dòng điện: ${_powerCurrent.toStringAsFixed(2)}A'
                              : 'Nhấn để bật')
                          : 'Thiết bị offline',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _acPowerOn,
                onChanged: _isOnline ? (_) => _togglePower() : null,
                activeColor: AppTheme.successColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== THÊM: VOICE CONTROL WIDGET =====
  /// Widget điều khiển giọng nói
  // ===== THÊM: FLOATING VOICE CONTROL BUTTON =====
  /// Nút microphone floating cố định ở dưới màn hình
  Widget _buildFloatingVoiceButton() {
    return VoiceControlButton(
      onCommandDetected: (command) async {
        // Hiển thị mô tả lệnh
        _showSnackBar(command.getDescription(), isError: false);

        // Xử lý lệnh sau 500ms để user thấy được mô tả
        await Future.delayed(const Duration(milliseconds: 500));
        await _handleVoiceCommand(command);
      },
      size: 65,
      showHint: false, // Không hiển thị hint text vì đã là floating button
    );
  }
  // ===== KẾT THÚC VOICE CONTROL WIDGET =====

  Widget _buildTemperatureControl() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nhiệt độ',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '16°C - 30°C',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Temperature Display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Decrease Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isOnline && _currentTemp > 16 ? _decreaseTemp : null,
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: (_isOnline && _currentTemp > 16)
                            ? AppTheme.primaryColor.withOpacity(0.1)
                            : Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.remove,
                        color: (_isOnline && _currentTemp > 16)
                            ? AppTheme.primaryColor
                            : Colors.grey[400],
                        size: 28,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(width: 40),
                
                // Temperature
                Text(
                  '$_currentTemp°C',
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                    height: 1,
                  ),
                ),
                
                const SizedBox(width: 40),
                
                // Increase Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isOnline && _currentTemp < 30 ? _increaseTemp : null,
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: (_isOnline && _currentTemp < 30)
                            ? AppTheme.primaryColor.withOpacity(0.1)
                            : Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add,
                        color: (_isOnline && _currentTemp < 30)
                            ? AppTheme.primaryColor
                            : Colors.grey[400],
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Temperature Slider
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 8,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
              ),
              child: Slider(
                value: _currentTemp.toDouble(),
                min: 16,
                max: 30,
                divisions: 14,
                label: '$_currentTemp°C',
                onChanged: _isOnline && _acPowerOn
                    ? (value) {
                        setState(() {
                          _currentTemp = value.round();
                        });
                      }
                    : null,
                onChangeEnd: (value) {
                  _setTemp(value.round());
                },
                activeColor: AppTheme.primaryColor,
                inactiveColor: Colors.grey[300],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Trạng thái phòng',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.thermostat_outlined,
                    label: 'Nhiệt độ',
                    value: _roomTemp > 0 ? '${_roomTemp.toStringAsFixed(1)}°C' : '--',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.water_drop_outlined,
                    label: 'Độ ẩm',
                    value: _roomHumidity > 0 ? '${_roomHumidity.toStringAsFixed(0)}%' : '--',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.person_outline,
                    label: 'Có người',
                    value: _hasPerson ? 'Có' : 'Không',
                    color: _hasPerson ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoOffSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.timer_off_outlined,
                      size: 22,
                      color: _autoOffSettings.enabled ? AppTheme.primaryColor : Colors.grey[600],
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Tự động tắt máy',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: _autoOffSettings.enabled,
                  onChanged: (value) async {
                    final newSettings = _autoOffSettings.copyWith(enabled: value);
                    await _updateAutoOffSettings(newSettings);
                  },
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Thông tin chức năng
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue[700]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tự động tắt máy lạnh khi không phát hiện người trong phòng',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[900],
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Slider chọn thời gian (chỉ hiện khi enabled)
            if (_autoOffSettings.enabled) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Thời gian chờ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppTheme.primaryColor,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      '${_autoOffSettings.delayMinutes} phút',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 6,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                ),
                child: Slider(
                  value: _autoOffSettings.delayMinutes.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '${_autoOffSettings.delayMinutes} phút',
                  onChanged: (value) {
                    setState(() {
                      _autoOffSettings = _autoOffSettings.copyWith(
                        delayMinutes: value.round(),
                      );
                    });
                  },
                  onChangeEnd: (value) async {
                    final newSettings = _autoOffSettings.copyWith(
                      delayMinutes: value.round(),
                    );
                    await _updateAutoOffSettings(newSettings);
                  },
                  activeColor: AppTheme.primaryColor,
                  inactiveColor: Colors.grey[300],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '1 phút',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '30 phút',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPowerInfo() {
    // Get electricity price from config (default: 3000 VND/kWh)
    const int electricityPrice = 3000; // VND per kWh

    return PowerConsumptionWidget(
      deviceId: widget.device.deviceId,
      voltage: _voltage,
      current: _powerCurrent,
      powerWatts: _powerWatt,
      energyKWh: _energyKWh,
      powerFactor: _powerFactor,
      electricityPrice: electricityPrice,
      ratedPowerWatts: 1100, // Rated power for typical AC unit (1.5HP)
      isAcOn: _acPowerOn,
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}