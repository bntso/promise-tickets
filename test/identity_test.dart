import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';

void main() {
  group('Identity', () {
    test('generates a keypair on first load and reuses it after', () async {
      final keyStore = MemoryKeyStore();
      final first = await Identity.load(keyStore, name: 'Ricardo');
      expect(first.publicKeyHex, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(first.name, 'Ricardo');

      final second = await Identity.load(keyStore, name: 'Ricardo');
      expect(second.publicKeyHex, first.publicKeyHex);
    });

    test('different stores get different identities', () async {
      final a = await Identity.load(MemoryKeyStore(), name: 'A');
      final b = await Identity.load(MemoryKeyStore(), name: 'B');
      expect(a.publicKeyHex, isNot(b.publicKeyHex));
    });

    test('sign/verify round-trips and rejects wrong message or key',
        () async {
      final identity = await Identity.load(MemoryKeyStore(), name: 'A');
      final message = utf8.encode('promise');
      final signature = await identity.signHex(message);
      expect(signature, matches(RegExp(r'^[0-9a-f]{128}$')));

      expect(
        await Identity.verify(
          publicKeyHex: identity.publicKeyHex,
          message: message,
          signatureHex: signature,
        ),
        isTrue,
      );
      expect(
        await Identity.verify(
          publicKeyHex: identity.publicKeyHex,
          message: utf8.encode('tampered'),
          signatureHex: signature,
        ),
        isFalse,
      );
      final other = await Identity.load(MemoryKeyStore(), name: 'B');
      expect(
        await Identity.verify(
          publicKeyHex: other.publicKeyHex,
          message: message,
          signatureHex: signature,
        ),
        isFalse,
      );
    });

    test('fingerprint is the first 8 hex chars of the public key', () async {
      final identity = await Identity.load(MemoryKeyStore(), name: 'A');
      expect(identity.fingerprint, identity.publicKeyHex.substring(0, 8));
      expect(identity.fingerprint, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('canonicalJson sorts keys', () {
      expect(
        canonicalJson({'b': 1, 'a': 2}),
        '{"a":2,"b":1}',
      );
    });
  });
}
