import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';
import 'package:promise_tickets/models/ticket.dart';
import 'package:promise_tickets/qr/payload.dart';

Map<String, dynamic> _decodePayload(String raw, String prefix) {
  return Map<String, dynamic>.from(
    jsonDecode(
      utf8.decode(base64Url.decode(raw.substring(prefix.length))),
    ) as Map,
  );
}

String _encodePayload(String prefix, Map<String, dynamic> map) =>
    '$prefix${base64Url.encode(utf8.encode(jsonEncode(map)))}';

void main() {
  late Identity giver;
  late Identity holder;

  setUp(() async {
    giver = await Identity.load(MemoryKeyStore(), name: 'Ricardo');
    holder = await Identity.load(MemoryKeyStore(), name: 'Ana');
  });

  group('PT2:ID', () {
    test('encode/decode round-trips', () {
      final raw = encodeId(giver);
      expect(raw, startsWith('PT2:ID:'));
      expect(payloadTypeOf(raw), PayloadType.id);

      final card = decodeId(raw);
      expect(card.name, 'Ricardo');
      expect(card.publicKeyHex, giver.publicKeyHex);
      expect(card.fingerprint, giver.fingerprint);
    });

    test('rejects malformed cards', () {
      expect(() => decodeId('PT2:ID:not-base64!!!'),
          throwsA(isA<FormatException>()));
      expect(
        () => decodeId(_encodePayload('PT2:ID:', {'name': 'NoKey'})),
        throwsA(isA<FormatException>()),
      );
      expect(() => decodeId('PT1:ID:abc'), throwsA(isA<FormatException>()));
    });
  });

  group('PT2:GIFT', () {
    test('sign → verify round-trips all fields', () async {
      final ticket = Ticket.create(
        title: "I'll do the dishes",
        note: 'Every night',
        giverName: 'Ricardo',
        giverPubKey: giver.publicKeyHex,
        recipientName: 'Ana',
        recipientPubKey: holder.publicKeyHex,
      );

      final raw = await encodeGiftV2(ticket, giver);
      expect(raw, startsWith('PT2:GIFT:'));
      expect(payloadTypeOf(raw), PayloadType.gift);

      final decoded = await decodeAnyGift(raw);
      expect(decoded.id, ticket.id);
      expect(decoded.title, ticket.title);
      expect(decoded.note, ticket.note);
      expect(decoded.giverName, 'Ricardo');
      expect(decoded.giverPubKey, giver.publicKeyHex);
      expect(decoded.recipientName, 'Ana');
      expect(decoded.recipientPubKey, holder.publicKeyHex);
      expect(decoded.nonce, ticket.nonce);
      expect(decoded.signature, isNotNull);
      expect(decoded.isSigned, isTrue);
    });

    test('a tampered field invalidates the signature', () async {
      final ticket = Ticket.create(
        title: 'Do the dishes',
        giverName: 'Ricardo',
      );
      final raw = await encodeGiftV2(ticket, giver);

      final map = _decodePayload(raw, 'PT2:GIFT:');
      map['title'] = 'Do NOTHING';
      final tampered = _encodePayload('PT2:GIFT:', map);

      await expectLater(
        decodeAnyGift(tampered),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('tampered'),
          ),
        ),
      );
    });

    test('a signature made by a different key is rejected', () async {
      final ticket = Ticket.create(title: 'T', giverName: 'Ricardo');
      final raw = await encodeGiftV2(ticket, giver);

      final map = _decodePayload(raw, 'PT2:GIFT:');
      map['giverPubKey'] = holder.publicKeyHex; // signed by giver, claims holder
      final forged = _encodePayload('PT2:GIFT:', map);

      await expectLater(
        decodeAnyGift(forged),
        throwsA(isA<FormatException>()),
      );
    });

    test('a PT2 gift without a signature is rejected', () async {
      final ticket = Ticket.create(title: 'T', giverName: 'Ricardo');
      final raw = await encodeGiftV2(ticket, giver);
      final map = _decodePayload(raw, 'PT2:GIFT:')..remove('signature');

      await expectLater(
        decodeAnyGift(_encodePayload('PT2:GIFT:', map)),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy PT1 gifts still decode, unverified', () async {
      final legacy = Ticket.create(title: 'Old promise', giverName: 'Ricardo');
      final decoded = await decodeAnyGift(encodeGift(legacy));

      expect(decoded.id, legacy.id);
      expect(decoded.signature, isNull);
      expect(decoded.isSigned, isFalse);
    });

    test('expired PT2 gifts are rejected', () async {
      final expired = Ticket.create(
        title: 'T',
        giverName: 'G',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      await expectLater(
        decodeAnyGift(await encodeGiftV2(expired, giver)),
        throwsA(
          isA<FormatException>()
              .having((e) => e.message, 'message', contains('expired')),
        ),
      );
    });
  });

  group('PT2:REDEEM', () {
    test('sign → verify round-trips', () async {
      final ticket = Ticket.create(title: 'T', giverName: 'Ricardo');
      final raw = await encodeRedeemV2(ticket, holder);

      expect(raw, startsWith('PT2:REDEEM:'));
      expect(payloadTypeOf(raw), PayloadType.redeem);

      final decoded = await decodeAnyRedeem(raw);
      expect(decoded.id, ticket.id);
      expect(decoded.nonce, ticket.nonce);
      expect(decoded.holderName, 'Ana');
      expect(decoded.holderPubKey, holder.publicKeyHex);
    });

    test('a tampered nonce is rejected', () async {
      final ticket = Ticket.create(title: 'T', giverName: 'Ricardo');
      final raw = await encodeRedeemV2(ticket, holder);

      final map = _decodePayload(raw, 'PT2:REDEEM:');
      map['nonce'] = 'f' * 32;
      await expectLater(
        decodeAnyRedeem(_encodePayload('PT2:REDEEM:', map)),
        throwsA(isA<FormatException>()),
      );
    });

    test('legacy PT1 redemption still decodes, without a key', () async {
      final ticket = Ticket.create(title: 'T', giverName: 'Ricardo');
      final decoded = await decodeAnyRedeem(encodeRedeem(ticket, 'Ana'));

      expect(decoded.id, ticket.id);
      expect(decoded.holderName, 'Ana');
      expect(decoded.holderPubKey, isNull);
    });
  });
}
