import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../people/contact.dart';
import '../people/contact_store.dart';
import '../server/server_service.dart';
import 'registration_screen.dart';
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

  Future<void> _searchDirectory(BuildContext context) async {
    final server = context.read<ServerService>();
    if (!server.isRegistered) {
      final register = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pick a username first'),
          content: const Text(
            'You need a username to search the directory.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Pick a username'),
            ),
          ],
        ),
      );
      if (register == true && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RegistrationScreen()),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => const _DirectorySearchDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = context.watch<ServerService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: [
          if (server.available)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search by username',
              onPressed: () => _searchDirectory(context),
            ),
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Key: ${fingerprintOf(contact.publicKeyHex)}'),
                      _SourceBadge(contact: contact),
                    ],
                  ),
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

/// Trust badge: scanned keys were verified face-to-face; directory keys
/// come from the untrusted server and are shown as less trusted.
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.contact});

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
          scanned ? 'verified in person' : 'from directory',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scanned ? null : colorScheme.outline),
        ),
      ],
    );
  }
}

class _DirectorySearchDialog extends StatefulWidget {
  const _DirectorySearchDialog();

  @override
  State<_DirectorySearchDialog> createState() =>
      _DirectorySearchDialogState();
}

class _DirectorySearchDialogState extends State<_DirectorySearchDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _searched = false;
  DirectoryEntry? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final server = context.read<ServerService>();
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return;
    setState(() {
      _busy = true;
      _searched = false;
      _result = null;
    });
    try {
      final entry = await server.lookupUser(query);
      if (!mounted) return;
      setState(() {
        _result = entry;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searched = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addContact(DirectoryEntry entry) async {
    final contacts = context.read<ContactStore>();
    try {
      await contacts.add(
        name: entry.displayName,
        publicKeyHex: entry.publicKeyHex,
        source: ContactSource.directory,
        username: entry.username,
        serverUid: entry.uid,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${entry.displayName} added to your people.')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return AlertDialog(
      title: const Text('Search by username'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixText: '@',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const CircularProgressIndicator()
          else if (result != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person),
              title: Text(result.displayName),
              subtitle: Text('@${result.username}'),
              trailing: FilledButton(
                onPressed: () => _addContact(result),
                child: const Text('Add'),
              ),
            )
          else if (_searched)
            const Text('Nobody found with that username.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.tonal(
          onPressed: _busy ? null : _search,
          child: const Text('Search'),
        ),
      ],
    );
  }
}
