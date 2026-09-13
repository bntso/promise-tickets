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

  Ticket? byId(String id) {
    final map = _box.get(id);
    return map == null ? null : Ticket.fromMap(map);
  }

  Future<Ticket> create({
    required String title,
    String? note,
    required String giverName,
    DateTime? expiresAt,
  }) async {
    final trimmedNote = note?.trim();
    final ticket = Ticket.create(
      title: title.trim(),
      note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
      giverName: giverName,
      expiresAt: expiresAt,
    );
    await _box.put(ticket.id, ticket.toMap());
    notifyListeners();
    return ticket;
  }

  Future<Ticket> importGift(String payload) async {
    final ticket = decodeGift(payload);
    if (_box.containsKey(ticket.id)) {
      throw const FormatException('You already have this ticket.');
    }
    final held = ticket.copyWith(role: TicketRole.holder);
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
