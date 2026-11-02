import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../repo.dart';
import '../theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _signUp = true;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String _friendly(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email already has an account. Sign in instead.';
      case 'invalid-email':
        return 'That email address doesn\'t look right.';
      case 'weak-password':
        return 'Use at least 6 characters for your password.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      default:
        return e.message ?? 'Could not sign in.';
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final auth = FirebaseAuth.instance;
    try {
      if (_signUp) {
        final cred = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
        await cred.user!.updateDisplayName(_name.text.trim());
        await Repo.instance.ensureProfile(cred.user!.uid, _name.text.trim(), cred.user!.email);
      } else {
        final cred = await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
        await Repo.instance.ensureProfile(cred.user!.uid, cred.user!.displayName ?? _email.text.split('@').first, cred.user!.email);
      }
    } on FirebaseAuthException catch (e) {
      throw Exception(_friendly(e));
    }
  }

  Future<void> _reset() async {
    if (_email.text.trim().isEmpty) {
      showInfo(context, 'Type your email first.');
      return;
    }
    await FirebaseAuth.instance.sendPasswordResetEmail(email: _email.text.trim());
    if (mounted) showInfo(context, 'Password reset email sent.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Align(alignment: Alignment.centerLeft, child: BrandMark()),
                  const SizedBox(height: 36),
                  Text(_signUp ? 'Money for home, spent the way your family agreed.' : 'Welcome back.', style: display(34)),
                  const SizedBox(height: 12),
                  Text(
                    _signUp ? 'Create your account to start or join a family pot.' : 'Sign in to see your family pot.',
                    style: const TextStyle(color: Brand.muted, fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (_signUp) ...[
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v ?? '').length < 6 ? 'At least 6 characters' : null,
                    onFieldSubmitted: (_) => _submit().catchError((Object e) => showError(context, e)),
                  ),
                  const SizedBox(height: 20),
                  BusyButton(label: _signUp ? 'Create account' : 'Sign in', onPressed: _submit),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _signUp = !_signUp),
                    child: Text(_signUp ? 'I already have an account' : 'New here? Create an account'),
                  ),
                  if (!_signUp) TextButton(onPressed: _reset, child: const Text('Forgot password?')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
