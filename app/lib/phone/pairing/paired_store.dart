/// Persistence for the phone-side pairing result (TV base URI + bearer
/// token), backed by `shared_preferences`.
///
/// The small interface exists so the pairing UI and the upcoming phone
/// controller (Task 13) can be tested with an in-memory fake — the platform
/// channel never runs under `flutter test`.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Stores and retrieves the pairing result: the TV's base URI and the
/// bearer token issued by `POST /api/pair`.
abstract interface class PairedStore {
  /// Persists [base] and [token], replacing any previous pairing.
  Future<void> save(Uri base, String token);

  /// The stored pairing, or null when the phone has never paired (or was
  /// cleared).
  Future<(Uri base, String token)?> load();

  /// Forgets the pairing.
  Future<void> clear();
}

/// [PairedStore] over `shared_preferences`.
class SharedPrefsPairedStore implements PairedStore {
  static const _baseKey = 'eleen.tv_base';
  static const _tokenKey = 'eleen.tv_token';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<void> save(Uri base, String token) async {
    final prefs = await _prefs;
    await prefs.setString(_baseKey, base.toString());
    await prefs.setString(_tokenKey, token);
  }

  @override
  Future<(Uri base, String token)?> load() async {
    final prefs = await _prefs;
    final base = prefs.getString(_baseKey);
    final token = prefs.getString(_tokenKey);
    if (base == null || token == null) return null;
    final parsed = Uri.tryParse(base);
    if (parsed == null) return null;
    return (parsed, token);
  }

  @override
  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove(_baseKey);
    await prefs.remove(_tokenKey);
  }
}
