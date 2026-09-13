import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'identity/identity.dart';
import 'identity/key_store.dart';
import 'people/contact_store.dart';
import 'screens/home_screen.dart';
import 'server/server_service.dart';
import 'server/server_sync.dart';
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
  final server = await _bootstrapServer(settingsBox);
  runApp(PromiseTicketsApp(
    ticketsBox: ticketsBox,
    settingsBox: settingsBox,
    contactsBox: contactsBox,
    identity: identity,
    serverService: server,
  ));
}

/// Initializes Firebase and signs in anonymously. On any failure the app
/// runs in degraded (offline-only) mode — all local/QR features keep
/// working and the server UI stays hidden.
Future<ServerService> _bootstrapServer(Box settings) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    return ServerService(
      auth: auth,
      firestore: FirebaseFirestore.instance,
      settings: settings,
    );
  } catch (_) {
    return ServerService.offline(settings: settings);
  }
}

class PromiseTicketsApp extends StatelessWidget {
  const PromiseTicketsApp({
    super.key,
    required this.ticketsBox,
    required this.settingsBox,
    required this.contactsBox,
    required this.identity,
    required this.serverService,
  });

  final Box<Map> ticketsBox;
  final Box settingsBox;
  final Box<Map> contactsBox;
  final Identity identity;
  final ServerService serverService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TicketStore(ticketsBox)),
        ChangeNotifierProvider(create: (_) => ContactStore(contactsBox)),
        ChangeNotifierProvider<Identity>.value(value: identity),
        Provider<Box>.value(value: settingsBox),
        ChangeNotifierProvider<ServerService>.value(value: serverService),
        ChangeNotifierProxyProvider3<TicketStore, Identity, ServerService,
            ServerSync>(
          create: (_) => ServerSync(service: serverService),
          update: (_, tickets, identity, server, sync) =>
              (sync ?? ServerSync(service: server))
                ..attach(tickets: tickets, identity: identity),
        ),
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
