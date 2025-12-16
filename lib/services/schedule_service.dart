import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/schedule_model.dart';

class ScheduleService extends ChangeNotifier {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  List<ScheduleModel> _schedules = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<ScheduleModel> get schedules => _schedules;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Load danh sách lịch của một thiết bị
  Future<void> loadDeviceSchedules(String deviceId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final snapshot = await _db.child('schedules/$deviceId').get();

      _schedules.clear();

      if (snapshot.exists) {
        final schedulesData = Map<String, dynamic>.from(snapshot.value as Map);

        for (var entry in schedulesData.entries) {
          final scheduleData = Map<String, dynamic>.from(entry.value);
          _schedules.add(ScheduleModel.fromJson(entry.key, scheduleData));
        }

        // Sắp xếp theo thời gian
        _schedules.sort((a, b) => a.time.compareTo(b.time));
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Lỗi tải danh sách lịch: $e';
      print('Error loadDeviceSchedules: $e');
      notifyListeners();
    }
  }

  // Thêm lịch mới
  Future<bool> addSchedule(ScheduleModel schedule) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      // Tạo ID mới cho schedule
      final scheduleRef = _db.child('schedules/${schedule.deviceId}').push();
      final scheduleId = scheduleRef.key!;

      // Lưu schedule
      await scheduleRef.set(schedule.toJson());

      print('✓ Đã thêm lịch: $scheduleId');

