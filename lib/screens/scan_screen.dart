import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../models/ticket.dart';
import '../people/contact_store.dart';
import '../qr/payload.dart';
import '../state/ticket_store.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy || capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null) return;
    _busy = true;
    HapticFeedback.mediumImpact();
    _handle(raw);
  }

  Future<void> _pasteFromClipboard() async {
    if (_busy) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim();
    if (raw == null || raw.isEmpty) {
      _showError('The clipboard is empty.');
      return;
    }
    _busy = true;
    await _handle(raw);
  }

  Future<void> _handle(String raw) async {
    try {
      switch (payloadTypeOf(raw)) {
        case PayloadType.id:
          await _handleId(raw);
        case PayloadType.gift:
          await _handleGift(raw);
        case PayloadType.redeem:
          await _handleRedeem(raw);
        case null:
          _showError('This is not a Promise Tickets code.');
      }
    } finally {
      if (mounted) _busy = false;
    }
  }

  Future<void> _handleId(String raw) async {
    final contacts = context.read<ContactStore>();
    final IdentityCard card;
    try {
      card = decodeId(raw);
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${card.name} to your people?'),
        content: Text('Fingerprint: ${card.fingerprint}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted || added != true) return;

    try {
      await contacts.add(name: card.name, publicKeyHex: card.publicKeyHex);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${card.name} added to your people.')),
      );
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _handleGift(String raw) async {
    final store = context.read<TicketStore>();
    final contacts = context.read<ContactStore>();
    final identity = context.read<Identity>();
    final Ticket ticket;
    try {
      ticket = await decodeAnyGift(raw);
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }
    if (!mounted) return;

    final accepted = await _showImportPreview(ticket, contacts);
    if (!mounted || accepted != true) return;

    try {
      await store.importGift(
        raw,
        holderName: identity.name,
        holderPubKey: identity.publicKeyHex,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promise saved to your wallet.')),
      );
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      _showError(e.message);
    }
  }

  /// Import preview: "From: name ✓ verified" for known signers,
  /// "From: self-claimed name — unverified" with an add-contact offer
  /// otherwise.
  Future<bool?> _showImportPreview(Ticket ticket, ContactStore contacts) {
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

  Future<void> _handleRedeem(String raw) async {
    final store = context.read<TicketStore>();
    final contacts = context.read<ContactStore>();
    final RedeemPayload payload;
    try {
      payload = await decodeAnyRedeem(raw);
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }

    final ticket = store.byId(payload.id);
    if (ticket == null ||
        ticket.role != TicketRole.giver ||
        ticket.nonce != payload.nonce) {
      _showError('This ticket is not on this device.');
      return;
    }
    if (ticket.status == TicketStatus.redeemed) {
      _showError('This ticket was already redeemed.');
      return;
    }
    if (ticket.isExpired) {
      _showError('This ticket has expired.');
      return;
    }

    final claimerContact = payload.holderPubKey == null
        ? null
        : contacts.byPubKey(payload.holderPubKey!);
    final claimerLine = claimerContact != null
        ? '${claimerContact.name} ✓ verified is claiming this promise.'
        : "'${payload.holderName}' — unverified — is claiming this promise.";
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Mark '${ticket.title}' as fulfilled?"),
        content: Text(claimerLine),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (confirmed == true) {
      await store.redeem(ticket.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Promise marked as fulfilled.')),
      );
      Navigator.of(context).pop();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a QR code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: 'Paste from clipboard',
            onPressed: _pasteFromClipboard,
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
      ),
    );
  }
}
