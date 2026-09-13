import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';
import 'package:promise_tickets/models/ticket.dart';
import 'package:promise_tickets/qr/payload.dart';
import 'package:promise_tickets/server/server_service.dart';
import 'package:promise_tickets/server/server_sync.dart';
import 'package:promise_tickets/state/ticket_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  var boxCounter = 0;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('promise_tickets_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<Box> newSettings() => Hive.openBox<dynamic>('settings_${boxCounter++}');

  Future<TicketStore> newStore() async =>
      TicketStore(await Hive.openBox<Map>('tickets_${boxCounter++}'));

  ServerService newService(
    FakeFirebaseFirestore firestore,
    Box settings, {
    required String uid,
  }) {
    return ServerService(
      auth: MockFirebaseAuth(mockUser: MockUser(uid: uid), signedIn: true),
      firestore: firestore,
      settings: settings,
    );
  }

  Future<void> waitFor(bool Function() condition) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Timed out waiting for condition.');
  }

  group('registration', () {
    test('username claim transaction: the first claimant wins', () async {
      final firestore = FakeFirebaseFirestore();
      final alice = await Identity.load(MemoryKeyStore(), name: 'Alice');
      final bob = await Identity.load(MemoryKeyStore(), name: 'Bob');
      final serviceA = newService(firestore, await newSettings(), uid: 'uid-a');
      final serviceB = newService(firestore, await newSettings(), uid: 'uid-b');

      expect(await serviceA.isUsernameAvailable('ana'), isTrue);
      await serviceA.register('ana', alice);

      expect(serviceA.isRegistered, isTrue);
      expect(serviceA.username, 'ana');
      expect(await serviceB.isUsernameAvailable('ana'), isFalse);
      expect(
        () => serviceB.register('ana', bob),
        throwsA(isA<FormatException>()),
      );

      // The directory doc records the winner's key and uid.
      final doc = await firestore.collection('users').doc('ana').get();
      expect(doc.data()!['uid'], 'uid-a');
      expect(doc.data()!['publicKey'], alice.publicKeyHex);
      expect(doc.data()!['displayName'], 'Alice');
      expect(doc.data()!['createdAt'], isA<String>());

      // Directory lookup finds the winner.
      final entry = await serviceB.lookupUser('ana');
      expect(entry!.displayName, 'Alice');
      expect(entry.uid, 'uid-a');
    });

    test('invalid usernames are rejected before hitting the server', () async {
      final service = newService(
        FakeFirebaseFirestore(),
        await newSettings(),
        uid: 'uid-a',
      );
      final identity = await Identity.load(MemoryKeyStore(), name: 'A');
      expect(() => service.register('a!', identity),
          throwsA(isA<FormatException>()));
      expect(() => service.register('ab', identity),
          throwsA(isA<FormatException>()));
    });
  });

  group('remote gifts', () {
    late FakeFirebaseFirestore firestore;
    late Identity giver;
    late Identity holder;
    late ServerService giverService;
    late ServerService holderService;
    late TicketStore giverStore;
    late TicketStore holderStore;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      giver = await Identity.load(MemoryKeyStore(), name: 'Ricardo');
      holder = await Identity.load(MemoryKeyStore(), name: 'Ana');
      final giverSettings = await newSettings();
      await giverSettings.put('username', 'ricardo');
      final holderSettings = await newSettings();
      await holderSettings.put('username', 'ana');
      giverService = newService(firestore, giverSettings, uid: 'uid-g');
      holderService = newService(firestore, holderSettings, uid: 'uid-h');
      giverStore = await newStore();
      holderStore = await newStore();
    });

    Future<Ticket> publish({String title = 'Do the dishes'}) async {
      final ticket = await giverStore.create(
        title: title,
        giverName: giver.name,
        giverPubKey: giver.publicKeyHex,
      );
      await giverService.publishGift(
        ticket,
        giver,
        toUid: 'uid-h',
        toUsername: 'ana',
      );
      return ticket;
    }

    test('publish shape matches the security rules', () async {
      final ticket = await publish();
      final doc =
          await firestore.collection('tickets').doc(ticket.id).get();
      final data = doc.data()!;

      expect(
        data.keys.toSet(),
        {
          'gift',
          'fromUid',
          'fromUsername',
          'fromPubKey',
          'toUid',
          'toUsername',
          'status',
          'createdAt',
          'expiresAt',
        },
      );
      expect(data['status'], 'offered');
      expect(data['fromUid'], 'uid-g');
      expect(data['fromUsername'], 'ricardo');
      expect(data['fromPubKey'], giver.publicKeyHex);
      expect(data['toUid'], 'uid-h');
      expect(data['toUsername'], 'ana');
      expect(data['createdAt'], ticket.createdAt.toIso8601String());
      expect(data['expiresAt'], ticket.expiresAt.toIso8601String());

      // The gift is the decoded signed PT2 map — and it verifies.
      final gift = data['gift'] as Map;
      expect(gift['signature'], isA<String>());
      expect(gift['giverPubKey'], giver.publicKeyHex);
      final decoded = await decodeGiftV2Map(gift);
      expect(decoded.id, ticket.id);
      expect(decoded.title, 'Do the dishes');
    });

    test('inbox query returns offered gifts addressed to me', () async {
      final ticket = await publish();
      final docs = await holderService.watchInbox().first;
      expect(docs, hasLength(1));
      expect(docs.single.id, ticket.id);
      expect(docs.single.fromUsername, 'ricardo');
      expect(docs.single.status, 'offered');
    });

    test('claim transition: recipient moves offered → claimRequested',
        () async {
      final ticket = await publish();
      await holderService.requestClaim(ticket.id);
      final doc =
          await firestore.collection('tickets').doc(ticket.id).get();
      expect(doc.data()!['status'], 'claimRequested');
    });

    test('giver fulfill writes a verifiable signed receipt', () async {
      final ticket = await publish();
      await holderService.requestClaim(ticket.id);
      await giverService.fulfill(ticket.id, ticket, giver);

      final doc =
          await firestore.collection('tickets').doc(ticket.id).get();
      final data = doc.data()!;
      expect(data['status'], 'fulfilled');
      final receipt = data['receipt'] as Map;
      expect(receipt['id'], ticket.id);
      expect(receipt['nonce'], ticket.nonce);
      expect(receipt['giverPubKey'], giver.publicKeyHex);
      expect(receipt['fulfilledAt'], isA<String>());
      expect(await verifyReceipt(receipt, ticket), isTrue);
    });

    test('fulfillIfExists updates the server doc, ignores local-only tickets',
        () async {
      final ticket = await publish();
      await giverService.fulfillIfExists(ticket, giver);
      var doc = await firestore.collection('tickets').doc(ticket.id).get();
      expect(doc.data()!['status'], 'fulfilled');

      // No server doc → no-op, no throw.
      final localOnly = await giverStore.create(
        title: 'Local',
        giverName: giver.name,
      );
      await giverService.fulfillIfExists(localOnly, giver);
      doc = await firestore.collection('tickets').doc(localOnly.id).get();
      expect(doc.exists, isFalse);
    });

    test('accept imports the gift as holder and hides it from the inbox',
        () async {
      final ticket = await publish();
      final sync = ServerSync(service: holderService)
        ..attach(tickets: holderStore, identity: holder);
      addTearDown(sync.dispose);

      await waitFor(() => sync.inbox.isNotEmpty);
      final doc = sync.inbox.single;
      expect(doc.id, ticket.id);

      final held = await sync.accept(doc);
      expect(held.role, TicketRole.holder);
      expect(held.holderName, 'Ana');
      expect(held.serverStatus, ServerTicketStatus.offered);
      expect(sync.inbox, isEmpty);
      expect(holderService.isAccepted(ticket.id), isTrue);

      // Accepting does not move the server state machine.
      final serverDoc =
          await firestore.collection('tickets').doc(ticket.id).get();
      expect(serverDoc.data()!['status'], 'offered');
    });

    test('reconciliation: verified fulfillment redeems both local copies',
        () async {
      final ticket = await publish();
      final holderSync = ServerSync(service: holderService)
        ..attach(tickets: holderStore, identity: holder);
      final giverSync = ServerSync(service: giverService)
        ..attach(tickets: giverStore, identity: giver);
      addTearDown(holderSync.dispose);
      addTearDown(giverSync.dispose);

      // Holder accepts from the inbox; giver sees the outgoing doc.
      await waitFor(() => holderSync.inbox.isNotEmpty);
      await holderSync.accept(holderSync.inbox.single);
      await waitFor(
        () => giverStore.byId(ticket.id)?.serverStatus ==
            ServerTicketStatus.offered,
      );

      // Holder requests the claim; the giver's copy shows claimRequested.
      await holderService.requestClaim(ticket.id);
      await waitFor(
        () => giverStore.byId(ticket.id)?.serverStatus ==
            ServerTicketStatus.claimRequested,
      );
      await waitFor(
        () => holderStore.byId(ticket.id)?.serverStatus ==
            ServerTicketStatus.claimRequested,
      );
      await waitFor(() => giverSync.pendingClaims.isNotEmpty);
      expect(giverSync.pendingClaims.single.id, ticket.id);

      // Giver confirms; both copies become redeemed with the receipt date.
      await giverService.fulfill(ticket.id, ticket, giver);
      await waitFor(
        () => holderStore.byId(ticket.id)?.status == TicketStatus.redeemed,
      );
      await waitFor(
        () => giverStore.byId(ticket.id)?.status == TicketStatus.redeemed,
      );

      final heldCopy = holderStore.byId(ticket.id)!;
      final giverCopy = giverStore.byId(ticket.id)!;
      expect(heldCopy.redeemedAt, isNotNull);
      expect(giverCopy.redeemedAt, isNotNull);
      expect(heldCopy.serverStatus, ServerTicketStatus.fulfilled);
      expect(holderStore.history.map((t) => t.id), contains(ticket.id));
    });

    test('reconciliation rejects a tampered receipt', () async {
      final ticket = await publish();
      final holderSync = ServerSync(service: holderService)
        ..attach(tickets: holderStore, identity: holder);
      addTearDown(holderSync.dispose);

      await waitFor(() => holderSync.inbox.isNotEmpty);
      await holderSync.accept(holderSync.inbox.single);

      // Someone forges a fulfillment: the receipt signature doesn't check
      // out for this ticket's giver key.
      final forger = await Identity.load(MemoryKeyStore(), name: 'Mallory');
      final forged = await encodeReceipt(ticket, forger);
      await firestore.collection('tickets').doc(ticket.id).update({
        'status': 'fulfilled',
        'receipt': forged,
      });

      // Give the listener time to deliver the tampered doc.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final local = holderStore.byId(ticket.id)!;
      expect(local.status, TicketStatus.active);
      expect(local.redeemedAt, isNull);
    });
  });
}
