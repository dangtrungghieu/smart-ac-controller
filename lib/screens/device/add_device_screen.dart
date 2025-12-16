import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import '../../utils/theme.dart';
import 'select_brand_screen.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _claimCodeController = TextEditingController();
  final _deviceNameController = TextEditingController();

  @override
  void dispose() {
    _deviceIdController.dispose();
    _claimCodeController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _handleValidate() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final deviceService = Provider.of<DeviceService>(context, listen: false);

    if (authService.currentUser == null) return;

    // CHỈ VALIDATE - KHÔNG CLAIM
    final success = await deviceService.validateDevice(
      deviceId: _deviceIdController.text.trim(),
      claimCode: _claimCodeController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      // Chuyển sang màn hình chọn hãng AC (truyền thông tin để claim sau)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SelectBrandScreen(
            userId: authService.currentUser!.uid,
            deviceId: _deviceIdController.text.trim(),
            claimCode: _claimCodeController.text.trim(),
            deviceName: _deviceNameController.text.trim(),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deviceService.errorMessage ?? 'Kiem tra thiet bi that bai'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Them thiet bi'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    size: 50,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Title
              const Text(
                'Thông tin thiết bị',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Nhập Device ID và Claim Code được cung cấp cùng thiết bị',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 24),

              // Device ID
              TextFormField(
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: 'Device ID',
                  hintText: '',
                  prefixIcon: Icon(Icons.device_hub),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập Device ID';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Claim Code
              TextFormField(
                controller: _claimCodeController,
                decoration: const InputDecoration(
                  labelText: 'Claim Code',
                  hintText: '',
                  prefixIcon: Icon(Icons.key),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập Claim Code';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Device Name
              TextFormField(
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên thiết bị',
                  hintText: '',
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập tên thiết bị';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Validate Button
              Consumer<DeviceService>(
                builder: (context, deviceService, child) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: deviceService.isLoading ? null : _handleValidate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: deviceService.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Tiếp tục'),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Info box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Device ID và Claim Code nằm trên thiết bị hoặc trong tài liệu hướng dẫn.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}