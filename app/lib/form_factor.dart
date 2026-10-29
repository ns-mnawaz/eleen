import 'package:device_info_plus/device_info_plus.dart';

/// Which device class the app is running on.
enum FormFactor { tv, phone }

/// Detects the form factor via Android system features.
///
/// A device is treated as a TV when it reports the television hardware type
/// or the leanback software feature; everything else is treated as a phone.
Future<FormFactor> detectFormFactor() async {
  final androidInfo = await DeviceInfoPlugin().androidInfo;
  final features = androidInfo.systemFeatures;
  final isTv = features.contains('android.hardware.type.television') ||
      features.contains('android.software.leanback');
  return isTv ? FormFactor.tv : FormFactor.phone;
}
