import 'package:flutter/material.dart';

import '../core/app_state.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.state});

  final AppState state;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _localError;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passCtrl.text;
    final isNew = !widget.state.dbExists;

    if (pass.length < 4) {
      setState(() => _localError = 'Bitte mindestens 4 Zeichen eingeben.');
      return;
    }

    if (isNew && pass != _confirmCtrl.text) {
      setState(() => _localError = 'Die Eingaben stimmen nicht überein.');
      return;
    }

    setState(() => _localError = null);
    final ok = await widget.state.unlockOrCreate(pass);
    if (ok && mounted) {
      _passCtrl.clear();
      _confirmCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final isNew = !widget.state.dbExists;
        final err = _localError ?? widget.state.error;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.lock_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        isNew ? 'Lokalen Tresor einrichten' : 'Entsperren',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isNew
                            ? 'Alle Daten werden ausschließlich lokal und verschlüsselt auf diesem Gerät gespeichert. Es gibt keine Cloud und kein Zurücksetzen der Passphrase.'
                            : 'Gib deine Passphrase oder PIN ein, um die lokale Datenbank zu entschlüsseln.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      TextField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        autofocus: true,
                        textInputAction: isNew
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: isNew ? null : (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Passphrase / PIN',
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (isNew) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirmCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Passphrase / PIN bestätigen',
                          ),
                        ),
                      ],
                      if (err != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          err,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: widget.state.busy ? null : _submit,
                        child: widget.state.busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(isNew ? 'Verschlüsselt anlegen' : 'Öffnen'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
