import 'package:flutter/material.dart';

import '../security/pin_service.dart';

/// A number keypad with dots that fill as you type.
///
/// It is used by the lock screen AND the set/change PIN screens, so the PIN
/// is typed the same way everywhere.
///
/// When the last digit is entered, [onCompleted] is called with the PIN. The
/// pad ignores taps while that runs, then clears itself for the next try.
///
/// NOTE: this widget is also shown ABOVE the app's navigator (on the lock
/// screen), where tooltips do not work, so it deliberately has none.
class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.title,
    required this.onCompleted,
    this.message,
    this.isError = false,
    this.enabled = true,
  });

  final String title;

  /// A line under the dots: an error, a hint, or a countdown.
  final String? message;
  final bool isError;

  /// False while locked out: taps are ignored.
  final bool enabled;

  final Future<void> Function(String pin) onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _digits = '';
  bool _busy = false;

  Future<void> _press(String digit) async {
    if (!widget.enabled || _busy || _digits.length >= pinLength) return;

    setState(() => _digits += digit);

    if (_digits.length == pinLength) {
      // Block more taps while the PIN is being checked.
      _busy = true;
      final pin = _digits;
      await widget.onCompleted(pin);

      // The screen may have closed (for example after a correct PIN).
      if (!mounted) return;
      setState(() {
        _digits = '';
        _busy = false;
      });
    }
  }

  void _backspace() {
    if (!widget.enabled || _busy || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Widget _key(String label) {
    return SizedBox(
      width: 76,
      height: 76,
      child: TextButton(
        style: TextButton.styleFrom(shape: const CircleBorder()),
        onPressed: () => _press(label),
        child: Text(label, style: const TextStyle(fontSize: 28)),
      ),
    );
  }

  Widget _row(List<String> labels) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (final l in labels) _key(l)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = widget.isError ? scheme.error : scheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 20),

        // The dots: filled for each digit typed so far.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < pinLength; i++)
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _digits.length ? dotColor : Colors.transparent,
                  border: Border.all(color: dotColor, width: 2),
                ),
              ),
          ],
        ),

        // Fixed height so the keypad does not jump when a message appears.
        SizedBox(
          height: 48,
          child: Center(
            child: Text(
              widget.message ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isError ? scheme.error : null,
                fontSize: 13,
              ),
            ),
          ),
        ),

        _row(['1', '2', '3']),
        _row(['4', '5', '6']),
        _row(['7', '8', '9']),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 76, height: 76), // Empty slot.
            _key('0'),
            SizedBox(
              width: 76,
              height: 76,
              child: IconButton(
                icon: const Icon(Icons.backspace_outlined),
                onPressed: _backspace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
