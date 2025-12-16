class BrandModel {
  final String id;
  final String name;
  final String protocol;
  final String logo;

  BrandModel({
    required this.id,
    required this.name,
    required this.protocol,
    required this.logo,
  });

  factory BrandModel.fromJson(String id, Map<String, dynamic> json) {
    return BrandModel(
      id: id,
      name: json['name'] ?? '',
      protocol: json['protocol'] ?? '',
      logo: json['logo'] ?? '',
    );
  }
}