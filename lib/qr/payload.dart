import 'dart:convert';

import '../models/ticket.dart';

const String kPayloadVersion = 'PT1';

enum PayloadType { gift, redeem }

class RedeemPayload {
  const RedeemPayload({
    required this.id,
    required this.nonce,
    required this.holderName,
  });

  final String id;
  final String nonce;
  final String holderName;
}

PayloadType? payloadTypeOf(String raw) {
  if (raw.startsWith('$kPayloadVersion:GIFT:')) return PayloadType.gift;
  if (raw.startsWith('$kPayloadVersion:REDEEM:')) return PayloadType.redeem;
  return null;
}

String encodeGift(Ticket ticket) =>
    '$kPayloadVersion:GIFT:${_encode(ticket.toMap())}';

Ticket decodeGift(String raw) {
  if (!raw.startsWith('$kPayloadVersion:GIFT:')) {
    throw const FormatException('This QR code is not a Promise Ticket gift.');
  }
  final ticket = Ticket.fromMap(_decode(raw.substring(9)));
  if (ticket.isExpired) {
    throw const FormatException('This ticket has expired.');
  }
  return ticket;
}

String encodeRedeem(Ticket ticket, String holderName) =>
    '$kPayloadVersion:REDEEM:${_encode({
      'id': ticket.id,
      'nonce': ticket.nonce,
      'holderName': holderName,
    })}';

RedeemPayload decodeRedeem(String raw) {
  if (!raw.startsWith('$kPayloadVersion:REDEEM:')) {
    throw const FormatException('This QR code is not a redemption request.');
  }
  final map = _decode(raw.substring(11));
  final id = map['id'];
  final nonce = map['nonce'];
  final holderName = map['holderName'];
  if (id is! String || id.isEmpty || nonce is! String || nonce.isEmpty) {
    throw const FormatException('This QR code is not valid.');
  }
  return RedeemPayload(
    id: id,
    nonce: nonce,
    holderName: holderName is String && holderName.isNotEmpty
        ? holderName
        : 'Someone',
  );
}

String _encode(Map<String, dynamic> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json)));

Map<String, dynamic> _decode(String data) {
  try {
    final decoded =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(data))));
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    // Fall through to the friendly error below.
  }
  throw const FormatException('This QR code is not valid.');
}
