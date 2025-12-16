import 'package:flutter/material.dart';
import '../utils/theme.dart';

class RealTimePowerGauge extends StatelessWidget {
  final double currentPowerWatts;
  final double ratedPowerWatts;
  final int electricityPrice; // VND per kWh
  final double sessionEnergyKWh;
  final double? roomTemp;
  final int? acSetTemp;
  final bool isAcOn;

  const RealTimePowerGauge({
    super.key,
    required this.currentPowerWatts,
    required this.ratedPowerWatts,
    required this.electricityPrice,
    required this.sessionEnergyKWh,
    this.roomTemp,
    this.acSetTemp,
    required this.isAcOn,
  });

  /// Format VND currency
  String _formatVND(double amount) {
    final formatted = amount.toStringAsFixed(0);
    // Format with thousands separator
    final parts = formatted.split('.');
    final mainPart = parts[0];
    final formattedMain = mainPart.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return formattedMain;
  }

  /// Format cost per hour (without đ/h suffix)
  String _formatCostPerHour(double amount) {
    return _formatVND(amount);
  }

  /// Get color based on load percentage
  Color _getLoadColor(double loadPercent) {
    if (loadPercent < 40) {
      return const Color(0xFF4CAF50); // Green - Eco mode
    } else if (loadPercent < 80) {
      return const Color(0xFFFF9800); // Orange - Normal
    } else {
      return const Color(0xFFF44336); // Red - High power
    }
  }

  /// Get load description
  String _getLoadDescription(double loadPercent) {
    if (loadPercent < 40) {
      return 'Eco Mode';
    } else if (loadPercent < 80) {
      return 'Normal Load';
    } else {
      return 'High Load';
    }
  }

  /// Get AI comment based on power consumption and conditions
  ({String text, IconData icon, Color color})? _getAIComment() {
    if (!isAcOn) return null;

    // Case 1: Power < 300W (maintenance mode)
    if (currentPowerWatts < 300 && currentPowerWatts > 100) {
      return (
        text: 'Máy đang chạy duy trì rất tiết kiệm.',
        icon: Icons.check_circle,
        color: const Color(0xFF4CAF50),
      );
    }

    // Case 2: Power > 1000W (high power cooling)
    if (currentPowerWatts > 1000) {
      return (
        text: 'Máy đang làm lạnh nhanh, sẽ tốn điện nhiều.',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFF44336),
      );
    }

    // Case 3: Room temp reached set temp but power still high
    if (roomTemp != null &&
        acSetTemp != null &&
        roomTemp! <= (acSetTemp! + 1) &&
        currentPowerWatts > 500) {
      return (
        text: 'Cảnh báo: Có thể thất thoát nhiệt hoặc máy bẩn.',
        icon: Icons.error_outline,
        color: const Color(0xFFFF9800),
      );
    }

    return null;
  }

  /// Calculate burn rate (cost per hour)
  double _calculateBurnRate() {
    return (currentPowerWatts / 1000) * electricityPrice;
  }

  /// Calculate session cost
  double _calculateSessionCost() {
    return sessionEnergyKWh * electricityPrice;
  }

  @override
  Widget build(BuildContext context) {
    final loadPercent = (currentPowerWatts / ratedPowerWatts) * 100;
    final loadColor = _getLoadColor(loadPercent);
    final loadDescription = _getLoadDescription(loadPercent);
    final burnRate = _calculateBurnRate();
    final sessionCost = _calculateSessionCost();
    final aiComment = _getAIComment();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with icon
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.bolt,
                color: loadColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'Ước tính công suất tiêu thụ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),
        ),

        // Main gauge card
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                loadColor.withOpacity(0.05),
                loadColor.withOpacity(0.02),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.grey[200]!,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // Circular Gauge - Centered
              Center(
                child: _buildGauge(loadPercent, loadColor, loadDescription),
              ),

              // AI Comment (if available)
              if (aiComment != null) ...[
                const SizedBox(height: 24),
                _buildAIComment(aiComment.text, aiComment.icon, aiComment.color),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Cost metrics cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Burn rate card
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.speed,
                  label: 'Tốc độ tiêu thụ',
                  value: _formatCostPerHour(burnRate),
                  unit: '₫ / giờ',
                  color: const Color(0xFF5C6BC0),
                ),
              ),
              const SizedBox(width: 12),
              // Session cost card - Only show if AC is on
              Expanded(
                child: _buildMetricCard(
                  icon: Icons.receipt_long,
                  label: 'Tổng chi phí phiên',
                  value: isAcOn ? _formatVND(sessionCost) : '0',
                  unit: '₫',
                  color: const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build circular gauge widget
  Widget _buildGauge(double loadPercent, Color loadColor, String loadDescription) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          SizedBox(
            width: 240,
            height: 240,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 20,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(Colors.grey[200]),
            ),
          ),

          // Progress circle
          SizedBox(
            width: 240,
            height: 240,
            child: CircularProgressIndicator(
              value: (loadPercent / 100).clamp(0, 1),
              strokeWidth: 20,
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
                currentPowerWatts.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 60,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[500],
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 16),

              // Percentage badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: loadColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${loadPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: loadColor,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Load description
              Text(
                loadDescription,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build AI comment widget
  Widget _buildAIComment(String comment, IconData icon, Color color) {
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
                fontSize: 14,
                color: color.withOpacity(0.9),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build metric card with proper Vietnamese dong symbol
  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 24,
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                    height: 1.2,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}