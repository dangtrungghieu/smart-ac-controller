import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/theme.dart';
import '../../models/device_model.dart';
import '../../models/schedule_model.dart';
import '../../services/schedule_service.dart';
import '../../services/schedule_executor.dart';
import 'add_schedule_screen.dart';

class ScheduleListScreen extends StatefulWidget {
  final DeviceModel device;
  final String userId;

  const ScheduleListScreen({
    super.key,
    required this.device,
    required this.userId,
  });

  @override
  State<ScheduleListScreen> createState() => _ScheduleListScreenState();
}

class _ScheduleListScreenState extends State<ScheduleListScreen> {
  @override
  void initState() {
    super.initState();
    _loadSchedules();
    _setupExecutor();
  }

  void _setupExecutor() {
    final executor = Provider.of<ScheduleExecutor>(context, listen: false);
    // Đăng ký userId để executor tự động load tất cả devices
    executor.setUserId(widget.userId);
  }

  Future<void> _loadSchedules() async {
    final scheduleService = Provider.of<ScheduleService>(context, listen: false);
    await scheduleService.loadDeviceSchedules(widget.device.deviceId);
  }

  Future<void> _deleteSchedule(ScheduleModel schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 28),
            SizedBox(width: 12),
            Expanded(child: Text('Xóa lịch?')),
          ],
        ),
        content: Text('Bạn có chắc muốn xóa lịch "${schedule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final scheduleService = Provider.of<ScheduleService>(context, listen: false);
      await scheduleService.deleteSchedule(widget.device.deviceId, schedule.scheduleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch điều khiển'),
      ),
      body: Consumer<ScheduleService>(
        builder: (context, scheduleService, child) {
          if (scheduleService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (scheduleService.schedules.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Chưa có lịch nào',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nhấn nút + để thêm lịch mới',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: scheduleService.schedules.length,
            itemBuilder: (context, index) {
              final schedule = scheduleService.schedules[index];
              return _buildScheduleCard(schedule, scheduleService);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddScheduleScreen(
                device: widget.device,
                userId: widget.userId,
              ),
            ),
          );

          if (result == true && mounted) {
            _loadSchedules();
          }
        },
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildScheduleCard(ScheduleModel schedule, ScheduleService scheduleService) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AddScheduleScreen(
                device: widget.device,
                userId: widget.userId,
                schedule: schedule,
              ),
            ),
          );

          if (result == true && mounted) {
            _loadSchedules();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Time
              Container(
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: schedule.enabled
                      ? AppTheme.primaryColor.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      schedule.time.split(':')[0],
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: schedule.enabled
                            ? AppTheme.primaryColor
                            : Colors.grey,
                      ),
                    ),
                    Text(
                      schedule.time.split(':')[1],
                      style: TextStyle(
                        fontSize: 16,
                        color: schedule.enabled
                            ? AppTheme.primaryColor
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schedule.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: schedule.enabled ? Colors.black : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Hiển thị action
                    _buildSingleActionPreview(schedule),
                    const SizedBox(height: 4),
                    Text(
                      schedule.daysText,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),

              // Switch
              Switch(
                value: schedule.enabled,
                onChanged: (value) {
                  scheduleService.toggleSchedule(
                    widget.device.deviceId,
                    schedule.scheduleId,
                    value,
                  );
                },
                activeColor: AppTheme.primaryColor,
              ),

              // Delete button
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                onPressed: () => _deleteSchedule(schedule),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'powerOn':
        return Icons.power_settings_new;
      case 'powerOff':
        return Icons.power_off;
      case 'tempUp':
        return Icons.arrow_upward;
      case 'tempDown':
        return Icons.arrow_downward;
      // Backward compatibility
      case 'power':
        return Icons.power_settings_new;
      default:
        return Icons.schedule;
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'powerOn':
        return Colors.green;
      case 'powerOff':
        return Colors.red;
      case 'tempUp':
        return Colors.orange;
      case 'tempDown':
        return Colors.blue;
      case 'power':
        return AppTheme.primaryColor;
      case 'multiple':
        return AppTheme.primaryColor;
      default:
        return Colors.grey;
    }
  }

  Widget _buildSingleActionPreview(ScheduleModel schedule) {
    return Row(
      children: [
        Icon(
          _getActionIcon(schedule.action),
          size: 14,
          color: _getActionColor(schedule.action),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            schedule.actionName,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Hiển thị nhiệt độ mục tiêu nếu có
        if (schedule.value != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getActionColor(schedule.action).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${schedule.value}°',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: _getActionColor(schedule.action),
              ),
            ),
          ),
        ],
      ],
    );
  }

}
