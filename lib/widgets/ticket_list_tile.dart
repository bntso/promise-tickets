import 'package:flutter/material.dart';

import '../models/ticket.dart';
import 'ticket_card.dart';

/// Compact list-row rendering of a ticket (wallet list view), reusing the
/// same counterparty, badge and status-chip helpers as [TicketCard].
class TicketListTile extends StatelessWidget {
  const TicketListTile({
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
  final VoidCallback? onConfirmClaim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final expired = ticket.isExpired;
    final expiringSoon = !expired &&
        ticket.expiresAt.difference(DateTime.now()).inDays < 30;

    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: expired
              ? colorScheme.outline
              : expiringSoon
                  ? colorScheme.error
                  : null,
        );

    return Opacity(
      opacity: expired ? 0.5 : 1,
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(
          ticket.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (counterpartyLabel != null)
              TicketCounterparty(
                label: counterpartyLabel!,
                verified: verified,
              ),
            Text(ticketExpiryLabel(ticket), style: subtitleStyle),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TicketStatusChip(
              ticket: ticket,
              onConfirmClaim: onConfirmClaim,
            ),
            if (ticket.status == TicketStatus.redeemed)
              Icon(Icons.check_circle, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
