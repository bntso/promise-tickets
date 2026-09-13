import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'screens/wallet_screen.dart';
import 'state/ticket_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final ticketsBox = await Hive.openBox<Map>('tickets');
  final settingsBox = await Hive.openBox<dynamic>('settings');
  runApp(PromiseTicketsApp(ticketsBox: ticketsBox, settingsBox: settingsBox));
}

class PromiseTicketsApp extends StatelessWidget {
  const PromiseTicketsApp({
    super.key,
    required this.ticketsBox,
    required this.settingsBox,
  });

  final Box<Map> ticketsBox;
  final Box settingsBox;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TicketStore(ticketsBox)),
        Provider<Box>.value(value: settingsBox),
      ],
      child: MaterialApp(
        title: 'Promise Tickets',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: const WalletScreen(),
      ),
    );
  }
}
