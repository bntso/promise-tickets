import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'contact.dart';

class ContactStore extends ChangeNotifier {
  ContactStore(this._box);

  final Box<Map> _box;

  List<Contact> get contacts {
    final list = _box.values.map(Contact.fromMap).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Contact? byPubKey(String publicKeyHex) {
    final map = _box.get(publicKeyHex);
    return map == null ? null : Contact.fromMap(map);
  }

  Future<Contact> add({
    required String name,
    required String publicKeyHex,
    ContactSource source = ContactSource.scanned,
    String? username,
    String? serverUid,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Please enter a name.');
    }
    if (_box.containsKey(publicKeyHex)) {
      throw const FormatException('This person is already in your contacts.');
    }
    final contact = Contact(
      name: trimmed,
      publicKeyHex: publicKeyHex,
      addedAt: DateTime.now(),
      source: source,
      username: username,
      serverUid: serverUid,
    );
    await _box.put(publicKeyHex, contact.toMap());
    notifyListeners();
    return contact;
  }

  /// Upgrades a directory-sourced contact to "verified in person" once their
  /// card has been scanned face-to-face.
  Future<void> markScanned(String publicKeyHex) async {
    final contact = byPubKey(publicKeyHex);
    if (contact == null || contact.source == ContactSource.scanned) return;
    await _box.put(
      publicKeyHex,
      contact.copyWith(source: ContactSource.scanned).toMap(),
    );
    notifyListeners();
  }

  Future<void> rename(String publicKeyHex, String newName) async {
    final contact = byPubKey(publicKeyHex);
    if (contact == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    await _box.put(publicKeyHex, contact.copyWith(name: trimmed).toMap());
    notifyListeners();
  }

  Future<void> delete(String publicKeyHex) async {
    await _box.delete(publicKeyHex);
    notifyListeners();
  }
}
