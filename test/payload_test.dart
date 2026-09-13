import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/models/ticket.dart';
import 'package:promise_tickets/qr/payload.dart';
import 'package:promise_tickets/state/ticket_store.dart';

String b64Json(Map<String, dynamic> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json)));

void main() {
  group('payload codec', () {
    test('GIFT encode/decode round-trips the full ticket', () {
      final ticket = Ticket.create(
        title: "I'll do the dishes",
        note: 'Every night',
        giverName: 'Ricardo',
      );

      final raw = encodeGift(ticket);
      expect(raw, startsWith('PT1:GIFT:'));
      expect(payloadTypeOf(raw), PayloadType.gift);

      final decoded = decodeGift(raw);
      expect(decoded.id, ticket.id);
      expect(decoded.title, ticket.title);
      expect(decoded.note, ticket.note);
      expect(decoded.giverName, ticket.giverName);
      expect(decoded.nonce, ticket.nonce);
    });

    test('REDEEM encode/decode round-trips', () {
      final ticket = Ticket.create(title: 'T', giverName: 'G');

      final raw = encodeRedeem(ticket, 'Alex');
      expect(raw, startsWith('PT1:REDEEM:'));
      expect(payloadTypeOf(raw), PayloadType.redeem);

      final decoded = decodeRedeem(raw);
      expect(decoded.id, ticket.id);
      expect(decoded.nonce, ticket.nonce);
      expect(decoded.holderName, 'Alex');
    });

    test('rejects unknown payload types and wrong prefixes', () {
      expect(payloadTypeOf('PT3:GIFT:abc'), isNull);
      expect(payloadTypeOf('hello world'), isNull);
      expect(
        () => decodeGift('PT2:GIFT:abc'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeRedeem('PT1:GIFT:abc'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed payloads', () {
      expect(
        () => decodeGift('PT1:GIFT:not-valid-base64!!!'),
        throwsA(isA<FormatException>()),
      );
      // Valid base64, but not JSON.
      expect(
        () => decodeGift('PT1:GIFT:aGVsbG8'),
        throwsA(isA<FormatException>()),
      );
      // Valid JSON, but not a ticket map.
      expect(
        () => decodeGift('PT1:GIFT:${b64Json({'foo': 'bar'})}'),
        throwsA(anything),
      );
      expect(
        () => decodeRedeem('PT1:REDEEM:${b64Json({'id': 42})}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects expired tickets on gift decode', () {
      final expired = Ticket.create(
        title: 'T',
        giverName: 'G',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(
        () => decodeGift(encodeGift(expired)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });
  });

  group('duplicate import', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('promise_tickets_test');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('importing the same ticket twice is rejected', () async {
      final box = await Hive.openBox<Map>('tickets_dup');
      final store = TicketStore(box);
      final ticket = Ticket.create(title: 'T', giverName: 'G');
      final raw = encodeGift(ticket);

      await store.importGift(raw);
      expect(
        () => store.importGift(raw),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('already'),
          ),
        ),
      );
    });
  });
}
