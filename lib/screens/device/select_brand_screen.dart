import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../models/brand_model.dart';
import '../../utils/theme.dart';
import '../home/device_list_screen.dart';
import 'ir_learning_screen.dart';

class SelectBrandScreen extends StatefulWidget {
  final String userId;
  final String deviceId;
  final String claimCode;
  final String deviceName;

  const SelectBrandScreen({
    super.key,
    required this.userId,
    required this.deviceId,
    required this.claimCode,
    required this.deviceName,
  });

  @override
  State<SelectBrandScreen> createState() => _SelectBrandScreenState();
}

class _SelectBrandScreenState extends State<SelectBrandScreen> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  List<BrandModel> _brands = [];
  bool _isLoading = true;
  String? _selectedBrandId;

  @override
  void initState() {
    super.initState();
    _loadBrands();
  }

  Future<void> _loadBrands() async {
    try {
      final snapshot = await _db.child('ir_library').get();

      if (snapshot.exists) {
        final brandsData = Map<String, dynamic>.from(snapshot.value as Map);
        _brands = brandsData.entries
            .map((e) => BrandModel.fromJson(e.key, Map<String, dynamic>.from(e.value)))
            .toList();
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Loi load brands: $e');
    }
  }

  Future<void> _handleSelectBrand(BrandModel brand) async {
    setState(() {
      _selectedBrandId = brand.id;
    });

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.ac_unit, color: AppTheme.primaryColor, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Xác nhận chọn hãng',
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
              'Bạn có chắc muốn chọn hãng:',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.ac_unit,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      brand.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Thiết bị sẽ được thêm với cấu hình hãng này.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
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
              'Xác nhận',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    // If user cancelled, deselect the brand
    if (confirmed != true) {
      setState(() {
        _selectedBrandId = null;
      });
      return;
    }

    try {
      print('>>> Bat dau claim device sau khi chon brand...');

      // ===== BƯỚC 1: CLAIM DEVICE TRƯỚC =====
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

      // ===== BƯỚC 2: LƯU BRAND VÀO DEVICE =====
      await _db.child('devices/${widget.deviceId}/ir').set({
        'method': 'library',
        'library': {
          'brandId': brand.id,
          'brandName': brand.name,
        },
      });
      print('✓ Da luu brand vao device');

      if (!mounted) return;

      // Hiển thị thông báo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Da them thiet bi voi hang ${brand.name}'),
          backgroundColor: AppTheme.successColor,
        ),
      );

      // Quay về Device List
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DeviceListScreen()),
        (route) => false,
      );
    } catch (e) {
      print('✗ Loi: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Loi them thiet bi: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _handleLearnMode() async {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => IRLearningScreen(
          userId: widget.userId,
          deviceId: widget.deviceId,
          claimCode: widget.claimCode,
          deviceName: widget.deviceName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chon hang may lanh'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: Colors.blue[50],
                  child: Column(
                    children: [
                      const Icon(
                        Icons.ac_unit,
                        size: 40,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chon hang may lanh cua ban',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Hoac hoc lenh tu remote',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                // Brands List
                Expanded(
                  child: _brands.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 80,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Chua co hang nao',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: _brands.length,
                          itemBuilder: (context, index) {
                            final brand = _brands[index];
                            final isSelected = _selectedBrandId == brand.id;

                            return InkWell(
                              onTap: () => _handleSelectBrand(brand),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryColor.withOpacity(0.1)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.primaryColor
                                        : Colors.grey[300]!,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Logo placeholder
                                    Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.ac_unit,
                                        size: 30,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      brand.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? AppTheme.primaryColor
                                            : Colors.black87,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    if (isSelected)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Icon(
                                          Icons.check_circle,
                                          size: 20,
                                          color: AppTheme.primaryColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Learn Mode Button
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Khong tim thay hang cua ban?',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _handleLearnMode,
                          icon: const Icon(Icons.settings_remote),
                          label: const Text('Hoc lenh tu remote'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryColor,
                            side: const BorderSide(color: AppTheme.primaryColor),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}