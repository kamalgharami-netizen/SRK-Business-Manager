import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CloudAuthPage extends StatefulWidget {
  const CloudAuthPage({super.key});

  @override
  State<CloudAuthPage> createState() => _CloudAuthPageState();
}

class _CloudAuthPageState extends State<CloudAuthPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creatingAccount = false;
  bool _busy = false;
  bool _obscurePassword = true;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || !email.contains('@') || password.length < 8) {
      _message('Enter a valid email address and a password of at least 8 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_creatingAccount) {
        final response = await _client.auth.signUp(
          email: email,
          password: password,
        );
        if (!mounted) return;
        if (response.session == null) {
          _message('Account request submitted. Check your email for the confirmation link, then sign in.');
        } else {
          _message('Account created successfully.');
        }
      } else {
        await _client.auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      _message(error.message);
    } catch (error) {
      _message('Unable to complete sign-in: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.business_center, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'SRK Business Manager',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _creatingAccount ? 'Create cloud account' : 'Sign in to your cloud account',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    autofillHints: _creatingAccount
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password (minimum 8 characters)',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_creatingAccount ? 'Create account' : 'Sign in'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _creatingAccount = !_creatingAccount),
                    child: Text(
                      _creatingAccount
                          ? 'Already registered? Sign in'
                          : 'New user? Create an account',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your local device data remains stored separately. Cloud sign-in is used for future company backup and synchronisation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
