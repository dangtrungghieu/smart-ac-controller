import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';
import '../../models/device_model.dart';

class ScheduleDebugScreen extends StatefulWidget {
  final DeviceModel device;

  const ScheduleDebugScreen({
    super.key,
    required this.device,
  });

  @override
  State<ScheduleDebugScreen> createState() => _ScheduleDebugScreenState();
}

class _ScheduleDebugScreenState extends State<ScheduleDebugScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final List<String> _logs = [];
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _addLog('🔧 Debug screen khởi tạo');
    _checkCurrentStatus();
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _logs.insert(0, '${DateTime.now().hour}:${DateTime.now().minute}:${DateTime.now().second} - $message');
        if (_logs.length > 50) _logs.removeLast();
      });
    }
  }

  Future<void> _checkCurrentStatus() async {
    _addLog('📡 Đang kiểm tra trạng thái...');

    try {
      // 1. Kiểm tra schedules
      final schedulesSnapshot = await _db.child('schedules/${widget.device.deviceId}').get();
      if (schedulesSnapshot.exists) {
        final data = schedulesSnapshot.value as Map<dynamic, dynamic>;
        _addLog('✅ Tìm thấy ${data.length} lịch');

        data.forEach((key, value) {
          final scheduleData = value as Map<dynamic, dynamic>;
          _addLog('  📅 ${scheduleData['name']} - ${scheduleData['time']} - ${scheduleData['action']}');
        });
      } else {
        _addLog('⚠️ Không có lịch nào');
      }

      // 2. Kiểm tra nhiệt độ hiện tại
      final tempSnapshot = await _db.child('status/${widget.device.deviceId}/ac/setTemp').get();
      if (tempSnapshot.exists) {
        _addLog('🌡️ Nhiệt độ hiện tại: ${tempSnapshot.value}°C');
      } else {
        _addLog('⚠️ Không đọc được nhiệt độ');
      }

      // 3. Kiểm tra trạng thái máy
      final powerSnapshot = await _db.child('status/${widget.device.deviceId}/ac/powerOn').get();
      if (powerSnapshot.exists) {
        _addLog('⚡ Máy lạnh: ${powerSnapshot.value == true ? "BẬT" : "TẮT"}');
      }

      // 4. Kiểm tra thời gian hiện tại
      final now = DateTime.now();
      final currentDay = now.weekday % 7;
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      _addLog('⏰ Thời gian: $currentTime (Thứ $currentDay)');

    } catch (e) {
      _addLog('❌ Lỗi: $e');
    }
  }

  Future<void> _manualTriggerSchedule() async {
    setState(() => _isChecking = true);
    _addLog('🚀 Kích hoạt thủ công schedule executor...');

    try {
      final now = DateTime.now();
      final currentDay = now.weekday % 7;
      final currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      _addLog('⏰ Đang ở: $currentTime, Thứ $currentDay');

      final schedulesSnapshot = await _db.child('schedules/${widget.device.deviceId}').get();

      if (!schedulesSnapshot.exists) {
        _addLog('⚠️ Không có lịch nào để kiểm tra');
        return;
      }

      final data = schedulesSnapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        final scheduleData = value as Map<dynamic, dynamic>;
        final scheduleName = scheduleData['name'] ?? 'Không tên';
        final scheduleTime = scheduleData['time'] ?? '00:00';
        final enabled = scheduleData['enabled'] ?? false;
        final daysOfWeek = scheduleData['daysOfWeek'] as List<dynamic>? ?? [];

        _addLog('🔍 Kiểm tra: $scheduleName');
        _addLog('  - Thời gian: $scheduleTime vs $currentTime');
        _addLog('  - Enabled: $enabled');
        _addLog('  - Ngày: $daysOfWeek vs $currentDay');

        if (enabled && scheduleTime == currentTime && daysOfWeek.contains(currentDay)) {
          _addLog('  ✅ KHỚP! Lịch này nên được thực thi');
        } else {
          if (!enabled) _addLog('  ⚠️ Lịch bị tắt');
          if (scheduleTime != currentTime) _addLog('  ⚠️ Thời gian không khớp');
          if (!daysOfWeek.contains(currentDay)) _addLog('  ⚠️ Ngày không khớp');
        }
      });

    } catch (e) {
      _addLog('❌ Lỗi: $e');
    } finally {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _testSendCommand() async {
    _addLog('📤 Test gửi lệnh power...');
    try {
      final commandPath = 'commands/${widget.device.deviceId}';

      // Xóa lệnh cũ
      await _db.child(commandPath).remove();

      // Gửi lệnh mới theo format ESP32
      await _db.child(commandPath).set({
        'action': 'power',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _addLog('✅ Đã gửi lệnh power tới: $commandPath');
      _addLog('ℹ️ ESP32 sẽ đọc từ: commands/${widget.device.deviceId}/action');
    } catch (e) {
      _addLog('❌ Lỗi gửi lệnh: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Debug'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkCurrentStatus,
          ),
        ],
      ),
      body: Column(
        children: [
          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isChecking ? null : _manualTriggerSchedule,
                    icon: _isChecking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Kiểm tra lịch'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _testSendCommand,
                    icon: const Icon(Icons.send),
                    label: const Text('Test lệnh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Logs
          Expanded(
            child: Container(
              color: Colors.grey[900],
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Nhấn "Kiểm tra lịch" để bắt đầu',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        Color textColor = Colors.white;

                        if (log.contains('❌')) textColor = Colors.red[300]!;
                        else if (log.contains('✅')) textColor = Colors.green[300]!;
                        else if (log.contains('⚠️')) textColor = Colors.orange[300]!;
                        else if (log.contains('🔍')) textColor = Colors.blue[300]!;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: textColor,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
