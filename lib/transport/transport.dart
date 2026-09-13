import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Delivery mechanism for self-contained signed payloads. Payloads carry
/// their own signatures, so transports stay untrusted: a future
/// ServerTransport can relay the same strings without changing trust.
abstract class Transport {
  String get name;
  IconData get icon;

  Future<void> send(BuildContext context, String payload);
}

/// In-person: presents the payload as a QR code for the other device to scan.
class QrTransport implements Transport {
  const QrTransport();

  @override
  String get name => 'Show QR code';

  @override
  IconData get icon => Icons.qr_code;

  @override
  Future<void> send(BuildContext context, String payload) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: payload,
                size: 260,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 16),
              const Text('Let them scan this code.'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Remote without a server: hands the payload text to any messenger the
/// user picks (WhatsApp, SMS, ...); the recipient pastes it in the app.
class LinkTransport implements Transport {
  const LinkTransport();

  @override
  String get name => 'Send as link';

  @override
  IconData get icon => Icons.share;

  @override
  Future<void> send(BuildContext context, String payload) {
    return SharePlus.instance.share(ShareParams(text: payload));
  }
}
