import 'dart:async';
import 'package:flutter/material.dart';
import '../models/temp_suggestion_model.dart'; // V2 - Logic thông minh
import '../services/weather_service.dart';
import '../utils/theme.dart';

/// Widget hiển thị gợi ý thông minh về điều chỉnh nhiệt độ máy lạnh
///
/// Widget này sẽ:
/// 1. Lấy nhiệt độ ngoài trời từ API thời tiết
/// 2. Sử dụng nhiệt độ phòng từ sensor
/// 3. Tính toán gợi ý điều chỉnh nhiệt độ máy lạnh
/// 4. Hiển thị gợi ý và nút "Áp dụng gợi ý"
///
/// Sử dụng:
/// ```dart
/// SmartTempSuggestionWidget(
///   roomTemp: 28.5,
///   acSetTemp: 26,
///   isAcOn: true,
///   onApplySuggestion: (newTemp) async {
///     // Gọi API để cài nhiệt độ mới
///     await _setTemp(newTemp);
///   },
/// )
/// ```
class SmartTempSuggestionWidget extends StatefulWidget {
  /// Nhiệt độ phòng hiện tại từ sensor (°C)
  final double roomTemp;

  /// Độ ẩm phòng hiện tại từ sensor (%)
  final double roomHumidity;

  /// Nhiệt độ đang cài trên máy lạnh (°C)
  final int acSetTemp;

  /// Trạng thái máy lạnh (true = đang bật)
  final bool isAcOn;

  /// Thiết bị có online không
  final bool isOnline;

  /// Callback khi người dùng nhấn "Áp dụng gợi ý"
  /// Trả về nhiệt độ mới cần cài đặt
  final Future<void> Function(int newTemp) onApplySuggestion;

  /// Callback khi người dùng nhấn "Bật máy lạnh" (khi máy đang tắt)
  final Future<void> Function()? onTurnOnAc;

  const SmartTempSuggestionWidget({
    super.key,
    required this.roomTemp,
    required this.roomHumidity,
    required this.acSetTemp,
    required this.isAcOn,
    required this.isOnline,
    required this.onApplySuggestion,
    this.onTurnOnAc,
  });

  @override
  State<SmartTempSuggestionWidget> createState() => _SmartTempSuggestionWidgetState();
}

class _SmartTempSuggestionWidgetState extends State<SmartTempSuggestionWidget> {
  double? _outdoorTemp; // Nhiệt độ ngoài trời từ API
  bool _isLoadingWeather = false;
  bool _isApplying = false; // Đang áp dụng gợi ý
  String? _weatherError;
  Timer? _autoRefreshTimer; // Timer tự động refresh
  DateTime? _lastUpdate; // Thời gian cập nhật lần cuối
  int _retryCount = 0; // Số lần retry
  DateTime? _lastAppliedTime; // Thời gian áp dụng gợi ý lần cuối
  Timer? _cooldownTimer; // Timer kiểm tra cooldown

