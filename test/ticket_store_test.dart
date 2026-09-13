import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';
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

  group('v2', () {
    test('directional getters split by role and status', () async {
      final store = await newStore();
      final identity = await Identity.load(MemoryKeyStore(), name: 'Me');

      // Giver copy → "I owe".
      final mine = await store.create(
        title: 'My promise',
        giverName: 'Me',
        giverPubKey: identity.publicKeyHex,
      );
      // Imported holder copy → "Owed to me".
      final otherStore = await newStore();
      final theirs = await otherStore.create(title: 'Theirs', giverName: 'Ana');
      final held = await store.importGift(
        encodeGift(theirs),
        holderName: identity.name,
        holderPubKey: identity.publicKeyHex,
      );

      expect(store.iOwe.map((t) => t.id), [mine.id]);
      expect(store.owedToMe.map((t) => t.id), [held.id]);
      expect(store.history, isEmpty);

      await store.redeem(mine.id);
      expect(store.iOwe, isEmpty);
      expect(store.history.map((t) => t.id), [mine.id]);
    });

    test('import stamps the holder counterparty fields', () async {
      final holder = await Identity.load(MemoryKeyStore(), name: 'Ana');
      final giver = await Identity.load(MemoryKeyStore(), name: 'Ricardo');

      final giverStore = await newStore();
      final ticket = await giverStore.create(
        title: 'Walk the dog',
        giverName: giver.name,
        giverPubKey: giver.publicKeyHex,
      );
      final raw = await encodeGiftV2(ticket, giver);

      final holderStore = await newStore();
      final held = await holderStore.importGift(
        raw,
        holderName: holder.name,
        holderPubKey: holder.publicKeyHex,
      );

      expect(held.holderName, 'Ana');
      expect(held.holderPubKey, holder.publicKeyHex);
      expect(held.giverPubKey, giver.publicKeyHex);
      expect(held.isSigned, isTrue);
    });

    test('attachRecipient records who the gift is for', () async {
      final store = await newStore();
      final ticket = await store.create(title: 'T', giverName: 'Me');
      final updated = await store.attachRecipient(
        ticket.id,
        recipientName: 'Ana',
        recipientPubKey: 'ab' * 32,
      );

      expect(updated!.recipientName, 'Ana');
      expect(store.byId(ticket.id)!.recipientPubKey, 'ab' * 32);
    });

    test('migration: PT1-era tickets without new fields still load', () async {
      final box = await Hive.openBox<Map>('tickets_${boxCounter++}');
      // A map as written by v1: no giverPubKey/holder/signature fields.
      await box.put('old-1', {
        'id': 'old-1',
        'title': 'Old promise',
        'note': null,
        'giverName': 'Me',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'expiresAt': DateTime(2027, 1, 1).toIso8601String(),
        'status': 'active',
        'nonce': 'f' * 32,
        'role': 'giver',
      });

      final store = TicketStore(box);
      final loaded = store.byId('old-1');
      expect(loaded, isNotNull);
      expect(loaded!.isSigned, isFalse);
      expect(store.iOwe.single.id, 'old-1');
    });

    test('migration: identity is generated and seeded with the profile name',
        () async {
      final keyStore = MemoryKeyStore();
      final identity = await Identity.load(keyStore, name: 'Ricardo');
      expect(identity.name, 'Ricardo');
      expect(identity.publicKeyHex, hasLength(64));
      // Persisted: a second load reuses the same key.
      expect(
        (await Identity.load(keyStore, name: 'Ricardo')).publicKeyHex,
        identity.publicKeyHex,
      );
    });
  });
}
