class UsuarioModel {
  String usuarioId;
  double trevnot;

  UsuarioModel({
    required this.usuarioId,
    required this.trevnot,
  });

  factory UsuarioModel.fromJson(Map<String, dynamic> json) {
    return UsuarioModel(
      usuarioId: json['USUARIOID'],
      trevnot: (json['TREVNOT'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'USUARIOID': usuarioId,
      'TREVNOT': trevnot,
    };
  }
}
