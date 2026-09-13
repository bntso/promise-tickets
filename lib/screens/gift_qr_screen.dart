import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../qr/payload.dart';
import '../transport/transport.dart';

class GiftQrScreen extends StatelessWidget {
  const GiftQrScreen({super.key, required this.ticket});

  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final identity = context.read<Identity>();
    final payload = encodeGiftV2(ticket, identity);

    return Scaffold(
      appBar: AppBar(title: const Text('Gift this promise')),
      body: Center(
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
                if (ticket.recipientName != null) ...[
                  const SizedBox(height: 8),
                  Text('For: ${ticket.recipientName}'),
                ],
                const SizedBox(height: 24),
                QrImageView(
                  data: data,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
                const SizedBox(height: 24),
                FilledButton.tonalIcon(
                  onPressed: () => const LinkTransport().send(context, data),
                  icon: Icon(const LinkTransport().icon),
                  label: Text(const LinkTransport().name),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Let them scan this code, or send it as a link — they can paste it into their app.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
