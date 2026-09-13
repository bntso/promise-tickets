import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/ticket.dart';
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

  Future<void> _handle(String raw) async {
    switch (payloadTypeOf(raw)) {
      case PayloadType.gift:
        await _handleGift(raw);
      case PayloadType.redeem:
        await _handleRedeem(raw);
      case null:
        _showError('This QR code is not a Promise Ticket.');
    }
    if (mounted) _busy = false;
  }

  Future<void> _handleGift(String raw) async {
    final store = context.read<TicketStore>();
    final Ticket ticket;
    try {
      ticket = decodeGift(raw);
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept this promise?'),
        content: Text("${ticket.giverName} promises: '${ticket.title}'"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No thanks'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (accepted == true) {
      try {
        await store.importGift(raw);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Promise saved to your wallet.')),
        );
        Navigator.of(context).pop();
      } on FormatException catch (e) {
        _showError(e.message);
      }
    }
  }

  Future<void> _handleRedeem(String raw) async {
    final store = context.read<TicketStore>();
    final RedeemPayload payload;
    try {
      payload = decodeRedeem(raw);
    } on FormatException catch (e) {
      _showError(e.message);
      return;
    }

    final ticket = store.byId(payload.id);
    if (ticket == null || ticket.nonce != payload.nonce) {
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Mark '${ticket.title}' as fulfilled?"),
        content: Text('${payload.holderName} is claiming this promise.'),
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
      appBar: AppBar(title: const Text('Scan a QR code')),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
      ),
    );
  }
}
