import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Box<Map> ticketsBox;
  late Box settingsBox;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('promise_tickets_test');
    Hive.init(dir.path);
    ticketsBox = await Hive.openBox<Map>('tickets');
    settingsBox = await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('wallet screen renders with tabs and empty state',
      (tester) async {
    await tester.pumpWidget(
      PromiseTicketsApp(ticketsBox: ticketsBox, settingsBox: settingsBox),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Promise Tickets'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Redeemed'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('No promises yet — create one!'), findsOneWidget);
  });
}