      // Sync pending schedules cho ESP32
      await syncPendingSchedules(schedule.deviceId);

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Lỗi thêm lịch: $e';
      print('✗ Lỗi: $e');
      notifyListeners();
      return false;
    }
  }

  // Cập nhật lịch
  Future<bool> updateSchedule(ScheduleModel schedule) async {
    try {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();

      final scheduleRef = _db.child('schedules/${schedule.deviceId}/${schedule.scheduleId}');

      // Nếu action là powerOn/powerOff và có field value cũ, xóa nó đi
      if (schedule.action == 'powerOn' || schedule.action == 'powerOff') {
        await scheduleRef.child('value').remove();
      }

      // Cập nhật toàn bộ schedule (sử dụng set thay vì update để đảm bảo xóa field không cần thiết)
      await scheduleRef.set({
        ...schedule.toJson(),
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });

      print('✓ Đã cập nhật lịch: ${schedule.scheduleId}');

      // Sync pending schedules cho ESP32
      await syncPendingSchedules(schedule.deviceId);

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Lỗi cập nhật lịch: $e';
      print('✗ Lỗi: $e');
      notifyListeners();
      return false;
    }
  }

  // Bật/Tắt lịch
  Future<bool> toggleSchedule(String deviceId, String scheduleId, bool enabled) async {
    try {
      await _db.child('schedules/$deviceId/$scheduleId').update({
        'enabled': enabled,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });

      // Sync pending schedules cho ESP32
      await syncPendingSchedules(deviceId);

      // Cập nhật local
      final index = _schedules.indexWhere((s) => s.scheduleId == scheduleId);
      if (index != -1) {
        _schedules[index] = _schedules[index].copyWith(enabled: enabled);
        notifyListeners();
      }

      return true;
    } catch (e) {
      _errorMessage = 'Lỗi cập nhật trạng thái: $e';
      notifyListeners();
      return false;
    }
  }

  // Xóa lịch
  Future<bool> deleteSchedule(String deviceId, String scheduleId) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _db.child('schedules/$deviceId/$scheduleId').remove();

      print('✓ Đã xóa lịch: $scheduleId');

      // Sync pending schedules cho ESP32
      await syncPendingSchedules(deviceId);

      // Reload danh sách
      await loadDeviceSchedules(deviceId);

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Lỗi xóa lịch: $e';
      print('✗ Lỗi xóa lịch: $e');
      notifyListeners();
      return false;
    }
  }

  // Sync schedules sang pending_schedules cho ESP32 đọc
  // Chỉ lấy 5 lịch enabled tiếp theo gần nhất
  Future<void> syncPendingSchedules(String deviceId) async {
    try {
      print('>>> Bat dau sync pending schedules cho device: $deviceId');

      // 1. Load tất cả schedules enabled
      final snapshot = await _db.child('schedules/$deviceId').get();

      if (!snapshot.exists) {
        // Không có schedule nào -> xóa pending_schedules
        await _db.child('pending_schedules/$deviceId').remove();
        print('✓ Khong co schedule nao, da xoa pending_schedules');
        return;
      }

      final schedulesData = Map<String, dynamic>.from(snapshot.value as Map);
      final now = DateTime.now();
      final currentTime = now.hour * 60 + now.minute; // Phút từ đầu ngày
      final currentDay = now.weekday % 7; // 0 = CN, 1 = T2, ..., 6 = T7

      List<Map<String, dynamic>> upcomingSchedules = [];

      // 2. Lọc các lịch enabled và sắp tới
      for (var entry in schedulesData.entries) {
        final scheduleData = Map<String, dynamic>.from(entry.value);
        final schedule = ScheduleModel.fromJson(entry.key, scheduleData);

        if (!schedule.enabled) continue;

        final timeParts = schedule.time.split(':');
        final scheduleTime = int.parse(timeParts[0]) * 60 + int.parse(timeParts[1]);

        // Kiểm tra nếu lịch có chạy hôm nay
        if (schedule.daysOfWeek.contains(currentDay)) {
          // Nếu chưa đến giờ hôm nay
          if (scheduleTime > currentTime) {
            upcomingSchedules.add({
              'scheduleId': schedule.scheduleId,
              'name': schedule.name,
              'action': schedule.action,
              'value': schedule.value ?? 0,
              'time': schedule.time,
              'daysOfWeek': schedule.daysOfWeek,
              'priority': scheduleTime - currentTime, // Độ ưu tiên = khoảng cách thời gian
            });
          }
        }

        // Kiểm tra các ngày tiếp theo trong tuần
        for (int dayOffset = 1; dayOffset <= 7; dayOffset++) {
          final nextDay = (currentDay + dayOffset) % 7;
          if (schedule.daysOfWeek.contains(nextDay)) {
            upcomingSchedules.add({
              'scheduleId': schedule.scheduleId,
              'name': schedule.name,
              'action': schedule.action,
              'value': schedule.value ?? 0,
              'time': schedule.time,
              'daysOfWeek': schedule.daysOfWeek,
              'priority': (dayOffset * 24 * 60) + scheduleTime - currentTime,
            });
            break; // Chỉ lấy lần xuất hiện gần nhất
          }
        }
      }

      // 3. Sắp xếp theo priority và lấy 5 lịch gần nhất
      upcomingSchedules.sort((a, b) => a['priority'].compareTo(b['priority']));
      final top5 = upcomingSchedules.take(5).toList();

      // 4. Ghi vào pending_schedules
      if (top5.isEmpty) {
        await _db.child('pending_schedules/$deviceId').remove();
        print('✓ Khong co schedule sap toi, da xoa pending_schedules');
      } else {
        final Map<String, dynamic> pendingData = {};
        for (var i = 0; i < top5.length; i++) {
          final schedule = top5[i];
          pendingData[schedule['scheduleId']] = {
            'name': schedule['name'],
            'action': schedule['action'],
            'value': schedule['value'],
            'time': schedule['time'],
            'daysOfWeek': schedule['daysOfWeek'],
          };
        }

        await _db.child('pending_schedules/$deviceId').set(pendingData);
        print('✓ Da sync ${top5.length} schedules vao pending_schedules');
      }
    } catch (e) {
      print('✗ Loi sync pending schedules: $e');
    }
  }

  // Cleanup schedules đã thực hiện (xóa lastExecuted cũ hơn 5 lần)
  Future<void> cleanupExecutedSchedules(String deviceId) async {
    try {
      print('>>> Bat dau cleanup executed schedules cho device: $deviceId');

      final snapshot = await _db.child('schedules/$deviceId').get();

      if (!snapshot.exists) return;

      final schedulesData = Map<String, dynamic>.from(snapshot.value as Map);
      final now = DateTime.now().millisecondsSinceEpoch;
      final fiveDaysAgo = now - (5 * 24 * 60 * 60 * 1000);

      int cleanedCount = 0;

      for (var entry in schedulesData.entries) {
        final scheduleData = Map<String, dynamic>.from(entry.value);
        final lastExecuted = scheduleData['lastExecuted'] as int?;

        // Nếu lastExecuted cũ hơn 5 ngày, xóa nó
        if (lastExecuted != null && lastExecuted < fiveDaysAgo) {
          await _db.child('schedules/$deviceId/${entry.key}/lastExecuted').remove();
          cleanedCount++;
        }
      }

      print('✓ Da cleanup $cleanedCount schedules');
    } catch (e) {
      print('✗ Loi cleanup schedules: $e');
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
