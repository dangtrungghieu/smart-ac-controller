import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../../utils/theme.dart';
import '../../models/device_model.dart';
import '../../services/device_service.dart';
import 'select_brand_screen.dart';
import 'ir_learning_screen.dart';

class DeviceSettingsScreen extends StatefulWidget {
  final DeviceModel device;
  final String userId;

  const DeviceSettingsScreen({
    super.key,
    required this.device,
    required this.userId,
  });

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  final TextEditingController _nameController = TextEditingController();

  String _currentMethod = '';
  String _currentBrand = '';
  bool _isLoading = true;
  bool _hasUnsavedChanges = false; // ← THÊM: Track thay đổi chưa lưu

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.device.name;

    // ← THÊM: Lắng nghe thay đổi trong TextField
    _nameController.addListener(() {
      final hasChanges = _nameController.text.trim() != widget.device.name;
      if (hasChanges != _hasUnsavedChanges) {
        setState(() {
          _hasUnsavedChanges = hasChanges;
        });
      }
    });

    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      setState(() => _isLoading = true);

      // Load IR method
      final methodSnapshot = await _db.child('devices/${widget.device.deviceId}/ir/method').get();
      if (methodSnapshot.exists) {
        _currentMethod = methodSnapshot.value as String;
      }

      // Load brand nếu method = library
      if (_currentMethod == 'library') {
        final brandSnapshot = await _db.child('devices/${widget.device.deviceId}/ir/library/brandId').get();
        if (brandSnapshot.exists) {
          _currentBrand = brandSnapshot.value as String;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('Loi load device info: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateDeviceName() async {
    final newName = _nameController.text.trim();

    if (newName.isEmpty) {
      _showMessage('Lỗi', 'Tên thiết bị không được để trống');
      return;
    }

    if (newName == widget.device.name) {
      _showMessage('Thông báo', 'Tên không thay đổi');
      return;
    }

    // ← THÊM: Unfocus TextField để tắt bàn phím
    FocusScope.of(context).unfocus();

    try {
      await _db.child('devices/${widget.device.deviceId}/info/deviceName').set(newName);

      if (!mounted) return;

      // ← Reset flag và TextField TRƯỚC KHI hiện thông báo
      _hasUnsavedChanges = false;
      _nameController.text = newName; // Cập nhật text để listener không trigger

      // Hiện thông báo và chờ user đóng
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.successColor, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Thành công')),
            ],
          ),
          content: const Text('Đã cập nhật tên thiết bị'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );

      // Pop về màn hình trước với flag reload
      if (mounted) {
        Navigator.of(context).pop(true); // true = cần reload
      }
    } catch (e) {
      _showMessage('Lỗi', 'Không thể cập nhật tên: $e');
    }
  }

