import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Schibsted Grotesk',
    ], await rootBundle.loadString('assets/fonts/schibsted-grotesk/OFL.txt'));
    yield LicenseEntryWithLineBreaks(const [
      'Spline Sans Mono',
    ], await rootBundle.loadString('assets/fonts/spline-sans-mono/OFL.txt'));
  });
}
