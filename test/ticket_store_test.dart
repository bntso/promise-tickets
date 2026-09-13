import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/models/ticket.dart';
import 'package:promise_tickets/qr/payload.dart';
import 'package:promise_tickets/state/ticket_store.dart';

void main() {
  late Directory dir;
  var boxCounter = 0;

  Future<TicketStore> newStore() async {
    final box = await Hive.openBox<Map>('tickets_${boxCounter++}');
    return TicketStore(box);
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('promise_tickets_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('create stores a giver ticket with default 1-year expiry', () async {
    final store = await newStore();
    final ticket = await store.create(title: "I'll do the dishes", giverName: 'Me');

    expect(ticket.role, TicketRole.giver);
    expect(ticket.status, TicketStatus.active);
    expect(ticket.expiresAt.year, ticket.createdAt.year + 1);
    expect(store.active.map((t) => t.id), contains(ticket.id));
  });

  test('lifecycle: create → gift → import → redeem on both devices', () async {
    final giverStore = await newStore();
    final holderStore = await newStore();

    // Giver creates the ticket and shows the gift QR.
    final ticket = await giverStore.create(title: 'Walk the dog', giverName: 'Me');
    final giftRaw = encodeGift(ticket);

    // Holder scans and imports it.
    final held = await holderStore.importGift(giftRaw);
    expect(held.role, TicketRole.holder);
    expect(held.id, ticket.id);
    expect(holderStore.active.single.id, ticket.id);

    // Holder claims; giver scans the redeem QR and confirms.
    final redeemRaw = encodeRedeem(held, 'Alex');
    final payload = decodeRedeem(redeemRaw);
    final giverCopy = giverStore.byId(payload.id);
    expect(giverCopy, isNotNull);
    expect(giverCopy!.nonce, payload.nonce);
    await giverStore.redeem(payload.id);

    // Holder marks their own copy after the giver scanned it.
    await holderStore.redeem(held.id);

    expect(giverStore.byId(ticket.id)!.status, TicketStatus.redeemed);
    expect(holderStore.byId(held.id)!.status, TicketStatus.redeemed);
    expect(giverStore.active, isEmpty);
    expect(giverStore.redeemed.single.id, ticket.id);
    expect(holderStore.redeemed.single.id, held.id);
  });

  test('expired tickets leave the active tab and appear in expired', () async {
    final store = await newStore();
    final ticket = await store.create(
      title: 'Old promise',
      giverName: 'Me',
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );

    expect(store.active, isEmpty);
    expect(store.expired.single.id, ticket.id);
  });

  test('redeeming an unknown id throws', () async {
    final store = await newStore();
    expect(
      () => store.redeem('no-such-id'),
      throwsA(isA<FormatException>()),
    );
  });

  test('delete removes the ticket', () async {
    final store = await newStore();
    final ticket = await store.create(title: 'T', giverName: 'Me');
    await store.delete(ticket.id);
    expect(store.byId(ticket.id), isNull);
    expect(store.tickets, isEmpty);
  });
}
