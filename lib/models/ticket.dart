import 'dart:math';

import 'package:uuid/uuid.dart';

enum TicketRole { giver, holder }

enum TicketStatus { active, redeemed }

class Ticket {
  Ticket({
    required this.id,
    required this.title,
    this.note,
    required this.giverName,
    required this.createdAt,
    required this.expiresAt,
    this.status = TicketStatus.active,
    required this.nonce,
    this.role = TicketRole.giver,
    this.giverPubKey,
    this.holderName,
    this.holderPubKey,
    this.recipientName,
    this.recipientPubKey,
    this.signature,
  });

  factory Ticket.create({
    required String title,
    String? note,
    required String giverName,
    DateTime? now,
    DateTime? expiresAt,
    TicketRole role = TicketRole.giver,
    String? giverPubKey,
    String? recipientName,
    String? recipientPubKey,
  }) {
    final created = now ?? DateTime.now();
    return Ticket(
      id: const Uuid().v4(),
      title: title,
      note: note,
      giverName: giverName,
      createdAt: created,
      expiresAt: expiresAt ??
          DateTime(created.year + 1, created.month, created.day),
      nonce: _randomNonce(),
      role: role,
      giverPubKey: giverPubKey,
      recipientName: recipientName,
      recipientPubKey: recipientPubKey,
    );
  }

  factory Ticket.fromMap(Map<dynamic, dynamic> map) {
    return Ticket(
      id: map['id'] as String,
      title: map['title'] as String,
      note: map['note'] as String?,
      giverName: map['giverName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      expiresAt: DateTime.parse(map['expiresAt'] as String),
      status: TicketStatus.values.byName(map['status'] as String? ?? 'active'),
      nonce: map['nonce'] as String,
      role: TicketRole.values.byName(map['role'] as String? ?? 'giver'),
      giverPubKey: map['giverPubKey'] as String?,
      holderName: map['holderName'] as String?,
      holderPubKey: map['holderPubKey'] as String?,
      recipientName: map['recipientName'] as String?,
      recipientPubKey: map['recipientPubKey'] as String?,
      signature: map['signature'] as String?,
    );
  }

  final String id;
  final String title;
  final String? note;
  final String giverName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final TicketStatus status;
  final String nonce;
  final TicketRole role;

  /// Public key (hex) of the giver, when the gift was signed (PT2).
  final String? giverPubKey;

  /// Who holds the ticket (set on the holder's copy at import time).
  final String? holderName;
  final String? holderPubKey;

  /// Intended recipient chosen by the giver before gifting, if any.
  final String? recipientName;
  final String? recipientPubKey;

  /// Ed25519 signature (hex) from the giver over the gift payload; null for
  /// legacy PT1-era tickets.
  final String? signature;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Signed and attributed to a key — whether that key is a known contact is
  /// decided by the ContactStore, not here.
  bool get isSigned => signature != null && giverPubKey != null;

  Ticket copyWith({
    TicketStatus? status,
    TicketRole? role,
    String? holderName,
    String? holderPubKey,
    String? recipientName,
    String? recipientPubKey,
  }) {
    return Ticket(
      id: id,
      title: title,
      note: note,
      giverName: giverName,
      createdAt: createdAt,
      expiresAt: expiresAt,
      status: status ?? this.status,
      nonce: nonce,
      role: role ?? this.role,
      giverPubKey: giverPubKey,
      holderName: holderName ?? this.holderName,
      holderPubKey: holderPubKey ?? this.holderPubKey,
      recipientName: recipientName ?? this.recipientName,
      recipientPubKey: recipientPubKey ?? this.recipientPubKey,
      signature: signature,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'note': note,
      'giverName': giverName,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'status': status.name,
      'nonce': nonce,
      'role': role.name,
      'giverPubKey': giverPubKey,
      'holderName': holderName,
      'holderPubKey': holderPubKey,
      'recipientName': recipientName,
      'recipientPubKey': recipientPubKey,
      'signature': signature,
    };
  }

  static String _randomNonce() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
