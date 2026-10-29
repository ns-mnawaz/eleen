// Master-lock toggle for the phone dashboard.
//
// Toggling always asks for the parent PIN and forwards it to the TV
// (`setMasterLock` — the server is the only verifier). While the lock is
// on, the TV blocks every profile; the rows on the dashboard dim
// accordingly.

import 'package:flutter/material.dart';

import '../../state/phone_controller.dart';
import 'pin_dialog.dart';

/// The master-lock switch, listening to [controller].
class MasterLockSwitch extends StatelessWidget {
  const MasterLockSwitch({super.key, required this.controller});

  final PhoneController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final enabled = controller.state?.masterLockEnabled ?? false;
        return SwitchListTile(
          key: const Key('master-lock-switch'),
          title: const Text('Master lock'),
          subtitle: Text(enabled
              ? 'On — the TV is locked for every profile'
              : 'Off — profiles can use their allowance'),
          value: enabled,
          onChanged: (value) {
            // The PIN is optional: with none set on the TV the toggle
            // applies straight away (the empty pin is accepted there).
            PinDialog.run(
              context,
              title: value
                  ? 'Turn the master lock on — enter parent PIN'
                  : 'Turn the master lock off — enter parent PIN',
              pinSet: controller.state?.parentPinSet ?? false,
              onSubmit: (pin) => controller.setMasterLock(value, pin),
            );
          },
        );
      },
    );
  }
}
