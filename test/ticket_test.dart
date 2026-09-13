import 'package:flutter_test/flutter_test.dart';
import 'package:promise_tickets/models/ticket.dart';

void main() {
  group('Ticket', () {
    test('toMap/fromMap round-trips', () {
      final ticket = Ticket.create(
        title: "I'll do the dishes",
        note: 'After dinner',
        giverName: 'Ricardo',
        now: DateTime(2026, 9, 13),
      );

      final restored = Ticket.fromMap(ticket.toMap());

      expect(restored.id, ticket.id);
      expect(restored.title, ticket.title);
      expect(restored.note, ticket.note);
      expect(restored.giverName, ticket.giverName);
      expect(restored.createdAt, ticket.createdAt);
      expect(restored.expiresAt, ticket.expiresAt);
      expect(restored.status, ticket.status);
      expect(restored.nonce, ticket.nonce);
      expect(restored.role, ticket.role);
    });

    test('note is nullable', () {
      final ticket = Ticket.create(title: 'T', giverName: 'G');
      expect(ticket.note, isNull);
      expect(Ticket.fromMap(ticket.toMap()).note, isNull);
    });

    test('expires one year after creation by default', () {
      final created = DateTime(2026, 9, 13, 10, 30);
      final ticket = Ticket.create(title: 'T', giverName: 'G', now: created);
      expect(ticket.createdAt, created);
      expect(ticket.expiresAt, DateTime(2027, 9, 13));
    });

    test('nonce is a 32-char hex string and unique per ticket', () {
      final a = Ticket.create(title: 'T', giverName: 'G');
      final b = Ticket.create(title: 'T', giverName: 'G');
      expect(a.nonce, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(a.nonce, isNot(b.nonce));
      expect(a.id, isNot(b.id));
    });

    test('isExpired is false before expiry and true after', () {
      final future = Ticket.create(
        title: 'T',
        giverName: 'G',
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      final past = Ticket.create(
        title: 'T',
        giverName: 'G',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(future.isExpired, isFalse);
      expect(past.isExpired, isTrue);
    });
  });
}
