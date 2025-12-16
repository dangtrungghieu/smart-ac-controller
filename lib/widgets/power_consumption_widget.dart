import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/device_energy_status.dart';
import '../services/energy_monitoring_service.dart';
import '../utils/theme.dart';

/// Widget ước tính tiền điện tiêu thụ của máy lạnh
/// Tích hợp Firebase để lưu trữ persistent data
class PowerConsumptionWidget extends StatefulWidget {
  // Dữ liệu từ PZEM-004T
  final String deviceId;
  final double voltage; // V
  final double current; // A
  final double powerWatts; // W
  final double energyKWh; // kWh (tích lũy từ PZEM)
  final double powerFactor; // PF (0-1)

  // Cấu hình từ user
  final int electricityPrice; // VNĐ/kWh
  final int ratedPowerWatts; // Công suất định mức (W)

  // Trạng thái máy lạnh
  final bool isAcOn;

  const PowerConsumptionWidget({
    super.key,
    required this.deviceId,
    required this.voltage,
    required this.current,
    required this.powerWatts,
    required this.energyKWh,
    required this.powerFactor,
    this.electricityPrice = 3000,
    this.ratedPowerWatts = 1100,
    required this.isAcOn,
  });

  @override
  State<PowerConsumptionWidget> createState() => _PowerConsumptionWidgetState();
}

class _PowerConsumptionWidgetState extends State<PowerConsumptionWidget> {
  final EnergyMonitoringService _energyService = EnergyMonitoringService();

  DeviceEnergyStatus? _energyStatus;
  bool _isLoading = true;

  // Stream subscription để lắng nghe thay đổi từ Firebase
  StreamSubscription? _energyStatusListener;

  // Timer để rebuild UI mỗi giây (hiển thị realtime counter)
  Timer? _uiUpdateTimer;

  @override
  void initState() {
    super.initState();
    // Load initial data và lắng nghe thay đổi từ Firebase
    _initializeStatus();
    _listenToEnergyStatus();

    // Timer để rebuild UI mỗi giây khi máy đang chạy
    _startUIUpdateTimer();
  }

  @override
  void didUpdateWidget(PowerConsumptionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Session tracking giờ được xử lý bởi BackgroundEnergyTracker
    // Widget này chỉ hiển thị dữ liệu từ Firebase (qua listener)

    // Nếu cấu hình thay đổi
    if (oldWidget.electricityPrice != widget.electricityPrice ||
        oldWidget.ratedPowerWatts != widget.ratedPowerWatts) {
      _updateConfiguration();
    }
  }

  @override
  void dispose() {
    _energyStatusListener?.cancel();
    _uiUpdateTimer?.cancel();
    // KHÔNG end session khi dispose widget vì máy vẫn đang chạy
    // Session được quản lý bởi BackgroundEnergyTracker
    super.dispose();
  }

