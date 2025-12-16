/// Các hằng số chung của ứng dụng
class AppConstants {
  /// Ngưỡng dòng điện (Ampere) để xác định máy lạnh đang bật hay tắt
  ///
  /// **QUAN TRỌNG**: Chỉ cần thay đổi giá trị này ở đây,
  /// tất cả các chỗ khác sẽ tự động áp dụng ngưỡng mới
  ///
  /// Ví dụ:
  /// - Nếu dòng điện > acPowerOnThreshold thì máy đang bật
  /// - Nếu dòng điện <= acPowerOnThreshold thì máy đang tắt
  static const double acPowerOnThreshold = 0.2; // Ampere (A)

  // Có thể thêm các hằng số khác ở đây nếu cần
}
