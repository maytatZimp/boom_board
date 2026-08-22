class SpectatorModel {
  final String id;
  final String name;

  SpectatorModel({required this.id, required this.name});

  static SpectatorModel fromJson(Map<String, dynamic> json) {
    return SpectatorModel(
      id: json['id'],
      name: json['name'],
    );
  }

  static List<SpectatorModel> listFromJson(dynamic json) {
    if (json is! List) return [];
    return json.map((e) => SpectatorModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}
