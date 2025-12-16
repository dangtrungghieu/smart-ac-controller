/// ========================================
/// VOSK SPEECH SERVICE V2 - REUSE APPROACH
/// ========================================
///
/// GIẢI PHÁP ĐÚNG: Tạo SpeechService 1 LẦN, REUSE nhiều lần
/// KHÔNG tạo mới mỗi lần → Tránh "instance already exist"
library;

import 'dart:async';
import 'dart:convert';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';
import 'package:permission_handler/permission_handler.dart';

class VoskSpeechServiceV2 {
  // ========================================
  // SINGLETON
  // ========================================
  static VoskSpeechServiceV2? _instance;

  factory VoskSpeechServiceV2() {
    _instance ??= VoskSpeechServiceV2._internal();
    return _instance!;
  }

  VoskSpeechServiceV2._internal();

  // ========================================
  // FIELDS
  // ========================================
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService; // ← Tạo 1 LẦN, REUSE mãi mãi!

  bool _isInitialized = false;
  bool _isListening = false;

  String _lastTranscript = '';
  Completer<String?>? _resultCompleter;

  StreamSubscription? _partialSubscription;
  StreamSubscription? _resultSubscription;

  // ========================================
  // INIT (1 LẦN DUY NHẤT)
  // ========================================
  Future<bool> initialize() async {
    if (_isInitialized) {
      print('✅ VOSK đã khởi tạo');
      return true;
    }

    try {
      print('🔄 Đang khởi tạo VOSK...');

      // Load model
      String? modelPath;
      try {
        modelPath = await ModelLoader().loadFromAssets(
          'assets/vosk-model-small-vi.zip',
        );
        print('📦 Model path: $modelPath');
      } catch (e, stackTrace) {
        print('❌ Lỗi load model từ assets: $e');
        print('Stack trace: $stackTrace');
        throw Exception('Không thể load model VOSK. Kiểm tra file assets/vosk-model-small-vi.zip');
      }

      // Create model
      try {
        _model = await _vosk.createModel(modelPath);
        print('✅ Model created');
      } catch (e, stackTrace) {
        print('❌ Lỗi tạo model: $e');
        print('Stack trace: $stackTrace');
        throw Exception('Không thể khởi tạo VOSK model. File model có thể bị lỗi.');
      }

      // Create recognizer
      try {
        _recognizer = await _vosk.createRecognizer(
          model: _model!,
          sampleRate: 16000,
        );
        print('✅ Recognizer created');
      } catch (e, stackTrace) {
        print('❌ Lỗi tạo recognizer: $e');
        print('Stack trace: $stackTrace');
        throw Exception('Không thể tạo recognizer');
      }

      // ========================================
      // TẠO SPEECHSERVICE 1 LẦN DUY NHẤT
      // ========================================
      try {
        _speechService = await _vosk.initSpeechService(_recognizer!);
        print('✅ SpeechService created (sẽ reuse mãi mãi)');
      } catch (e, stackTrace) {
        print('❌ Lỗi tạo speech service: $e');
        print('Stack trace: $stackTrace');
        throw Exception('Không thể khởi tạo speech service');
      }

      _isInitialized = true;
      print('✅ VOSK khởi tạo thành công hoàn toàn');
      return true;
    } catch (e, stackTrace) {
      print('❌ Lỗi init VOSK: $e');
      print('Stack trace: $stackTrace');

      // Cleanup nếu init fail
      _model = null;
      _recognizer = null;
      _speechService = null;
      _isInitialized = false;

      return false;
    }
  }

  // ========================================
  // CHECK PERMISSION
  // ========================================
  Future<bool> checkPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  // ========================================
  // LISTEN (REUSE SPEECHSERVICE)
  // ========================================
  Future<String?> listen({
    Function(String text)? onResult,
    int listenSeconds = 0,
  }) async {
    // Init nếu chưa
    if (!_isInitialized) {
      final success = await initialize();
      if (!success) return null;
    }

    // Check permission
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      print('❌ Không có quyền mic');
      return null;
    }

