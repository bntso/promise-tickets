import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../people/contact_store.dart';
import '../state/profile.dart';
import '../state/ticket_store.dart';
import '../widgets/server_sections.dart';
import '../widgets/ticket_card.dart';
import '../widgets/ticket_list_tile.dart';
import 'create_ticket_screen.dart';
import 'scan_screen.dart';
import 'ticket_detail_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  /// Cards vs compact list, persisted in the settings box.
  late bool _listView;

  @override
  void initState() {
    super.initState();
    _listView = context.read<Box>().get(kWalletViewKey) == 'list';
  }

  void _toggleView() {
    setState(() => _listView = !_listView);
    context.read<Box>().put(kWalletViewKey, _listView ? 'list' : 'cards');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Promise Tickets'),
          actions: [
            IconButton(
              icon: Icon(_listView ? Icons.dashboard : Icons.view_list),
              tooltip: _listView ? 'Show card view' : 'Show list view',
              onPressed: _toggleView,
            ),
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
                      listView: _listView,
                      emptyMessage: 'No promises owed to you yet — scan one!',
                    ),
                    _TicketList(
                      tickets: store.iOwe,
                      contacts: contacts,
                      listView: _listView,
                      emptyMessage: 'You owe nothing — create a promise!',
                    ),
                    _TicketList(
                      tickets: store.history,
                      contacts: contacts,
                      listView: _listView,
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
    required this.listView,
    required this.emptyMessage,
  });

  final List<Ticket> tickets;
  final ContactStore contacts;
  final bool listView;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    if (listView) {
      return ListView.separated(
        itemCount: tickets.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final ticket = tickets[index];
          final counterparty = TicketCard.counterpartyOf(ticket, contacts);
          return TicketListTile(
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
