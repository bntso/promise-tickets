import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/ticket.dart';
import '../people/contact_store.dart';

/// Human-readable expiry line shared by card and list views.
String ticketExpiryLabel(Ticket ticket) {
  final now = DateTime.now();
  if (ticket.isExpired) return 'Expired';
  final days = ticket.expiresAt.difference(now).inDays;
  if (days <= 0) return 'Expires today';
  if (days == 1) return 'Expires in 1 day';
  return 'Expires in $days days';
}

/// Counterparty line with verification badge: "From: Ricardo ✓",
/// "To: whoever scans it", ... [verified] is null when no badge applies.
class TicketCounterparty extends StatelessWidget {
  const TicketCounterparty({
    super.key,
    required this.label,
    this.verified,
  });

  final String label;

  /// true → ✓ verified, false → unverified, null → no badge.
  final bool? verified;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        if (verified != null) ...[
          const SizedBox(width: 4),
          Icon(
            verified! ? Icons.verified : Icons.shield_outlined,
            size: 16,
            color: verified! ? colorScheme.primary : colorScheme.outline,
          ),
          if (!verified!)
            Text(
              ' unverified',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}

/// Server-sync chip: giver sees Sent / Claim requested / Fulfilled;
/// holder sees In wallet / Waiting confirmation / Fulfilled.
class TicketStatusChip extends StatelessWidget {
  const TicketStatusChip({
    super.key,
    required this.ticket,
    this.onConfirmClaim,
  });

  final Ticket ticket;

  /// Set when the giver can confirm a server claim from this chip.
  final VoidCallback? onConfirmClaim;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (ticket.status == TicketStatus.redeemed) {
      final at = ticket.redeemedAt;
      if (at == null) return const SizedBox.shrink();
      return Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.check_circle_outline, size: 16),
        label: Text('Fulfilled ${DateFormat.yMMMd().format(at)}'),
      );
    }
    final giver = ticket.role == TicketRole.giver;
    switch (ticket.serverStatus) {
      case ServerTicketStatus.offered:
        return Chip(
          visualDensity: VisualDensity.compact,
          label: Text(giver ? 'Sent' : 'In wallet'),
        );
      case ServerTicketStatus.claimRequested:
        if (giver) {
          return ActionChip(
            visualDensity: VisualDensity.compact,
            backgroundColor: colorScheme.primaryContainer,
            avatar: const Icon(Icons.front_hand_outlined, size: 16),
            label: const Text('Claim requested'),
            onPressed: onConfirmClaim,
          );
        }
        return Chip(
          visualDensity: VisualDensity.compact,
          backgroundColor: colorScheme.tertiaryContainer,
          label: const Text('Waiting confirmation'),
        );
      case ServerTicketStatus.fulfilled:
      case null:
        return const SizedBox.shrink();
    }
  }
}

/// Counterparty line and verification badge for a ticket card.
/// [verified] is null when no badge applies (e.g. the giver's own copy).
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    this.counterpartyLabel,
    this.verified,
    this.onConfirmClaim,
    this.onTap,
  });

  final Ticket ticket;
  final String? counterpartyLabel;

  /// true → ✓ verified, false → unverified, null → no badge.
  final bool? verified;

  /// Set when the giver can confirm a server claim from this card.
  final VoidCallback? onConfirmClaim;
  final VoidCallback? onTap;

  /// Computes the counterparty label and badge for [ticket] as seen on this
  /// device, using [contacts] for verified names.
  static ({String label, bool? verified}) counterpartyOf(
    Ticket ticket,
    ContactStore contacts,
  ) {
    if (ticket.role == TicketRole.giver) {
      return (
        label: ticket.recipientName != null
            ? 'To: ${ticket.recipientName}'
            : 'To: whoever scans it',
        verified: null,
      );
    }
    if (!ticket.isSigned) {
      return (label: 'From: ${ticket.giverName}', verified: false);
    }
    final contact = contacts.byPubKey(ticket.giverPubKey!);
    if (contact == null) {
      return (label: 'From: ${ticket.giverName}', verified: false);
    }
    return (label: 'From: ${contact.name}', verified: true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expired = ticket.isExpired;
    final expiringSoon = !expired &&
        ticket.expiresAt.difference(DateTime.now()).inDays < 30;

    final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: expired
              ? colorScheme.outline
              : expiringSoon
                  ? colorScheme.error
                  : null,
        );

    final statusChip = TicketStatusChip(
      ticket: ticket,
      onConfirmClaim: onConfirmClaim,
    );

    return Opacity(
      opacity: expired ? 0.5 : 1,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          title: Text(ticket.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (counterpartyLabel != null)
                TicketCounterparty(
                  label: counterpartyLabel!,
                  verified: verified,
                ),
              Text(ticketExpiryLabel(ticket), style: subtitleStyle),
              Align(alignment: Alignment.centerLeft, child: statusChip),
            ],
          ),
          trailing: ticket.status == TicketStatus.redeemed
              ? Icon(Icons.check_circle, color: colorScheme.primary)
              : null,
        ),
      ),
    );
  }
}