    // Prevent concurrent listen
    if (_isListening) {
      print('⚠️ Đang nghe rồi, bỏ qua');
      return null;
    }

    try {
      _lastTranscript = '';
      _resultCompleter = Completer<String?>();
      _isListening = true;

      print('🎤 Bắt đầu nghe...');

      // ========================================
      // SETUP LISTENERS (mỗi lần nghe)
      // ========================================
      _partialSubscription = _speechService!.onPartial().listen((partial) {
        if (partial.isNotEmpty) {
          try {
            final decoded = jsonDecode(partial);
            final text = decoded['partial'] as String? ?? '';
            if (text.isNotEmpty) {
              print('📝 Partial: "$text"');
              onResult?.call(text);
              _lastTranscript = text;
            }
          } catch (e) {
            onResult?.call(partial);
            _lastTranscript = partial;
          }
        }
      });

      _resultSubscription = _speechService!.onResult().listen((result) {
        if (result.isNotEmpty) {
          try {
            final decoded = jsonDecode(result);
            final text = decoded['text'] as String? ?? '';
            if (text.isNotEmpty) {
              print('✅ Final: "$text"');
              _lastTranscript = text;
              onResult?.call(text);
            }
          } catch (e) {
            _lastTranscript = result;
            onResult?.call(result);
          }
        }
      });

      // ========================================
      // START (REUSE SPEECHSERVICE)
      // ========================================
      await _speechService!.start();
      print('✅ Đã start (reuse service)');

      // Auto stop
      if (listenSeconds > 0) {
        Future.delayed(Duration(seconds: listenSeconds), () async {
          await stopListening();
        });
      }

      // Wait result
      final result = await _resultCompleter!.future;
      print('🎯 Kết quả: "${result ?? '(trống)'}"');
      return result;
    } catch (e) {
      print('❌ Lỗi listen: $e');
      await _cleanup();
      return null;
    }
  }

  // ========================================
  // STOP LISTENING
  // ========================================
  Future<void> stopListening() async {
    if (!_isListening) {
      print('⚠️ Không trong trạng thái listening');
      return;
    }

    try {
      print('⏹️ Đang dừng...');

      // ========================================
      // STOP (KHÔNG DISPOSE SPEECHSERVICE!)
      // ========================================
      await _speechService?.stop();
      print('✅ Đã stop (service vẫn còn, chỉ dừng record)');

      // ========================================
      // DELAY để VOSK xử lý hết buffer
      // ========================================
      // VOSK cần thời gian để xử lý các audio frames cuối cùng
      // và trả về final result hoàn chỉnh
      print('⏳ Đợi VOSK xử lý buffer cuối (300ms)...');
      await Future.delayed(const Duration(milliseconds: 300));

      await _cleanup();

      // Complete result
      if (_resultCompleter != null && !_resultCompleter!.isCompleted) {
        _resultCompleter!.complete(
          _lastTranscript.isNotEmpty ? _lastTranscript : null,
        );
      }
    } catch (e) {
      print('❌ Lỗi stop: $e');
      await _cleanup();
      if (_resultCompleter != null && !_resultCompleter!.isCompleted) {
        _resultCompleter!.complete(null);
      }
    }
  }

  // ========================================
  // CLEANUP LISTENERS (KHÔNG DISPOSE SERVICE!)
  // ========================================
  Future<void> _cleanup() async {
    // Cancel subscriptions IN PARALLEL for faster cleanup
    await Future.wait([
      _partialSubscription?.cancel() ?? Future.value(),
      _resultSubscription?.cancel() ?? Future.value(),
    ]);

    _partialSubscription = null;
    _resultSubscription = null;

    _isListening = false;
    print('🧹 Cleaned listeners (parallel)');
  }

  // ========================================
  // DISPOSE (CHỈ KHI APP THOÁT)
  // ========================================
  Future<void> dispose() async {
    print('🗑️ Disposing service...');

    await _cleanup();

    // Stop service
    if (_speechService != null) {
      await _speechService!.stop();
      _speechService = null;
    }

    _recognizer = null;
    _model = null;
    _isInitialized = false;

    print('🗑️ Disposed');
  }
}
