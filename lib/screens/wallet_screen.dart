import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../people/contact_store.dart';
import '../state/ticket_store.dart';
import '../widgets/server_sections.dart';
import '../widgets/ticket_card.dart';
import 'create_ticket_screen.dart';
import 'scan_screen.dart';
import 'ticket_detail_screen.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Promise Tickets'),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan a QR code',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Owed to me'),
              Tab(text: 'I owe'),
              Tab(text: 'History'),
            ],
          ),
        ),
        body: Consumer2<TicketStore, ContactStore>(
          builder: (context, store, contacts, _) => Column(
            children: [
              const ServerSections(),
              Expanded(
                child: TabBarView(
                  children: [
                    _TicketList(
                      tickets: store.owedToMe,
                      contacts: contacts,
                      emptyMessage: 'No promises owed to you yet — scan one!',
                    ),
                    _TicketList(
                      tickets: store.iOwe,
                      contacts: contacts,
                      emptyMessage: 'You owe nothing — create a promise!',
                    ),
                    _TicketList(
                      tickets: store.history,
                      contacts: contacts,
                      emptyMessage: 'No past promises.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'New promise',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CreateTicketScreen()),
          ),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList({
    required this.tickets,
    required this.contacts,
    required this.emptyMessage,
  });

  final List<Ticket> tickets;
  final ContactStore contacts;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        final counterparty = TicketCard.counterpartyOf(ticket, contacts);
        return TicketCard(
          ticket: ticket,
          counterpartyLabel: counterparty.label,
          verified: counterparty.verified,
          onConfirmClaim: ticket.role == TicketRole.giver &&
                  ticket.serverStatus == ServerTicketStatus.claimRequested
              ? () => confirmTicketFulfillment(context, ticket)
              : null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TicketDetailScreen(ticketId: ticket.id),
            ),
          ),
        );
      },
    );
  }
}
