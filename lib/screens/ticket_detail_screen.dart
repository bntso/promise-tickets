import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../people/contact_store.dart';
import '../state/ticket_store.dart';
import '../widgets/ticket_card.dart';
import 'claim_screen.dart';
import 'gift_qr_screen.dart';

class TicketDetailScreen extends StatelessWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  Future<void> _confirmDelete(BuildContext context) async {
    final store = context.read<TicketStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this ticket?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.delete(ticketId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TicketStore>();
    final contacts = context.watch<ContactStore>();
    final ticket = store.byId(ticketId);
    if (ticket == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This ticket is gone.')),
      );
    }

    final active = ticket.status == TicketStatus.active && !ticket.isExpired;
    final counterparty = TicketCard.counterpartyOf(ticket, contacts);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ticket')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticket.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(child: Text(counterparty.label)),
                      if (counterparty.verified != null) ...[
                        const SizedBox(width: 4),
                        Icon(
                          counterparty.verified!
                              ? Icons.verified
                              : Icons.shield_outlined,
                          size: 18,
                          color: counterparty.verified!
                              ? colorScheme.primary
                              : colorScheme.outline,
                        ),
                        Text(
                          counterparty.verified! ? ' verified' : ' unverified',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  if (ticket.note != null) ...[
                    const SizedBox(height: 8),
                    Text(ticket.note!),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    ticket.isExpired
                        ? 'Expired ${DateFormat.yMMMd().format(ticket.expiresAt)}'
                        : 'Expires ${DateFormat.yMMMd().format(ticket.expiresAt)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (ticket.status == TicketStatus.redeemed)
            const Center(child: Chip(label: Text('Redeemed')))
          else if (ticket.isExpired)
            const Center(child: Chip(label: Text('Expired')))
          else if (ticket.role == TicketRole.giver && active)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GiftQrScreen(ticket: ticket),
                ),
              ),
              icon: const Icon(Icons.card_giftcard),
              label: const Text('Gift'),
            )
          else if (ticket.role == TicketRole.holder && active)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ClaimScreen(ticket: ticket),
                ),
              ),
              icon: const Icon(Icons.qr_code),
              label: const Text('Claim'),
            ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ),
        ],
      ),
    );
  }
}
