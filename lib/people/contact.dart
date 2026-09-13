/// How a contact's key was obtained. Scanned keys were verified in person;
/// directory keys come from the (untrusted) server.
enum ContactSource { scanned, directory }

class Contact {
  Contact({
    required this.name,
    required this.publicKeyHex,
    required this.addedAt,
    this.source = ContactSource.scanned,
    this.username,
    this.serverUid,
  });

  factory Contact.fromMap(Map<dynamic, dynamic> map) {
    return Contact(
      name: map['name'] as String,
      publicKeyHex: map['publicKey'] as String,
      addedAt: DateTime.parse(map['addedAt'] as String),
      source: map['source'] is String
          ? ContactSource.values.byName(map['source'] as String)
          : ContactSource.scanned,
      username: map['username'] as String?,
      serverUid: map['serverUid'] as String?,
    );
  }

  final String name;
  final String publicKeyHex;
  final DateTime addedAt;
  final ContactSource source;

  /// Server directory username and uid, when the contact was added from the
  /// directory (needed to send them remote gifts).
  final String? username;
  final String? serverUid;

  /// Can receive a server-sent gift right now.
  bool get canReceiveRemote => username != null && serverUid != null;

  Contact copyWith({
    String? name,
    ContactSource? source,
    String? username,
    String? serverUid,
  }) {
    return Contact(
      name: name ?? this.name,
      publicKeyHex: publicKeyHex,
      addedAt: addedAt,
      source: source ?? this.source,
      username: username ?? this.username,
      serverUid: serverUid ?? this.serverUid,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'publicKey': publicKeyHex,
      'addedAt': addedAt.toIso8601String(),
      'source': source.name,
      'username': username,
      'serverUid': serverUid,
    };
  }
}
