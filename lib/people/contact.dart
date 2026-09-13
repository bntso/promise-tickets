class Contact {
  Contact({
    required this.name,
    required this.publicKeyHex,
    required this.addedAt,
  });

  factory Contact.fromMap(Map<dynamic, dynamic> map) {
    return Contact(
      name: map['name'] as String,
      publicKeyHex: map['publicKey'] as String,
      addedAt: DateTime.parse(map['addedAt'] as String),
    );
  }

  final String name;
  final String publicKeyHex;
  final DateTime addedAt;

  Contact copyWith({String? name}) {
    return Contact(
      name: name ?? this.name,
      publicKeyHex: publicKeyHex,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'publicKey': publicKeyHex,
      'addedAt': addedAt.toIso8601String(),
    };
  }
}
