import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../people/contact.dart';
import '../people/contact_store.dart';

/// Trust badge: scanned keys were verified face-to-face; directory keys
/// come from the untrusted server and are shown as less trusted.
class ContactSourceBadge extends StatelessWidget {
  const ContactSourceBadge({super.key, required this.contact});

  final Contact contact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final scanned = contact.source == ContactSource.scanned;
    return Row(
      children: [
        Icon(
          scanned ? Icons.verified : Icons.cloud_outlined,
          size: 14,
          color: scanned ? colorScheme.primary : colorScheme.outline,
        ),
        const SizedBox(width: 4),
        Text(
          scanned ? '✓ verified in person' : 'from directory',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scanned ? null : colorScheme.outline),
        ),
      ],
    );
  }
}

/// Rename dialog shared by the people list and the person detail screen.
Future<void> renameContact(BuildContext context, Contact contact) async {
  final store = context.read<ContactStore>();
  final controller = TextEditingController(text: contact.name);
  final newName = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename contact'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (newName != null) {
    await store.rename(contact.publicKeyHex, newName);
  }
}

/// Delete confirmation shared by the people list and the person detail
/// screen. Resolves true when the contact was removed.
Future<bool> deleteContact(BuildContext context, Contact contact) async {
  final store = context.read<ContactStore>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Remove ${contact.name}?'),
      content: const Text('Their future promises will show as unverified.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  await store.delete(contact.publicKeyHex);
  return true;
}
