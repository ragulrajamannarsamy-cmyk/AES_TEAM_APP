import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/user_service.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String? _verificationId;
  bool _busy = false;
  String? _error;

  Future<void> _sendOtp() async {
    final phone = normalizePhone(_phoneCtrl.text);
    if (phone.length != 13) {
      setState(() => _error = 'Enter your 10-digit mobile number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (cred) async {
        // Android can auto-read the SMS and sign in directly.
        await FirebaseAuth.instance.signInWithCredential(cred);
      },
      verificationFailed: (e) => setState(() {
        _busy = false;
        _error = e.message ?? 'Could not send OTP. Try again.';
      }),
      codeSent: (id, _) => setState(() {
        _busy = false;
        _verificationId = id;
      }),
      codeAutoRetrievalTimeout: (id) => _verificationId = id,
    );
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _busy = false;
        _error = e.code == 'invalid-verification-code'
            ? 'Wrong OTP. Check the SMS and try again.'
            : (e.message ?? 'Login failed.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpStage = _verificationId != null;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            const Icon(Icons.bolt, size: 64, color: kAmber),
            const SizedBox(height: 12),
            Text('Aishwarya Engineering Services',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const Text('Team App', textAlign: TextAlign.center),
            const SizedBox(height: 40),
            if (!otpStage) ...[
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91 ',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _sendOtp,
                child: Text(_busy ? 'Sending…' : 'Send OTP'),
              ),
            ] else ...[
              Text('OTP sent to +91 ${_phoneCtrl.text}'),
              const SizedBox(height: 12),
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: '6-digit OTP'),
              ),
              FilledButton(
                onPressed: _busy ? null : _verifyOtp,
                child: Text(_busy ? 'Checking…' : 'Login'),
              ),
              TextButton(
                onPressed: () => setState(() => _verificationId = null),
                child: const Text('Change number'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: kRed)),
            ],
          ],
        ),
      ),
    );
  }
}
