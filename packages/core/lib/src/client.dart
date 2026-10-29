/// Phone-side HTTP client for the Eleen LAN API.
///
/// [EleenClient] is the counterpart to the TV-side [EleenServer] (see
/// `server.dart` for the wire contract). Every request maps server failures
/// onto two exception types the phone UI branches on:
///
/// - [EleenOffline] — the TV could not be reached at all (`SocketException`,
///   e.g. connection refused because the TV app is closed or the device left
///   the network). Drives the "TV offline" UI.
/// - [EleenApiError] — the TV answered with a non-200 status (401 token,
///   403 PIN, 400 validation, 404 unknown id). Carries the status code.
library eleen_core.client;

import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// The TV could not be reached (connection refused / reset mid-request).
class EleenOffline implements Exception {
  const EleenOffline(this.cause);

  final Object cause;

  @override
  String toString() => 'EleenOffline: $cause';
}

/// The TV answered with a non-200 status.
class EleenApiError implements Exception {
  const EleenApiError(this.status, [this.message]);

  final int status;

  /// The server's `error` field, when it sent one.
  final String? message;

  @override
  String toString() =>
      'EleenApiError($status${message == null ? '' : ': $message'})';
}

/// Talks to a TV running [EleenServer] over the LAN.
///
/// Construct with the [base] URI (e.g. `http://192.168.1.5:8477`, from a
/// parsed pairing payload) and optionally a previously stored [token]. A
/// successful [pair] stores the issued token on the instance and uses it for
/// all subsequent requests.
class EleenClient {
  EleenClient({required this.base, String? token}) : _token = token;

  /// Root of the TV server, e.g. `http://192.168.1.5:8477`.
  final Uri base;

  String? _token;

  /// The bearer token to send, either passed to the constructor or obtained
  /// by [pair]. Null until then.
  String? get token => _token;

  /// Exchanges a single-use pairing [nonce] (from the TV's pairing screen,
  /// via `PairingCodec`) for a bearer token, stores it on this client and
  /// returns it.
  Future<String> pair(String nonce) async {
    final body = await _send('POST', _uri('/api/pair'), {'nonce': nonce});
    final token = body['token'];
    if (token is! String) {
      throw EleenApiError(200, 'pair response missing token');
    }
    _token = token;
    return token;
  }

  /// Fetches the current TV state and maps it into the domain [TvState].
  ///
  /// The wire format only carries `activeProfileId`, so a returned
  /// `activeSession` is reconstructed from it: the profile's remaining
  /// seconds and `active: true` (a session is only surfaced as active by the
  /// server when it is in fact active). Its `date` is the phone's today and
  /// carries no wire meaning.
  Future<TvState> state() async {
    final body = await _send('GET', _uri('/api/state'), null);

    final profiles = [
      for (final raw in body['profiles'] as List)
        Profile(
          id: raw['id'] as String,
          name: raw['name'] as String,
          avatar: raw['avatar'] as String,
          allowance:
              AllowanceMinutes.fromMinutes(raw['allowanceMinutes'] as int) ??
              AllowanceMinutes.thirty,
          isParent: raw['isParent'] as bool? ?? false,
        ),
    ];
    final remainingByProfile =
        (body['remainingByProfile'] as Map).cast<String, int>();
    final activeProfileId = body['activeProfileId'] as String?;
    final SessionState? activeSession = activeProfileId == null
        ? null
        : SessionState(
            profileId: activeProfileId,
            date: DateTime.now(),
            remainingSeconds: remainingByProfile[activeProfileId] ?? 0,
            active: true,
          );

    return TvState(
      profiles: profiles,
      activeSession: activeSession,
      masterLockEnabled: body['masterLockEnabled'] as bool,
      parentPinSet: body['parentPinSet'] as bool? ?? false,
      // Absent on older servers — default to granted (fail open, matching
      // the TV's own banner logic).
      overlayPermissionGranted: body['overlayPermissionGranted'] as bool? ?? true,
      remainingByProfile: remainingByProfile,
      usageByProfile: parseUsage(body['usage']),
    );
  }

