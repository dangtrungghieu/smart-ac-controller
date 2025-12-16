/// ========================================
/// VOICE CONTROL BUTTON WIDGET
/// ========================================
///
/// Widget nút ghi âm để điều khiển giọng nói
///
/// TÍNH NĂNG:
/// - Nút tròn với icon microphone
/// - Animation khi đang ghi âm
/// - Hiển thị trạng thái (sẵn sàng/đang nghe/đang xử lý)
/// - Callback khi nhận được lệnh
///
/// SỬ DỤNG:
/// ```dart
/// VoiceControlButton(
///   onCommandDetected: (VoiceCommand command) {
///     // Xử lý lệnh
///   },
/// )
/// ```
library;

import 'package:flutter/material.dart';
import '../models/voice_command_model.dart';
import '../services/vosk_speech_service_v2.dart';
import '../services/ultra_simple_parser.dart';
import '../utils/theme.dart';

class VoiceControlButton extends StatefulWidget {
  /// Callback khi phát hiện được lệnh giọng nói
  final Function(VoiceCommand command) onCommandDetected;

  /// Kích thước nút (mặc định 60)
  final double size;

  /// Có hiển thị text hướng dẫn không
  final bool showHint;

  const VoiceControlButton({
    super.key,
    required this.onCommandDetected,
    this.size = 60,
    this.showHint = true,
  });

  @override
  State<VoiceControlButton> createState() => _VoiceControlButtonState();
}

