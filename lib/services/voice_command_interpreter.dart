/// ========================================
/// VOICE COMMAND INTERPRETER
/// ========================================
///
/// Service xử lý và phân tích lệnh giọng nói từ VOSK
/// - Bỏ dấu tiếng Việt
/// - Fuzzy matching với Levenshtein distance
/// - Trích xuất tham số (số độ, phút/giờ)
/// - Hỗ trợ tiếng Việt với sai sót phát âm
library;

import 'dart:math';

/// Kết quả phân tích lệnh giọng nói
class VoiceCommandResult {
  /// Loại lệnh
  final InterpretedCommandType type;

  /// Text gốc từ VOSK
  final String rawText;

  /// Text đã chuẩn hóa (bỏ dấu, lowercase)
  final String cleanedText;

  /// Lệnh được match (nếu có)
  final String? matchedCommand;

  /// Độ tương đồng (0.0 - 1.0)
  final double similarity;

  /// Tham số: số độ tăng/giảm nhiệt độ
  final int? temperatureStep;

  /// Tham số: số phút hẹn giờ tắt
  final int? timerMinutes;

  const VoiceCommandResult({
    required this.type,
    required this.rawText,
    required this.cleanedText,
    this.matchedCommand,
    this.similarity = 0.0,
    this.temperatureStep,
    this.timerMinutes,
  });

  @override
  String toString() {
    return 'VoiceCommandResult(type: $type, matched: "$matchedCommand", similarity: ${similarity.toStringAsFixed(2)}, params: temp=$temperatureStep, timer=$timerMinutes)';
  }
}

/// Loại lệnh giọng nói (từ interpreter)
enum InterpretedCommandType {
  powerOn,      // Bật máy lạnh
  powerOff,     // Tắt máy lạnh
  tempUp,       // Tăng nhiệt độ
  tempDown,     // Giảm nhiệt độ
  timerOff,     // Hẹn giờ tắt
  unknown,      // Không nhận dạng được
}

/// Service phân tích lệnh giọng nói
class VoiceCommandInterpreter {
  /// Ngưỡng similarity tối thiểu để chấp nhận (0.7 = 70% giống)
  static const double similarityThreshold = 0.7;

  /// Từ khóa quan trọng cần giữ lại
  static const List<String> _keywords = [
    'bat', 'tat', 'tac', 'mo', 'dong',  
    'tang', 'giam', 'len', 'xuong',
    'nhiet', 'do', 'doc',
    'may', 'lanh', 'dieu', 'hoa',
    'tu', 'dong', 'hen', 'gio',
    'sau', 'phut', 'tieng', 'gio',
    '1', '2', '3', '4', '5', '10', '15', '20', '30', '60',
  ];

  /// Dictionary các câu lệnh chuẩn cho từng loại
  static final Map<InterpretedCommandType, List<String>> _commandTemplates = {
    InterpretedCommandType.powerOn: [
      'bat',
      'bat may',
      'bat may lanh',
      'mo may lanh',
      'bat dieu hoa',
      'mo dieu hoa',
      'khoi dong',
      'khoi dong may lanh',
    ],
    InterpretedCommandType.powerOff: [
      'tat',
      'tat may',
      'tat may lanh',
      'tat dieu hoa',
      'dong may lanh',
      'tat may lanh di',
      'tat dieu hoa di',
      'tat di',
    ],
    InterpretedCommandType.tempUp: [
      'tang',
      'tang nhiet do',
      'tang nhiet do len',
      'tang do',
      'tang len',
    ],
    InterpretedCommandType.tempDown: [
      'giam',
      'giam nhiet do',
      'giam nhiet do xuong',
      'giam do',
      'giam xuong',
    ],
    InterpretedCommandType.timerOff: [
      'tu dong tat',
      'tu dong tac', 
      'hen gio tat',
      'tat sau',
      'tu dong tat sau',
      'hen tat',
      'tu dong',
    ],
  };

  // ========================================
  // PUBLIC API
  // ========================================

