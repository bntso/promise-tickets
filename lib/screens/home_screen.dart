import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import '../server/server_service.dart';
import 'my_card_screen.dart';
import 'people_screen.dart';
import 'registration_screen.dart';
import 'wallet_screen.dart';

const String kRegistrationDismissedKey = 'registrationDismissed';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeOfferRegistration();
    });
  }

  /// First launch with a working server: offer to pick a username. "Not
  /// now" is remembered; the offer stays available from My card and People.
  void _maybeOfferRegistration() {
    if (!mounted) return;
    final server = context.read<ServerService>();
    final settings = context.read<Box>();
    if (!server.available ||
        server.isRegistered ||
        settings.get(kRegistrationDismissedKey) == true) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick a username?'),
        content: const Text(
          'Let people find you and send you promises directly. '
          'Everything keeps working offline either way.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              settings.put(kRegistrationDismissedKey, true);
              Navigator.of(context).pop();
            },
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RegistrationScreen(),
                ),
              );
            },
            child: const Text('Pick a username'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          WalletScreen(),
          PeopleScreen(),
          MyCardScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wallet), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.people), label: 'People'),
          NavigationDestination(icon: Icon(Icons.badge), label: 'My card'),
        ],
      ),
    );
  }
}
