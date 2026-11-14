import 'package:flutter/material.dart';

import '../security/pin_service.dart';
import '../widgets/pin_pad.dart';

/// Which job the page is doing.
enum PinSetupMode { set, change, remove }

// The stages of the flow.
enum _Step { verifyCurrent, enterNew, confirmNew }

/// One page for setting, changing and removing the PIN:
///  - set:    choose a PIN, then type it again to confirm
///  - change: prove you know the current PIN, then choose and confirm a new one
///  - remove: prove you know the current PIN, then it is removed
/// Pops with "true" when the job is done.
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key, required this.mode});

  final PinSetupMode mode;

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  late _Step _step;

  // The first entry of a new PIN, kept to compare with the confirmation.
  String _first = '';

  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    // Changing or removing a PIN starts by checking the current one.
    _step = widget.mode == PinSetupMode.set
        ? _Step.enterNew
        : _Step.verifyCurrent;
  }

  String get _appBarTitle {
    switch (widget.mode) {
      case PinSetupMode.set:
        return 'Set PIN';
      case PinSetupMode.change:
        return 'Change PIN';
      case PinSetupMode.remove:
        return 'Remove PIN';
    }
  }

  String get _padTitle {
    switch (_step) {
      case _Step.verifyCurrent:
        return 'Enter your current PIN';
      case _Step.enterNew:
        return 'Choose a $pinLength-digit PIN';
      case _Step.confirmNew:
        return 'Enter it again to confirm';
    }
  }

  Future<void> _onPin(String pin) async {
    switch (_step) {
      case _Step.verifyCurrent:
        await _verifyCurrent(pin);
      case _Step.enterNew:
        setState(() {
          _first = pin;
          _step = _Step.confirmNew;
          _message = null;
          _isError = false;
        });
      case _Step.confirmNew:
        await _confirm(pin);
    }
  }

  Future<void> _verifyCurrent(String pin) async {
    // Uses the same checking (and the same pauses for wrong tries) as the
    // lock screen, so this page cannot be used to guess the PIN freely.
    final result = await PinService.verify(pin);
    if (!mounted) return;

    switch (result.status) {
      case PinStatus.ok:
        if (widget.mode == PinSetupMode.remove) {
          await PinService.removePin();
          if (!mounted) return;
          Navigator.pop(context, true);
        } else {
          setState(() {
            _step = _Step.enterNew;
            _message = null;
            _isError = false;
          });
        }
      case PinStatus.wrong:
        setState(() {
          _isError = true;
          _message = 'Wrong PIN. Try again.';
        });
      case PinStatus.lockedOut:
        final secs = result.retryAfter.inSeconds + 1;
        setState(() {
          _isError = true;
          _message = 'Too many wrong tries. Try again in $secs s.';
        });
    }
  }

  Future<void> _confirm(String pin) async {
    if (pin != _first) {
      // Typed differently the second time: start the new-PIN step again.
      setState(() {
        _first = '';
        _step = _Step.enterNew;
        _isError = true;
        _message = 'The two PINs did not match. Start again.';
      });
      return;
    }

    await PinService.setPin(pin);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_appBarTitle)),
      body: Center(
        child: SingleChildScrollView(
          child: PinPad(
            title: _padTitle,
            message: _message,
            isError: _isError,
            onCompleted: _onPin,
          ),
        ),
      ),
    );
  }
}