  /// Parses the optional `usage` block of the state payload. Absent
  /// ([raw] null — an older server) or malformed entries yield an empty
  /// map: usage lines just don't render, nothing throws.
  static Map<String, ProfileUsage> parseUsage(Object? raw) {
    final usage = <String, ProfileUsage>{};
    if (raw is! Map) return usage;
    raw.forEach((profileId, rawUsage) {
      if (profileId is! String || rawUsage is! Map) return;
      final todaySeconds = rawUsage['todaySeconds'];
      final history = <DayUsage>[];
      if (rawUsage['history'] is List) {
        for (final rawDay in rawUsage['history'] as List) {
          if (rawDay is! Map) continue;
          final date = rawDay['date'];
          final seconds = rawDay['seconds'];
          if (date is! String || seconds is! int) continue;
          final parsed = DateTime.tryParse(date);
          if (parsed == null) continue;
          history.add(DayUsage(date: parsed, seconds: seconds));
        }
      }
      usage[profileId] = ProfileUsage(
        todaySeconds: todaySeconds is int ? todaySeconds : 0,
        history: history,
      );
    });
    return usage;
  }

  /// Adds [addSeconds] of session time to [profileId] (PIN-gated).
  Future<void> addTime(String profileId, int addSeconds, String pin) async {
    await _send('POST', _uri('/api/time'), {
      'profileId': profileId,
      'addSeconds': addSeconds,
      'pin': pin,
    });
  }

  /// Overwrites the remaining session seconds of [profileId] (PIN-gated).
  Future<void> overrideTime(
    String profileId,
    int remainingSeconds,
    String pin,
  ) async {
    await _send('PUT', _uri('/api/time/$profileId'), {
      'remainingSeconds': remainingSeconds,
      'pin': pin,
    });
  }

  /// Enables or disables the TV-wide master lock (PIN-gated).
  Future<void> setMasterLock(bool enabled, String pin) async {
    await _send('POST', _uri('/api/lock'), {'enabled': enabled, 'pin': pin});
  }

  /// Sets or changes the parent PIN (`PUT /api/pin`).
  ///
  /// Provisioning route for the pairing phone: while no PIN is set, [pin]
  /// alone provisions it. Once set, [currentPin] must match the current PIN
  /// (a wrong one comes back as 403). [pin] must be exactly 4 characters.
  Future<void> setPin(String pin, {String? currentPin}) async {
    await _send('PUT', _uri('/api/pin'), {
      'pin': pin,
      if (currentPin != null) 'currentPin': currentPin,
    });
  }

  /// Creates or updates a profile (PIN-gated).
  ///
  /// A profile with an empty [Profile.id] is created (`POST /api/profiles`;
  /// the server assigns the id). A non-empty id is patched
  /// (`PATCH /api/profiles/{id}`); if the server does not know that id (404)
  /// the client falls back to creating it.
  Future<void> upsertProfile(Profile p, String pin) async {
    final body = {
      'name': p.name,
      'avatar': p.avatar,
      'allowanceMinutes': p.allowance.minutes,
      'isParent': p.isParent,
      'pin': pin,
    };
    if (p.id.isEmpty) {
      await _send('POST', _uri('/api/profiles'), body);
      return;
    }
    try {
      await _send('PATCH', _uri('/api/profiles/${p.id}'), body);
    } on EleenApiError catch (e) {
      if (e.status != HttpStatus.notFound) rethrow;
      await _send('POST', _uri('/api/profiles'), body);
    }
  }

  Uri _uri(String path) => base.resolve(path);

  /// Performs one JSON round-trip. Returns the decoded response object
  /// (always a JSON object for the routes used here); throws [EleenOffline]
  /// or [EleenApiError] as documented on the library.
  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    Map<String, dynamic>? body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      final token = _token;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();

      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw EleenApiError(response.statusCode, _errorMessage(text));
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw EleenOffline(e);
    } finally {
      client.close(force: true);
    }
  }

  /// Extracts the server's error message from an error body, if it parses
  /// as the expected `{"error": ...}` shape.
  String? _errorMessage(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      // Non-JSON error body; leave the message null.
    }
    return null;
  }
}
