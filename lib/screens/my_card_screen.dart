import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../identity/identity.dart';
import '../qr/payload.dart';
import '../server/server_service.dart';
import '../transport/transport.dart';
import 'profile_screen.dart';
import 'registration_screen.dart';

class MyCardScreen extends StatelessWidget {
  const MyCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = context.watch<Identity>();
    final server = context.watch<ServerService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My card'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit your name',
            onPressed: () => Navigator.of(context)
                .push(
                  MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
                )
                .then((_) {
                  if (context.mounted) {
                    identity.refreshName(context.read<Box>());
                  }
                }),
          ),
          ],
        ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              identity.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            if (server.isRegistered)
              Chip(
                avatar: const Icon(Icons.alternate_email, size: 18),
                label: Text(server.username!),
              )
            else if (server.available)
              ActionChip(
                avatar: const Icon(Icons.alternate_email, size: 18),
                label: const Text('Pick a username'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RegistrationScreen(),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            QrImageView(
              data: encodeId(identity),
              size: 240,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              'Fingerprint: ${identity.fingerprint}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  const LinkTransport().send(context, encodeId(identity)),
              icon: Icon(const LinkTransport().icon),
              label: Text(const LinkTransport().name),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Share this so people can add you — their app will show your promises as verified.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
