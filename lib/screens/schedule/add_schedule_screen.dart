import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';
import '../../models/device_model.dart';
import '../../models/schedule_model.dart';
import '../../services/schedule_service.dart';

class AddScheduleScreen extends StatefulWidget {
  final DeviceModel device;
  final String userId;
  final ScheduleModel? schedule; // null = thêm mới, có giá trị = sửa

  const AddScheduleScreen({
    super.key,
    required this.device,
    required this.userId,
    this.schedule,
  });

  @override
  State<AddScheduleScreen> createState() => _AddScheduleScreenState();
}

class _AddScheduleScreenState extends State<AddScheduleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  String _selectedAction = 'powerOn';
  int _targetTemp = 24;
  int _currentTemp = 24;

  TimeOfDay _selectedTime = TimeOfDay.now();
  final Set<int> _selectedDays = {};

  @override
  void initState() {
    super.initState();

    // Nếu đang sửa, load dữ liệu cũ TRƯỚC
    if (widget.schedule != null) {
      _nameController.text = widget.schedule!.name;
      _selectedAction = widget.schedule!.action;

      final timeParts = widget.schedule!.time.split(':');
      _selectedTime = TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      );

      _selectedDays.addAll(widget.schedule!.daysOfWeek);

      // Load nhiệt độ mục tiêu nếu có
      if (widget.schedule!.value != null) {
        _targetTemp = widget.schedule!.value!;
      }
    }

    // Load nhiệt độ hiện tại SAU (để không ghi đè _targetTemp khi edit)
    _loadCurrentTemperature();
  }

  // Lấy nhiệt độ hiện tại từ Firebase
  Future<void> _loadCurrentTemperature() async {
    try {
      final snapshot = await _db.child('status/${widget.device.deviceId}/ac/setTemp').get();
      if (snapshot.exists && mounted) {
        setState(() {
          _currentTemp = snapshot.value as int? ?? 24;

          // CHỈ khởi tạo target = current khi THÊM MỚI (không phải edit)
          if (widget.schedule == null) {
            _targetTemp = _currentTemp;
          } else {
            // Khi EDIT: validate lại targetTemp với currentTemp mới
            if (_selectedAction == 'tempUp' || _selectedAction == 'tempDown') {
              _validateAndAdjustTargetTemp();
            }
          }
        });
      }
    } catch (e) {
      // Bỏ qua lỗi
    }
  }

  // Validate và điều chỉnh target temp nếu không hợp lệ
  void _validateAndAdjustTargetTemp() {
    if (_selectedAction == 'tempUp') {
      // Tăng: target phải > current và <= 30
      if (_targetTemp <= _currentTemp) {
        _targetTemp = _currentTemp < 30 ? _currentTemp + 1 : 30;
      }
      if (_targetTemp > 30) {
        _targetTemp = 30;
      }
    } else if (_selectedAction == 'tempDown') {
      // Giảm: target phải < current và >= 16
      if (_targetTemp >= _currentTemp) {
        _targetTemp = _currentTemp > 16 ? _currentTemp - 1 : 16;
      }
      if (_targetTemp < 16) {
        _targetTemp = 16;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveSchedule() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất 1 ngày'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
      return;
    }

    final scheduleService = Provider.of<ScheduleService>(context, listen: false);

    // Kiểm tra xung đột thời gian với các lịch khác
    final newTime = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    final conflictSchedule = scheduleService.schedules.firstWhere(
      (s) {
        // Bỏ qua chính lịch đang edit
        if (widget.schedule != null && s.scheduleId == widget.schedule!.scheduleId) {
          return false;
        }
        // Kiểm tra nếu trùng thời gian
        if (s.time != newTime) {
          return false;
        }
        // Kiểm tra nếu có ngày trùng nhau
        return s.daysOfWeek.any((day) => _selectedDays.contains(day));
      },
      orElse: () => ScheduleModel(
        scheduleId: '',
        deviceId: '',
        name: '',
        action: '',
        time: '',
        daysOfWeek: [],
        enabled: false,
        createdAt: 0,
        lastModified: 0,
      ),
    );

    // Nếu tìm thấy lịch trùng
    if (conflictSchedule.scheduleId.isNotEmpty) {
      final dayNames = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
      final conflictDays = conflictSchedule.daysOfWeek
          .where((day) => _selectedDays.contains(day))
          .map((day) => dayNames[day])
          .join(', ');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã có lịch "${conflictSchedule.name}" vào lúc $newTime vào các ngày: $conflictDays',
          ),
          backgroundColor: AppTheme.errorColor,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Xác định value: chỉ set khi là tempUp/tempDown, null khi là powerOn/powerOff
    int? scheduleValue;
    if (_selectedAction == 'tempUp' || _selectedAction == 'tempDown') {
      scheduleValue = _targetTemp;
    } else {
      // Khi chuyển sang powerOn/powerOff, value sẽ là null
      scheduleValue = null;
    }

    final schedule = ScheduleModel(
      scheduleId: widget.schedule?.scheduleId ?? '',
      deviceId: widget.device.deviceId,
      name: _nameController.text.trim(),
      action: _selectedAction,
      value: scheduleValue,
      time: '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
      daysOfWeek: _selectedDays.toList()..sort(),
      enabled: widget.schedule?.enabled ?? true,
      createdAt: widget.schedule?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      lastModified: DateTime.now().millisecondsSinceEpoch,
    );

    bool success;
    if (widget.schedule == null) {
      // Thêm mới
      success = await scheduleService.addSchedule(schedule);
    } else {
      // Cập nhật
      success = await scheduleService.updateSchedule(schedule);
    }

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(scheduleService.errorMessage ?? 'Lỗi lưu lịch'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.schedule != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Sửa lịch' : 'Thêm lịch mới'),
        actions: [
          TextButton(
            onPressed: _saveSchedule,
            child: const Text(
              'Lưu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device info
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.devices, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.device.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Tên lịch
              const Text(
                'Tên lịch',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập tên lịch';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Hành động
              const Text(
                'Hành động',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildActionSelector(),

              // Chọn nhiệt độ mục tiêu (chỉ hiện khi chọn tempUp/tempDown)
              if (_selectedAction == 'tempUp' || _selectedAction == 'tempDown') ...[
                const SizedBox(height: 16),
                _buildTemperatureSelector(),
                const SizedBox(height: 12),
                // Chú thích về tự động bật máy
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!, width: 1),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.green[700]),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nếu máy lạnh chưa bật, hệ thống sẽ tự động bật máy trước, sau đó mới điều chỉnh nhiệt độ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green[900],
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Thời gian
              const Text(
                'Thời gian',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectTime,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, color: AppTheme.primaryColor),
                      const SizedBox(width: 12),
                      Text(
                        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Ngày lặp lại
              const Text(
                'Lặp lại',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildDaySelector(),

              const SizedBox(height: 32),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveSchedule,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    isEditing ? 'Cập nhật lịch' : 'Tạo lịch',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionSelector() {
    final actions = [
      {'value': 'powerOn', 'label': 'Bật máy lạnh', 'icon': Icons.power_settings_new, 'color': Colors.green},
      {'value': 'powerOff', 'label': 'Tắt máy lạnh', 'icon': Icons.power_off, 'color': Colors.red},
      {'value': 'tempUp', 'label': 'Tăng nhiệt độ', 'icon': Icons.arrow_upward, 'color': Colors.orange},
      {'value': 'tempDown', 'label': 'Giảm nhiệt độ', 'icon': Icons.arrow_downward, 'color': Colors.blue},
    ];

    return Column(
      children: actions.map((action) {
        final isSelected = _selectedAction == action['value'];
        final actionColor = action['color'] as Color;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? actionColor : Colors.grey[300]!,
              width: isSelected ? 2.5 : 1.5,
            ),
            color: isSelected ? actionColor.withOpacity(0.08) : Colors.white,
            boxShadow: isSelected ? [
              BoxShadow(
                color: actionColor.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ] : null,
          ),
          child: InkWell(
            onTap: () {
              setState(() {
                final newAction = action['value'] as String;

                // Nếu đổi action và action mới là temp, reset target về current
                if (_selectedAction != newAction &&
                    (newAction == 'tempUp' || newAction == 'tempDown')) {
                  _targetTemp = _currentTemp;
                }

                _selectedAction = newAction;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected ? actionColor : Colors.grey[200],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      action['icon'] as IconData,
                      color: isSelected ? Colors.white : Colors.grey[600],
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      action['label'] as String,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.black87 : Colors.grey[700],
                      ),
                    ),
                  ),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: actionColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 18,
                      ),
                    )
                  else
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[400]!, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTemperatureSelector() {
    // Tính min/max dựa trên action và nhiệt độ hiện tại
    int minTemp, maxTemp;
    String rangeText;
    Color actionColor;

    if (_selectedAction == 'tempUp') {
      // Tăng: chỉ được chọn từ (current + 1) đến 30
      minTemp = _currentTemp < 30 ? _currentTemp + 1 : 30;
      maxTemp = 30;
      rangeText = 'Nhiệt độ cũ: $_currentTemp°C → Chọn từ $minTemp°C đến $maxTemp°C';
      actionColor = Colors.orange;
    } else {
      // Giảm: chỉ được chọn từ 16 đến (current - 1)
      minTemp = 16;
      maxTemp = _currentTemp > 16 ? _currentTemp - 1 : 16;
      rangeText = 'Nhiệt độ cũ: $_currentTemp°C → Chọn từ $minTemp°C đến $maxTemp°C';
      actionColor = Colors.blue;
    }

    // Đảm bảo _targetTemp nằm trong phạm vi hợp lệ
    if (_targetTemp < minTemp || _targetTemp > maxTemp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _targetTemp = minTemp;
          });
        }
      });
    }

    // Kiểm tra nếu không có phạm vi hợp lệ
    if (minTemp > maxTemp) {
      return Card(
        elevation: 2,
        color: Colors.orange[50],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.orange[700]),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _selectedAction == 'tempUp'
                      ? 'Nhiệt độ hiện tại đã ở mức tối đa (30°C)'
                      : 'Nhiệt độ hiện tại đã ở mức tối thiểu (16°C)',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange[900],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Nhiệt độ mục tiêu',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: actionColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: actionColor,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$_targetTemp°C',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: actionColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.thermostat, size: 18, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rangeText,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('$minTemp°C', style: TextStyle(color: actionColor, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Slider(
                    value: _targetTemp.toDouble().clamp(minTemp.toDouble(), maxTemp.toDouble()),
                    min: minTemp.toDouble(),
                    max: maxTemp.toDouble(),
                    divisions: maxTemp - minTemp,
                    activeColor: actionColor,
                    inactiveColor: Colors.grey[300],
                    onChanged: (value) {
                      setState(() {
                        _targetTemp = value.round();
                      });
                    },
                  ),
                ),
                Text('$maxTemp°C', style: TextStyle(color: actionColor, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _selectedAction == 'tempUp'
                  ? 'Máy lạnh sẽ được tăng từ $_currentTemp°C lên $_targetTemp°C (+${_targetTemp - _currentTemp}°C)'
                  : 'Máy lạnh sẽ được giảm từ $_currentTemp°C xuống $_targetTemp°C (-${_currentTemp - _targetTemp}°C)',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    final days = [
      {'value': 1, 'label': 'T2'},
      {'value': 2, 'label': 'T3'},
      {'value': 3, 'label': 'T4'},
      {'value': 4, 'label': 'T5'},
      {'value': 5, 'label': 'T6'},
      {'value': 6, 'label': 'T7'},
      {'value': 0, 'label': 'CN'},
    ];

    // Lấy ngày hiện tại (0 = CN, 1 = T2, ..., 6 = T7)
    final today = DateTime.now().weekday % 7;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((day) {
        final dayValue = day['value'] as int;
        final isSelected = _selectedDays.contains(dayValue);
        final isToday = dayValue == today;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedDays.remove(dayValue);
                    } else {
                      _selectedDays.add(dayValue);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  height: 64,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColor
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isToday
                          ? AppTheme.primaryColor
                          : (isSelected ? AppTheme.primaryColor : Colors.grey[300]!),
                      width: isToday ? 2.5 : 1.5,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ] : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        day['label'] as String,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.grey[800],
                        ),
                      ),
                      if (isToday) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
