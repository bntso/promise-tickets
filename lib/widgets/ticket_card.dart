import 'package:flutter/material.dart';

import '../models/ticket.dart';

class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket, this.onTap});

  final Ticket ticket;
  final VoidCallback? onTap;

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
              Text('Promised by ${ticket.giverName}'),
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
