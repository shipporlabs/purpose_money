// PLACEHOLDER — replace this file by running, inside the app folder:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// FlutterFire CLI writes your project's real keys here for Android, iOS and web.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return _missing('web');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _missing('android');
      case TargetPlatform.iOS:
        return _missing('ios');
      default:
        return _missing(defaultTargetPlatform.name);
    }
  }

  static FirebaseOptions _missing(String platform) {
    throw UnsupportedError(
      'Firebase is not configured for $platform yet. Run "flutterfire configure" in the app folder (see README).',
    );
  }
}
