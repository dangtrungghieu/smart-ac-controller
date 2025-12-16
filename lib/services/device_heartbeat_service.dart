/// Service để theo dõi heartbeat (lastSeen) của thiết bị
/// lastSeen là uptime của ESP32 (tính bằng milliseconds từ lúc khởi động)
/// Nếu lastSeen thay đổi → thiết bị đang hoạt động
class DeviceHeartbeatService {
  // Lưu trữ lastSeen và thời gian nhận được lastSeen đó
  final Map<String, _HeartbeatInfo> _deviceHeartbeats = {};

  // Thời gian timeout để xác định thiết bị offline (10 giây)
  static const int timeoutSeconds = 10;

  /// Cập nhật lastSeen từ database (lần đầu load)
  /// Không coi là "thay đổi", chỉ lưu trữ giá trị ban đầu
  void initLastSeen(String deviceId, int? lastSeen) {
    if (lastSeen == null) return;

    // Lưu với thời gian trong quá khứ xa để thiết bị hiển thị offline
    // trừ khi có update thật sự
    _deviceHeartbeats[deviceId] = _HeartbeatInfo(
      lastSeen: lastSeen,
      lastReceivedTime: DateTime.now().subtract(const Duration(minutes: 5)),
    );
  }

  /// Cập nhật lastSeen từ database (khi có thay đổi thật)
  /// Trả về true nếu có thay đổi
  bool updateLastSeen(String deviceId, int? lastSeen) {
    if (lastSeen == null) return false;

    final now = DateTime.now();

    // Nếu chưa có thông tin về device này (không nên xảy ra nếu đã gọi initLastSeen)
    if (!_deviceHeartbeats.containsKey(deviceId)) {
      _deviceHeartbeats[deviceId] = _HeartbeatInfo(
        lastSeen: lastSeen,
        lastReceivedTime: now,
      );
      return true;
    }

    final info = _deviceHeartbeats[deviceId]!;

    // Kiểm tra xem lastSeen có thay đổi không
    if (info.lastSeen != lastSeen) {
      // lastSeen đã thay đổi → thiết bị đang hoạt động
      _deviceHeartbeats[deviceId] = _HeartbeatInfo(
        lastSeen: lastSeen,
        lastReceivedTime: now,
      );
      return true;
    }

    return false;
  }

  /// Kiểm tra thiết bị có online không
  /// Online nếu lastSeen thay đổi trong vòng 30 giây gần đây
  bool isDeviceOnline(String deviceId) {
    if (!_deviceHeartbeats.containsKey(deviceId)) {
      return false;
    }

    final info = _deviceHeartbeats[deviceId]!;
    final now = DateTime.now();
    final difference = now.difference(info.lastReceivedTime);

    return difference.inSeconds <= timeoutSeconds;
  }

  /// Lấy thời gian từ lần nhận lastSeen cuối cùng
  String getLastSeenText(String deviceId) {
    if (!_deviceHeartbeats.containsKey(deviceId)) {
      return 'Chưa có dữ liệu';
    }

    final info = _deviceHeartbeats[deviceId]!;
    final now = DateTime.now();
    final difference = now.difference(info.lastReceivedTime);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} giây trước';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else {
      return '${difference.inDays} ngày trước';
    }
  }

  /// Lấy giá trị lastSeen hiện tại
  int? getLastSeen(String deviceId) {
    return _deviceHeartbeats[deviceId]?.lastSeen;
  }

  /// Xóa thông tin heartbeat của thiết bị
  void removeDevice(String deviceId) {
    _deviceHeartbeats.remove(deviceId);
  }

  /// Xóa tất cả thông tin heartbeat
  void clear() {
    _deviceHeartbeats.clear();
  }
}

/// Class để lưu thông tin heartbeat
class _HeartbeatInfo {
  final int lastSeen; // Giá trị uptime từ ESP32
  final DateTime lastReceivedTime; // Thời gian app nhận được giá trị này

  _HeartbeatInfo({
    required this.lastSeen,
    required this.lastReceivedTime,
  });
}
