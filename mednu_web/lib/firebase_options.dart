// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError('Unsupported platform');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBh_sDZlUDbE-u-c_4-sWsT1gxvfTYqoco',
    appId: '1:1056867138858:web:2a2aa821fa4ab4f545b253',
    messagingSenderId: '1056867138858',
    projectId: 'mednu-healthcare-app',
    authDomain: 'mednu-healthcare-app.firebaseapp.com',
    storageBucket: 'mednu-healthcare-app.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBTt8cnzrKMOxMJpAnFgTiZxJSaqxE3aj8',
    appId: '1:1056867138858:android:b16d2368d9e4032645b253',
    messagingSenderId: '1056867138858',
    projectId: 'mednu-healthcare-app',
    storageBucket: 'mednu-healthcare-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDzlSykM7H8c4RRPaDw-ehNSjLTstfKjDA',
    appId: '1:1056867138858:ios:069a23eb3e74c71645b253',
    messagingSenderId: '1056867138858',
    projectId: 'mednu-healthcare-app',
    storageBucket: 'mednu-healthcare-app.firebasestorage.app',
    iosClientId: '1056867138858-nc5t6lvorjjc8qm5bevnqgpfd7ejf492.apps.googleusercontent.com',
    iosBundleId: 'com.example.mednu',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDzlSykM7H8c4RRPaDw-ehNSjLTstfKjDA',
    appId: '1:1056867138858:ios:069a23eb3e74c71645b253',
    messagingSenderId: '1056867138858',
    projectId: 'mednu-healthcare-app',
    storageBucket: 'mednu-healthcare-app.firebasestorage.app',
    iosClientId: '1056867138858-nc5t6lvorjjc8qm5bevnqgpfd7ejf492.apps.googleusercontent.com',
    iosBundleId: 'com.example.mednu',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBh_sDZlUDbE-u-c_4-sWsT1gxvfTYqoco',
    appId: '1:1056867138858:web:67a89f449fe5ef0345b253',
    messagingSenderId: '1056867138858',
    projectId: 'mednu-healthcare-app',
    authDomain: 'mednu-healthcare-app.firebaseapp.com',
    storageBucket: 'mednu-healthcare-app.firebasestorage.app',
  );
}
