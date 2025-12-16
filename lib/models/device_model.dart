class DeviceModel {
  final String deviceId;
  final String name;
  final String claimCode;
  final bool claimed;
  final String? roomName;
  final String ownerId;
  final int createdAt;
  final int lastModified;
  
  // IR Config
  final String irMethod;
  final String? brandId;
  final String? brandName;
  
  // Status
  final bool online;
  final int? lastSeen;

  DeviceModel({
    required this.deviceId,
    required this.name,
    required this.claimCode,
    this.claimed = false,
    this.roomName,
    required this.ownerId,
    required this.createdAt,
    required this.lastModified,
    this.irMethod = '',
    this.brandId,
    this.brandName,
    this.online = false,
    this.lastSeen,
  });

  factory DeviceModel.fromJson(String deviceId, Map<String, dynamic> json) {
    final info = json['info'] != null ? Map<String, dynamic>.from(json['info']) : {};
    final ir = json['ir'] != null ? Map<String, dynamic>.from(json['ir']) : {};
    
    return DeviceModel(
      deviceId: deviceId,
      name: info['deviceName'] ?? 'AC Device',
      claimCode: info['claimCode'] ?? '',
      claimed: info['claimed'] ?? false,
      roomName: info['roomName'],
      ownerId: info['ownerId'] ?? '',
      createdAt: info['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      lastModified: info['lastModified'] ?? DateTime.now().millisecondsSinceEpoch,
      irMethod: ir['method'] ?? '',
      brandId: ir['library'] != null ? ir['library']['brandId'] : null,
      brandName: ir['library'] != null ? ir['library']['brandName'] : null,
      online: info['online'] ?? false,
      lastSeen: info['lastSeen'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'info': {
        'deviceId': deviceId,
        'deviceName': name,
        'claimCode': claimCode,
        'claimed': claimed,
        'ownerId': ownerId,
        'roomName': roomName,
        'createdAt': createdAt,
        'lastModified': lastModified,
        'published': true,
      },
      'ir': {
        'method': irMethod,
        if (brandId != null) 'library': {
          'brandId': brandId,
          'brandName': brandName,
        },
      },
    };
  }
}