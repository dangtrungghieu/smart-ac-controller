import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../../services/device_heartbeat_service.dart';
import '../../services/schedule_executor.dart';
import '../../services/auto_off_service.dart';
import '../../services/background_energy_tracker.dart';
import '../../utils/theme.dart';
import '../../utils/sensor_calibration.dart'; // THÊM: Import sensor calibration
import '../../utils/constants.dart';
import '../../models/device_model.dart';
import '../auth/login_screen.dart';
import '../auth/change_password_screen.dart';
import '../device/add_device_screen.dart';
import '../device/control_screen.dart';
import '../device/device_settings_screen.dart';
import 'package:firebase_database/firebase_database.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final DeviceHeartbeatService _heartbeatService = DeviceHeartbeatService();
  final BackgroundEnergyTracker _energyTracker = BackgroundEnergyTracker();
  Timer? _statusCheckTimer;
  final Map<String, bool> _lastOnlineStatus = {};
  final Map<String, StreamSubscription> _deviceListeners = {};

  @override
  void initState() {
    super.initState();

    // Timer kiểm tra trạng thái mỗi 1 giây để cập nhật UI ngay lập tức
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        bool needsRebuild = false;

        // Kiểm tra từng thiết bị xem có thay đổi trạng thái không
        final deviceService = Provider.of<DeviceService>(context, listen: false);
        for (var device in deviceService.devices) {
          final currentOnline = _heartbeatService.isDeviceOnline(device.deviceId);
          final lastOnline = _lastOnlineStatus[device.deviceId];

          if (lastOnline != currentOnline) {
            _lastOnlineStatus[device.deviceId] = currentOnline;
            needsRebuild = true;
          }
        }

        // Chỉ rebuild nếu có thay đổi
        if (needsRebuild) {
          setState(() {});
        }
      }
    });

    // Load devices và kiểm tra thông báo sau khi build xong
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDevices();

      final deviceService = Provider.of<DeviceService>(context, listen: false);
      if (deviceService.errorMessage != null &&
          deviceService.errorMessage!.contains('Đã xóa')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(deviceService.errorMessage!),
            backgroundColor: AppTheme.warningColor,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
        deviceService.clearError();
      }
    });
  }

  @override
  void dispose() {
    _statusCheckTimer?.cancel();
    _cancelAllDeviceListeners();
    super.dispose();
  }

  // ===== THÊM: HỦY TẤT CẢ LISTENERS =====
  void _cancelAllDeviceListeners() {
    for (var subscription in _deviceListeners.values) {
      subscription.cancel();
    }
    _deviceListeners.clear();
  }

  // ===== THÊM: THEO DÕI THIẾT BỊ BỊ RESET =====
  void _listenToDeviceChanges(String deviceId) {
    // Hủy listener cũ nếu có
    _deviceListeners[deviceId]?.cancel();

    // Tạo listener mới theo dõi claimed status
    _deviceListeners[deviceId] = FirebaseDatabase.instance
        .ref('devices/$deviceId/info/claimed')
        .onValue
        .listen((event) {
      if (mounted && event.snapshot.exists) {
        final claimed = event.snapshot.value as bool?;

        // Nếu thiết bị bị reset (claimed = false)
        if (claimed == false) {
          print('⚠️ Phát hiện thiết bị $deviceId bị reset!');

          // Reload danh sách thiết bị
          _loadDevices();

          // Hiển thị thông báo
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Thiết bị đã bị xóa khỏi tài khoản của bạn.'),
                backgroundColor: AppTheme.warningColor,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    });
  }


  Future<void> _loadDevices() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final deviceService = Provider.of<DeviceService>(context, listen: false);
    final executor = Provider.of<ScheduleExecutor>(context, listen: false);
    final autoOffService = Provider.of<AutoOffService>(context, listen: false);

    if (authService.currentUser != null) {
      // Khởi tạo schedule executor với userId để tự động load devices
      executor.setUserId(authService.currentUser!.uid);

      // Khởi tạo auto-off service với userId
      autoOffService.setUserId(authService.currentUser!.uid);

      await deviceService.loadUserDevices(authService.currentUser!.uid);

      // ===== THÊM: BẮT ĐẦU LISTEN CHO MỖI DEVICE =====
      for (var device in deviceService.devices) {
        _listenToDeviceChanges(device.deviceId);

        // BẮT ĐẦU BACKGROUND ENERGY TRACKING CHO TẤT CẢ THIẾT BỊ
        _energyTracker.startTracking(device.deviceId);
      }
    }
  }

  void _showAccountMenu(AuthService authService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),

            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(height: 24),

            // Avatar và tên tài khoản
            CircleAvatar(
              radius: 40,
              backgroundColor: AppTheme.primaryColor,
              child: Text(
                _getInitials(authService.currentUser?.displayName ?? 'U'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              authService.currentUser?.displayName ?? 'Người dùng',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              authService.currentUser?.email ?? '',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 24),

            const Divider(height: 1),

            // Menu items
            ListTile(
              leading: const Icon(Icons.lock_reset, color: AppTheme.primaryColor),
              title: const Text('Đổi mật khẩu'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              },
            ),

            const Divider(height: 1),

            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Đăng xuất',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _handleLogout();
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await authService.logout();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  // Lấy chữ cái đầu từ tên
  String _getInitials(String name) {
    if (name.isEmpty) return 'U';

    final words = name.trim().split(' ');
    if (words.length >= 2) {
      // Lấy chữ cái đầu của 2 từ đầu
      return (words[0][0] + words[1][0]).toUpperCase();
    } else {
      // Lấy chữ cái đầu tiên
      return name[0].toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceService = Provider.of<DeviceService>(context);
    final authService = Provider.of<AuthService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thiết bị của tôi'),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: () async {
              // Hiển thị loading
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Đang tải lại...'),
                  duration: Duration(milliseconds: 500),
                ),
              );

              await _loadDevices();

              if (!mounted) return;

              // Hiển thị kết quả
              final deviceService = Provider.of<DeviceService>(context, listen: false);

              if (deviceService.errorMessage != null &&
                  deviceService.errorMessage!.contains('Da xoa')) {
                // Có device bị xóa
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(deviceService.errorMessage!),
                    backgroundColor: AppTheme.warningColor,
                    duration: const Duration(seconds: 3),
                  ),
                );
                deviceService.clearError();
              } else {
                // Không có gì thay đổi
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật danh sách'),
                    backgroundColor: AppTheme.successColor,
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
          // Avatar Button
          GestureDetector(
            onTap: () => _showAccountMenu(authService),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primaryColor,
                child: Text(
                  _getInitials(authService.currentUser?.displayName ?? 'U'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadDevices();
          
          if (!mounted) return;
          
          // Hiển thị thông báo nếu có device bị xóa
          final deviceService = Provider.of<DeviceService>(context, listen: false);
          
          if (deviceService.errorMessage != null && 
              deviceService.errorMessage!.contains('Da xoa')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(deviceService.errorMessage!),
                backgroundColor: AppTheme.warningColor,
                duration: const Duration(seconds: 3),
              ),
            );
            deviceService.clearError();
          }
        },
        child: deviceService.isLoading
            ? const Center(child: CircularProgressIndicator())
            : deviceService.devices.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: deviceService.devices.length,
                    itemBuilder: (context, index) {
                      final device = deviceService.devices[index];
                      return _buildDeviceCard(device);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
           Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddDeviceScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Thêm thiết bị'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.devices_other,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có thiết bị nào',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nhấn nút bên dưới để thêm thiết bị',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(DeviceModel device) {
  return Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: InkWell(
      onTap: () {
        // Kiểm tra thiết bị có online không trước khi vào Control Screen
        final isOnline = _heartbeatService.isDeviceOnline(device.deviceId);

        if (!isOnline) {
          // Hiển thị thông báo thiết bị offline
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Thiết bị "${device.name}" đang offline. Vui lòng kiểm tra kết nối.'),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        // Thiết bị online → cho phép vào Control Screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ControlScreen(device: device),
          ),
        );
      },
      onLongPress: () => _showDeleteDialog(device),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref('status/${device.deviceId}')
              .onValue,
          builder: (context, snapshot) {
            // Dữ liệu mặc định
            double roomTemp = 0;
            double roomHumidity = 0;
            bool hasPerson = false;
            bool acPowerOn = false;
            bool isOnline = false;
            int? lastUpdateTimestamp;

            if (snapshot.hasData && snapshot.data!.snapshot.exists) {
              final data = Map<String, dynamic>.from(
                snapshot.data!.snapshot.value as Map
              );

              // Đọc lastSeen từ root level (ESP32 gửi lên)
              lastUpdateTimestamp = data['lastSeen'];

              // Kiểm tra xem đây có phải lần đầu load không
              final isFirstLoad = _heartbeatService.getLastSeen(device.deviceId) == null;

              if (lastUpdateTimestamp != null) {
                if (isFirstLoad) {
                  // Lần đầu load: chỉ lưu giá trị, không coi là thay đổi
                  _heartbeatService.initLastSeen(device.deviceId, lastUpdateTimestamp);
                  isOnline = false; // Mặc định offline cho đến khi có update thật
                } else {
                  // Có update mới: cập nhật và kiểm tra online
                  _heartbeatService.updateLastSeen(device.deviceId, lastUpdateTimestamp);
                  isOnline = _heartbeatService.isDeviceOnline(device.deviceId);
                }
              }

              // Đọc room data - Áp dụng hiệu chỉnh cho cảm biến DHT22
              if (data['room'] != null) {
                final room = Map<String, dynamic>.from(data['room']);
                final double rawTemp = (room['temp'] ?? 0).toDouble();
                final double rawHumidity = (room['humidity'] ?? 0).toDouble();

                // Hiệu chỉnh dữ liệu cảm biến DHT22
                roomTemp = SensorCalibration.calibrateTemperature(rawTemp) ?? 0.0;
                roomHumidity = SensorCalibration.calibrateHumidity(rawHumidity) ?? 0.0;
                hasPerson = room['hasPerson'] ?? false;
              }

              // Đọc AC data
              if (data['ac'] != null) {
                final ac = Map<String, dynamic>.from(data['ac']);
                final powerCurrent = (ac['current'] ?? 0).toDouble();
                acPowerOn = powerCurrent > AppConstants.acPowerOnThreshold;  // Ngưỡng công suất để xác định bật/tắt
              }
            }

            return Column(
              children: [
                // Header
                Row(
                  children: [
                    // Icon
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.ac_unit,
                        color: AppTheme.primaryColor,
                        size: 28,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Name & Status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isOnline ? AppTheme.successColor : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isOnline ? AppTheme.successColor : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Settings Button
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.grey),
                      onPressed: () async {
                        final authService = Provider.of<AuthService>(context, listen: false);
                        final userId = authService.currentUser?.uid ?? '';

                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeviceSettingsScreen(
                              device: device,
                              userId: userId,
                            ),
                          ),
                        );

                        // Nếu có thay đổi, reload danh sách
                        if (result == true && mounted) {
                          _loadDevices();
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // AC Status Row
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: acPowerOn
                        ? AppTheme.successColor.withOpacity(0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.power_settings_new,
                        size: 18,
                        color: acPowerOn ? AppTheme.successColor : Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        acPowerOn ? 'Máy lạnh đang bật' : 'Máy lạnh đang tắt',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: acPowerOn ? AppTheme.successColor : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),

                // Chỉ hiển thị dữ liệu cảm biến khi thiết bị online
                if (isOnline) ...[
                  const SizedBox(height: 12),

                  // Sensor Data Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.thermostat_outlined,
                          label: 'Nhiệt độ',
                          value: roomTemp > 0
                              ? '${roomTemp.toStringAsFixed(0)}°C'
                              : '--°C',
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.water_drop_outlined,
                          label: 'Độ ẩm',
                          value: roomHumidity > 0
                              ? '${roomHumidity.toStringAsFixed(0)}%'
                              : '--%',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          icon: hasPerson ? Icons.person : Icons.person_outline,
                          label: 'Có người',
                          value: hasPerson ? 'Có' : 'Không',
                          color: hasPerson ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

Widget _buildInfoCard({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
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

  Future<void> _showDeleteDialog(DeviceModel device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa thiết bị'),
        content: Text('Bạn có chắc muốn xóa "${device.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final deviceService = Provider.of<DeviceService>(context, listen: false);
      final authService = Provider.of<AuthService>(context, listen: false);

      await deviceService.removeDevice(
        authService.currentUser!.uid,
        device.deviceId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa "${device.name}"'),
          backgroundColor: AppTheme.successColor,
        ),
      );
    }
  }
}