import 'package:drift/native.dart';
import 'package:eleen/form_factor.dart';
import 'package:eleen/main.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/profile_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tv form factor shows the profile picker',
      (WidgetTester tester) async {
    final controller = TvController(
      db: EleenDatabase(NativeDatabase.memory()),
      speedFactor: 1,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      EleenApp(formFactor: FormFactor.tv, tvController: controller),
    );

    expect(find.byType(ProfilePicker), findsOneWidget);
    expect(find.text('Eleen Phone'), findsNothing);
  });

  testWidgets('phone form factor shows the phone home (pairing entry)',
      (WidgetTester tester) async {
    // The default SharedPrefsPairedStore needs mock platform values.
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const EleenApp(formFactor: FormFactor.phone));
    // The real PhoneHome, not the old Task-1 placeholder: pairing entry.
    // Pumps flush the store load into the unpaired UI.
    await tester.pump();
    await tester.pump();
    expect(find.text('Not paired yet'), findsOneWidget);
    expect(find.text('Scan TV code'), findsOneWidget);
    expect(find.text('No profiles yet'), findsNothing);
  });
}