  /// Timer để rebuild UI mỗi giây (chỉ khi máy đang chạy)
  void _startUIUpdateTimer() {
    _uiUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final isAcOn = widget.isAcOn;
        final hasSession = _energyStatus?.sessionStartTimestamp != null;

        // Debug: Log mỗi 5 giây để không spam console
        if (DateTime.now().second % 5 == 0) {
          print('🖥️ [UI_TIMER] isAcOn=$isAcOn, hasSession=$hasSession, sessionStart=${_energyStatus?.sessionStartTimestamp}');
        }

        if (isAcOn && hasSession) {
          // Rebuild UI để cập nhật "Thời gian chạy hôm nay"
          setState(() {
            // Chỉ rebuild, không thay đổi data
          });
        }
      }
    });
  }

  /// Lắng nghe thay đổi energy status từ Firebase
  void _listenToEnergyStatus() {
    _energyStatusListener = FirebaseDatabase.instance
        .ref('status/${widget.deviceId}/energy')
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          final status = DeviceEnergyStatus.fromJson(data);

          setState(() {
            _energyStatus = status;
          });
        } catch (e) {
          print('❌ Error parsing energy status: $e');
        }
      }
    });
  }

  /// Khởi tạo trạng thái lần đầu
  Future<void> _initializeStatus() async {
    if (!mounted) return;

    try {
      // Load status từ Firebase
      var status = await _energyService.loadEnergyStatus(widget.deviceId);

      // Nếu chưa có energy data → khởi tạo
      if (status == null) {
        print('🆕 Energy data not found, initializing for ${widget.deviceId}');
        await _energyService.initializeStatus(
          deviceId: widget.deviceId,
          electricityPrice: widget.electricityPrice,
          ratedPowerWatts: widget.ratedPowerWatts,
        );
        status = await _energyService.loadEnergyStatus(widget.deviceId);
      }

      if (mounted) {
        setState(() {
          _energyStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error initializing status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Cập nhật cấu hình (giá điện, công suất định mức)
  Future<void> _updateConfiguration() async {
    if (!mounted) return;

    try {
      await _energyService.updateConfiguration(
        deviceId: widget.deviceId,
        electricityPrice: widget.electricityPrice,
        ratedPowerWatts: widget.ratedPowerWatts,
      );

      // Reload status sau khi update config
      final status = await _energyService.loadEnergyStatus(widget.deviceId);
      if (mounted) {
        setState(() {
          _energyStatus = status;
        });
      }
    } catch (e) {
      print('❌ Error updating configuration: $e');
    }
  }

  /// Format VND currency
  String _formatVND(double amount) {
    final formatted = amount.toStringAsFixed(0);
    final parts = formatted.split('.');
    final mainPart = parts[0];
    final formattedMain = mainPart.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return formattedMain;
  }

  /// Get color based on load percentage
  Color _getLoadColor(double loadPercent) {
    if (loadPercent < 30) {
      return const Color(0xFF4CAF50); // Green - Eco mode
    } else if (loadPercent < 70) {
      return const Color(0xFFFF9800); // Orange - Normal
    } else {
      return const Color(0xFFF44336); // Red - High power
    }
  }

  /// Get load description
  String _getLoadDescription(double loadPercent) {
    if (loadPercent < 30 && loadPercent > 5) {
      return 'Tiết kiệm điện';
    } else if (loadPercent < 80 && loadPercent > 30) {
      return 'Bình thường';
    } else if (loadPercent > 80){
      return 'Tiêu thụ cao';
    } else {
      return 'Đang chờ...';
    }
  }

  /// Get AI comment based on power consumption and room temperature
  ({String text, IconData icon, Color color})? _getAIComment() {
    if (!widget.isAcOn) return null;

    // Case 1: Power < 300W (maintenance mode)
    if (widget.powerWatts < 300 && widget.powerWatts > 100) {
      return (
        text: 'Máy đang chạy duy trì rất tiết kiệm.',
        icon: Icons.check_circle,
        color: const Color(0xFF4CAF50),
      );
    }

    // Case 2: Power > 1000W (high power cooling)
    if (widget.powerWatts > 1000) {
      return (
        text: 'Máy đang làm lạnh nhanh, sẽ tốn điện nhiều.',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF44336),
      );
    }

    // Case 3: Very low power (< 100W) but AC is supposedly on
    if (widget.powerWatts < 20 && widget.current < 0.5) {
      return (
        text: 'Máy đang chế độ chờ',
        icon: Icons.info_outline,
        color: const Color(0xFF2196F3),
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingCard();
    }

    // Tính toán các thông số
    final loadPercent = calculateLoadPercent(widget.powerWatts, widget.ratedPowerWatts.toDouble());
    final costPerHour = calculateCostPerHour(widget.powerWatts, widget.electricityPrice);
    final loadColor = _getLoadColor(loadPercent);
    final loadDescription = _getLoadDescription(loadPercent);
    final aiComment = _getAIComment();

    // Tính công suất AC (Power Triangle)
    final realPower = calculateRealPower(widget.voltage, widget.current, widget.powerFactor);
    final apparentPower = calculateApparentPower(widget.voltage, widget.current);
    final reactivePower = calculateReactivePower(widget.voltage, widget.current, widget.powerFactor);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _buildHeader(),

        const SizedBox(height: 16),

        // Main Gauge Card
        _buildGaugeCard(loadPercent, loadColor, loadDescription, aiComment),

        const SizedBox(height: 16),

        // Cost Metrics Row
        _buildCostMetricsRow(costPerHour),

        const SizedBox(height: 16),

        // Load Distribution Card
        if (_energyStatus != null) _buildLoadDistributionCard(),

        const SizedBox(height: 16),

        // Advanced Power Metrics (PZEM-004T)
        _buildAdvancedPowerMetrics(realPower, apparentPower, reactivePower),

        const SizedBox(height: 16),

        // Monthly Accumulation Card
        if (_energyStatus != null) _buildMonthlyAccumulationCard(),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return Card(
      child: Container(
        padding: const EdgeInsets.all(24),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.electric_bolt,
              color: AppTheme.primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Giám sát điện năng',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Dữ liệu được lấy từ cảm biến trong thiết bị',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          // Reset button
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _showResetDialog,
            tooltip: 'Reset baseline',
            color: Colors.grey[600],
          ),
        ],
      ),
    );
  }

  Widget _buildGaugeCard(
    double loadPercent,
    Color loadColor,
    String loadDescription,
    ({String text, IconData icon, Color color})? aiComment,
  ) {
    return Card(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              loadColor.withOpacity(0.05),
              loadColor.withOpacity(0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Circular Gauge
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background circle
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: 1.0,
                      strokeWidth: 18,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation(Colors.grey[200]),
                    ),
                  ),

                  // Progress circle
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: (loadPercent / 100).clamp(0, 1),
                      strokeWidth: 18,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(loadColor),
                    ),
                  ),

                  // Center content
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Power value
                      Text(
                        widget.powerWatts.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          color: loadColor,
                          height: 1,
                          letterSpacing: -2,
                        ),
                      ),

                      // Unit
                      Text(
                        'WATTS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                          letterSpacing: 2,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Percentage badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                        decoration: BoxDecoration(
                          color: loadColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${loadPercent.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: loadColor,
                          ),
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Load description
                      Text(
                        loadDescription,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // AI Comment (if available)
            if (aiComment != null) _buildAIComment(aiComment.text, aiComment.icon, aiComment.color),

            if (aiComment != null) const SizedBox(height: 12),

            // Info explanation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.blue[700]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Đồng hồ hiển thị mức tải của máy lạnh so với công suất định mức',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[900],
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCostMetricsRow(double costPerHour) {
    // Session hiện tại (khi máy đang chạy)
    final sessionEnergy = _energyStatus?.currentSessionEnergyKWh ?? 0;
    final sessionCost = sessionEnergy * widget.electricityPrice;

    // Thời gian chạy hôm nay
    // Backend (BackgroundEnergyTracker) đã tính sẵn và cập nhật mỗi 5 giây vào Firebase
    // UI CHỈ HIỂN THỊ giá trị từ Firebase, KHÔNG tự tính thêm để tránh tính 2 lần
    final runtimeTodaySeconds = _energyStatus?.runtimeTodaySeconds ?? 0;
    final runtimeTodayHours = runtimeTodaySeconds / 3600.0;

    // Điện năng hôm nay = đã lưu + session hiện tại
    final dailyEnergy = (_energyStatus?.dailyEnergyKWh ?? 0) + sessionEnergy;

    // Tiền điện hôm nay = đã lưu + session hiện tại
    final dailyCost = (_energyStatus?.dailyCost ?? 0) + sessionCost;

    // Tổng tháng = đã lưu + session hiện tại
    final monthlyEnergy = (_energyStatus?.estimatedMonthlyEnergyKWh ?? 0) + sessionEnergy;
    final monthlyCost = (_energyStatus?.estimatedMonthlyCost ?? 0) + sessionCost;

    // Tính % tải và màu tương ứng
    final loadPercent = calculateLoadPercent(widget.powerWatts, widget.ratedPowerWatts.toDouble());
    final loadColor = _getLoadColor(loadPercent);
    final loadDescription = _getLoadDescription(loadPercent);

    // Kiểm tra cảnh báo tải cao
    final showHighLoadWarning = (_energyStatus?.highLoadCurrentStreakSec ?? 0) >= 1800; // 30 phút
    final warningMinutes = (_energyStatus?.highLoadCurrentStreakSec ?? 0) / 60;

    return Column(
      children: [
        // Row 1: Ước tính 1 giờ (card nổi bật với màu động)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: loadColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: loadColor.withOpacity(0.6),
              width: 2,
            ),
          ),
          child: Column(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: loadColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.speed_rounded, color: loadColor, size: 28),
              ),

              const SizedBox(height: 12),

              // Label
              Text(
                'Tốc độ tiêu tiền ước tính',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              // Value (căn giữa)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatVND(costPerHour),
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: loadColor,
                      height: 1,
                      letterSpacing: -1.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'đ/giờ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: loadColor.withOpacity(0.85),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: loadColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: loadColor.withOpacity(0.4), width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: loadColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      widget.isAcOn ? loadDescription : 'Máy tắt ( đang trong trạng thái chờ)',
                      style: TextStyle(
                        fontSize: 12,
                        color: loadColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Cảnh báo tải cao (nếu có)
              if (showHighLoadWarning) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red[300]!, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Máy đang chạy tải cao (>80%) liên tục ${warningMinutes.toStringAsFixed(0)} phút, cần kiểm tra máy lạnh để tiết kiệm điện',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[900],
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Lưu ý về cập nhật dữ liệu
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue[200]!, width: 1),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Các thông số sẽ được cập nhật khi máy tắt !',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[900],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Row 2: Thời gian chạy hôm nay + Điện năng hôm nay
        Row(
          children: [
            // Runtime today
            Expanded(
              child: _buildMetricCard(
                icon: Icons.access_time_rounded,
                label: 'Thời gian sử dụng hôm nay',
                value: runtimeTodayHours.toStringAsFixed(2),
                unit: 'giờ',
                color: const Color(0xFF26A69A),
                subtitle: '$runtimeTodaySeconds giây',
              ),
            ),

            const SizedBox(width: 12),

            // Daily energy
            Expanded(
              child: _buildMetricCard(
                icon: Icons.bolt_rounded,
                label: 'Điện năng tiêu thụ hôm nay',
                value: dailyEnergy.toStringAsFixed(3),
                unit: 'kWh',
                color: const Color(0xFFFFA726),
                subtitle: 'Tiêu thụ trong ngày',
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Row 3: Tiền điện hôm nay + Tổng tháng này
        Row(
          children: [
            // Daily cost
            Expanded(
              child: _buildMetricCard(
                icon: Icons.payments_rounded,
                label: 'Tiền điện hôm nay',
                value: _formatVND(dailyCost),
                unit: 'đ',
                color: const Color(0xFFE91E63),
                subtitle: 'Tính từ 00:00',
              ),
            ),

            const SizedBox(width: 12),

            // Monthly total (bao gồm cả session hiện tại)
            Expanded(
              child: _buildMetricCard(
                icon: Icons.calendar_month_rounded,
                label: 'Tổng tháng này',
                value: _formatVND(monthlyCost),
                unit: 'đ',
                color: const Color(0xFFFF9800),
                subtitle: '${monthlyEnergy.toStringAsFixed(2)} kWh',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadDistributionCard() {
    // Tính tổng thời gian
    final totalSeconds = _energyStatus!.timeLowTodaySec +
                        _energyStatus!.timeMidTodaySec +
                        _energyStatus!.timeHighTodaySec;

    // Tính phần trăm cho từng vùng
    final lowPercent = totalSeconds > 0 ? (_energyStatus!.timeLowTodaySec / totalSeconds * 100) : 0.0;
    final midPercent = totalSeconds > 0 ? (_energyStatus!.timeMidTodaySec / totalSeconds * 100) : 0.0;
    final highPercent = totalSeconds > 0 ? (_energyStatus!.timeHighTodaySec / totalSeconds * 100) : 0.0;

    // Format thời gian
    final lowHours = _energyStatus!.timeLowTodaySec / 3600;
    final midHours = _energyStatus!.timeMidTodaySec / 3600;
    final highHours = _energyStatus!.timeHighTodaySec / 3600;

    // Check high load warning
    final showWarning = _energyStatus!.highLoadCurrentStreakSec >= 1800; // 30 minutes
    final warningMinutes = _energyStatus!.highLoadCurrentStreakSec / 60;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart_rounded, size: 20, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Phân bố thời gian theo tải',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Load distribution bar
            if (totalSeconds > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      if (lowPercent > 0)
                        Expanded(
                          flex: _energyStatus!.timeLowTodaySec,
                          child: Container(
                            color: const Color(0xFF4CAF50),
                            alignment: Alignment.center,
                            child: lowPercent > 10 ? Text(
                              '${lowPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ) : null,
                          ),
                        ),
                      if (midPercent > 0)
                        Expanded(
                          flex: _energyStatus!.timeMidTodaySec,
                          child: Container(
                            color: const Color(0xFFFF9800),
                            alignment: Alignment.center,
                            child: midPercent > 10 ? Text(
                              '${midPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ) : null,
                          ),
                        ),
                      if (highPercent > 0)
                        Expanded(
                          flex: _energyStatus!.timeHighTodaySec,
                          child: Container(
                            color: const Color(0xFFF44336),
                            alignment: Alignment.center,
                            child: highPercent > 10 ? Text(
                              '${highPercent.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ) : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Legend with time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildLoadLegend(
                    color: const Color(0xFF4CAF50),
                    label: 'Tải thấp (<30%)',
                    time: lowHours,
                    percent: lowPercent,
                  ),
                  _buildLoadLegend(
                    color: const Color(0xFFFF9800),
                    label: 'Tải TB (30-70%)',
                    time: midHours,
                    percent: midPercent,
                  ),
                  _buildLoadLegend(
                    color: const Color(0xFFF44336),
                    label: 'Tải cao (>70%)',
                    time: highHours,
                    percent: highPercent,
                  ),
                ],
              ),
            ] else ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Chưa có dữ liệu thời gian chạy hôm nay',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],

            // High load warning
            if (showWarning) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[300]!, width: 1),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red[700], size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cảnh báo: Máy đang chạy tải cao (>80%) liên tục ${warningMinutes.toStringAsFixed(0)} phút',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red[900],
                          fontWeight: FontWeight.w500,
                        ),
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

  Widget _buildLoadLegend({
    required Color color,
    required String label,
    required double time,
    required double percent,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${time.toStringAsFixed(2)}h',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedPowerMetrics(double realPower, double apparentPower, double reactivePower) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, size: 20, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Thông số nâng cao (PZEM-004T)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Grid layout 2 columns
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _buildSmallMetricCard('Điện áp', '${widget.voltage.toStringAsFixed(0)} V', Colors.purple),
                _buildSmallMetricCard('Dòng điện', '${widget.current.toStringAsFixed(2)} A', Colors.blue),
                _buildSmallMetricCard('Công suất thực', '${realPower.toStringAsFixed(0)} W', Colors.green),
                _buildSmallMetricCard('Công suất biểu kiến', '${apparentPower.toStringAsFixed(0)} VA', Colors.orange),
                _buildSmallMetricCard('Công suất phản kháng', '${reactivePower.toStringAsFixed(0)} VAR', Colors.red),
                _buildSmallMetricCard('Hệ số công suất', widget.powerFactor.toStringAsFixed(2), Colors.teal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyAccumulationCard() {
    if (_energyStatus == null) return const SizedBox.shrink();

    final monthStart = DateTime.fromMillisecondsSinceEpoch(_energyStatus!.monthStartTimestamp);
    // Tính số ngày bằng cách so sánh ngày trong tháng (không cần đủ 24h)
    final now = DateTime.now();
    final daysSinceStart = now.day - monthStart.day + 1; // +1 vì tính cả ngày bắt đầu

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.receipt_long_rounded, size: 20, color: Colors.green[700]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tích lũy tháng ${monthStart.month}/${monthStart.year}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Theo dõi từ ngày ${monthStart.day}/${monthStart.month} ($daysSinceStart ngày)',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Energy consumed
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.green[50]!,
                    Colors.green[100]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.electric_meter_rounded, size: 32, color: Colors.green[700]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Điện năng tiêu thụ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_energyStatus!.estimatedMonthlyEnergyKWh.toStringAsFixed(3)} kWh',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.green[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Total cost
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange[50]!,
                    Colors.orange[100]!,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!, width: 1),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments_rounded, size: 32, color: Colors.orange[700]),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tổng chi phí ước tính',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatVND(_energyStatus!.estimatedMonthlyCost)} đ',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Config info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildConfigItem('Giá điện', '${_energyStatus!.electricityPrice} đ/kWh'),
                  Container(width: 1, height: 30, color: Colors.grey[300]),
                  _buildConfigItem('Công suất định mức', '${_energyStatus!.ratedPowerWatts} W'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmallMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Build AI comment widget
  Widget _buildAIComment(String comment, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              comment,
              style: TextStyle(
                fontSize: 13,
                color: color.withOpacity(0.9),
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show dialog để reset tháng
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.refresh, color: AppTheme.warningColor),
            SizedBox(width: 12),
            Text('Reset tháng'),
          ],
        ),
        content: const Text(
          'Bạn có chắc muốn reset lại thống kê tháng này?\n\n'
          'Điện năng tích lũy và chi phí trong tháng sẽ được tính lại từ 0.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _energyService.resetMonth(
                deviceId: widget.deviceId,
              );

              // Reload status
              final status = await _energyService.loadEnergyStatus(widget.deviceId);
              if (mounted) {
                setState(() {
                  _energyStatus = status;
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã reset thống kê tháng'),
                    backgroundColor: AppTheme.successColor,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
