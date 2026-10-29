import 'package:flutter/material.dart';

import 'form_factor.dart';
import 'phone/phone_home.dart';
import 'state/tv_controller.dart';
import 'tv/lock_overlay.dart';
import 'tv/tv_home.dart';

/// Entry point for the plugin-spawned platform overlay engine
/// (flutter_overlay_window resolves this name from the app's root library
/// only). DISPLAY ONLY: renders reminder toasts and the last-minute badge
/// pushed by the main isolate over the messenger (see
/// tv/overlay_channel.dart). The interactive lock is NOT here — a platform
/// overlay window cannot take TV-remote key input; a lock while
/// backgrounded brings the Eleen activity to the front instead.
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const BackgroundReminderOverlay());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final formFactor = await detectFormFactor();
  runApp(EleenApp(formFactor: formFactor));
}

class EleenApp extends StatelessWidget {
  const EleenApp({super.key, required this.formFactor, this.tvController});

  final FormFactor formFactor;

  /// Optional pre-built TV controller. When null, [TvHome] builds its own
  /// production controller (file-backed database + LAN server). Tests inject
  /// an in-memory one to stay hermetic.
  final TvController? tvController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eleen',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: switch (formFactor) {
        FormFactor.tv => TvHome(controller: tvController),
        FormFactor.phone => const PhoneHome(),
      },
    );
  }
}
