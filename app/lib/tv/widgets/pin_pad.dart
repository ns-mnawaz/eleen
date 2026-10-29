// The TV PIN pad: a D-pad-traversable 0-9 grid for the parent PIN entry.
//
// The grid is laid out 1-2-3 / 4-5-6 / 7-8-9 / 0, so the focus traversal
// order (widget order) is exactly 1..9 then 0. Cell sizes derive from the
// screen via [MediaQuery], never from fixed pixels, and the focused cell
// shows a visible border so the D-pad user can always see where they are.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tv_theme.dart';

/// Digit grid 1-9 then 0; selecting a cell (D-pad enter/Select, or tap)
/// reports the digit through [onDigit].
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    this.autofocus = true,
    this.cellSize,
  });

  final ValueChanged<String> onDigit;

  /// Whether the '1' cell takes focus on first build (so the D-pad works
  /// immediately without a pointer).
  final bool autofocus;

  /// Overrides the natural (width-proportional) cell size. Callers on short
  /// 540p TVs cap the pad's height (see [TvPinPad]) so the surrounding
  /// content stays on-screen; null keeps the natural size.
  final double? cellSize;

  static const List<List<String>> _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['0'],
  ];

  @override
  Widget build(BuildContext context) {
    // All sizes proportional to the screen, never fixed pixels.
    final cell =
        cellSize ?? TvPinPad.naturalCell(MediaQuery.sizeOf(context).width);
    return FocusTraversalGroup(
      key: const Key('pin-pad'),
      // Widget order == the row layout above: 1..9 then 0.
      policy: WidgetOrderTraversalPolicy(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _rows)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final digit in row)
                    _PinKey(
                      key: Key('pin-key-$digit'),
                      digit: digit,
                      size: cell,
                      autofocus: autofocus && digit == '1',
                      onSelected: () => onDigit(digit),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One selectable digit cell: big digit, visible focus border, D-pad/tap
/// activation. Mirrors the profile-picker cell's focus treatment.
class _PinKey extends StatefulWidget {
  const _PinKey({
    super.key,
    required this.digit,
    required this.size,
    required this.autofocus,
    required this.onSelected,
  });

  final String digit;
  final double size;
  final bool autofocus;
  final VoidCallback onSelected;

  @override
  State<_PinKey> createState() => _PinKeyState();
}

class _PinKeyState extends State<_PinKey> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'pin-key-${widget.digit}',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      // D-pad center arrives as Select; accept Enter too for emulators.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: FocusableActionDetector(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onSelected(),
          ),
        },
        child: ListenableBuilder(
          listenable: _focusNode,
          builder: (context, _) {
            final focused = _focusNode.hasFocus;
            final colorScheme = Theme.of(context).colorScheme;
            return Padding(
              padding: EdgeInsets.all(widget.size * 0.06),
              child: Container(
                decoration: BoxDecoration(
                  color: focused
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(widget.size * 0.2),
                  border: Border.all(
                    color: focused ? TvColors.accent : Colors.transparent,
                    width: widget.size * 0.06,
                  ),
                ),
                child: InkWell(
                  onTap: widget.onSelected,
                  // Focus is owned by the FocusableActionDetector above;
                  // the InkWell's internal focus node must not become a
                  // second traversal stop per cell.
                  canRequestFocus: false,
                  borderRadius: BorderRadius.circular(widget.size * 0.2),
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Center(
                      child: Text(
                        widget.digit,
                        style: TextStyle(
                          fontSize: widget.size * 0.5,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
