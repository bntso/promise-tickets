import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'identity/identity.dart';
import 'identity/key_store.dart';
import 'people/contact_store.dart';
import 'screens/home_screen.dart';
import 'state/profile.dart';
import 'state/ticket_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final ticketsBox = await Hive.openBox<Map>('tickets');
  final settingsBox = await Hive.openBox<dynamic>('settings');
  final contactsBox = await Hive.openBox<Map>('contacts');
  // Migration: generates an identity on first launch or upgrade, seeding the
  // display name from the existing profile name. PT1-era tickets keep working
  // and are shown as unverified.
  final identity = await Identity.load(
    SecureKeyStore(),
    name: profileName(settingsBox),
  );
  runApp(PromiseTicketsApp(
    ticketsBox: ticketsBox,
    settingsBox: settingsBox,
    contactsBox: contactsBox,
    identity: identity,
  ));
}

class PromiseTicketsApp extends StatelessWidget {
  const PromiseTicketsApp({
    super.key,
    required this.ticketsBox,
    required this.settingsBox,
    required this.contactsBox,
    required this.identity,
  });

  final Box<Map> ticketsBox;
  final Box settingsBox;
  final Box<Map> contactsBox;
  final Identity identity;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TicketStore(ticketsBox)),
        ChangeNotifierProvider(create: (_) => ContactStore(contactsBox)),
        ChangeNotifierProvider<Identity>.value(value: identity),
        Provider<Box>.value(value: settingsBox),
      ],
      child: MaterialApp(
        title: 'Promise Tickets',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
