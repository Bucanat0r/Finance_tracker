import 'dart:async';

import 'package:flutter/material.dart';

import '../security/pin_service.dart';
import '../widgets/pin_pad.dart';

/// The full-screen "enter your PIN" page. It is drawn on top of the whole
/// app by AppLockGate, and calls [onUnlocked] when the PIN is correct.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _message;
  bool _isError = false;

  // Set while a pause from too many wrong tries is running.
  DateTime? _lockedUntil;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _resumeLockoutIfAny();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// If the app was closed in the middle of a pause, carry on counting down
  /// instead of letting the pause be skipped by restarting the app.
  Future<void> _resumeLockoutIfAny() async {
    final remaining = await PinService.lockoutRemaining();
    if (remaining > Duration.zero && mounted) _startCountdown(remaining);
  }

  void _startCountdown(Duration duration) {
    _timer?.cancel();
    _lockedUntil = DateTime.now().add(duration);
    _tick(); // Show the first message immediately.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final left = _lockedUntil!.difference(DateTime.now());
    if (left <= Duration.zero) {
      // The pause is over: re-enable the keypad.
      _timer?.cancel();
      setState(() {
        _lockedUntil = null;
        _message = null;
        _isError = false;
      });
      return;
    }
    setState(() {
      _message = 'Too many wrong tries. Try again in ${_format(left)}.';
      _isError = true;
    });
  }

  /// 75 seconds -> "1 min 15 s", 20 seconds -> "20 s".
  String _format(Duration d) {
    final secs = (d.inMilliseconds / 1000).ceil();
    return secs >= 60 ? '${secs ~/ 60} min ${secs % 60} s' : '$secs s';
  }

  Future<void> _check(String pin) async {
    final result = await PinService.verify(pin);
    if (!mounted) return;

    switch (result.status) {
      case PinStatus.ok:
        widget.onUnlocked();
      case PinStatus.wrong:
        final n = result.attemptsLeft;
        setState(() {
          _isError = true;
          _message = n > 0
              ? 'Wrong PIN. $n ${n == 1 ? 'try' : 'tries'} left before a pause.'
              : 'Wrong PIN.';
        });
      case PinStatus.lockedOut:
        _startCountdown(result.retryAfter);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                PinPad(
                  title: 'Enter your PIN',
                  message: _message,
                  isError: _isError,
                  enabled: _lockedUntil == null,
                  onCompleted: _check,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
