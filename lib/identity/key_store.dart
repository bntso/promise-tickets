import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over private-key persistence so tests can use [MemoryKeyStore]
/// instead of the platform secure-storage channel.
abstract class KeyStore {
  Future<String?> readPrivateKeyHex();
  Future<void> writePrivateKeyHex(String hex);
}

class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'promise_tickets_ed25519_private_key';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPrivateKeyHex() => _storage.read(key: _key);

  @override
  Future<void> writePrivateKeyHex(String hex) =>
      _storage.write(key: _key, value: hex);
}

class MemoryKeyStore implements KeyStore {
  String? _value;

  @override
  Future<String?> readPrivateKeyHex() async => _value;

  @override
  Future<void> writePrivateKeyHex(String hex) async => _value = hex;
}
