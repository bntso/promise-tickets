import 'dart:convert';

import '../identity/identity.dart';
import '../models/ticket.dart';

const String kPayloadVersion = 'PT1';
const String kPayloadVersionV2 = 'PT2';

enum PayloadType { id, gift, redeem }

class RedeemPayload {
  const RedeemPayload({
    required this.id,
    required this.nonce,
    required this.holderName,
    this.holderPubKey,
  });

  final String id;
  final String nonce;
  final String holderName;

  /// Present in PT2 (signed) redemption requests; null for legacy PT1.
  final String? holderPubKey;
}

class IdentityCard {
  const IdentityCard({required this.name, required this.publicKeyHex});

  final String name;
  final String publicKeyHex;

  String get fingerprint => fingerprintOf(publicKeyHex);
}

PayloadType? payloadTypeOf(String raw) {
  if (raw.startsWith('$kPayloadVersionV2:ID:')) return PayloadType.id;
  if (raw.startsWith('$kPayloadVersion:GIFT:') ||
      raw.startsWith('$kPayloadVersionV2:GIFT:')) {
    return PayloadType.gift;
  }
  if (raw.startsWith('$kPayloadVersion:REDEEM:') ||
      raw.startsWith('$kPayloadVersionV2:REDEEM:')) {
    return PayloadType.redeem;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Identity cards (PT2:ID)
// ---------------------------------------------------------------------------

String encodeId(Identity identity) => '$kPayloadVersionV2:ID:${_encode({
      'name': identity.name,
      'publicKey': identity.publicKeyHex,
    })}';

IdentityCard decodeId(String raw) {
  if (!raw.startsWith('$kPayloadVersionV2:ID:')) {
    throw const FormatException('This is not an identity card.');
  }
  final map = _decode(raw.substring(7));
  final name = map['name'];
  final publicKey = map['publicKey'];
  if (name is! String || name.isEmpty || !_isPubKey(publicKey)) {
    throw const FormatException('This identity card is not valid.');
  }
  return IdentityCard(name: name, publicKeyHex: publicKey as String);
}

// ---------------------------------------------------------------------------
// Gifts — legacy PT1 (unsigned) and PT2 (Ed25519-signed)
// ---------------------------------------------------------------------------

/// Signed fields for a PT2 gift payload (signature covers the canonical JSON
/// of exactly these keys, sorted): createdAt, expiresAt, giverName,
/// giverPubKey, id, nonce, title — plus note, recipientName and
/// recipientPubKey when they are set. The signature field itself is excluded.
Map<String, Object?> _giftSignedFields(Ticket ticket, String giverPubKey) {
  return {
    'id': ticket.id,
    'title': ticket.title,
    if (ticket.note != null) 'note': ticket.note,
    'giverName': ticket.giverName,
    'giverPubKey': giverPubKey,
    'createdAt': ticket.createdAt.toIso8601String(),
    'expiresAt': ticket.expiresAt.toIso8601String(),
    'nonce': ticket.nonce,
    if (ticket.recipientName != null) 'recipientName': ticket.recipientName,
    if (ticket.recipientPubKey != null)
      'recipientPubKey': ticket.recipientPubKey,
  };
}

/// The signed PT2 gift payload as a plain JSON map — the form uploaded to
/// the server (Firestore stores the decoded map, not the base64 string).
Future<Map<String, Object?>> encodeGiftV2Map(
  Ticket ticket,
  Identity identity,
) async {
  final signed = _giftSignedFields(ticket, identity.publicKeyHex);
  final signature = await identity.signHex(utf8.encode(canonicalJson(signed)));
  return {...signed, 'signature': signature};
}

Future<String> encodeGiftV2(Ticket ticket, Identity identity) async =>
    '$kPayloadVersionV2:GIFT:${_encode(await encodeGiftV2Map(ticket, identity))}';

/// Verifies and decodes a PT2 gift already in map form (e.g. read back from
/// the server). Same verification as [decodeGiftV2].
Future<Ticket> decodeGiftV2Map(Map<dynamic, dynamic> map) async {
  final signature = map['signature'];
  final giverPubKey = map['giverPubKey'];
  if (signature is! String || !_isPubKey(giverPubKey)) {
    throw const FormatException('This ticket is missing its signature.');
  }
  final signed = Map<String, Object?>.from(map)..remove('signature');
  final valid = await Identity.verify(
    publicKeyHex: giverPubKey as String,
    message: utf8.encode(canonicalJson(signed)),
    signatureHex: signature,
  );
  if (!valid) {
    throw const FormatException(
      "This ticket's signature doesn't check out — it may have been tampered with.",
    );
  }
  final ticket = Ticket.fromMap({...map, 'role': 'giver', 'status': 'active'});
  if (ticket.isExpired) {
    throw const FormatException('This ticket has expired.');
  }
  return ticket;
}

Future<Ticket> decodeGiftV2(String raw) async {
  if (!raw.startsWith('$kPayloadVersionV2:GIFT:')) {
    throw const FormatException('This QR code is not a Promise Ticket gift.');
  }
  return decodeGiftV2Map(_decode(raw.substring(9)));
}