  /// Phân tích lệnh giọng nói từ raw text
  static VoiceCommandResult interpret(String rawText) {
    print('\n========================================');
    print('🧠 VOICE COMMAND INTERPRETER');
    print('📥 Raw text: "$rawText"');

    // Bước 1: Chuẩn hóa text
    final cleaned = _cleanText(rawText);
    print('✨ Cleaned: "$cleaned"');

    // Bước 2: Lọc từ khóa quan trọng
    final filtered = _filterKeywords(cleaned);
    print('🔍 Filtered: "$filtered"');

    // Bước 3: Fuzzy matching với từng loại lệnh
    InterpretedCommandType? bestType;
    String? bestCommand;
    double bestSimilarity = 0.0;

    for (final entry in _commandTemplates.entries) {
      final type = entry.key;
      final templates = entry.value;

      for (final template in templates) {
        final similarity = _calculateSimilarity(filtered, template);

        if (similarity > bestSimilarity) {
          bestSimilarity = similarity;
          bestType = type;
          bestCommand = template;
        }
      }
    }

    print('🎯 Best match: "$bestCommand" (${(bestSimilarity * 100).toStringAsFixed(1)}% similar)');

    // Bước 4: Kiểm tra ngưỡng
    if (bestSimilarity < similarityThreshold) {
      print('❌ Similarity too low (< ${similarityThreshold * 100}%), marking as unknown');
      return VoiceCommandResult(
        type: InterpretedCommandType.unknown,
        rawText: rawText,
        cleanedText: cleaned,
        matchedCommand: null,
        similarity: bestSimilarity,
      );
    }

    // Bước 5: Trích xuất tham số
    int? tempStep;
    int? timerMinutes;

    if (bestType == InterpretedCommandType.tempUp || bestType == InterpretedCommandType.tempDown) {
      tempStep = _extractTemperatureStep(cleaned);
      print('🌡️ Temperature step: $tempStep');
    }

    if (bestType == InterpretedCommandType.timerOff) {
      timerMinutes = _extractTimerMinutes(cleaned);
      print('⏰ Timer minutes: $timerMinutes');
    }

    print('✅ Recognized: ${bestType.toString()}');
    print('========================================\n');

    return VoiceCommandResult(
      type: bestType!,
      rawText: rawText,
      cleanedText: cleaned,
      matchedCommand: bestCommand,
      similarity: bestSimilarity,
      temperatureStep: tempStep,
      timerMinutes: timerMinutes,
    );
  }

  // ========================================
  // TEXT PROCESSING
  // ========================================

  /// Chuẩn hóa text: lowercase, bỏ dấu, bỏ ký tự đặc biệt
  static String _cleanText(String text) {
    if (text.isEmpty) return '';

    // 1. Lowercase
    String result = text.toLowerCase().trim();

    // 2. Bỏ dấu tiếng Việt
    result = _removeDiacritics(result);

    // 3. Bỏ ký tự đặc biệt, chỉ giữ chữ cái (a-z), số (0-9), khoảng trắng
    // Dùng regex an toàn: chỉ giữ a-z, 0-9, và space
    result = result.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

    // 4. Chuẩn hóa khoảng trắng
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

    return result;
  }

  /// Bỏ dấu tiếng Việt
  static String _removeDiacritics(String text) {
    if (text.isEmpty) return '';

    // Map an toàn: tất cả ký tự có dấu → không dấu
    const diacriticMap = {
      // Lowercase
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd',
      // Uppercase (nếu có)
      'À': 'a', 'Á': 'a', 'Ả': 'a', 'Ã': 'a', 'Ạ': 'a',
      'Ă': 'a', 'Ằ': 'a', 'Ắ': 'a', 'Ẳ': 'a', 'Ẵ': 'a', 'Ặ': 'a',
      'Â': 'a', 'Ầ': 'a', 'Ấ': 'a', 'Ẩ': 'a', 'Ẫ': 'a', 'Ậ': 'a',
      'È': 'e', 'É': 'e', 'Ẻ': 'e', 'Ẽ': 'e', 'Ẹ': 'e',
      'Ê': 'e', 'Ề': 'e', 'Ế': 'e', 'Ể': 'e', 'Ễ': 'e', 'Ệ': 'e',
      'Ì': 'i', 'Í': 'i', 'Ỉ': 'i', 'Ĩ': 'i', 'Ị': 'i',
      'Ò': 'o', 'Ó': 'o', 'Ỏ': 'o', 'Õ': 'o', 'Ọ': 'o',
      'Ô': 'o', 'Ồ': 'o', 'Ố': 'o', 'Ổ': 'o', 'Ỗ': 'o', 'Ộ': 'o',
      'Ơ': 'o', 'Ờ': 'o', 'Ớ': 'o', 'Ở': 'o', 'Ỡ': 'o', 'Ợ': 'o',
      'Ù': 'u', 'Ú': 'u', 'Ủ': 'u', 'Ũ': 'u', 'Ụ': 'u',
      'Ư': 'u', 'Ừ': 'u', 'Ứ': 'u', 'Ử': 'u', 'Ữ': 'u', 'Ự': 'u',
      'Ỳ': 'y', 'Ý': 'y', 'Ỷ': 'y', 'Ỹ': 'y', 'Ỵ': 'y',
      'Đ': 'd',
    };

    String result = text;

    // Thay thế từng ký tự một cách an toàn
    for (final entry in diacriticMap.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }

    return result;
  }

