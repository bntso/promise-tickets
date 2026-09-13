import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';
import 'package:promise_tickets/main.dart';

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

  testWidgets('wallet renders with directional tabs and empty state',
      (tester) async {
    await tester.pumpWidget(
      PromiseTicketsApp(
        ticketsBox: ticketsBox,
        settingsBox: settingsBox,
        contactsBox: contactsBox,
        identity: identity,
      ),
    );
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
  });
}
