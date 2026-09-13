import 'package:flutter/material.dart';

import '../models/ticket.dart';
import '../people/contact_store.dart';

/// Counterparty line and verification badge for a ticket card.
/// [verified] is null when no badge applies (e.g. the giver's own copy).
class TicketCard extends StatelessWidget {
  const TicketCard({
    super.key,
    required this.ticket,
    this.counterpartyLabel,
    this.verified,
    this.onTap,
  });

  final Ticket ticket;
  final String? counterpartyLabel;

  /// true → ✓ verified, false → unverified, null → no badge.
  final bool? verified;
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

  String _expiryLabel() {
    final now = DateTime.now();
    if (ticket.isExpired) return 'Expired';
    final days = ticket.expiresAt.difference(now).inDays;
    if (days <= 0) return 'Expires today';
    if (days == 1) return 'Expires in 1 day';
    return 'Expires in $days days';
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
                Row(
                  children: [
                    Flexible(child: Text(counterpartyLabel!)),
                    if (verified != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        verified! ? Icons.verified : Icons.shield_outlined,
                        size: 16,
                        color: verified!
                            ? colorScheme.primary
                            : colorScheme.outline,
                      ),
                      if (!verified!)
                        Text(
                          ' unverified',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ],
                ),
              Text(_expiryLabel(), style: subtitleStyle),
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
