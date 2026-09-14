import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../people/contact.dart';
import '../people/contact_store.dart';
import '../state/ticket_store.dart';
import '../widgets/contact_actions.dart';
import '../widgets/ticket_card.dart';
import 'ticket_detail_screen.dart';

/// Drill-down for one contact: identity details, trust badge, and every
/// ticket between us in both directions (active first, history muted).
class PersonScreen extends StatelessWidget {
  const PersonScreen({super.key, required this.publicKeyHex});

  final String publicKeyHex;

  Future<void> _delete(BuildContext context, Contact contact) async {
    final deleted = await deleteContact(context, contact);
    if (deleted && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = context.watch<ContactStore>();
    final store = context.watch<TicketStore>();
    final contact = contacts.byPubKey(publicKeyHex);
    if (contact == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This person is gone.')),
      );
    }

    final between = store.ticketsForContact(publicKeyHex);

    return Scaffold(
      appBar: AppBar(
        title: Text(contact.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () => renameContact(context, contact),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: () => _delete(context, contact),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          contact.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ContactSourceBadge(contact: contact),
                  const SizedBox(height: 4),
                  Text('Key: ${fingerprintOf(contact.publicKeyHex)}'),
                  if (contact.username != null)
                    Text('@${contact.username}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _TicketSection(
            title: 'They owe me',
            tickets: between.theyOweMe,
            contacts: contacts,
          ),
          _TicketSection(
            title: 'I owe them',
            tickets: between.iOweThem,
            contacts: contacts,
          ),
        ],
      ),
    );
  }
}

class _TicketSection extends StatelessWidget {
  const _TicketSection({
    required this.title,
    required this.tickets,
    required this.contacts,
  });

  final String title;
  final List<Ticket> tickets;
  final ContactStore contacts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (tickets.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('No promises between you yet.'),
          )
        else
          for (final ticket in tickets)
            _PersonTicketTile(
              ticket: ticket,
              contacts: contacts,
            ),
      ],
    );
  }
}

class _PersonTicketTile extends StatelessWidget {
  const _PersonTicketTile({required this.ticket, required this.contacts});

  final Ticket ticket;
  final ContactStore contacts;

  @override
  Widget build(BuildContext context) {
    final counterparty = TicketCard.counterpartyOf(ticket, contacts);
    final history =
        ticket.status == TicketStatus.redeemed && !ticket.isExpired;
    return Opacity(
      opacity: history ? 0.6 : 1,
      child: TicketCard(
        ticket: ticket,
        counterpartyLabel: counterparty.label,
        verified: counterparty.verified,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TicketDetailScreen(ticketId: ticket.id),
          ),
        ),
      ),
    );
  }
}
