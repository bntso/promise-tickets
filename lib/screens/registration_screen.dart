import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../identity/identity.dart';
import '../server/server_service.dart';

/// Pick-a-username flow: checks availability in the directory and claims
/// the name in a transaction. Skippable — the app stays fully usable
/// offline-only.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _available = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final server = context.read<ServerService>();
    final username = _controller.text.trim().toLowerCase();
    final error = ServerService.validateUsername(username);
    if (error != null) {
      setState(() {
        _message = error;
        _available = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final free = await server.isUsernameAvailable(username);
      if (!mounted) return;
      setState(() {
        _available = free;
        _message = free ? '@$username is available!' : 'That username is taken.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not reach the server. Try again later.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim() async {
    final server = context.read<ServerService>();
    final identity = context.read<Identity>();
    final username = _controller.text.trim().toLowerCase();
    setState(() => _busy = true);
    try {
      await server.register(username, identity);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You are @$username!')),
      );
      Navigator.of(context).pop();
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.message;
        _available = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Could not reach the server. Try again later.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pick a username')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'A username lets people find you and send you promises directly '
            '— no QR code needed. You can skip this and keep using the app '
            'offline-only.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              hintText: 'ana_silva',
              prefixText: '@',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_message != null || _available) {
                setState(() {
                  _message = null;
                  _available = false;
                });
              }
            },
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(
              _message!,
              style: TextStyle(
                color: _available
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_available)
            FilledButton.icon(
              onPressed: _claim,
              icon: const Icon(Icons.check),
              label: const Text('Claim this username'),
            )
          else
            FilledButton.tonalIcon(
              onPressed: _check,
              icon: const Icon(Icons.search),
              label: const Text('Check availability'),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now — stay offline-only'),
          ),
        ],
      ),
    );
  }
}
