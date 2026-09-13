import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../qr/payload.dart';
import '../state/ticket_store.dart';

class ClaimScreen extends StatelessWidget {
  const ClaimScreen({super.key, required this.ticket});

  final Ticket ticket;

  Future<void> _markRedeemed(BuildContext context) async {
    await context.read<TicketStore>().redeem(ticket.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as redeemed. Enjoy!')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final identity = context.read<Identity>();
    final payload = encodeRedeemV2(ticket, identity);

    return Scaffold(
      appBar: AppBar(title: const Text('Claim this promise')),
      body: Center(
        child: SingleChildScrollView(
          child: FutureBuilder<String>(
            future: payload,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) {
                return const CircularProgressIndicator();
              }
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    ticket.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  QrImageView(
                    data: data,
                    size: 260,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Show this to ${ticket.giverName} so they can confirm your claim.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _markRedeemed(context),
                    icon: const Icon(Icons.check),
                    label:
                        const Text('The giver scanned it — mark as redeemed'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
