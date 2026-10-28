import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens(this.access, this.refresh);
  final String access;
  final String refresh;
}

/// Minimal key-value contract so tests can run without platform channels.
abstract class SecureKV {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed encrypted storage.
class KeystoreKV implements SecureKV {
  const KeystoreKV();
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKV implements SecureKV {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Tokens live only in encrypted storage (never in plain preferences or logs).
class SessionStore {
  SessionStore([SecureKV? kv]) : _kv = kv ?? const KeystoreKV();

  final SecureKV _kv;
  static const _access = 'rf_access';
  static const _refresh = 'rf_refresh';
  static const _cursor = 'rf_event_cursor';

  Tokens? _cache;

  /// An unreadable store (Keystore key invalidated after a restore/reinstall, or a write interrupted by the OS
  /// killing the app) means "signed out", not a dead-end error screen: the stale entries are dropped and the
  /// driver signs in again.
  Future<Tokens?> read() async {
    if (_cache != null) return _cache;
    try {
      final access = await _kv.read(_access);
      final refresh = await _kv.read(_refresh);
      if (access == null || refresh == null) return null;
      return _cache = Tokens(access, refresh);
    } catch (_) {
      await _dropUnreadable();
      return null;
    }
  }

  Future<void> _dropUnreadable() async {
    for (final key in [_access, _refresh, _cursor]) {
      try {
        await _kv.delete(key);
      } catch (_) {}
    }
  }

  Future<void> save(Tokens tokens) async {
    _cache = tokens;
    await _kv.write(_access, tokens.access);
    await _kv.write(_refresh, tokens.refresh);
  }

  Future<void> clear() async {
    _cache = null;
    await _kv.delete(_access);
    await _kv.delete(_refresh);
    await _kv.delete(_cursor);
  }

  /// Last realtime cursor seen, so a reconnect resumes (replays) instead of missing hints.
  Future<int> readCursor() async {
    try {
      return int.tryParse(await _kv.read(_cursor) ?? '') ?? 0;
    } catch (_) {
      return 0; // resume from the start: the server replays, the client dedupes
    }
  }
  Future<void> saveCursor(int cursor) => _kv.write(_cursor, '$cursor');
}
