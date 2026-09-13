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
  });

  factory Ticket.create({
    required String title,
    String? note,
    required String giverName,
    DateTime? now,
    DateTime? expiresAt,
    TicketRole role = TicketRole.giver,
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
      status: TicketStatus.values.byName(map['status'] as String),
      nonce: map['nonce'] as String,
      role: TicketRole.values.byName(map['role'] as String),
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

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Ticket copyWith({
    TicketStatus? status,
    TicketRole? role,
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
    };
  }

  static String _randomNonce() {
    final rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
