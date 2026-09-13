import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../people/contact.dart';
import '../people/contact_store.dart';
import '../server/server_service.dart';
import '../state/ticket_store.dart';
import 'gift_qr_screen.dart';

class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _expiresAt;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final initial = _expiresAt ?? DateTime(now.year + 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please give your promise a title.')),
      );
      return;
    }
    final store = context.read<TicketStore>();
    final identity = context.read<Identity>();
    var ticket = await store.create(
      title: _titleController.text,
      note: _noteController.text,
      giverName: identity.name,
      expiresAt: _expiresAt,
      giverPubKey: identity.publicKeyHex,
    );
    if (!mounted) return;

    final contact = await _pickRecipient();
    if (contact != null) {
      ticket = (await store.attachRecipient(
        ticket.id,
        recipientName: contact.name,
        recipientPubKey: contact.publicKeyHex,
      ))!;
    }
    if (!mounted) return;

    // Directory contacts can receive the promise straight to their inbox.
    final server = context.read<ServerService>();
    if (contact != null && contact.canReceiveRemote && server.isRegistered) {
      final sendNow = await _chooseDelivery(contact);
      if (!mounted) return;
      if (sendNow == true) {
        await _sendNow(ticket, contact);
        return;
      }
      if (sendNow == null) return; // dismissed — stay on the form
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => GiftQrScreen(ticket: ticket)),
    );
  }

  /// Server ("Send now") vs in-person ("Show QR") delivery.
  Future<bool?> _chooseDelivery(Contact contact) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Gift to ${contact.name}'),
        content: Text(
          'Send it now to the inbox of @${contact.username}, or show a QR '
          'code to hand it over in person?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Show QR'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send now'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendNow(Ticket ticket, Contact contact) async {
    final store = context.read<TicketStore>();
    final server = context.read<ServerService>();
    final identity = context.read<Identity>();
    try {
      await server.publishGift(
        ticket,
        identity,
        toUid: contact.serverUid!,
        toUsername: contact.username!,
      );
      await store.markServerStatus(ticket.id, ServerTicketStatus.offered);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent to @${contact.username}.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send right now — try the QR code instead.'),
        ),
      );
    }
  }

  /// Optional "Who is this for?" picker — skipping leaves the gift open to
  /// whoever scans it.
  Future<Contact?> _pickRecipient() {
    final contacts = context.read<ContactStore>().contacts;
    if (contacts.isEmpty) return Future.value();
    return showDialog<Contact?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Who is this for?'),
        children: [
          for (final contact in contacts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(contact),
              child: Text(contact.name),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Skip — I’ll decide when I gift it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiryLabel = _expiresAt == null
        ? 'Expires in 1 year'
        : 'Expires ${DateFormat.yMMMd().format(_expiresAt!)}';

    return Scaffold(
      appBar: AppBar(title: const Text('New promise')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'What do you promise?',
              hintText: "I'll do the dishes",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              avatar: const Icon(Icons.event, size: 18),
              label: Text(expiryLabel),
              onPressed: _pickExpiry,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.card_giftcard),
            label: const Text('Create & gift'),
          ),
        ],
      ),
    );
  }
}
