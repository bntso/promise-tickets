import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../people/contact_store.dart';
import '../qr/payload.dart';
import '../server/server_service.dart';
import '../server/server_sync.dart';
import '../state/ticket_store.dart';
import 'import_preview.dart';

/// Giver confirms a claim: signs the fulfillment receipt and writes
/// fulfilled + receipt to the server doc. Both wallets then sync.
Future<void> confirmFulfillment(BuildContext context, ServerTicket doc) async {
  final store = context.read<TicketStore>();
  final server = context.read<ServerService>();
  final identity = context.read<Identity>();
  final title = doc.gift['title'] as String? ?? 'this promise';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Mark '$title' as fulfilled?"),
      content: Text('@${doc.toUsername} wants to claim this promise.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final ticket = store.byId(doc.id);
  if (ticket == null) return;
  try {
    await server.fulfill(doc.id, ticket, identity);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not reach the server. Try again.')),
    );
  }
}

/// Same confirmation, starting from the local giver-copy ticket (tappable
/// "Claim requested" chip / detail screen).
Future<void> confirmTicketFulfillment(
  BuildContext context,
  Ticket ticket,
) async {
  final server = context.read<ServerService>();
  final identity = context.read<Identity>();
  final claimer = ticket.recipientName != null
      ? '${ticket.recipientName} wants to claim this promise.'
      : 'The holder wants to claim this promise.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Mark '${ticket.title}' as fulfilled?"),
      content: Text(claimer),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await server.fulfill(ticket.id, ticket, identity);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not reach the server. Try again.')),
    );
  }
}

/// Inbox + claims sections shown atop the wallet tabs (registered users
/// only; hidden in degraded mode).
class ServerSections extends StatelessWidget {
  const ServerSections({super.key});

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerService>();
    if (!server.isRegistered) return const SizedBox.shrink();
    return Consumer<ServerSync>(
      builder: (context, sync, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sync.inbox.isNotEmpty) _InboxSection(sync: sync),
            if (sync.pendingClaims.isNotEmpty)
              _ClaimsSection(claims: sync.pendingClaims),
          ],
        );
      },
    );
  }
}

class _InboxSection extends StatelessWidget {
  const _InboxSection({required this.sync});

  final ServerSync sync;

  Future<void> _open(BuildContext context, ServerTicket doc) async {
    final contacts = context.read<ContactStore>();
    final Ticket ticket;
    try {
      // Verify the signed gift before showing anything trust-worthy.
      ticket = await decodeGiftV2Map(doc.gift);
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      return;
    }
    if (!context.mounted) return;
    final accepted = await showImportPreview(context, ticket, contacts);
    if (!context.mounted || accepted != true) return;
    try {
      await sync.accept(doc);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promise saved to your wallet.')),
      );
    } on FormatException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inbox = sync.inbox;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: colorScheme.secondaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Inbox (${inbox.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final doc in inbox)
            ListTile(
              leading: const Icon(Icons.move_to_inbox),
              title: Text(doc.gift['title'] as String? ?? 'A promise'),
              subtitle: Text('From: @${doc.fromUsername}'),
              onTap: () => _open(context, doc),
            ),
        ],
      ),
    );
  }
}

class _ClaimsSection extends StatelessWidget {
  const _ClaimsSection({required this.claims});

  final List<ServerTicket> claims;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: colorScheme.tertiaryContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Claims (${claims.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          for (final doc in claims)
            ListTile(
              leading: const Icon(Icons.front_hand_outlined),
              title: Text(
                '@${doc.toUsername} wants to claim '
                "'${doc.gift['title'] as String? ?? 'a promise'}'",
              ),
              trailing: FilledButton(
                onPressed: () => confirmFulfillment(context, doc),
                child: const Text('Confirm'),
              ),
            ),
        ],
      ),
    );
  }
}