class _VoiceControlButtonState extends State<VoiceControlButton>
    with SingleTickerProviderStateMixin {
  final VoskSpeechServiceV2 _speechService = VoskSpeechServiceV2();

  /// Trạng thái của nút
  VoiceButtonState _state = VoiceButtonState.ready;

  /// Transcript hiện tại (realtime)
  String _currentTranscript = '';

  /// Animation controller cho hiệu ứng pulse khi ghi âm
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Khởi tạo animation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Lặp animation
    _pulseController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _pulseController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _pulseController.forward();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    // KHÔNG dispose service vì nó là Singleton (sẽ được reuse cho widget khác)
    // Chỉ stop listening nếu đang nghe
    if (_state == VoiceButtonState.listening) {
      _speechService.stopListening();
    }
    super.dispose();
  }

  /// Xử lý khi bắt đầu nhấn giữ (push-to-talk)
  Future<void> _handleLongPressStart() async {
    // Nếu đang bận, bỏ qua
    if (_state != VoiceButtonState.ready) {
      return;
    }

    // Kiểm tra khởi tạo VOSK
    try {
      final initialized = await _speechService.initialize();
      if (!initialized) {
        if (mounted) {
          _showMessage('Không thể khởi tạo nhận diện giọng nói. Vui lòng thử lại sau.', isError: true);
        }
        return;
      }
    } catch (e) {
      print('❌ Error initialize: $e');
      if (mounted) {
        _showMessage('Lỗi khởi tạo: ${e.toString()}', isError: true);
      }
      return;
    }

    // Kiểm tra quyền
    try {
      final hasPermission = await _speechService.checkPermission();
      if (!hasPermission) {
        if (mounted) {
          _showMessage('Cần cấp quyền microphone để sử dụng tính năng này', isError: true);
        }
        return;
      }
    } catch (e) {
      print('❌ Error check permission: $e');
      if (mounted) {
        _showMessage('Lỗi kiểm tra quyền: ${e.toString()}', isError: true);
      }
      return;
    }

    // Bắt đầu nghe
    if (!mounted) return; // ← FIX: Kiểm tra mounted trước khi setState

    setState(() {
      _state = VoiceButtonState.listening;
      _currentTranscript = '';
    });
    _pulseController.forward();

    try {
      // Lắng nghe không giới hạn thời gian (listenSeconds = 0)
      // Sẽ dừng khi user thả nút (gọi stopListening())
      await _speechService.listen(
        onResult: (text) {
          // Update UI realtime
          if (mounted) {
            setState(() {
              _currentTranscript = text;
            });
          }
        },
        listenSeconds: 0, // Không tự động dừng
      ).then((transcript) async {
        // Callback này chạy khi stopListening() được gọi
        if (mounted) {
          await _processTranscript(transcript);
        }
      }).catchError((e) {
        print('❌ Error listen: $e');
        print('Stack trace: ${StackTrace.current}');
        _resetState();
        if (mounted) {
          _showMessage('Lỗi khi xử lý giọng nói: ${e.toString()}', isError: true);
        }
      });
    } catch (e, stackTrace) {
      print('❌ Error _handleLongPressStart: $e');
      print('Stack trace: $stackTrace');
      _resetState();
      if (mounted) {
        _showMessage('Lỗi khi bắt đầu ghi âm: ${e.toString()}', isError: true);
      }
    }
  }

  /// Xử lý khi thả nút (push-to-talk release)
  Future<void> _handleLongPressEnd() async {
    if (_state != VoiceButtonState.listening) {
      return;
    }

    // Dừng ghi âm và trả kết quả
    try {
      await _speechService.stopListening();
    } catch (e, stackTrace) {
      print('❌ Error stopListening: $e');
      print('Stack trace: $stackTrace');
      _resetState();
      if (mounted) {
        _showMessage('Lỗi khi dừng ghi âm: ${e.toString()}', isError: true);
      }
    }
  }

  /// Xử lý transcript nhận được
  Future<void> _processTranscript(String? transcript) async {
    try {
      // Dừng animation
      _pulseController.stop();
      _pulseController.reset();

      if (transcript == null || transcript.isEmpty) {
        // Không nhận được gì
        if (!mounted) return; // ← FIX: Kiểm tra mounted

        setState(() {
          _state = VoiceButtonState.ready;
          _currentTranscript = '';
        });

        if (mounted) {
          _showMessage('Không nhận được lệnh, vui lòng thử lại', isError: true);
        }
        // KHÔNG gọi callback để tránh hiển thị 2 SnackBars
        return;
      }

      // Đang xử lý
      if (!mounted) return; // ← FIX: Kiểm tra mounted

      setState(() {
        _state = VoiceButtonState.processing;
      });

      // Parse lệnh
      await Future.delayed(const Duration(milliseconds: 300)); // Delay nhẹ cho UX

      if (!mounted) return; // ← FIX: Kiểm tra mounted sau delay

      final command = UltraSimpleParser.parseCommand(transcript);

      // Reset trạng thái
      if (!mounted) return; // ← FIX: Kiểm tra mounted

      setState(() {
        _state = VoiceButtonState.ready;
      });

      // Callback (CHỈ khi có transcript)
      // Nếu lệnh không được nhận diện (unknown), hiển thị thông báo tại đây
      // và KHÔNG gọi callback để tránh duplicate SnackBars
      if (command.type == VoiceCommandType.unknown) {
        if (mounted) {
          _showMessage(
            'Không hiểu lệnh: "$transcript"\nVui lòng thử lại hoặc xem hướng dẫn',
            isError: true,
          );
        }
        return;
      }

      // Callback (CHỈ khi lệnh hợp lệ)
      if (mounted) {
        widget.onCommandDetected(command);
      }
    } catch (e, stackTrace) {
      print('❌ Error _processTranscript: $e');
      print('Stack trace: $stackTrace');
      _resetState();
      if (mounted) {
        _showMessage('Lỗi khi xử lý lệnh: ${e.toString()}', isError: true);
      }
    }
  }

  /// Reset trạng thái
  void _resetState() {
    _pulseController.stop();
    _pulseController.reset();
    if (mounted) {
      setState(() {
        _state = VoiceButtonState.ready;
        _currentTranscript = '';
      });
    }
  }

  /// Hiển thị thông báo SnackBar
  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nút microphone
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _state == VoiceButtonState.listening
                  ? _pulseAnimation.value
                  : 1.0,
              child: child,
            );
          },
          child: GestureDetector(
            onLongPressStart: (_) {
              try {
                _handleLongPressStart();
              } catch (e, stackTrace) {
                print('❌ Error in onLongPressStart: $e');
                print('Stack trace: $stackTrace');
                _resetState();
                if (mounted) {
                  _showMessage('Lỗi khi bắt đầu: ${e.toString()}', isError: true);
                }
              }
            },
            onLongPressEnd: (_) {
              try {
                _handleLongPressEnd();
              } catch (e, stackTrace) {
                print('❌ Error in onLongPressEnd: $e');
                print('Stack trace: $stackTrace');
                _resetState();
                if (mounted) {
                  _showMessage('Lỗi khi kết thúc: ${e.toString()}', isError: true);
                }
              }
            },
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _getGradientColors(),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _getGradientColors()[0].withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Icon hoặc loading
                  _state == VoiceButtonState.processing
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(
                          _getIcon(),
                          color: Colors.white,
                          size: widget.size * 0.5,
                        ),
                ],
              ),
            ),
          ),
        ),

        // Text hướng dẫn
        if (widget.showHint) ...[
          const SizedBox(height: 8),
          Text(
            _getHintText(),
            style: TextStyle(
              fontSize: 12,
              color: _state == VoiceButtonState.listening
                  ? AppTheme.primaryColor
                  : Colors.grey[600],
              fontWeight: _state == VoiceButtonState.listening
                  ? FontWeight.w600
                  : FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  /// Lấy màu gradient theo trạng thái
  List<Color> _getGradientColors() {
    switch (_state) {
      case VoiceButtonState.ready:
        return [
          AppTheme.primaryColor,
          AppTheme.primaryColor.withOpacity(0.7),
        ];
      case VoiceButtonState.listening:
        return [
          Colors.red.shade400,
          Colors.red.shade600,
        ];
      case VoiceButtonState.processing:
        return [
          Colors.orange.shade400,
          Colors.orange.shade600,
        ];
    }
  }

  /// Lấy icon theo trạng thái
  IconData _getIcon() {
    switch (_state) {
      case VoiceButtonState.ready:
        return Icons.mic;
      case VoiceButtonState.listening:
        return Icons.mic;
      case VoiceButtonState.processing:
        return Icons.mic;
    }
  }

  /// Lấy text hướng dẫn
  String _getHintText() {
    switch (_state) {
      case VoiceButtonState.ready:
        return 'Nhấn giữ để nói lệnh';
      case VoiceButtonState.listening:
        return 'Đang nghe... thả ra khi xong';
      case VoiceButtonState.processing:
        return 'Đang xử lý...';
    }
  }
}

/// Trạng thái của nút voice control
enum VoiceButtonState {
  /// Sẵn sàng (có thể nhấn)
  ready,

  /// Đang ghi âm
  listening,

  /// Đang xử lý (gửi lên API và parse)
  processing,
}
