import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/ticket.dart';
import '../qr/payload.dart';

class TicketStore extends ChangeNotifier {
  TicketStore(this._box);

  final Box<Map> _box;

  List<Ticket> get tickets {
    final list = _box.values.map(Ticket.fromMap).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  List<Ticket> get active => tickets
      .where((t) => t.status == TicketStatus.active && !t.isExpired)
      .toList();

  List<Ticket> get redeemed => tickets
      .where((t) => t.status == TicketStatus.redeemed && !t.isExpired)
      .toList();

  List<Ticket> get expired => tickets.where((t) => t.isExpired).toList();

  /// Tickets I hold and can claim.
  List<Ticket> get owedToMe => active
      .where((t) => t.role == TicketRole.holder)
      .toList();

  /// Tickets I created and owe to someone.
  List<Ticket> get iOwe => active
      .where((t) => t.role == TicketRole.giver)
      .toList();

  /// Redeemed or expired tickets.
  List<Ticket> get history => tickets
      .where((t) => t.status == TicketStatus.redeemed || t.isExpired)
      .toList();

  Ticket? byId(String id) {
    final map = _box.get(id);
    return map == null ? null : Ticket.fromMap(map);
  }

  Future<Ticket> create({
    required String title,
    String? note,
    required String giverName,
    DateTime? expiresAt,
    String? giverPubKey,
  }) async {
    final trimmedNote = note?.trim();
    final ticket = Ticket.create(
      title: title.trim(),
      note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
      giverName: giverName,
      expiresAt: expiresAt,
      giverPubKey: giverPubKey,
    );
    await _box.put(ticket.id, ticket.toMap());
    notifyListeners();
    return ticket;
  }

  /// Records who this ticket is intended for (chosen after creation, before
  /// the gift QR is shown).
  Future<Ticket?> attachRecipient(
    String id, {
    required String recipientName,
    required String recipientPubKey,
  }) async {
    final ticket = byId(id);
    if (ticket == null) return null;
    final updated = ticket.copyWith(
      recipientName: recipientName,
      recipientPubKey: recipientPubKey,
    );
    await _box.put(id, updated.toMap());
    notifyListeners();
    return updated;
  }

  Future<Ticket> importGift(
    String payload, {
    String? holderName,
    String? holderPubKey,
  }) async {
    final ticket = await decodeAnyGift(payload);
    if (_box.containsKey(ticket.id)) {
      throw const FormatException('You already have this ticket.');
    }
    final held = ticket.copyWith(
      role: TicketRole.holder,
      holderName: holderName,
      holderPubKey: holderPubKey,
    );
    await _box.put(held.id, held.toMap());
    notifyListeners();
    return held;
  }

  Future<void> redeem(String id) async {
    final ticket = byId(id);
    if (ticket == null) {
      throw const FormatException('This ticket is not on this device.');
    }
    await _box.put(id, ticket.copyWith(status: TicketStatus.redeemed).toMap());
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    notifyListeners();
  }
}
