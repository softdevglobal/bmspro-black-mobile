// File generated manually - configuration for bmspro-black Firebase project
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAgrG7oHTHu_hocI7S7FfwslA7M6sIZ6Gc',
    appId: '1:807442450614:web:539a7034e62d1d3f60fe17',
    messagingSenderId: '807442450614',
    projectId: 'bmspro-black',
    authDomain: 'bmspro-black.firebaseapp.com',
    storageBucket: 'bmspro-black.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAgrG7oHTHu_hocI7S7FfwslA7M6sIZ6Gc',
    appId: '1:807442450614:android:539a7034e62d1d3f60fe17',
    messagingSenderId: '807442450614',
    projectId: 'bmspro-black',
    storageBucket: 'bmspro-black.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCMGI_tsXhwwFBi_p-wBIVG4TG_VYYAlbU',
    appId: '1:807442450614:ios:f83c91754b091d9a60fe17',
    messagingSenderId: '807442450614',
    projectId: 'bmspro-black',
    storageBucket: 'bmspro-black.firebasestorage.app',
    iosBundleId: 'bmspro.black',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCMGI_tsXhwwFBi_p-wBIVG4TG_VYYAlbU',
    appId: '1:807442450614:ios:f83c91754b091d9a60fe17',
    messagingSenderId: '807442450614',
    projectId: 'bmspro-black',
    storageBucket: 'bmspro-black.firebasestorage.app',
    iosBundleId: 'bmspro.black',
  );
}
