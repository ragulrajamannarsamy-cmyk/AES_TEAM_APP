import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models/app_user.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_registered_screen.dart';
import 'services/user_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AesApp());
}

class AesApp extends StatelessWidget {
  const AesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AES Team',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}

/// Routes to login, "not registered", or the home screen.
/// Staff are identified by their verified phone number (e.g. +919840921142),
/// which is also their document id in the `users` collection.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _Loading();
        }
        final user = authSnap.data;
        if (user == null || user.phoneNumber == null) {
          return const LoginScreen();
        }
        return StreamBuilder<AppUser?>(
          stream: UserService.watch(user.phoneNumber!),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _Loading();
            }
            final appUser = snap.data;
            if (appUser == null || !appUser.active) {
              return NotRegisteredScreen(phone: user.phoneNumber!);
            }
            return HomeScreen(me: appUser);
          },
        );
      },
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
