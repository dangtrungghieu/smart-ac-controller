import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device_model.dart';
import '../models/room_status_model.dart';
import 'energy_monitoring_service.dart';

class DeviceService extends ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  
  List<DeviceModel> _devices = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<DeviceModel> get devices => _devices;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Load danh sách thiết bị của user
Future<void> loadUserDevices(String userId) async {
  try {
    _isLoading = true;
    notifyListeners();

    final snapshot = await _db.child('user_devices/$userId').get();
    
    _devices.clear();
    List<String> removedDevices = []; // Danh sách device bị reset
    
    if (snapshot.exists) {
      final deviceIds = Map<String, dynamic>.from(snapshot.value as Map);
      
      for (var deviceId in deviceIds.keys) {
        final deviceSnapshot = await _db.child('devices/$deviceId').get();
        
        if (!deviceSnapshot.exists) {
          // Device không tồn tại trong devices/ = đã bị xóa
          print('⚠️ Device $deviceId khong ton tai trong devices/');
          await _db.child('user_devices/$userId/$deviceId').remove();
          removedDevices.add(deviceId);
          continue;
        }
        
        final deviceData = Map<String, dynamic>.from(deviceSnapshot.value as Map);
        
        if (deviceData['info'] == null) {
          // Device không có info = dữ liệu lỗi
          print('⚠️ Device $deviceId khong co info');
          await _db.child('user_devices/$userId/$deviceId').remove();
          removedDevices.add(deviceId);
          continue;
        }
        
        final info = Map<String, dynamic>.from(deviceData['info']);
        final deviceName = info['deviceName'] ?? deviceId;
        
        // ===== KIỂM TRA DEVICE CÓ BỊ RESET KHÔNG =====
        if (info['claimed'] == false) {
          // Device bị reset về unclaimed
          print('⚠️ Device $deviceId (${deviceName}) da bi reset (claimed = false)');
          await _db.child('user_devices/$userId/$deviceId').remove();
          removedDevices.add(deviceName);
          continue;
        }
        
        if (info['ownerId'] != userId) {
          // Owner khác = device đã được claim bởi người khác
          print('⚠️ Device $deviceId (${deviceName}) khong phai cua user nay (ownerId khac)');
          await _db.child('user_devices/$userId/$deviceId').remove();
          removedDevices.add(deviceName);
          continue;
        }
        
        // ===== DEVICE HỢP LỆ - THÊM VÀO DANH SÁCH =====
        final device = DeviceModel.fromJson(deviceId, deviceData);
        
        // Load status
        final statusSnapshot = await _db.child('status/$deviceId').get();
        if (statusSnapshot.exists) {
          final statusData = Map<String, dynamic>.from(statusSnapshot.value as Map);
          final updatedDevice = DeviceModel.fromJson(
            deviceId,
            {
              ...deviceData,
              'info': {
                ...info,
                'online': statusData['online'] ?? false,
                'lastSeen': statusData['lastSeen'],
              }
            },
          );
          _devices.add(updatedDevice);
        } else {
          _devices.add(device);
        }
      }
    }

    _isLoading = false;
    
    // Thông báo nếu có device bị xóa
    if (removedDevices.isNotEmpty) {
      _errorMessage = 'Da xoa ${removedDevices.length} thiet bi bi reset: ${removedDevices.join(", ")}';
    }
    
    notifyListeners();
  } catch (e) {
    _isLoading = false;
    _errorMessage = 'Loi tai danh sach thiet bi: $e';
    print('Error loadUserDevices: $e');
    notifyListeners();
  }
}

  // ===== THÊM: VALIDATE DEVICE (không claim) =====
  Future<bool> validateDevice({
    required String deviceId,
    required String claimCode,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      print('>>> Bat dau validate device: $deviceId');

      // Kiểm tra device có tồn tại không
      final deviceSnapshot = await _db.child('devices/$deviceId/info').get();

      if (!deviceSnapshot.exists) {
        _errorMessage = 'Thiet bi khong ton tai trong he thong';
        _isLoading = false;
        notifyListeners();
        print('✗ Device khong ton tai');
        return false;
      }

      final deviceData = Map<String, dynamic>.from(deviceSnapshot.value as Map);
      print('✓ Device ton tai: ${deviceData['deviceId']}');

      // Kiểm tra claim code
      if (deviceData['claimCode'] != claimCode) {
        _errorMessage = 'Claim code khong dung';
        _isLoading = false;
        notifyListeners();
        print('✗ Claim code sai');
        return false;
      }
      print('✓ Claim code dung');

      // Kiểm tra device đã published chưa
      if (deviceData['published'] != true) {
        _errorMessage = 'Thiet bi chua duoc kich hoat boi admin';
        _isLoading = false;
        notifyListeners();
        print('✗ Device chua duoc published');
        return false;
      }
      print('✓ Device da duoc published');

      // Kiểm tra device đã bị claim chưa
      if (deviceData['claimed'] == true) {
        _errorMessage = 'Thiet bi da duoc them boi nguoi khac';
        _isLoading = false;
        notifyListeners();
        print('✗ Device da duoc claim');
        return false;
      }
      print('✓ Device chua duoc claim');

      _isLoading = false;
      notifyListeners();

      print('✓✓✓ VALIDATE THANH CONG!');
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Loi kiem tra thiet bi: $e';
      print('✗ Loi validate: $e');
      notifyListeners();
      return false;
    }
  }

  // Thêm thiết bị mới (claim)
  Future<bool> claimDevice({
    required String userId,
    required String deviceId,
    required String claimCode,
    required String deviceName,
  }) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      print('>>> Bat dau claim device: $deviceId');

      // ===== BƯỚC 1: KIỂM TRA DEVICE CÓ TỒN TẠI KHÔNG =====
      final deviceSnapshot = await _db.child('devices/$deviceId/info').get();

      if (!deviceSnapshot.exists) {
        _errorMessage = 'Thiet bi khong ton tai trong he thong';
        _isLoading = false;
        notifyListeners();
        print('✗ Device khong ton tai');
        return false;
      }

      final deviceData = Map<String, dynamic>.from(deviceSnapshot.value as Map);

      print('✓ Device ton tai: ${deviceData['deviceId']}');

      // ===== BƯỚC 2: KIỂM TRA CLAIM CODE =====
      if (deviceData['claimCode'] != claimCode) {
        _errorMessage = 'Claim code khong dung';
        _isLoading = false;
        notifyListeners();
        print('✗ Claim code sai');
        return false;
      }

      print('✓ Claim code dung');

      // ===== BƯỚC 3: KIỂM TRA DEVICE CÓ PUBLISHED KHÔNG =====
      if (deviceData['published'] != true) {
        _errorMessage = 'Thiet bi chua duoc kich hoat boi admin';
        _isLoading = false;
        notifyListeners();
        print('✗ Device chua duoc published');
        return false;
      }

      print('✓ Device da duoc published');

      // ===== BƯỚC 4: CẬP NHẬT DEVICE INFO =====
      await _db.child('devices/$deviceId/info').update({
        'deviceName': deviceName,
        'claimed': true,
        'ownerId': userId,
        'claimedAt': DateTime.now().millisecondsSinceEpoch,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });

      print('✓ Da cap nhat device info');

      // ===== BƯỚC 5: THÊM VÀO USER_DEVICES =====
      await _db.child('user_devices/$userId/$deviceId').set(true);

      print('✓ Da them vao user_devices');
      print('✓✓✓ CLAIM THANH CONG!');

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Loi them thiet bi: $e';
      print('✗ Loi: $e');
      notifyListeners();
      return false;
    }
  }

  // Xóa thiết bị (Factory Reset - giống ESP32)
  Future<bool> removeDevice(String userId, String deviceId) async {
  try {
    _isLoading = true;
    notifyListeners();

    print('>>> Bat dau xoa thiet bi: $deviceId');

    // ===== BƯỚC 1: RESET DEVICE INFO =====
    print('Dang reset device info...');
    await _db.child('devices/$deviceId/info').update({
      'claimed': false,
      'ownerId': '',
      'deviceName': '',
      'roomName': '',
      'macAddress': '', // Xóa MAC Address
      'lastModified': DateTime.now().millisecondsSinceEpoch,
    });
    print('✓ Da reset device info');

    // ===== BƯỚC 2: XÓA IR CONFIG =====
    print('Dang xoa IR config...');
    await _db.child('devices/$deviceId/ir').remove();
    print('✓ Da xoa IR config');

    // ===== BƯỚC 3: XÓA KHỎI USER_DEVICES =====
    print('Dang xoa khoi user_devices/$userId/$deviceId');
    await _db.child('user_devices/$userId/$deviceId').remove();
    print('✓ Da xoa khoi user_devices');

    // ===== BƯỚC 4: XÓA STATUS =====
    print('Dang xoa status...');
    await _db.child('status/$deviceId').remove();
    print('✓ Da xoa status');

    // ===== BƯỚC 5: XÓA COMMANDS =====
    print('Dang xoa commands...');
    await _db.child('commands/$deviceId').remove();
    print('✓ Da xoa commands');

    // ===== BƯỚC 6: XÓA IR_LEARNING =====
    print('Dang xoa ir_learning...');
    await _db.child('ir_learning/$deviceId').remove();
    print('✓ Da xoa ir_learning');

    // ===== BƯỚC 7: XÓA ENERGY CACHE =====
    print('Dang xoa energy cache...');
    final energyService = EnergyMonitoringService();
    energyService.clearCache(deviceId);
    print('✓ Da xoa energy cache');

    print('✓✓✓ HOAN THANH xoa thiet bi!');

    // Reload danh sách
    await loadUserDevices(userId);

    _isLoading = false;
    notifyListeners();

    return true;
  } catch (e) {
    _isLoading = false;
    _errorMessage = 'Loi xoa thiet bi: $e';
    print('✗ Loi xoa thiet bi: $e');
    notifyListeners();
    return false;
  }
}
  // Cập nhật tên thiết bị
  Future<bool> updateDeviceName(String deviceId, String newName) async {
    try {
      await _db.child('devices/$deviceId/name').set(newName);
      
      // Cập nhật local
      final index = _devices.indexWhere((d) => d.deviceId == deviceId);
      if (index != -1) {
        _devices[index] = DeviceModel.fromJson(
          deviceId,
          {
            ..._devices[index].toJson(),
            'name': newName,
          },
        );
        notifyListeners();
      }
      
      return true;
    } catch (e) {
      _errorMessage = 'Lỗi cập nhật tên: $e';
      notifyListeners();
      return false;
    }
  }

  // Gửi lệnh điều khiển
  Future<bool> sendCommand({
    required String deviceId,
    required String action,
    int? value,
  }) async {
    try {
      await _db.child('commands/$deviceId').set({
        'action': action,
        'value': value ?? 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'executed': false,
      });
      
      return true;
    } catch (e) {
      _errorMessage = 'Lỗi gửi lệnh: $e';
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}