/// Decodes either a legacy PT1 gift (unsigned, shown as unverified) or a
/// signed PT2 gift (tampering is rejected).
Future<Ticket> decodeAnyGift(String raw) async {
  if (raw.startsWith('$kPayloadVersion:GIFT:')) return decodeGift(raw);
  if (raw.startsWith('$kPayloadVersionV2:GIFT:')) return decodeGiftV2(raw);
  throw const FormatException('This QR code is not a Promise Ticket gift.');
}

// --- Legacy PT1 gifts (kept so tickets created before v2 still work) ---

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

// ---------------------------------------------------------------------------
// Redemption requests — legacy PT1 and signed PT2
// ---------------------------------------------------------------------------

/// Signed fields for a PT2 redemption request: holderName, holderPubKey,
/// id, nonce. The signature field itself is excluded.
Future<String> encodeRedeemV2(Ticket ticket, Identity identity) async {
  final signed = <String, Object?>{
    'id': ticket.id,
    'nonce': ticket.nonce,
    'holderName': identity.name,
    'holderPubKey': identity.publicKeyHex,
  };
  final signature = await identity.signHex(utf8.encode(canonicalJson(signed)));
  return '$kPayloadVersionV2:REDEEM:${_encode({...signed, 'signature': signature})}';
}

Future<RedeemPayload> decodeRedeemV2(String raw) async {
  if (!raw.startsWith('$kPayloadVersionV2:REDEEM:')) {
    throw const FormatException('This QR code is not a redemption request.');
  }
  final map = _decode(raw.substring(11));
  final signature = map['signature'];
  final holderPubKey = map['holderPubKey'];
  if (signature is! String || !_isPubKey(holderPubKey)) {
    throw const FormatException('This claim is missing its signature.');
  }
  final signed = Map<String, Object?>.from(map)..remove('signature');
  final valid = await Identity.verify(
    publicKeyHex: holderPubKey as String,
    message: utf8.encode(canonicalJson(signed)),
    signatureHex: signature,
  );
  if (!valid) {
    throw const FormatException(
      "This claim's signature doesn't check out — it may have been tampered with.",
    );
  }
  final payload = _redeemFromMap(map);
  return RedeemPayload(
    id: payload.id,
    nonce: payload.nonce,
    holderName: payload.holderName,
    holderPubKey: holderPubKey,
  );
}

/// Decodes either a legacy PT1 or a signed PT2 redemption request.
Future<RedeemPayload> decodeAnyRedeem(String raw) async {
  if (raw.startsWith('$kPayloadVersion:REDEEM:')) return decodeRedeem(raw);
  if (raw.startsWith('$kPayloadVersionV2:REDEEM:')) return decodeRedeemV2(raw);
  throw const FormatException('This QR code is not a redemption request.');
}

// --- Legacy PT1 redemption ---

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
  return _redeemFromMap(_decode(raw.substring(11)));
}

RedeemPayload _redeemFromMap(Map<String, dynamic> map) {
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

// ---------------------------------------------------------------------------
// Fulfillment receipts (server flow) — giver-signed proof of fulfillment
// ---------------------------------------------------------------------------

/// Signed fields for a fulfillment receipt: id, nonce, fulfilledAt. The
/// giverPubKey and signature fields themselves are excluded from signing.
Future<Map<String, Object?>> encodeReceipt(
  Ticket ticket,
  Identity identity, {
  DateTime? fulfilledAt,
}) async {
  final signed = <String, Object?>{
    'id': ticket.id,
    'nonce': ticket.nonce,
    'fulfilledAt': (fulfilledAt ?? DateTime.now()).toIso8601String(),
  };
  final signature = await identity.signHex(utf8.encode(canonicalJson(signed)));
  return {
    ...signed,
    'giverPubKey': identity.publicKeyHex,
    'signature': signature,
  };
}

/// Verifies [receipt] against the local [ticket]: id and nonce must match,
/// the giver key must be the ticket's signer, and the signature must check
/// out over the canonical JSON of {id, nonce, fulfilledAt}.
Future<bool> verifyReceipt(Map<dynamic, dynamic> receipt, Ticket ticket) async {
  final id = receipt['id'];
  final nonce = receipt['nonce'];
  final fulfilledAt = receipt['fulfilledAt'];
  final giverPubKey = receipt['giverPubKey'];
  final signature = receipt['signature'];
  if (id != ticket.id || nonce != ticket.nonce) return false;
  if (fulfilledAt is! String || DateTime.tryParse(fulfilledAt) == null) {
    return false;
  }
  if (!_isPubKey(giverPubKey) || signature is! String) return false;
  if (ticket.isSigned && giverPubKey != ticket.giverPubKey) return false;
  final signed = <String, Object?>{
    'id': id,
    'nonce': nonce,
    'fulfilledAt': fulfilledAt,
  };
  return Identity.verify(
    publicKeyHex: giverPubKey as String,
    message: utf8.encode(canonicalJson(signed)),
    signatureHex: signature,
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool _isPubKey(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

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
