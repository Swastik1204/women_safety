// Aanchal — Auth Screen
//
// Minimal register / login flow.
//   • Register tab: Name + Email + Password → Firebase Auth + Firestore profile.
//   • Login tab:    Email + Password → sign in + fetch profile.
//
// On success, [onAuthSuccess] is called so the root navigator can replace
// this screen with the main app shell.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  /// Called with the signed-in profile after successful auth.
  final void Function(UserProfile profile) onAuthSuccess;

  const AuthScreen({super.key, required this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  String? _error;

  // Register controllers
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();

  // Login controllers
  final _loginEmailCtrl = TextEditingController();
  final _loginPasswordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPasswordCtrl.dispose();
    super.dispose();
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _register() async {
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final password = _regPasswordCtrl.text;

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await AuthService.register(
        firstName: firstName,
        lastName: lastName,
        email: email,
        password: password,
      );
      if (mounted) widget.onAuthSuccess(profile);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim();
    final password = _loginPasswordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await AuthService.login(email: email, password: password);
      if (mounted) widget.onAuthSuccess(profile);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile = await AuthService.signInWithGoogle();
      if (mounted) widget.onAuthSuccess(profile);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code));
    } on PlatformException catch (e) {
      setState(() => _error = _friendlyGooglePlatformError(e));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),

            // Logo / title
            Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.shield, size: 40, color: scheme.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Aanchal',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your safety companion',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Tab bar
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Register'),
                Tab(text: 'Login'),
              ],
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _googleSignIn,
                icon: const Icon(Icons.g_mobiledata_rounded, size: 26),
                label: const Text('Continue with Google'),
              ),
            ),

            // Forms
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _RegisterForm(
                    firstNameCtrl: _firstNameCtrl,
                    lastNameCtrl: _lastNameCtrl,
                    emailCtrl: _regEmailCtrl,
                    passwordCtrl: _regPasswordCtrl,
                    onSubmit: _loading ? null : _register,
                    loading: _loading,
                    error: _tabs.index == 0 ? _error : null,
                  ),
                  _LoginForm(
                    emailCtrl: _loginEmailCtrl,
                    passwordCtrl: _loginPasswordCtrl,
                    onSubmit: _loading ? null : _login,
                    loading: _loading,
                    error: _tabs.index == 1 ? _error : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Register Form ────────────────────────────────────────────────────────────

class _RegisterForm extends StatefulWidget {
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final VoidCallback? onSubmit;
  final bool loading;
  final String? error;

  const _RegisterForm({
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.onSubmit,
    required this.loading,
    this.error,
  });

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            controller: widget.firstNameCtrl,
            label: 'First Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: widget.lastNameCtrl,
            label: 'Last Name',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: widget.emailCtrl,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: widget.passwordCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            _ErrorCard(widget.error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onSubmit,
            child: widget.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create Account'),
          ),
        ],
      ),
    );
  }
}

// ─── Login Form ───────────────────────────────────────────────────────────────

class _LoginForm extends StatefulWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final VoidCallback? onSubmit;
  final bool loading;
  final String? error;

  const _LoginForm({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.onSubmit,
    required this.loading,
    this.error,
  });

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            controller: widget.emailCtrl,
            label: 'Email',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 14),
          _Field(
            controller: widget.passwordCtrl,
            label: 'Password',
            icon: Icons.lock_outline,
            obscure: _obscure,
            suffix: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          if (widget.error != null) ...[
            const SizedBox(height: 12),
            _ErrorCard(widget.error!),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onSubmit,
            child: widget.loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Sign In'),
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Utilities ────────────────────────────────────────────────────────────────

String _friendlyAuthError(String code) {
  switch (code) {
    case 'email-already-in-use':
      return 'An account with this email already exists.';
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'weak-password':
      return 'Password is too weak. Use at least 6 characters.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'network-request-failed':
      return 'No internet connection. Please check your network.';
    case 'too-many-requests':
      return 'Too many attempts. Please try again later.';
    case 'google-sign-in-cancelled':
      return 'Google sign-in was cancelled.';
    default:
      return 'Authentication failed ($code). Please try again.';
  }
}

String _friendlyGooglePlatformError(PlatformException e) {
  final message = '${e.code} ${e.message ?? ''} ${e.details ?? ''}'
      .toLowerCase();
  if (message.contains('apiexception: 10') ||
      message.contains('developer_error')) {
    return 'Google Sign-In is not configured for this Android app yet. Add SHA-1/SHA-256 in Firebase for my.aanchal, download updated google-services.json, then rebuild.';
  }
  if (message.contains('network_error')) {
    return 'Google Sign-In failed due to network error. Please try again.';
  }
  return 'Google Sign-In failed. Please try again.';
}
