import 'package:flutter/material.dart';

import '../services/online_game_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.onlineGameService, super.key});

  final OnlineGameService onlineGameService;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pseudoController = TextEditingController();
  bool _createAccount = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pseudoController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final pseudo = _pseudoController.text.trim();

    if (email.isEmpty || password.length < 6) {
      setState(() {
        _error = 'Entre un email et un mot de passe de 6 caractères minimum.';
      });
      return;
    }
    if (_createAccount && pseudo.length < 3) {
      setState(() => _error = 'Choisis un pseudo de 3 caractères minimum.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_createAccount) {
        await widget.onlineGameService.signUpWithEmail(
          email: email,
          password: password,
          pseudo: pseudo,
        );
      } else {
        await widget.onlineGameService.signInWithEmail(
          email: email,
          password: password,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_createAccount ? 'Créer un compte' : 'Connexion')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _createAccount ? 'Bienvenue dans RueDex.' : 'Retour dans RueDex.',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le compte sert à garder ton équipe, tes rues, ton clan et ta saison synchronisés.',
            ),
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Créer')),
                ButtonSegment(value: false, label: Text('Connexion')),
              ],
              selected: {_createAccount},
              onSelectionChanged: _loading
                  ? null
                  : (values) => setState(() => _createAccount = values.first),
            ),
            const SizedBox(height: 18),
            if (_createAccount) ...[
              TextField(
                controller: _pseudoController,
                enabled: !_loading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Pseudo',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _emailController,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              enabled: !_loading,
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: Icon(Icons.lock_outline),
              ),
              onSubmitted: (_) => _loading ? null : _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_createAccount ? 'Créer mon compte' : 'Me connecter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
