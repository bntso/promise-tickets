import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../state/profile.dart';
import 'key_store.dart';

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> hexDecode(String hex) {
  if (hex.length % 2 != 0) {
    throw const FormatException('Invalid hex string.');
  }
  return [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

/// First 8 hex chars of the public key — shown so two people can compare
/// keys in person.
String fingerprintOf(String publicKeyHex) => publicKeyHex.substring(0, 8);

/// Canonical signing bytes: JSON with sorted keys of the signed fields only
/// (the signature field itself is excluded), UTF-8 encoded.
String canonicalJson(Map<String, Object?> fields) {
  final sorted = Map.fromEntries(
    fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  return jsonEncode(sorted);
}

/// The device's Ed25519 identity. Loaded (or generated) once at startup.
class Identity extends ChangeNotifier {
  Identity._(this._keyPair, {required this.name, required this.publicKeyHex});

  final SimpleKeyPair _keyPair;

  /// Display name shown to counterparties (seeded from the profile name).
  String name;

  /// 64-char hex (32-byte Ed25519 public key).
  final String publicKeyHex;

  String get fingerprint => fingerprintOf(publicKeyHex);

  /// Re-reads the display name from the settings box (after a profile edit).
  void refreshName(Box settings) {
    final fresh = profileName(settings);
    if (fresh != name) {
      name = fresh;
      notifyListeners();
    }
  }

  /// Loads the identity from [keyStore], generating and persisting a new
  /// keypair on first launch or upgrade from a version without identities.
  static Future<Identity> load(KeyStore keyStore, {required String name}) async {
    final algorithm = Ed25519();
    final stored = await keyStore.readPrivateKeyHex();
    SimpleKeyPair keyPair;
    if (stored != null && stored.length == 64) {
      try {
        keyPair = await algorithm.newKeyPairFromSeed(hexDecode(stored));
      } on FormatException {
        keyPair = await _generate(algorithm, keyStore);
      }
    } else {
      keyPair = await _generate(algorithm, keyStore);
    }
    final publicKey = await keyPair.extractPublicKey();
    return Identity._(
      keyPair,
      name: name,
      publicKeyHex: hexEncode(publicKey.bytes),
    );
  }

  static Future<SimpleKeyPair> _generate(
    Ed25519 algorithm,
    KeyStore keyStore,
  ) async {
    final keyPair = await algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    await keyStore.writePrivateKeyHex(hexEncode(seed));
    return keyPair;
  }

  /// Signs [message] and returns the 64-byte signature as 128 hex chars.
  Future<String> signHex(List<int> message) async {
    final signature = await Ed25519().sign(message, keyPair: _keyPair);
    return hexEncode(signature.bytes);
  }

  static Future<bool> verify({
    required String publicKeyHex,
    required List<int> message,
    required String signatureHex,
  }) async {
    try {
      final publicKey = SimplePublicKey(
        hexDecode(publicKeyHex),
        type: KeyPairType.ed25519,
      );
      return await Ed25519().verify(
        message,
        signature: Signature(hexDecode(signatureHex), publicKey: publicKey),
      );
    } on FormatException {
      return false;
    }
  }
}
