import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../utils/theme.dart';
import '../home/device_list_screen.dart';
import 'select_brand_screen.dart';

class IRLearningScreen extends StatefulWidget {
  final String userId;
  final String deviceId;
  final String claimCode;
  final String deviceName;

  const IRLearningScreen({
    super.key,
    required this.userId,
    required this.deviceId,
    required this.claimCode,
    required this.deviceName,
  });

  @override
  State<IRLearningScreen> createState() => _IRLearningScreenState();
}

class _IRLearningScreenState extends State<IRLearningScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  int _currentStep = 0;
  bool _isLearning = false;
  bool _isWaiting = false;
  bool _processingResult = false;
  bool _isTesting = false; // ← THÊM: Đang test lệnh
  bool _needsTest = false; // ← THÊM: Cần test lệnh trước khi chuyển bước
  String _statusMessage = '';

  // ← THÊM: Lưu trữ IR codes đã học
  final Map<String, String> _learnedCodes = {};

  final List<Map<String, String>> _steps = [
    {
      'title': 'Lenh BAT',
      'command': 'power_on',
      'instruction': 'Nhan nut BAT tren remote',
    },
    {
      'title': 'Lenh TAT',
      'command': 'power_off',
      'instruction': 'Nhan nut TAT tren remote (co the giong nut BAT)',
    },
    {
      'title': 'Lenh TANG NHIET DO',
      'command': 'temp_up',
      'instruction': 'Nhan nut TANG NHIET DO tren remote',
    },
    {
      'title': 'Lenh GIAM NHIET DO',
      'command': 'temp_down',
      'instruction': 'Nhan nut GIAM NHIET DO tren remote',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initLearningSession();
    _listenToLearningSession();
  }

  // Khởi tạo session học mới
  Future<void> _initLearningSession() async {
    try {
      // Xóa session cũ nếu có
      await _db.child('ir_learning/${widget.deviceId}').remove();

      // ===== LƯU IR METHOD = "learned" NGAY TỪ ĐẦU =====
      // ESP32 cần biết method để xử lý lệnh đúng
      await _db.child('devices/${widget.deviceId}/ir').set({
        'method': 'learned',
        'learningStartedAt': DateTime.now().millisecondsSinceEpoch,
      });

      print('✓ Da khoi tao learning session moi');
      print('✓ Da set ir/method = learned');
    } catch (e) {
      print('Loi khoi tao session: $e');
    }
  }

  void _listenToLearningSession() {
    _db.child('ir_learning/${widget.deviceId}').onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);

        setState(() {
          _isWaiting = data['waiting'] ?? false;

          // ===== KIỂM TRA RESULT VỚI DEBOUNCING =====
          if (data['result'] != null && !_processingResult) {
            _processingResult = true; // ← Đánh dấu đang xử lý

            print('>>> RAW Firebase data[result]: ${data['result']}');

            final result = Map<String, dynamic>.from(data['result']);
            final success = result['success'] ?? false;

            print('>>> Result keys: ${result.keys.toList()}');
            print('>>> Success: $success');

            if (success) {
              // ← LƯU IR CODE VÀO MAP (ESP32 ghi vào 'code', không phải 'irCode')
              final irCode = result['code'] as String?;

              print('>>> IR Code value: ${irCode != null ? "Found (${irCode.length} chars)" : "NULL"}');

              if (irCode != null && irCode.isNotEmpty) {
                final currentCommand = _steps[_currentStep]['command']!;
                _learnedCodes[currentCommand] = irCode;
                print('✓ Da luu IR code cho $currentCommand: ${irCode.length} characters');
                print('  Preview: ${irCode.substring(0, irCode.length > 50 ? 50 : irCode.length)}...');
                print('  _learnedCodes map: ${_learnedCodes.keys.toList()}');
              } else {
                print('⚠️ Khong tim thay IR code trong result');
                print('  Result data: $result');
              }

              _statusMessage = 'Da hoc thanh cong!';

              print('✓ Hoc thanh cong buoc ${_currentStep + 1}: ${_steps[_currentStep]['command']}');

              // ← HIỂN thị nút test thay vì tự động chuyển bước
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (!mounted) return;

                setState(() {
                  _needsTest = true; // Cho phép test lệnh
                  _statusMessage = 'Hay test lenh!';
                  _isLearning = false;
                });

                _clearResult();
              });
            } else {
              _statusMessage = 'Loi! Thu lai';
              _isLearning = false;

              print('✗ Hoc that bai buoc ${_currentStep + 1}');

              // Xóa result để có thể thử lại
              _clearResult().then((_) {
                if (mounted) {
                  setState(() {
                    _processingResult = false; // ← Reset flag
                  });
                }
              });
            }
          }
        });
      }
    });
  }

  // XÓA result sau khi xử lý xong
  Future<void> _clearResult() async {
    try {
      print('>>> Dang xoa result...');

      // Xóa toàn bộ các field liên quan
      await _db.child('ir_learning/${widget.deviceId}/result').remove();
      await _db.child('ir_learning/${widget.deviceId}/waiting').set(false);
      await _db.child('ir_learning/${widget.deviceId}/active').set(false);

      // Chờ một chút để Firebase propagate changes
      await Future.delayed(const Duration(milliseconds: 300));

      print('✓ Da xoa result, san sang cho lenh tiep theo');
    } catch (e) {
      print('Loi xoa result: $e');
    }
  }

  Future<void> _startLearning() async {
    setState(() {
      _isLearning = true;
      _statusMessage = 'Dang cho tin hieu...';
      _processingResult = false; // ← Reset flag trước khi bắt đầu
    });

    try {
      final currentCommand = _steps[_currentStep]['command'];

      print('>>> Bat dau hoc lenh: $currentCommand (buoc ${_currentStep + 1}/${_steps.length})');

      // ===== XÓA SESSION CŨ HOÀN TOÀN TRƯỚC =====
      await _db.child('ir_learning/${widget.deviceId}').remove();
      await Future.delayed(const Duration(milliseconds: 200)); // Đợi Firebase xóa xong

      // ===== TẠO SESSION MỚI =====
      await _db.child('ir_learning/${widget.deviceId}').set({
        'active': true,
        'currentStep': _currentStep,
        'command': currentCommand,
        'waiting': true,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      print('✓ Da gui yeu cau hoc len Firebase');
    } catch (e) {
      setState(() {
        _statusMessage = 'Loi: $e';
        _isLearning = false;
        _processingResult = false;
      });
      print('✗ Loi: $e');
    }
  }

  // ← THÊM: TEST LỆNH ĐÃ HỌC
  Future<void> _testCommand() async {
    setState(() {
      _isTesting = true;
      _statusMessage = 'Dang gui lenh test...';
    });

    try {
      final currentCommand = _steps[_currentStep]['command']!;

      print('>>> Test lenh: $currentCommand');

      // Chuyển đổi command name sang action format mà ESP32 mong đợi
      // ESP32 sendIRLearnedCommand() nhận: "power", "tempUp", "tempDown"
      String action;
      if (currentCommand == 'power_on' || currentCommand == 'power_off') {
        action = 'power'; // ESP32 tự quyết định bật/tắt dựa vào acPowerOn
      } else if (currentCommand == 'temp_up') {
        action = 'tempUp';
      } else if (currentCommand == 'temp_down') {
        action = 'tempDown';
      } else {
        action = currentCommand;
      }

      await _db.child('commands/${widget.deviceId}').set({
        'action': action,
        'value': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'executed': false,
      });

      print('✓ Da gui lenh test (action: $action, value: 0)');

      // Hiển thị thông báo thành công
      setState(() {
        _isTesting = false;
        _statusMessage = 'Da gui lenh test!';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _statusMessage = 'Loi test: $e';
      });
      print('✗ Loi test: $e');
    }
  }

  // ← THÊM: CHUYỂN SANG BƯỚC TIẾP THEO
  Future<void> _nextStep() async {
    if (_currentStep < _steps.length - 1) {
      // Xóa result và session cũ trước khi chuyển bước
      await _clearResult();

      setState(() {
        _currentStep++;
        _statusMessage = '';
        _isLearning = false;
        _needsTest = false;
        _processingResult = false;
      });

      print('→ Chuyen sang buoc ${_currentStep + 1}');
    } else {
      // Đã hoàn thành tất cả
      await _finishLearning();
    }
  }

  Future<void> _finishLearning() async {
    print('✓✓✓ HOAN THANH tat ca cac lenh!');

    try {
      // ===== BƯỚC 1: CLAIM DEVICE TRƯỚC =====
      print('>>> Bat dau claim device sau khi hoc xong...');
      await _db.child('devices/${widget.deviceId}/info').update({
        'deviceName': widget.deviceName,
        'claimed': true,
        'ownerId': widget.userId,
        'claimedAt': DateTime.now().millisecondsSinceEpoch,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      });
      print('✓ Da claim device');

      // Thêm vào user_devices
      await _db.child('user_devices/${widget.userId}/${widget.deviceId}').set(true);
      print('✓ Da them vao user_devices');

      // ===== BƯỚC 2: LƯU TẤT CẢ IR CODES VÀO FIREBASE (THEO CẤU TRÚC ESP32) =====
      // ESP32 đọc từ: devices/{deviceId}/ir/learned/commands/{command_name}

      print('>>> DEBUG: Dang luu ${_learnedCodes.length} lenh vao Firebase:');
      print('>>> _learnedCodes map keys: ${_learnedCodes.keys.toList()}');

      // Lưu từng lệnh riêng biệt theo cấu trúc ESP32 TRƯỚC
      for (var entry in _learnedCodes.entries) {
        print('>>> Luu lenh: ${entry.key} (${entry.value.length} characters)');
        print('    IR code preview: ${entry.value.substring(0, entry.value.length > 100 ? 100 : entry.value.length)}...');

        await _db.child('devices/${widget.deviceId}/ir/learned/commands/${entry.key}').set(entry.value);
        print('✓ Da luu lenh ${entry.key} len Firebase');
      }

      // Sau đó mới update metadata (dùng update thay vì set để không xóa commands)
      await _db.child('devices/${widget.deviceId}/ir').update({
        'method': 'learned',
        'learnedAt': DateTime.now().millisecondsSinceEpoch,
      });

      print('✓ Da luu tat ca IR codes vao Firebase');

      // Xóa learning session
      await _db.child('ir_learning/${widget.deviceId}').remove();

      if (!mounted) return;

      // Hiển thị dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.successColor, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hoan thanh',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: const Text('Da hoc thanh cong tat ca lenh!\n\nThiet bi da san sang de dieu khien.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const DeviceListScreen()),
                  (route) => false,
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
              ),
              child: const Text('Dong'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('✗ Loi finish learning: $e');

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Loi'),
          content: Text('Loi them thiet bi: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Dong'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    // Dọn dẹp khi thoát màn hình (trường hợp user back giữa chừng)
    if (_currentStep < _steps.length - 1) {
      _cleanupLearningData();
    }
    super.dispose();
  }

  // ← THÊM: Dọn dẹp toàn bộ dữ liệu học lệnh
  Future<void> _cleanupLearningData() async {
    try {
      print('>>> Dang don dep du lieu hoc lenh...');

      // Xóa ir_learning session
      await _db.child('ir_learning/${widget.deviceId}').remove();

      // Xóa ir/method và learned commands
      await _db.child('devices/${widget.deviceId}/ir').remove();

      print('✓ Da xoa ir/method va learned commands');
    } catch (e) {
      print('✗ Loi don dep: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStepData = _steps[_currentStep];
    
    return WillPopScope(
      onWillPop: () async {
        // Xác nhận trước khi thoát
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Huy hoc lenh?'),
            content: const Text('Ban co chac muon huy qua trinh hoc lenh?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Tiep tuc hoc'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
                child: const Text('Huy'),
              ),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Hoc lenh tu remote'),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Progress
              LinearProgressIndicator(
                value: (_currentStep + 1) / _steps.length,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'Buoc ${_currentStep + 1}/${_steps.length}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Instruction Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.settings_remote,
                          size: 40,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Title
                      Text(
                        currentStepData['title']!,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Instruction
                      Text(
                        currentStepData['instruction']!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[700],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Status
                      if (_statusMessage.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _statusMessage.contains('thanh cong')
                                ? AppTheme.successColor.withOpacity(0.1)
                                : (_statusMessage.contains('Loi')
                                    ? AppTheme.errorColor.withOpacity(0.1)
                                    : AppTheme.warningColor.withOpacity(0.1)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _statusMessage.contains('thanh cong')
                                  ? AppTheme.successColor
                                  : (_statusMessage.contains('Loi')
                                      ? AppTheme.errorColor
                                      : AppTheme.warningColor),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _statusMessage.contains('thanh cong')
                                    ? Icons.check_circle
                                    : (_statusMessage.contains('Loi')
                                        ? Icons.error
                                        : Icons.info),
                                color: _statusMessage.contains('thanh cong')
                                    ? AppTheme.successColor
                                    : (_statusMessage.contains('Loi')
                                        ? AppTheme.errorColor
                                        : AppTheme.warningColor),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                _statusMessage,
                                style: TextStyle(
                                  color: _statusMessage.contains('thanh cong')
                                      ? AppTheme.successColor
                                      : (_statusMessage.contains('Loi')
                                          ? AppTheme.errorColor
                                          : AppTheme.warningColor),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              const Spacer(),

              // ← NÚT TEST VÀ TIẾP TUC (khi đã học xong)
              if (_needsTest) ...[
                // Nút Test và Học lại
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isTesting ? null : _testCommand,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          disabledBackgroundColor: Colors.grey[300],
                        ),
                        icon: _isTesting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: Text(
                          _isTesting ? 'Dang test...' : 'Test lenh',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // Reset trạng thái để học lại
                          setState(() {
                            _needsTest = false;
                            _statusMessage = '';
                            _isLearning = false;
                            _isTesting = false;
                            _processingResult = false;
                          });
                          // Xóa IR code đã lưu cho lệnh này
                          final currentCommand = _steps[_currentStep]['command']!;
                          _learnedCodes.remove(currentCommand);
                          print('>>> Da xoa lenh $currentCommand, san sang hoc lai');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.errorColor,
                          side: const BorderSide(color: AppTheme.errorColor),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'Hoc lai',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Nút Tiếp tục (full width)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.successColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(
                      _currentStep < _steps.length - 1 ? 'Tiep tuc' : 'Hoan thanh',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ] else ...[
                // Learn Button (khi chưa học hoặc đang học)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLearning ? null : _startLearning,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: Colors.grey[300],
                    ),
                    child: _isLearning
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(_isWaiting ? 'Dang cho...' : 'Dang hoc...'),
                            ],
                          )
                        : const Text(
                            'Bat dau hoc',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Huong remote vao cam bien IR cua thiet bi khi nhan nut',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Back to Brand Selection Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    // Show confirmation dialog
                    final shouldGoBack = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: const Row(
                          children: [
                            Icon(Icons.arrow_back, color: AppTheme.primaryColor, size: 28),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Quay lại chọn hãng',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Bạn có muốn quay lại để chọn hãng máy lạnh khác?',
                              style: TextStyle(fontSize: 15),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.errorColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppTheme.errorColor.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppTheme.errorColor,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Tiến trình học lệnh hiện tại sẽ bị xóa.',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.errorColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text(
                              'Hủy',
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Quay lại',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (shouldGoBack == true && mounted) {
                      // Xóa toàn bộ dữ liệu học lệnh (ir_learning + ir/method + learned commands)
                      await _cleanupLearningData();

                      if (!mounted) return;

                      // Navigate back to brand selection
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => SelectBrandScreen(
                            userId: widget.userId,
                            deviceId: widget.deviceId,
                            claimCode: widget.claimCode,
                            deviceName: widget.deviceName,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Chon lai hang may lanh'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: const BorderSide(color: AppTheme.primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}