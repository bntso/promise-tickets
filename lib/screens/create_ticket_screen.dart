import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/profile.dart';
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
    final giverName = profileName(context.read<Box>());
    final ticket = await store.create(
      title: _titleController.text,
      note: _noteController.text,
      giverName: giverName,
      expiresAt: _expiresAt,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => GiftQrScreen(ticket: ticket)),
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
