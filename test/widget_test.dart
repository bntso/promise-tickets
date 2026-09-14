import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';
import 'package:promise_tickets/main.dart';
import 'package:promise_tickets/models/ticket.dart';
import 'package:promise_tickets/people/contact.dart';
import 'package:promise_tickets/qr/payload.dart';
import 'package:promise_tickets/server/server_service.dart';
import 'package:promise_tickets/state/profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box<Map> ticketsBox;
  late Box settingsBox;
  late Box<Map> contactsBox;
  late Identity identity;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('promise_tickets_test');
    Hive.init(dir.path);
    ticketsBox = await Hive.openBox<Map>('tickets');
    settingsBox = await Hive.openBox<dynamic>('settings');
    contactsBox = await Hive.openBox<Map>('contacts');
    identity = await Identity.load(MemoryKeyStore(), name: 'Me');
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Widget app(ServerService server) => PromiseTicketsApp(
        ticketsBox: ticketsBox,
        settingsBox: settingsBox,
        contactsBox: contactsBox,
        identity: identity,
        serverService: server,
      );

  ServerService fakeServer({String uid = 'uid-me'}) => ServerService(
        auth: MockFirebaseAuth(
          mockUser: MockUser(uid: uid),
          signedIn: true,
        ),
        firestore: FakeFirebaseFirestore(),
        settings: settingsBox,
      );

  testWidgets('wallet renders with directional tabs and empty state',
      (tester) async {
    await tester.pumpWidget(app(ServerService.offline(settings: settingsBox)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Promise Tickets'), findsOneWidget);
    expect(find.text('Owed to me'), findsOneWidget);
    expect(find.text('I owe'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('No promises owed to you yet — scan one!'), findsOneWidget);
    // Bottom navigation.
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('My card'), findsOneWidget);
    // Degraded mode: no registration prompt.
    expect(find.text('Pick a username?'), findsNothing);
  });

  testWidgets('registration prompt appears when the server is available',
      (tester) async {
    await tester.pumpWidget(app(fakeServer()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Pick a username?'), findsOneWidget);
    // Accepting the offer opens the registration screen.
    await tester.tap(find.text('Pick a username'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pick a username?'), findsNothing);
    expect(find.text('Check availability'), findsOneWidget);
  });

  group('registered', () {
    setUp(() async {
      await settingsBox.put('username', 'me');
    });

    testWidgets('inbox section shows an offered gift from the server',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final server = ServerService(
        auth:
            MockFirebaseAuth(mockUser: MockUser(uid: 'uid-me'), signedIn: true),
        firestore: firestore,
        settings: settingsBox,
      );

      // A gift sent by someone else, addressed to me.
      final giver = await Identity.load(MemoryKeyStore(), name: 'Ana');
      final ticket = Ticket.create(
        title: 'Do the dishes',
        giverName: giver.name,
        giverPubKey: giver.publicKeyHex,
      );
      await firestore.collection('tickets').doc(ticket.id).set({
        'gift': await encodeGiftV2Map(ticket, giver),
        'fromUid': 'uid-ana',
        'fromUsername': 'ana',
        'fromPubKey': giver.publicKeyHex,
        'toUid': 'uid-me',
        'toUsername': 'me',
        'status': 'offered',
        'createdAt': ticket.createdAt.toIso8601String(),
        'expiresAt': ticket.expiresAt.toIso8601String(),
      });

      await tester.pumpWidget(app(server));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Inbox (1)'), findsOneWidget);
      expect(find.text('Do the dishes'), findsOneWidget);
      expect(find.text('From: @ana'), findsOneWidget);
    });
  });

  group('wallet view toggle', () {
    testWidgets('switches between cards and list and persists', (tester) async {
      await tester.pumpWidget(app(ServerService.offline(settings: settingsBox)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Default is cards; the button offers the list view. The toggle
      // writes to Hive, so the taps run in a real-async zone.
      expect(find.byTooltip('Show list view'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Show list view'));
      });
      await tester.pump();

      expect(settingsBox.get(kWalletViewKey), 'list');
      expect(find.byTooltip('Show card view'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Show card view'));
      });
      await tester.pump();
      expect(settingsBox.get(kWalletViewKey), 'cards');
    });

    group('with list view saved', () {
      setUp(() async {
        await settingsBox.put(kWalletViewKey, 'list');
      });

      testWidgets('saved preference is applied at startup', (tester) async {
        await tester
            .pumpWidget(app(ServerService.offline(settings: settingsBox)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byTooltip('Show card view'), findsOneWidget);
      });
    });
  });

  group('person detail', () {
    late Identity ana;

    setUp(() async {
      ana = await Identity.load(MemoryKeyStore(), name: 'Ana');
      final bo = await Identity.load(MemoryKeyStore(), name: 'Bo');
      await contactsBox.put(
        ana.publicKeyHex,
        Contact(
          name: 'Ana',
          publicKeyHex: ana.publicKeyHex,
          addedAt: DateTime(2026),
        ).toMap(),
      );
      await contactsBox.put(
        bo.publicKeyHex,
        Contact(
          name: 'Bo',
          publicKeyHex: bo.publicKeyHex,
          addedAt: DateTime(2026),
        ).toMap(),
      );
      // A promise Ana gave me (they owe me) and one I addressed to her
      // (I owe them).
      final fromAna = Ticket.create(
        title: 'Wash the car',
        giverName: 'Ana',
        role: TicketRole.holder,
        giverPubKey: ana.publicKeyHex,
      );
      await ticketsBox.put(fromAna.id, fromAna.toMap());
      final toAna = Ticket.create(
        title: 'Walk the dog',
        giverName: 'Me',
        recipientName: 'Ana',
        recipientPubKey: ana.publicKeyHex,
      );
      await ticketsBox.put(toAna.id, toAna.toMap());
    });

    Future<void> openPerson(WidgetTester tester, String name) async {
      await tester.pumpWidget(app(ServerService.offline(settings: settingsBox)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.people));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text(name));
      await tester.pump();
      // Let the push transition finish so the people list is offstage.
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('shows both directions of tickets for the contact',
        (tester) async {
      await openPerson(tester, 'Ana');

      expect(find.text('They owe me'), findsOneWidget);
      expect(find.text('I owe them'), findsOneWidget);
      expect(find.text('Wash the car'), findsOneWidget);
      expect(find.text('Walk the dog'), findsOneWidget);
      expect(find.text('✓ verified in person'), findsOneWidget);
    });

    testWidgets('empty sections show a friendly line', (tester) async {
      await openPerson(tester, 'Bo');

      expect(find.text('They owe me'), findsOneWidget);
      expect(find.text('I owe them'), findsOneWidget);
      expect(find.text('No promises between you yet.'), findsNWidgets(2));
    });
  });
}
