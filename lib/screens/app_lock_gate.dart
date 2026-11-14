import 'package:flutter/material.dart';

import '../security/pin_service.dart';
import 'lock_screen.dart';

/// Wraps the whole app and puts the lock screen on top when needed:
///  - when the app starts, if a PIN is set
///  - when you come back after being away longer than [relockAfter]
///
/// It is placed ABOVE the app's navigator (see main.dart) so the lock
/// covers everything, including screens and popups you had open.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

// "with WidgetsBindingObserver" lets this class hear about the app going to
// the background and coming back.
class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  // False until we know whether a PIN exists. Until then we show a blank
  // screen instead of the app, so your data never flashes before the lock.
  bool _ready = false;
  bool _locked = false;

  // When the app last went to the background.
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAtStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkAtStartup() async {
    final hasPin = await PinService.hasPin();
    if (!mounted) return;
    setState(() {
      _locked = hasPin;
      _ready = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // The app left the screen: remember when.
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _checkOnReturn();
    }
  }

  Future<void> _checkOnReturn() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;

    // Nothing to do if we were never paused, or we are already locked.
    if (pausedAt == null || _locked) return;

    // Back quickly: stay unlocked.
    if (DateTime.now().difference(pausedAt) < relockAfter) return;

    // Away long enough: lock, but only if a PIN is actually set.
    if (await PinService.hasPin() && mounted) {
      setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // The app stays alive underneath while locked, so unlocking returns
        // you to exactly the screen you were on.
        widget.child,
        if (_locked)
          Positioned.fill(
            child: LockScreen(
              onUnlocked: () => setState(() => _locked = false),
            ),
          ),
      ],
    );
  }
}
