import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../theme/yele_theme.dart';
import '../widgets/yele_scaffold.dart';

/// Écran « Mon compte » (IMP-03) : connexion, création de compte, profil.
///
/// Le compte reste facultatif, et l'écran le dit d'emblée : personne ne doit
/// croire qu'il faut s'inscrire pour mesurer.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return YeleScaffold(
      title: 'Mon compte',
      route: '/account',
      body: Container(
        color: YeleColors.panel,
        child: ValueListenableBuilder<Account?>(
          valueListenable: AccountService.instance.current,
          builder: (_, account, _) => account == null
              ? const _SignIn()
              : _Profile(account: account),
        ),
      ),
    );
  }
}

// ── Connexion / création ──────────────────────────────────────────────────────

class _SignIn extends StatefulWidget {
  const _SignIn();

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _create = false;
  bool _hidden = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = AccountService.instance;
      final account = _create
          ? await service.register(_email.text, _password.text, _name.text)
          : await service.login(_email.text, _password.text);
      if (mounted) {
        _snack(context, 'Bienvenue, ${account.displayName} !');
      }
    } on AccountException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      children: [
        const _Badge(icon: Icons.person_outline),
        const SizedBox(height: 16),
        const Text('Votre compte Yélé',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: YeleColors.ink)),
        const SizedBox(height: 6),
        const Text(
            'Retrouvez vos mesures sur tous vos appareils.\n'
            'Facultatif : Yélé fonctionne aussi sans compte.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: YeleColors.muted, height: 1.4)),
        const SizedBox(height: 24),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Se connecter')),
            ButtonSegment(value: true, label: Text('Créer un compte')),
          ],
          selected: {_create},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() {
            _create = v.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
          child: Column(
            children: [
              if (_create) ...[
                _field(_name, 'Nom (facultatif)', Icons.badge_outlined,
                    capitalize: true),
                const SizedBox(height: 12),
              ],
              _field(_email, 'Adresse e-mail', Icons.mail_outline,
                  keyboard: TextInputType.emailAddress,
                  validator: (v) => (v ?? '').contains('@')
                      ? null
                      : 'Adresse e-mail invalide'),
              const SizedBox(height: 12),
              _field(_password, 'Mot de passe', Icons.lock_outline,
                  obscure: _hidden,
                  suffix: IconButton(
                    icon: Icon(_hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hidden = !_hidden),
                  ),
                  validator: (v) {
                    if ((v ?? '').isEmpty) return 'Mot de passe requis';
                    if (_create && v!.length < 8) {
                      return '8 caractères minimum';
                    }
                    return null;
                  }),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: YeleColors.danger, fontSize: 14)),
        ],
        const SizedBox(height: 22),
        _PrimaryButton(
          label: _create ? 'Créer mon compte' : 'Se connecter',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// ── Profil ────────────────────────────────────────────────────────────────────

class _Profile extends StatefulWidget {
  final Account account;
  const _Profile({required this.account});

  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  bool _syncing = false;

  Account get a => widget.account;

  @override
  void initState() {
    super.initState();
    AccountService.instance.refresh(); // compteur de mesures à jour
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final added = await AccountService.instance.syncResults();
    await AccountService.instance.refresh();
    if (!mounted) return;
    setState(() => _syncing = false);
    _snack(
        context,
        added == 0
            ? 'Votre historique est à jour.'
            : '$added mesure${added > 1 ? 's' : ''} récupérée${added > 1 ? 's' : ''}.');
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      children: [
        Center(
          child: CircleAvatar(
            radius: 36,
            backgroundColor: YeleColors.primary,
            child: Text(a.initial,
                style: const TextStyle(
                    fontSize: 30,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 14),
        Text(a.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: YeleColors.ink)),
        const SizedBox(height: 2),
        Text(a.email,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: YeleColors.muted)),
        const SizedBox(height: 18),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: YeleColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
                '${a.tests} mesure${a.tests > 1 ? 's' : ''} sur ce compte',
                style: const TextStyle(
                    color: YeleColors.primaryDk,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
        const SizedBox(height: 26),
        _Card(children: [
          _tile(Icons.edit_outlined, 'Modifier le profil',
              () => _editProfile(context, a)),
          _tile(Icons.sync, 'Synchroniser mes mesures', _syncing ? null : _sync,
              trailing: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null),
          _tile(Icons.logout, 'Se déconnecter', () async {
            await AccountService.instance.logout();
            if (context.mounted) _snack(context, 'Vous êtes déconnecté.');
          }),
        ]),
        const SizedBox(height: 12),
        const Text(
            'Chaque mesure faite en étant connecté est rattachée à ce compte. '
            'Déconnecté, l\'historique n\'affiche que les mesures anonymes.',
            style: TextStyle(fontSize: 13, color: YeleColors.muted, height: 1.4)),
        const SizedBox(height: 28),
        Center(
          child: TextButton(
            onPressed: () => _deleteAccount(context),
            style: TextButton.styleFrom(foregroundColor: YeleColors.danger),
            child: const Text('Supprimer mon compte'),
          ),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback? onTap,
      {Widget? trailing}) {
    return ListTile(
      leading: Icon(icon, color: YeleColors.primary),
      title: Text(label,
          style: const TextStyle(fontSize: 15, color: YeleColors.ink)),
      trailing: trailing ??
          const Icon(Icons.chevron_right, color: YeleColors.muted),
      onTap: onTap,
    );
  }
}

// ── Feuilles et dialogues ─────────────────────────────────────────────────────

Future<void> _editProfile(BuildContext context, Account a) async {
  final name = TextEditingController(text: a.name);
  final current = TextEditingController();
  final next = TextEditingController();
  String? error;
  bool busy = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Modifier le profil',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _field(name, 'Nom', Icons.badge_outlined, capitalize: true),
            const SizedBox(height: 18),
            const Text('Changer de mot de passe (facultatif)',
                style: TextStyle(fontSize: 13, color: YeleColors.muted)),
            const SizedBox(height: 8),
            _field(current, 'Mot de passe actuel', Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 12),
            _field(next, 'Nouveau mot de passe', Icons.lock_reset,
                obscure: true),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(error!,
                  style:
                      const TextStyle(color: YeleColors.danger, fontSize: 14)),
            ],
            const SizedBox(height: 18),
            _PrimaryButton(
              label: 'Enregistrer',
              busy: busy,
              onPressed: () async {
                if (next.text.isNotEmpty && next.text.length < 8) {
                  setSheet(() => error =
                      'Le nouveau mot de passe doit faire au moins 8 caractères.');
                  return;
                }
                setSheet(() {
                  busy = true;
                  error = null;
                });
                try {
                  await AccountService.instance.updateProfile(
                    name: name.text,
                    currentPassword: current.text,
                    newPassword: next.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) _snack(context, 'Profil mis à jour.');
                } on AccountException catch (e) {
                  setSheet(() {
                    busy = false;
                    error = e.message;
                  });
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _deleteAccount(BuildContext context) async {
  final password = TextEditingController();
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Vos mesures restent sur la carte de couverture, mais ne sont '
                'plus liées à vous. Elles sont effacées de ce téléphone. '
                'Cette action est définitive.',
                style: TextStyle(height: 1.4)),
            const SizedBox(height: 14),
            _field(password, 'Mot de passe', Icons.lock_outline,
                obscure: true),
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: YeleColors.danger)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: YeleColors.danger),
            onPressed: () async {
              try {
                await AccountService.instance.deleteAccount(password.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) _snack(context, 'Compte supprimé.');
              } on AccountException catch (e) {
                setDialog(() => error = e.message);
              }
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    ),
  );
}

// ── Éléments communs ──────────────────────────────────────────────────────────

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Widget _field(
  TextEditingController controller,
  String label,
  IconData icon, {
  bool obscure = false,
  bool capitalize = false,
  TextInputType? keyboard,
  Widget? suffix,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscure,
    keyboardType: keyboard,
    autocorrect: false,
    textCapitalization:
        capitalize ? TextCapitalization.words : TextCapitalization.none,
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: YeleColors.muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: YeleColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: YeleColors.line),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  final IconData icon;
  const _Badge({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: YeleColors.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 36, color: YeleColors.primary),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: YeleColors.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  const _PrimaryButton(
      {required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: YeleColors.primary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
