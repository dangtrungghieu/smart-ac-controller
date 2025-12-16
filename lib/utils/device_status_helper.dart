class DeviceStatusHelper {
  // Thời gian timeout để xác định thiết bị offline (30 giây)
  static const int offlineTimeoutSeconds = 30;

  /// Kiểm tra xem thiết bị có online không dựa trên lastUpdate timestamp
  /// Trả về true nếu dữ liệu được cập nhật trong vòng 30 giây gần đây
  ///
  /// Thiết bị được coi là online nếu:
  /// - Có cập nhật nhiệt độ/độ ẩm trong 30 giây gần đây (cho thiết bị điều khiển)
  /// - Có cập nhật PZEM (dòng điện) trong 30 giây gần đây (cho máy lạnh)
  static bool isDeviceOnline(int? lastUpdateTimestamp) {
    if (lastUpdateTimestamp == null) return false;

    final lastUpdate = DateTime.fromMillisecondsSinceEpoch(lastUpdateTimestamp);
    final now = DateTime.now();
    final difference = now.difference(lastUpdate);

    return difference.inSeconds <= offlineTimeoutSeconds;
  }

  /// Lấy thời gian từ lần cập nhật cuối (vd: "5 giây trước", "2 phút trước")
  static String getLastUpdateText(int? lastUpdateTimestamp) {
    if (lastUpdateTimestamp == null) return 'Chưa có dữ liệu';

    final lastUpdate = DateTime.fromMillisecondsSinceEpoch(lastUpdateTimestamp);
    final now = DateTime.now();
    final difference = now.difference(lastUpdate);

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
}