  /// Lọc chỉ giữ từ khóa quan trọng
  static String _filterKeywords(String text) {
    final words = text.split(' ');
    final filtered = words.where((word) {
      if (word.isEmpty) return false;

      // Giữ số
      if (RegExp(r'^\d+$').hasMatch(word)) return true;

      // Giữ từ khóa
      for (final keyword in _keywords) {
        if (word.contains(keyword) || keyword.contains(word)) {
          return true;
        }
      }

      return false;
    }).toList();

    return filtered.join(' ');
  }

  // ========================================
  // FUZZY MATCHING
  // ========================================

  /// Tính độ tương đồng giữa 2 chuỗi (0.0 - 1.0)
  /// Sử dụng Levenshtein distance
  static double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty && s2.isEmpty) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final distance = _levenshteinDistance(s1, s2);
    final maxLen = max(s1.length, s2.length);
    final similarity = 1.0 - (distance / maxLen);

    return similarity.clamp(0.0, 1.0);
  }

  /// Tính Levenshtein distance (edit distance)
  static int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final len1 = s1.length;
    final len2 = s2.length;

    // Tạo ma trận dynamic programming
    final matrix = List.generate(
      len1 + 1,
      (i) => List.filled(len2 + 1, 0),
    );

    // Khởi tạo hàng/cột đầu
    for (int i = 0; i <= len1; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      matrix[0][j] = j;
    }

    // Tính distance
    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;

        matrix[i][j] = min(
          min(
            matrix[i - 1][j] + 1,      // deletion
            matrix[i][j - 1] + 1,      // insertion
          ),
          matrix[i - 1][j - 1] + cost, // substitution
        );
      }
    }

    return matrix[len1][len2];
  }

  // ========================================
  // PARAMETER EXTRACTION
  // ========================================

  /// Trích xuất số độ tăng/giảm nhiệt độ
  static int _extractTemperatureStep(String text) {
    // Tìm số trong text
    final numbers = _extractNumbers(text);

    // Nếu có số và nằm trong khoảng hợp lý (1-5 độ)
    for (final num in numbers) {
      if (num >= 1 && num <= 5) {
        return num;
      }
    }

    // Mặc định: 1 độ
    return 1;
  }

  /// Trích xuất số phút hẹn giờ tắt
  static int _extractTimerMinutes(String text) {
    final numbers = _extractNumbers(text);

    // Kiểm tra từ khóa "tiếng" hoặc "giờ"
    final hasHourKeyword = text.contains('tieng') || text.contains('gio');

    // Nếu có từ khóa "giờ" → nhân 10
    if (hasHourKeyword && numbers.isNotEmpty) {
      final hours = numbers.first;
      if (hours >= 1 && hours <= 3) {
        return hours * 10;
      }
    }

    // Kiểm tra từ khóa "phút"
    final hasMinuteKeyword = text.contains('phut');

    if (hasMinuteKeyword && numbers.isNotEmpty) {
      final minutes = numbers.first;
      if (minutes >= 1 && minutes <= 120) {
        return minutes;
      }
    }

    // Nếu chỉ có số không có đơn vị, giả sử là phút
    if (numbers.isNotEmpty) {
      final value = numbers.first;
      // Nếu số nhỏ (1-5) → có thể là giờ
      if (value >= 1 && value <= 5) {
        return value * 60; // Giả sử giờ
      }
      // Nếu số lớn (10-120) → chắc là phút
      if (value >= 10 && value <= 120) {
        return value;
      }
    }

    // Mặc định: 30 phút
    return 30;
  }

  /// Trích xuất tất cả số trong text
  static List<int> _extractNumbers(String text) {
    final numbers = <int>[];

    // Tìm số viết (1, 2, 3, ...)
    final digitMatches = RegExp(r'\d+').allMatches(text);
    for (final match in digitMatches) {
      final num = int.tryParse(match.group(0)!);
      if (num != null) {
        numbers.add(num);
      }
    }

    // Tìm số chữ (một, hai, ba, ...)
    const wordNumbers = {
      'mot': 1, 'một': 1,
      'hai': 2,
      'ba': 3,
      'bon': 4, 'bốn': 4,
      'nam': 5, 'năm': 5,
      'sau': 6, 'sáu': 6,
      'bay': 7, 'bảy': 7,
      'tam': 8, 'tám': 8,
      'chin': 9, 'chín': 9,
      'muoi': 10, 'mười': 10,
      'muoi lam': 15, 'mười lăm': 15,
      'hai muoi': 20, 'hai mươi': 20,
      'ba muoi': 30, 'ba mươi': 30,
      'bon muoi': 40, 'bốn mươi': 40,
      'nam muoi': 50, 'năm mươi': 50,
      'sau muoi': 60, 'sáu mươi': 60,
    };

    for (final entry in wordNumbers.entries) {
      if (text.contains(entry.key)) {
        numbers.add(entry.value);
      }
    }

    return numbers;
  }
}
