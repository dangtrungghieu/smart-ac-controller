import '../utils/sensor_calibration.dart';

class RoomStatusModel {
  final double temperature;
  final double humidity;
  final bool hasPerson;
  final DateTime lastUpdate;

  RoomStatusModel({
    required this.temperature,
    required this.humidity,
    required this.hasPerson,
    required this.lastUpdate,
  });

  factory RoomStatusModel.fromJson(Map<String, dynamic> json) {
    // Lấy giá trị thô từ cảm biến
    final double rawTemp = (json['temp'] ?? 0).toDouble();
    final double rawHumidity = (json['humidity'] ?? 0).toDouble();

    // Áp dụng hiệu chỉnh cho cảm biến DHT22
    final double? calibratedTemp = SensorCalibration.calibrateTemperature(rawTemp);
    final double? calibratedHumidity = SensorCalibration.calibrateHumidity(rawHumidity);

    return RoomStatusModel(
      temperature: calibratedTemp ?? 0.0,
      humidity: calibratedHumidity ?? 0.0,
      hasPerson: json['hasPerson'] ?? false,
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(json['lastUpdate'] ?? DateTime.now().millisecondsSinceEpoch),
    );
  }
}

class ACStatusModel {
  final bool powerOn;
  final int setTemp;
  final double current;
  final double power;
  final DateTime lastUpdate;

  ACStatusModel({
    required this.powerOn,
    required this.setTemp,
    required this.current,
    required this.power,
    required this.lastUpdate,
  });

  factory ACStatusModel.fromJson(Map<String, dynamic> json) {
    return ACStatusModel(
      powerOn: json['powerOn'] ?? false,
      setTemp: json['setTemp'] ?? 24,
      current: (json['current'] ?? 0).toDouble(),
      power: (json['power'] ?? 0).toDouble(),
      lastUpdate: DateTime.fromMillisecondsSinceEpoch(json['lastUpdate'] ?? DateTime.now().millisecondsSinceEpoch),
    );
  }
}