import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:promise_tickets/identity/identity.dart';
import 'package:promise_tickets/identity/key_store.dart';
import 'package:promise_tickets/people/contact_store.dart';

void main() {
  late Directory dir;
  var boxCounter = 0;

  Future<ContactStore> newStore() async {
    final box = await Hive.openBox<Map>('contacts_${boxCounter++}');
    return ContactStore(box);
  }

  Future<String> newPubKey() async =>
      (await Identity.load(MemoryKeyStore(), name: 'X')).publicKeyHex;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('promise_tickets_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('add, rename and delete a contact', () async {
    final store = await newStore();
    final pubKey = await newPubKey();

    final contact = await store.add(name: 'Ana', publicKeyHex: pubKey);
    expect(store.contacts.single.name, 'Ana');
    expect(store.byPubKey(pubKey)!.addedAt, contact.addedAt);

    await store.rename(pubKey, 'Ana Maria');
    expect(store.byPubKey(pubKey)!.name, 'Ana Maria');

    await store.delete(pubKey);
    expect(store.contacts, isEmpty);
    expect(store.byPubKey(pubKey), isNull);
  });

  test('duplicate public key is rejected', () async {
    final store = await newStore();
    final pubKey = await newPubKey();

    await store.add(name: 'Ana', publicKeyHex: pubKey);
    expect(
      () => store.add(name: 'Ana again', publicKeyHex: pubKey),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('already'),
        ),
      ),
    );
  });

  test('empty names are rejected and contacts sort by name', () async {
    final store = await newStore();
    final blankKey = await newPubKey();
    expect(
      () => store.add(name: '  ', publicKeyHex: blankKey),
      throwsA(isA<FormatException>()),
    );

    await store.add(name: 'Zoe', publicKeyHex: await newPubKey());
    await store.add(name: 'Ana', publicKeyHex: await newPubKey());
    expect(store.contacts.map((c) => c.name), ['Ana', 'Zoe']);
  });
}