  Future<void> _switchToLibrary() async {
    final confirmed = await _showConfirmDialog(
      title: 'Chuyển sang điều khiển bằng hãng',
      message: 'Tất cả lệnh đã học sẽ bị xóa.\n\nBạn có chắc chắn muốn chuyển?',
      confirmText: 'Chuyển',
    );

    if (confirmed != true) return;

    if (!mounted) return;

    // Navigate đến màn hình chọn hãng
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SelectBrandScreen(
          userId: widget.userId,
          deviceId: widget.device.deviceId,
          claimCode: widget.device.claimCode,
          deviceName: widget.device.name,
        ),
      ),
    );

    // Nếu user hoàn thành chọn hãng, reload info
    if (result == true && mounted) {
      await _loadDeviceInfo();
      setState(() {});
    }
  }

  Future<void> _switchToLearned() async {
    final confirmed = await _showConfirmDialog(
      title: 'Chuyển sang học lệnh',
      message: 'Cấu hình hãng hiện tại sẽ bị xóa.\n\nBạn có chắc chắn muốn chuyển?',
      confirmText: 'Chuyển',
    );

    if (confirmed != true) return;

    if (!mounted) return;

    // Navigate đến màn hình học lệnh
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IRLearningScreen(
          userId: widget.userId,
          deviceId: widget.device.deviceId,
          claimCode: widget.device.claimCode,
          deviceName: widget.device.name,
        ),
      ),
    );

    // Nếu user hoàn thành học lệnh, reload info
    if (result == true && mounted) {
      await _loadDeviceInfo();
      setState(() {});
    }
  }

  Future<void> _deleteDevice() async {
    final confirmed = await _showDeleteConfirmDialog();

    if (confirmed != true) return;

    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final deviceService = Provider.of<DeviceService>(context, listen: false);
      final success = await deviceService.removeDevice(widget.userId, widget.device.deviceId);

      if (!mounted) return;

      // Close loading
      Navigator.of(context).pop();

      if (success) {
        // Show success dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.successColor, size: 28),
                SizedBox(width: 12),
                Expanded(child: Text('Đã xóa thiết bị')),
              ],
            ),
            content: const Text('Thiết bị đã được khôi phục về cài đặt gốc'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );

        // Go back to device list with reload flag
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        _showMessage('Lỗi', deviceService.errorMessage ?? 'Không thể xóa thiết bị');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading
      _showMessage('Lỗi', 'Không thể xóa thiết bị: $e');
    }
  }

  Future<bool?> _showDeleteConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: AppTheme.errorColor, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text('Xóa thiết bị "${widget.device.name}"?')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Thiết bị sẽ được khôi phục về cài đặt gốc và bị xóa khỏi tài khoản của bạn.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Dữ liệu bị xóa bao gồm:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildDeleteItem('Cấu hình IR (hãng/lệnh đã học)'),
            _buildDeleteItem('Trạng thái thiết bị'),
            _buildDeleteItem('Lịch sử lệnh điều khiển'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: AppTheme.errorColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hành động này không thể hoàn tác!',
                      style: TextStyle(
                        fontSize: 13,
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
  }

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.close, size: 16, color: AppTheme.errorColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String title, String message, {bool isSuccess = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.error,
              color: isSuccess ? AppTheme.successColor : AppTheme.errorColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.errorColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hành động này không thể hoàn tác!',
                      style: TextStyle(
                        fontSize: 13,
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
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  // ← THÊM: Xử lý nút back
  Future<void> _handleBackButton() async {
    if (_hasUnsavedChanges) {
      final shouldPop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 28),
              SizedBox(width: 12),
              Expanded(child: Text('Có thay đổi chưa lưu')),
            ],
          ),
          content: const Text('Bạn có thay đổi chưa được lưu.\n\nBạn có muốn thoát mà không lưu?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Ở lại'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.errorColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Thoát'),
            ),
          ],
        ),
      );

      if (shouldPop == true && mounted) {
        Navigator.of(context).pop(false); // false = không cần reload
      }
    } else {
      Navigator.of(context).pop(false); // false = không cần reload
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // ← THÊM: Kiểm tra thay đổi chưa lưu khi back
        if (_hasUnsavedChanges) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.warningColor, size: 28),
                  SizedBox(width: 12),
                  Expanded(child: Text('Có thay đổi chưa lưu')),
                ],
              ),
              content: const Text('Bạn có thay đổi chưa được lưu.\n\nBạn có muốn thoát mà không lưu?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Ở lại'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Thoát'),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cài đặt thiết bị'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBackButton,
          ),
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Device Info Card
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.devices,
                                  color: AppTheme.primaryColor,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.device.name,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Device ID: ${widget.device.deviceId}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          _buildInfoRow('Phương thức điều khiển',
                            _currentMethod == 'library' ? 'Bằng hãng' :
                            _currentMethod == 'learned' ? 'Học lệnh' : 'Chưa cấu hình',
                          ),
                          if (_currentMethod == 'library' && _currentBrand.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildInfoRow('Hãng máy lạnh', _currentBrand),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Rename Device Section
                  const Text(
                    'Tên thiết bị',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'Nhập tên mới',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.edit),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _updateDeviceName,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.save),
                              label: const Text('Lưu tên'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Control Method Section
                  const Text(
                    'Phương thức điều khiển',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Chuyển sang Library
                  if (_currentMethod != 'library') ...[
                    Card(
                      elevation: 1,
                      child: InkWell(
                        onTap: _switchToLibrary,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.library_books, color: Colors.blue, size: 28),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Chuyển sang bằng hãng',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Điều khiển bằng thư viện hãng có sẵn',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Chuyển sang Learned
                  if (_currentMethod != 'learned') ...[
                    Card(
                      elevation: 1,
                      child: InkWell(
                        onTap: _switchToLearned,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.settings_remote, color: Colors.orange, size: 28),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Chuyển sang học lệnh',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Học từ remote điều khiển',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Delete Device Section
                  const Divider(),
                  const SizedBox(height: 16),

                  OutlinedButton.icon(
                    onPressed: _deleteDevice,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red[700],
                      side: BorderSide(color: Colors.red[300]!, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: const Text(
                      'Xóa thiết bị',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
