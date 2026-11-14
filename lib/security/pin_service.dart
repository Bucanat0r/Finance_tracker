import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------
// SETTINGS YOU MAY WANT TO CHANGE
// ---------------------------------------------------------------------------

/// How many digits the PIN has. If you change this AFTER setting a PIN, the
/// old PIN will no longer be enterable (the keypad would auto-submit at a
/// different length), so remove the PIN first.
const int pinLength = 4;

/// How long the app can be in the background before it asks for the PIN
/// again. Switching to another app for a few seconds (to copy a number, say)
/// should not force you to unlock again.
const Duration relockAfter = Duration(seconds: 30);

/// The outcome of checking a PIN.
enum PinStatus { ok, wrong, lockedOut }

class PinResult {
  const PinResult(
    this.status, {
    this.retryAfter = Duration.zero,
    this.attemptsLeft = 0,
  });

  final PinStatus status;

  /// When locked out: how long until the next try is allowed.
  final Duration retryAfter;

  /// When wrong: how many more wrong tries before a pause starts.
  final int attemptsLeft;
}

/// Stores and checks the PIN.
///
/// WHAT THIS PROTECTS: the PIN is never saved as typed. We save a salted,
/// repeatedly-hashed version, inside Android's secure storage (backed by the
/// Keystore). The wrong-attempt counter lives there too, so closing and
/// reopening the app does not reset it.
///
/// WHAT IT DOES NOT PROTECT: it gates the app's screens. It does not encrypt
/// the database file itself (see the notes after the code).
class PinService {
  // Only static methods, so nobody should create an instance.
  PinService._();

  static const _storage = FlutterSecureStorage();

  // The keys under which things are saved.
  static const _kSalt = 'pin_salt';
  static const _kHash = 'pin_hash';
  static const _kFailed = 'pin_failed_count';
  static const _kLockedUntil = 'pin_locked_until_ms';

  /// After this many wrong tries in a row, a pause starts.
  static const int _freeAttempts = 5;

  // -------------------------------------------------------------------------
  // QUERIES
  // -------------------------------------------------------------------------

  /// True if a PIN has been set.
  static Future<bool> hasPin() async {
    return (await _storage.read(key: _kHash)) != null;
  }

  /// How much of a lockout pause is left (zero if none).
  static Future<Duration> lockoutRemaining() async {
    final until = await _readInt(_kLockedUntil);
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  // -------------------------------------------------------------------------
  // CHANGING THE PIN
  // -------------------------------------------------------------------------

  /// Saves a new PIN (replacing any old one) and clears the attempt counters.
  static Future<void> setPin(String pin) async {
    // A random "salt" is mixed into the hash. It makes the saved value
    // different from anyone else's hash of the same PIN, so precomputed
    // tables of hashed PINs are useless.
    final salt = _randomSalt();
    await _storage.write(key: _kSalt, value: salt);
    await _storage.write(key: _kHash, value: _hash(pin, salt));
    await _resetFailures();
  }

  /// Removes the PIN completely (the app stops asking for one).
  static Future<void> removePin() async {
    await _storage.delete(key: _kSalt);
    await _storage.delete(key: _kHash);
    await _resetFailures();
  }

  // -------------------------------------------------------------------------
  // CHECKING THE PIN
  // -------------------------------------------------------------------------

  /// Checks a typed PIN and keeps count of wrong tries.
  ///
  /// Guessing is slowed down on purpose: after 5 wrong tries in a row you
  /// must wait, and the wait grows with each further miss. With only 10,000
  /// possible 4-digit PINs, this is what stops someone from simply trying
  /// them all.
  static Future<PinResult> verify(String pin) async {
    // 1. Still in a pause from earlier wrong tries? Do not even check.
    final remaining = await lockoutRemaining();
    if (remaining > Duration.zero) {
      return PinResult(PinStatus.lockedOut, retryAfter: remaining);
    }

    // 2. No PIN saved (should not happen): treat as unlocked.
    final salt = await _storage.read(key: _kSalt);
    final saved = await _storage.read(key: _kHash);
    if (salt == null || saved == null) return const PinResult(PinStatus.ok);

    // 3. Correct PIN: forget any earlier wrong tries.
    if (_hash(pin, salt) == saved) {
      await _resetFailures();
      return const PinResult(PinStatus.ok);
    }

    // 4. Wrong PIN: count it, and start a pause if it was one too many.
    final failed = (await _readInt(_kFailed)) + 1;
    await _storage.write(key: _kFailed, value: '$failed');

    final wait = _lockoutFor(failed);
    if (wait > Duration.zero) {
      final until = DateTime.now().add(wait).millisecondsSinceEpoch;
      await _storage.write(key: _kLockedUntil, value: '$until');
      return PinResult(PinStatus.lockedOut, retryAfter: wait);
    }

    return PinResult(
      PinStatus.wrong,
      attemptsLeft: max(0, _freeAttempts - failed),
    );
  }

  // -------------------------------------------------------------------------
  // INTERNAL HELPERS
  // -------------------------------------------------------------------------

  /// How long to pause after [failed] wrong tries in a row.
  static Duration _lockoutFor(int failed) {
    if (failed < _freeAttempts) return Duration.zero;
    switch (failed) {
      case 5:
        return const Duration(seconds: 30);
      case 6:
        return const Duration(minutes: 1);
      case 7:
        return const Duration(minutes: 5);
      default:
        return const Duration(minutes: 15);
    }
  }

  static Future<void> _resetFailures() async {
    await _storage.delete(key: _kFailed);
    await _storage.delete(key: _kLockedUntil);
  }

  static Future<int> _readInt(String key) async {
    return int.tryParse(await _storage.read(key: key) ?? '') ?? 0;
  }

  /// 16 random bytes as text. Random.secure() uses the phone's secure random
  /// source, unlike the plain Random(), which is predictable.
  static String _randomSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }

  /// Turns a PIN into a one-way fingerprint. The same PIN and salt always
  /// give the same result, but you cannot work backwards to the PIN.
  ///
  /// It hashes 10,000 times in a row ("key stretching"), so every single
  /// guess costs an attacker 10,000 times more work than one hash.
  static String _hash(String pin, String salt) {
    List<int> bytes = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64Encode(bytes);
  }
}
