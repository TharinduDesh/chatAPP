// lib/screens/login_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import '../services/services_locator.dart';
import 'signup_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  static const String routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _canUseBiometrics = false;
  bool _isCheckingBiometrics = true;

  @override
  void initState() {
    super.initState();
    _checkBiometricsOnStartup();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricsOnStartup() async {
    try {
      final bool canAuthenticate = await biometricService.canAuthenticate();
      final credentials = await biometricService.getSavedCredentials();
      if (mounted) {
        setState(() {
          _canUseBiometrics = canAuthenticate && (credentials != null);
          _isCheckingBiometrics = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingBiometrics = false);
      }
    }
  }

  Future<void> _handleBiometricLogin() async {
    try {
      setState(() => _isLoading = true);

      final isAuthenticated = await biometricService.authenticate(
        'Log in using your fingerprint',
      );
      if (!isAuthenticated) return;

      final credentials = await biometricService.getSavedCredentials();
      if (credentials == null) {
        throw Exception("No saved credentials found");
      }

      final result = await authService.login(
        email: credentials['email']!,
        password: credentials['password']!,
      );

      if (!result['success']) {
        throw Exception(result['message'] ?? "Biometric login failed");
      }

      // Initialize services without waiting for socket
      unawaited(initializeServicesOnLogin());

      if (mounted) {
        Navigator.of(context).pushReplacementNamed(HomeScreen.routeName);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Biometric login failed. Use password.";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage!), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!result['success']) {
        throw Exception(result['message'] ?? 'Login failed');
      }

      // Initialize services without waiting for socket
      unawaited(initializeServicesOnLogin());

      if (mounted) {
        Navigator.of(context).pushReplacementNamed(HomeScreen.routeName);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst("Exception: ", "");
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_errorMessage!), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 80,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 20),
                Text(
                  'Welcome Back!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColorDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Login to continue your conversations',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                const SizedBox(height: 40),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!RegExp(
                      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                    ).hasMatch(value)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Your secure password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _loginUser,
                          child: const Text('Login'),
                        ),
                      ),
                      if (_canUseBiometrics) ...[
                        const SizedBox(width: 16),
                        IconButton(
                          icon: Icon(
                            Icons.fingerprint,
                            color: Theme.of(context).primaryColor,
                            size: 36,
                          ),
                          onPressed: _handleBiometricLogin,
                          tooltip: 'Login with Fingerprint',
                        ),
                      ] else if (_isCheckingBiometrics) ...[
                        const SizedBox(width: 16),
                        const SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Text("Don't have an account?"),
                    TextButton(
                      onPressed:
                          () => Navigator.of(
                            context,
                          ).pushReplacementNamed(SignupScreen.routeName),
                      child: Text(
                        'Sign Up',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
