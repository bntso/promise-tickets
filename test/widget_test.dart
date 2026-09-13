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
import 'package:promise_tickets/qr/payload.dart';
import 'package:promise_tickets/server/server_service.dart';

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
}
