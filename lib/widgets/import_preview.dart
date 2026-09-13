import 'package:flutter/material.dart';

import '../models/ticket.dart';
import '../people/contact_store.dart';

/// Import preview shared by QR scan and the server inbox:
/// "From: name ✓ verified" for known signers, "unverified" with an
/// add-contact offer otherwise. Resolves true when the user accepts.
Future<bool?> showImportPreview(
  BuildContext context,
  Ticket ticket,
  ContactStore contacts,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      var known =
          ticket.isSigned && contacts.byPubKey(ticket.giverPubKey!) != null;
      return StatefulBuilder(
        builder: (context, setState) {
          final fromName = known
              ? contacts.byPubKey(ticket.giverPubKey!)!.name
              : ticket.giverName;
          return AlertDialog(
            title: const Text('Accept this promise?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text('From: $fromName')),
                    const SizedBox(width: 4),
                    if (known)
                      Icon(
                        Icons.verified,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                ),
                Text(
                  known ? 'verified' : 'unverified',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Text('“${ticket.title}”'),
                if (ticket.note != null) ...[
                  const SizedBox(height: 4),
                  Text(ticket.note!),
                ],
              ],
            ),
            actions: [
              if (!known && ticket.isSigned)
                TextButton(
                  onPressed: () async {
                    await contacts.add(
                      name: ticket.giverName,
                      publicKeyHex: ticket.giverPubKey!,
                    );
                    setState(() => known = true);
                  },
                  child: const Text('Add to contacts'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('No thanks'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Accept'),
              ),
            ],
          );
        },
      );
    },
  );
}
