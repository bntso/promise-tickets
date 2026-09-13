import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../people/contact.dart';
import '../people/contact_store.dart';
import 'scan_screen.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  Future<void> _renameContact(BuildContext context, Contact contact) async {
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

  Future<void> _deleteContact(BuildContext context, Contact contact) async {
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
    if (confirmed == true) {
      await store.delete(contact.publicKeyHex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Add by scanning their card',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<ContactStore>(
        builder: (context, store, _) {
          final contacts = store.contacts;
          if (contacts.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No people yet — scan their "My card" QR to add them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(contact.name),
                  subtitle: Text('Key: ${fingerprintOf(contact.publicKeyHex)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Rename',
                        onPressed: () => _renameContact(context, contact),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove',
                        onPressed: () => _deleteContact(context, contact),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
