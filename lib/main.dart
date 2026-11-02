import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'repo.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    initError = e;
  }
  runApp(PurposeMoneyApp(initError: initError));
}

class PurposeMoneyApp extends StatelessWidget {
  const PurposeMoneyApp({super.key, this.initError});
  final Object? initError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Purpose Money',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: initError != null ? _SetupError(initError!) : const AuthGate(),
    );
  }
}

class _SetupError extends StatelessWidget {
  const _SetupError(this.error);
  final Object error;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.settings_outlined, size: 40, color: Brand.green),
              const SizedBox(height: 12),
              Text('Firebase isn\'t set up yet', style: display(24), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
            ]),
          ),
        ),
      );
}

/// Signed out → auth screen. Signed in → profile → onboarding or the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const _Splash();
        final user = snap.data;
        if (user == null) return const AuthScreen();
        return StreamBuilder<Profile>(
          stream: Repo.instance.profile(user.uid),
          builder: (context, p) {
            if (p.hasError) return _SetupError(p.error!);
            if (!p.hasData) return const _Splash();
            final profile = p.data!;
            if (profile.familyId == null || profile.role == null) return OnboardingScreen(profile: profile);
            return HomeShell(key: ValueKey(profile.familyId), profile: profile);
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
