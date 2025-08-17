// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../services/services_locator.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  static const String routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBiometricEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    final credentials = await biometricService.getSavedCredentials();
    if (mounted) {
      setState(() {
        _isBiometricEnabled = credentials != null;
        _isLoading = false;
      });
    }
  }

  Future<void> _onBiometricToggle(bool value) async {
    if (value) {
      // Logic to ENABLE biometrics
      final bool canAuthenticate = await biometricService.canAuthenticate();
      if (canAuthenticate && mounted) {
        final password = await _promptForPassword();
        if (password != null) {
          final email = authService.currentUser?.email;
          if (email == null) return;

          // Verify the password before saving
          final result = await authService.login(
            email: email,
            password: password,
          );
          if (result['success']) {
            await biometricService.saveCredentials(email, password);
            setState(() => _isBiometricEnabled = true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Fingerprint Login Enabled!'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Incorrect password. Please try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometric authentication is not available on this device.',
            ),
          ),
        );
      }
    } else {
      // Logic to DISABLE biometrics
      await biometricService.deleteCredentials();
      setState(() => _isBiometricEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fingerprint Login Disabled.')),
      );
    }
  }

  Future<String?> _promptForPassword() {
    final passwordController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Your Password'),
            content: TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(passwordController.text);
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                children: [
                  SwitchListTile(
                    title: const Text('Enable Fingerprint Login'),
                    subtitle: const Text(
                      'Use your fingerprint for quick and secure login.',
                    ),
                    value: _isBiometricEnabled,
                    onChanged: _onBiometricToggle,
                    secondary: const Icon(Icons.fingerprint),
                  ),
                ],
              ),
    );
  }
}