  @override
  void initState() {
    super.initState();
    // Load nhiệt độ ngay khi khởi tạo
    _fetchOutdoorTemperature();

    // ===== TỰ ĐỘNG REFRESH MỖI 1 PHÚT =====
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        print('>>> Auto-refresh nhiệt độ ngoài trời (sau 1 phút)');
        _fetchOutdoorTemperature();
      }
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Lấy nhiệt độ ngoài trời từ API
  Future<void> _fetchOutdoorTemperature() async {
    setState(() {
      _isLoadingWeather = true;
      _weatherError = null;
    });

    try {
      double? temp;

      // Kiểm tra API đã được cấu hình chưa
      if (WeatherService.isApiConfigured()) {
        // Gọi API thật
        temp = await WeatherService.fetchOutdoorTemperature();
      } else {
        // Dùng dữ liệu MOCK để test
        temp = await WeatherService.fetchMockTemperature();
      }

      if (mounted) {
        setState(() {
          _outdoorTemp = temp;
          _isLoadingWeather = false;
          _lastUpdate = DateTime.now(); // Cập nhật thời gian
          _retryCount = 0; // Reset retry count khi thành công
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weatherError = 'Không lấy được nhiệt độ ngoài trời';
          _isLoadingWeather = false;
          _retryCount++;
        });

        // ===== TỰ ĐỘNG RETRY KHI LỖI (TỐI ĐA 3 LẦN) =====
        if (_retryCount <= 3) {
          print('>>> Retry lần $_retryCount sau 5 giây...');
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              _fetchOutdoorTemperature();
            }
          });
        } else {
          print('>>> Đã retry 3 lần, dừng lại');
        }
      }
    }
  }

  /// Áp dụng gợi ý
  Future<void> _applySuggestion(TempSuggestion suggestion) async {
    if (!widget.isOnline) {
      _showMessage('Thiết bị đang offline', isError: true);
      return;
    }

    setState(() {
      _isApplying = true;
    });

    try {
      // Nếu máy đang tắt và có callback bật máy
      if (!widget.isAcOn && widget.onTurnOnAc != null) {
        await widget.onTurnOnAc!();
        // Đợi 1 giây để máy lạnh bật
        await Future.delayed(const Duration(seconds: 1));
      }

      // Áp dụng nhiệt độ mới
      await widget.onApplySuggestion(suggestion.suggestedTemp);

      if (mounted) {
        // Lưu thời gian áp dụng gợi ý
        setState(() {
          _lastAppliedTime = DateTime.now();
        });

        // Thiết lập timer để tự động hiện lại sau 10 phút
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer(const Duration(minutes: 1), () {
          if (mounted) {
            setState(() {
              _lastAppliedTime = null;
            });
          }
        });

        _showMessage('Đã áp dụng gợi ý: ${suggestion.suggestedTemp}°C', isError: false);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Lỗi khi áp dụng gợi ý', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ===== ẨN HOÀN TOÀN WIDGET TRONG 1 PHÚT SAU KHI ÁP DỤNG GỢI Ý =====
    if (_lastAppliedTime != null) {
      final timeSinceApplied = DateTime.now().difference(_lastAppliedTime!);
      if (timeSinceApplied.inMinutes < 1) {
        // Không hiển thị gì cả - tạo cảm giác tự động hóa
        return const SizedBox.shrink();
      }
    }

    // Nếu đang load nhiệt độ ngoài trời, hiển thị loading
    if (_isLoadingWeather) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                'Đang lấy dữ liệu thời tiết...',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // Tính toán gợi ý (V2 - Thông minh hơn)
    final suggestion = TempSuggestionService.calculateSuggestion(
      realTemp: _outdoorTemp ?? 0,
      roomTemp: widget.roomTemp,
      roomHumidity: widget.roomHumidity, // THÊM ĐỘ ẨM
      acSetTemp: widget.acSetTemp,
      isAcOn: widget.isAcOn,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.lightbulb_outline,
                    color: AppTheme.primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gợi ý thông minh',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_lastUpdate != null)
                        Text(
                          _getTimeAgo(_lastUpdate!),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                // ẨN NÚT REFRESH - CHỈ AUTO-LOAD
                if (_isLoadingWeather)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // Thông tin nhiệt độ ngoài trời
            if (_outdoorTemp != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wb_sunny, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Nhiệt độ ngoài trời:',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_outdoorTemp!.toStringAsFixed(1)}°C',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),

            if (_weatherError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _weatherError!,
                        style: TextStyle(fontSize: 12, color: Colors.orange[900]),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Gợi ý
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _getSuggestionGradient(suggestion.action),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        suggestion.icon,
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.message,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              suggestion.reason,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Nút áp dụng gợi ý (chỉ hiện khi có thay đổi)
                  if (suggestion.shouldShow) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: (!widget.isOnline || _isApplying)
                            ? null
                            : () => _applySuggestion(suggestion),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _getSuggestionColor(suggestion.action),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: _isApplying
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(_getSuggestionIcon(suggestion.action)),
                        label: Text(
                          _isApplying
                              ? 'Đang áp dụng...'
                              : (!widget.isAcOn
                                  ? 'Bật máy và cài ${suggestion.suggestedTemp}°C'
                                  : 'Áp dụng gợi ý (${suggestion.suggestedTemp}°C)'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Lưu ý khi offline
            if (!widget.isOnline) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Thiết bị offline. Vui lòng kiểm tra kết nối.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
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

  /// Lấy màu gradient cho container gợi ý
  List<Color> _getSuggestionGradient(TempSuggestionAction action) {
    switch (action) {
      case TempSuggestionAction.decrease:
        return [Colors.blue[400]!, Colors.blue[600]!];
      case TempSuggestionAction.increase:
        return [Colors.orange[400]!, Colors.orange[600]!];
      case TempSuggestionAction.keep:
        return [Colors.green[400]!, Colors.green[600]!];
      case TempSuggestionAction.turnOff:
        return [Colors.purple[400]!, Colors.purple[600]!];
    }
  }

  /// Lấy màu chính cho action
  Color _getSuggestionColor(TempSuggestionAction action) {
    switch (action) {
      case TempSuggestionAction.decrease:
        return Colors.blue[700]!;
      case TempSuggestionAction.increase:
        return Colors.orange[700]!;
      case TempSuggestionAction.keep:
        return Colors.green[700]!;
      case TempSuggestionAction.turnOff:
        return Colors.purple[700]!;
    }
  }

  /// Lấy icon cho action
  IconData _getSuggestionIcon(TempSuggestionAction action) {
    switch (action) {
      case TempSuggestionAction.decrease:
        return Icons.arrow_downward;
      case TempSuggestionAction.increase:
        return Icons.arrow_upward;
      case TempSuggestionAction.keep:
        return Icons.check_circle;
      case TempSuggestionAction.turnOff:
        return Icons.power_settings_new;
    }
  }

  /// Lấy chuỗi thời gian "X phút trước", "X giờ trước"
  String _getTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inSeconds < 60) {
      return 'Vừa cập nhật';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else {
      return '${difference.inDays} ngày trước';
    }
  }
}
