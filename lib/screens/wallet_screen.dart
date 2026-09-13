import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
import '../state/ticket_store.dart';
import '../widgets/ticket_card.dart';
import 'create_ticket_screen.dart';
import 'profile_screen.dart';
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
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Your profile',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Redeemed'),
              Tab(text: 'Expired'),
            ],
          ),
        ),
        body: Consumer<TicketStore>(
          builder: (context, store, _) => TabBarView(
            children: [
              _TicketList(
                tickets: store.active,
                emptyMessage: 'No promises yet — create one!',
              ),
              _TicketList(
                tickets: store.redeemed,
                emptyMessage: 'Nothing redeemed yet.',
              ),
              _TicketList(
                tickets: store.expired,
                emptyMessage: 'No expired tickets.',
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
  const _TicketList({required this.tickets, required this.emptyMessage});

  final List<Ticket> tickets;
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
        return TicketCard(
          ticket: ticket,
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
