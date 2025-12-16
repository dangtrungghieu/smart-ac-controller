/// ========================================
/// ULTRA SIMPLE VOICE PARSER - V3
/// ========================================
///
/// Wrapper around VoiceCommandInterpreter
/// Sử dụng fuzzy matching với Levenshtein distance
/// Hỗ trợ tiếng Việt với sai sót phát âm
///
/// LỆNH HỖ TRỢ:
/// 1. ON (bật máy lạnh)
/// 2. OFF (tắt máy lạnh)
/// 3. TĂNG N độ (tăng nhiệt độ)
/// 4. GIẢM N độ (giảm nhiệt độ)
/// 5. HẸN GIỜ TẮT (tự động tắt sau X phút/giờ)
library;

import '../models/voice_command_model.dart';
import 'voice_command_interpreter.dart';

class UltraSimpleParser {
  /// Parse lệnh từ VOSK
  ///
  /// Sử dụng VoiceCommandInterpreter với fuzzy matching
  /// để xử lý lỗi phát âm và sai sót từ VOSK
  static VoiceCommand parseCommand(String rawText) {
    // Sử dụng VoiceCommandInterpreter để phân tích
    final result = VoiceCommandInterpreter.interpret(rawText);

    // Chuyển đổi VoiceCommandResult → VoiceCommand
    return _convertToVoiceCommand(result);
  }

  /// Chuyển đổi VoiceCommandResult → VoiceCommand
  static VoiceCommand _convertToVoiceCommand(VoiceCommandResult result) {
    switch (result.type) {
      case InterpretedCommandType.powerOn:
        print('✅ → BẬT MÁY LẠNH');
        return VoiceCommand.power(
          text: result.rawText,
          action: PowerAction.turnOn,
        );

      case InterpretedCommandType.powerOff:
        print('✅ → TẮT MÁY LẠNH');
        return VoiceCommand.power(
          text: result.rawText,
          action: PowerAction.turnOff,
        );

      case InterpretedCommandType.tempUp:
        final step = result.temperatureStep ?? 1;
        print('✅ → TĂNG $step độ');
        return VoiceCommand.temperature(
          text: result.rawText,
          action: TemperatureAction.increase,
          step: step,
        );

      case InterpretedCommandType.tempDown:
        final step = result.temperatureStep ?? 1;
        print('✅ → GIẢM $step độ');
        return VoiceCommand.temperature(
          text: result.rawText,
          action: TemperatureAction.decrease,
          step: step,
        );

      case InterpretedCommandType.timerOff:
        final minutes = result.timerMinutes ?? 30;
        print('✅ → HẸN GIỜ TẮT sau $minutes phút');
        return VoiceCommand.autoOff(
          text: result.rawText,
          action: AutoOffAction.enable,
          minutes: minutes,
          warning: minutes > 60,
        );

      case InterpretedCommandType.unknown:
        print('❌ → KHÔNG HIỂU LỆNH');
        return VoiceCommand.unknown(
          result.rawText,
          error: _getErrorMessage(result),
        );
    }
  }

  /// Tạo error message chi tiết
  static String _getErrorMessage(VoiceCommandResult result) {
    final similarity = (result.similarity * 100).toStringAsFixed(0);

    String message = 'Không hiểu lệnh: "${result.rawText}"';

    if (result.matchedCommand != null) {
      message += '\n\nGần giống: "${result.matchedCommand}" ($similarity% giống)';
      message += '\nNhưng độ chính xác quá thấp (< 70%)';
    }

    message += '\n\nVui lòng thử:';
    message += '\n• "bật" / "tắt"';
    message += '\n• "tăng 2" / "giảm 3"';
    message += '\n• "tự động tắt sau 30 phút"';

    return message;
  }
}
