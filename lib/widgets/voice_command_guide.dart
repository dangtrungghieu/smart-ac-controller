/// ========================================
/// VOICE COMMAND GUIDE WIDGET
/// ========================================
///
/// Widget hiển thị hướng dẫn các câu lệnh giọng nói
/// Hiển thị dưới dạng BottomSheet với danh sách câu lệnh mẫu
library;

import 'package:flutter/material.dart';
import '../utils/theme.dart';

class VoiceCommandGuide {
  /// Hiển thị guide dưới dạng BottomSheet
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _VoiceCommandGuideContent(),
    );
  }
}

class _VoiceCommandGuideContent extends StatelessWidget {
  const _VoiceCommandGuideContent();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: AppTheme.primaryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hướng dẫn lệnh giọng nói',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Các câu lệnh bạn có thể sử dụng',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Danh sách lệnh
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _buildCommandSection(
                      icon: Icons.power_settings_new,
                      iconColor: Colors.green,
                      title: '1. Bật / Tắt máy lạnh',
                      examples: [
                        '🔵 "Bật máy lạnh"',
                        '🔵 "Mở điều hòa"',
                        '🔴 "Tắt máy lạnh"',
                        '🔴 "Tắt điều hòa"',
                        '🔵 "Turn on air"',
                        '🔴 "Turn off air"',
                      ],
                    ),

                    _buildCommandSection(
                      icon: Icons.thermostat,
                      iconColor: Colors.orange,
                      title: '2. Tăng / Giảm nhiệt độ',
                      examples: [
                        '❄️ "Giảm nhiệt độ"',
                        '❄️ "Giảm 2 độ"',
                        '❄️ "Cho mát hơn 3 độ"',
                        '❄️ "Lạnh hơn"',
                        '🔥 "Tăng nhiệt độ"',
                        '🔥 "Tăng 1 độ"',
                        '🔥 "Ấm hơn"',
                        '🔥 "Bớt lạnh"',
                      ],
                      note: 'Có thể nói số độ từ 1-5',
                    ),

                    _buildCommandSection(
                      icon: Icons.schedule,
                      iconColor: Colors.blue,
                      title: '3. Lên lịch bật / tắt',
                      examples: [
                        '⏰ "Hẹn bật máy lạnh lúc 7 giờ sáng thứ hai"',
                        '⏰ "Lên lịch tắt điều hòa 10 giờ tối thứ bảy"',
                        '⏰ "Bật máy lúc 6h30 chủ nhật"',
                        '⏰ "Tắt máy lúc 11 giờ trưa thứ năm"',
                        '⏰ "Hẹn bật lúc 8 giờ rưỡi sáng thứ ba"',
                      ],
                      note: 'Nói rõ: bật/tắt + thứ + giờ phút',
                    ),

                    _buildCommandSection(
                      icon: Icons.timer,
                      iconColor: Colors.purple,
                      title: '4. Auto Off (Tự động tắt)',
                      examples: [
                        '⏲️ "Bật auto off sau 30 phút"',
                        '⏲️ "Bật tự tắt sau 45 phút"',
                        '⏲️ "Tắt auto off"',
                        '⏲️ "Hủy chế độ tự tắt"',
                      ],
                      note: 'Thời gian tối đa 60 phút để tiết kiệm điện',
                      warning: true,
                    ),

                    const SizedBox(height: 12),

                    // Tips
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.tips_and_updates, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Mẹo sử dụng',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildTip('Nói rõ ràng, từ tốn'),
                          _buildTip('Ở nơi yên tĩnh để nhận dạng tốt hơn'),
                          _buildTip('Có thể nói nhiều cách khác nhau'),
                          _buildTip('Kết hợp tiếng Việt và tiếng Anh'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommandSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<String> examples,
    String? note,
    bool warning = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Examples
          ...examples.map((example) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        example,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[800],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),

          // Note
          if (note != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: warning ? Colors.orange[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    warning ? Icons.warning_amber : Icons.info_outline,
                    size: 16,
                    color: warning ? Colors.orange[700] : Colors.blue[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        color: warning ? Colors.orange[900] : Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue[900],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
