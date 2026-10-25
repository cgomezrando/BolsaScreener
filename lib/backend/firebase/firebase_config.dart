import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

Future initFirebase() async {
  if (kIsWeb) {
    await Firebase.initializeApp(
        options: FirebaseOptions(
            apiKey: "AIzaSyClLiyaUjnDUe0v65jE-ShBUsz0zm7MD3o",
            authDomain: "bolsascreener.firebaseapp.com",
            projectId: "bolsascreener",
            storageBucket: "bolsascreener.firebasestorage.app",
            messagingSenderId: "426840025292",
            appId: "1:426840025292:web:b8cf17e50f385c29cffa69",
            measurementId: "G-HQD9L3BKHB"));
  } else {
    await Firebase.initializeApp();
  }
}
