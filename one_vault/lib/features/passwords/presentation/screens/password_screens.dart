import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_fields.dart';
import '../../../../core/widgets/app_filter_chips.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/form_page.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/search_field.dart';
import '../../../../core/widgets/shell_fab.dart';
import '../../../../app/app_state.dart';
import '../../../../shared/enums/enums.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/snack.dart';
import '../../../../shared/models/models.dart';
import '../../data/clipboard_guard.dart';
import '../../data/password_generator.dart';
import '../../data/screen_security.dart';
import '../../data/vault_service.dart';
import '../../data/vault_urls.dart';

class PasswordListScreen extends StatefulWidget {
  const PasswordListScreen({super.key});

  @override
  State<PasswordListScreen> createState() => _PasswordListScreenState();
}

class _PasswordListScreenState extends State<PasswordListScreen> {
  String _query = '';
  PasswordCategory? _category;
  bool _requestedSync = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vault = AppScope.of(context).vault;
    if (_requestedSync || !vault.isUnlocked) return;
    _requestedSync = true;
    unawaited(vault.ensureRemoteSync());
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final vault = state.vault;

    if (!vault.isSetup) {
      return const _VaultSetupScreen();
    }
    if (!vault.isUnlocked) {
      return const _VaultUnlockScreen();
    }

    final items = state.passwords.where((item) {
      final matchesQuery =
          _query.isEmpty ||
          item.title.toLowerCase().contains(_query.toLowerCase()) ||
          item.username.toLowerCase().contains(_query.toLowerCase()) ||
          item.tags.any((tag) => tag.toLowerCase().contains(_query.toLowerCase()));
      final matchesCategory = _category == null || item.category == _category;
      return matchesQuery && matchesCategory;
    }).toList();
    final health = PasswordHealthSummary.from(state.passwords);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Passwords'),
        actions: [
          IconButton(
            tooltip: 'Lock vault',
            onPressed: () => vault.lock(),
            icon: const Icon(Icons.lock_outline),
          ),
          IconButton(
            tooltip: 'Generator',
            onPressed: () => context.push(AppRoutes.passwordGenerator),
            icon: const Icon(Icons.password),
          ),
        ],
      ),
      floatingActionButton: ShellFab(
        heroTag: 'fab-passwords',
        tooltip: 'Add password',
        onPressed: () => context.push(AppRoutes.passwordNew),
      ),
      body: ListView(
        key: const Key('password-list'),
        padding: AppDimensions.pagePaddingFab,
        children: [
          AppSearchField(
            hintText: 'Search passwords',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Password health', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'Weak ${health.weak} · Reused ${health.reused} · Old ${health.old} · Strong ${health.strong}',
                  style: TextStyle(color: AppColors.muted(context), fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppFilterChips<PasswordCategory>(
            value: _category,
            options: PasswordCategory.values,
            labelOf: (category) => category.label,
            onChanged: (value) => setState(() => _category = value),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: EmptyState(
                icon: Icons.lock_outline,
                title: 'No passwords',
                subtitle: 'Add a credential or clear the current filter.',
              ),
            )
          else
            ...items.map(
              (item) => ListTileCard(
                  icon: item.isFavorite ? Icons.star : Icons.lock_outline,
                  title: item.title,
                  subtitle: '${item.username} · ${item.category.label}',
                  trailing: IconButton(
                    tooltip: item.isFavorite ? 'Unfavorite' : 'Favorite',
                    onPressed: () => state.togglePasswordFavorite(item.id),
                    icon: Icon(
                      item.isFavorite ? Icons.star : Icons.star_border,
                      color: item.isFavorite ? AppColors.warning : Colors.grey,
                    ),
                  ),
                  onTap: () => context.push(AppRoutes.passwordDetail(item.id)),
                  margin: AppDimensions.itemSpacing,
                ),
            ),
        ],
      ),
    );
  }
}

class _VaultSetupScreen extends StatefulWidget {
  const _VaultSetupScreen();

  @override
  State<_VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<_VaultSetupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Passwords',
      padding: AppDimensions.pagePaddingAuth,
      children: [
        const EmptyState(
          icon: Icons.lock_outline,
          title: 'Create your vault',
          subtitle:
              'This password encrypts your credentials on this device. It is never sent to the server.',
        ),
        const SizedBox(height: 24),
        AppTextField(
          controller: _password,
          label: 'Vault password',
          obscureText: true,
        ),
        AppDimensions.fieldGap,
        AppTextField(
          controller: _confirm,
          label: 'Confirm vault password',
          obscureText: true,
        ),
        const SizedBox(height: 20),
        AppPrimaryButton(
          label: _busy ? 'Creating…' : 'Create vault',
          loading: _busy,
          onPressed: _setup,
        ),
      ],
    );
  }

  Future<void> _setup() async {
    if (_password.text.trim().length < 6 || _password.text != _confirm.text) {
      showAppSnack(context, 'Passwords must match and be at least 6 characters');
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.of(context).vault.setup(_password.text);
      if (!mounted) return;
      showAppSnack(context, 'Vault ready');
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _VaultUnlockScreen extends StatefulWidget {
  const _VaultUnlockScreen();

  @override
  State<_VaultUnlockScreen> createState() => _VaultUnlockScreenState();
}

class _VaultUnlockScreenState extends State<_VaultUnlockScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final vault = AppScope.of(context).vault;
    return AppPage(
      title: 'Passwords',
      padding: AppDimensions.pagePaddingAuth,
      children: [
        const EmptyState(
          icon: Icons.lock,
          title: 'Vault locked',
          subtitle: 'Unlock to view and use your passwords.',
        ),
        const SizedBox(height: 24),
        if (vault.biometricEnabled) ...[
          AppPrimaryButton(
            label: 'Unlock with device authentication',
            icon: Icons.fingerprint,
            loading: _busy,
            onPressed: _biometric,
          ),
          AppDimensions.fieldGap,
        ],
        AppPrimaryButton(
          label: _busy || vault.unlocking ? 'Unlocking…' : 'Unlock',
          loading: _busy || vault.unlocking,
          onPressed: _unlock,
        ),
      ],
    );
  }

  Future<void> _biometric() async {
    setState(() => _busy = true);
    final ok = await AppScope.of(context).vault.unlockWithBiometric();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) showAppSnack(context, 'Biometric unlock failed');
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).vault.unlock();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class PasswordDetailScreen extends StatefulWidget {
  const PasswordDetailScreen({super.key, required this.id});

  final String id;

  @override
  State<PasswordDetailScreen> createState() => _PasswordDetailScreenState();
}

class _PasswordDetailScreenState extends State<PasswordDetailScreen> {
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    ScreenSecurity.setSecure(true);
  }

  @override
  void dispose() {
    ScreenSecurity.setSecure(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.vault.isUnlocked) {
      return const _VaultUnlockScreen();
    }
    final item = state.vault.byId(widget.id);
    if (item == null) {
      return const AppMissingPage(
        icon: Icons.lock_outline,
        title: 'Not found',
        subtitle: 'This password was removed.',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(item.title),
        actions: [
          IconButton(
            tooltip: item.isFavorite ? 'Unfavorite' : 'Favorite',
            onPressed: () => state.togglePasswordFavorite(item.id),
            icon: Icon(item.isFavorite ? Icons.star : Icons.star_border),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.passwordEdit(item.id)),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: () => _confirmDelete(state, item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: AppDimensions.pagePadding,
        children: [
          InfoRow(label: 'Category', value: item.category.label),
          InfoRow(
            label: 'Username',
            value: item.username,
            action: IconButton(
              onPressed: () => _copy(context, item.username, 'Username copied', secret: false),
              icon: const Icon(Icons.copy),
            ),
          ),
          InfoRow(
            label: 'Password',
            value: _revealed ? item.password : '••••••••••••',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => setState(() => _revealed = !_revealed),
                  icon: Icon(_revealed ? Icons.visibility_off : Icons.visibility),
                ),
                IconButton(
                  onPressed: () => _copy(context, item.password, 'Password copied'),
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
          if (item.website.isNotEmpty)
            InfoRow(
              label: 'Website',
              value: item.website,
              action: IconButton(
                onPressed: () => _openWebsite(item.website),
                icon: const Icon(Icons.open_in_new),
              ),
            ),
          if (item.notes.isNotEmpty) InfoRow(label: 'Notes', value: item.notes),
          if (item.tags.isNotEmpty) InfoRow(label: 'Tags', value: item.tags.join(', ')),
          if (item.recoveryEmail.isNotEmpty)
            InfoRow(label: 'Recovery email', value: item.recoveryEmail),
          if (item.recoveryPhone.isNotEmpty)
            InfoRow(label: 'Recovery phone', value: item.recoveryPhone),
          if (item.twoFactorMethod.isNotEmpty)
            InfoRow(label: '2FA method', value: item.twoFactorMethod),
          if (item.backupCodes.isNotEmpty)
            InfoRow(
              label: 'Backup codes',
              value: _revealed ? item.backupCodes : '••••••••',
            ),
          if (item.securityNotes.isNotEmpty)
            InfoRow(label: 'Security notes', value: item.securityNotes),
          InfoRow(label: 'Updated', value: Formatters.date(item.updatedAt)),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(AppState state, PasswordItem item) async {
    final confirmed = await showAppConfirm(
      context,
      title: 'Delete this password?',
      message: '${item.title} will be removed from OneVault. This cannot be undone.',
    );
    if (!confirmed || !mounted) return;
    await state.deletePassword(item.id);
    if (!mounted) return;
    showAppSnack(context, 'Password deleted');
    context.pop();
  }

  Future<void> _openWebsite(String website) async {
    final uri = VaultUrls.launchUri(website);
    if (uri == null) {
      showAppSnack(context, 'This website cannot be opened');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppSnack(context, 'Could not open website');
  }

  Future<void> _copy(
    BuildContext context,
    String value,
    String message, {
    bool secret = true,
  }) async {
    if (secret) {
      await ClipboardGuard.copySecret(value);
    } else {
      await ClipboardGuard.copySecret(value, ttl: const Duration(minutes: 2));
    }
    if (!context.mounted) return;
    showAppSnack(context, message);
  }
}

class PasswordFormScreen extends StatefulWidget {
  const PasswordFormScreen({super.key, this.id});

  final String? id;

  @override
  State<PasswordFormScreen> createState() => _PasswordFormScreenState();
}

class _PasswordFormScreenState extends State<PasswordFormScreen> {
  final _title = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _website = TextEditingController();
  final _notes = TextEditingController();
  final _tag = TextEditingController();
  final _recoveryEmail = TextEditingController();
  final _recoveryPhone = TextEditingController();
  final _backupCodes = TextEditingController();
  final _securityNotes = TextEditingController();
  PasswordCategory _category = PasswordCategory.other;
  String _twoFactor = '';
  List<String> _tags = [];
  bool _hydrated = false;
  bool _saving = false;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    ScreenSecurity.setSecure(true);
    _password.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hydrated || widget.id == null) return;
    _hydrated = true;
    final existing = AppScope.of(context).vault.byId(widget.id!);
    if (existing == null) return;
    _title.text = existing.title;
    _username.text = existing.username;
    _password.text = existing.password;
    _website.text = existing.website;
    _notes.text = existing.notes;
    _category = existing.category;
    _tags = [...existing.tags];
    _recoveryEmail.text = existing.recoveryEmail;
    _recoveryPhone.text = existing.recoveryPhone;
    _twoFactor = existing.twoFactorMethod;
    _backupCodes.text = existing.backupCodes;
    _securityNotes.text = existing.securityNotes;
  }

  @override
  void dispose() {
    ScreenSecurity.setSecure(false);
    _title.dispose();
    _username.dispose();
    _password.dispose();
    _website.dispose();
    _notes.dispose();
    _tag.dispose();
    _recoveryEmail.dispose();
    _recoveryPhone.dispose();
    _backupCodes.dispose();
    _securityNotes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.id != null;
    final strength = PasswordGenerator.strength(_password.text);
    return FormPage(
      title: isEdit ? 'Edit password' : 'Add password',
      submitting: _saving,
      onSubmit: () => _save(AppScope.of(context)),
      children: [
        AppTextField(controller: _title, label: 'Title'),
        AppDimensions.fieldGap,
        AppTextField(controller: _username, label: 'Username'),
        AppDimensions.fieldGap,
        AppTextField(
          controller: _password,
          label: 'Password',
          obscureText: _hidePassword,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: _hidePassword ? 'Show' : 'Hide',
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                icon: Icon(_hidePassword ? Icons.visibility : Icons.visibility_off),
              ),
              IconButton(
                tooltip: 'Generate',
                onPressed: _useGenerated,
                icon: const Icon(Icons.password),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          PasswordGenerator.label(strength),
          style: TextStyle(
            color: switch (strength) {
              PasswordStrength.strong => AppColors.success,
              PasswordStrength.medium => AppColors.warning,
              PasswordStrength.weak => AppColors.danger,
            },
          ),
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _website, label: 'Website'),
        AppDimensions.fieldGap,
        AppDropdown<PasswordCategory>(
          label: 'Category',
          value: _category,
          items: PasswordCategory.values
              .map((item) => DropdownMenuItem(value: item, child: Text(item.label)))
              .toList(),
          onChanged: (value) => setState(() => _category = value ?? _category),
        ),
        AppDimensions.fieldGap,
        AppTextField(controller: _notes, label: 'Notes', maxLines: 3),
        AppDimensions.sectionGap,
        const Text('Tags', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final tag in _tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => setState(() => _tags.remove(tag)),
              ),
          ],
        ),
        AppTextField(controller: _tag, label: 'Add tag', onSubmitted: _addTag),
        const SizedBox(height: 20),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Recovery & Security'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            AppTextField(controller: _recoveryEmail, label: 'Recovery email'),
            AppDimensions.fieldGap,
            AppTextField(controller: _recoveryPhone, label: 'Recovery phone'),
            AppDimensions.fieldGap,
            AppDropdown<String>(
              label: '2FA method',
              value: _twoFactor,
              items: const [
                DropdownMenuItem(value: '', child: Text('None')),
                DropdownMenuItem(value: 'Authenticator', child: Text('Authenticator')),
                DropdownMenuItem(value: 'SMS', child: Text('SMS')),
                DropdownMenuItem(value: 'Email', child: Text('Email')),
                DropdownMenuItem(value: 'Security key', child: Text('Security key')),
              ],
              onChanged: (value) => setState(() => _twoFactor = value ?? ''),
            ),
            AppDimensions.fieldGap,
            AppTextField(controller: _backupCodes, label: 'Backup codes', maxLines: 3),
            AppDimensions.fieldGap,
            AppTextField(controller: _securityNotes, label: 'Security notes', maxLines: 3),
          ],
        ),
      ],
    );
  }

  void _addTag(String value) {
    final tag = value.trim().toLowerCase();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags = [..._tags, tag];
      _tag.clear();
    });
  }

  Future<void> _useGenerated() async {
    final generated = await context.push<String>(AppRoutes.passwordGenerator);
    if (generated == null || generated.isEmpty || !mounted) return;
    setState(() => _password.text = generated);
  }

  Future<void> _save(AppState state) async {
    if (_title.text.trim().isEmpty || _password.text.trim().isEmpty) {
      showAppSnack(context, 'Title and password are required');
      return;
    }
    if (!state.vault.isUnlocked) {
      showAppSnack(context, 'Unlock the vault first');
      return;
    }
    final website = VaultUrls.normalize(_website.text);
    if (_website.text.trim().isNotEmpty && VaultUrls.launchUri(website) == null) {
      showAppSnack(context, 'Enter a valid http or https website');
      return;
    }
    setState(() => _saving = true);
    try {
      if (widget.id == null) {
        await state.addPassword(
          PasswordItem(
            id: '',
            title: _title.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            website: website,
            category: _category,
            notes: _notes.text.trim(),
            tags: _tags,
            updatedAt: DateTime.now(),
            recoveryEmail: _recoveryEmail.text.trim(),
            recoveryPhone: _recoveryPhone.text.trim(),
            twoFactorMethod: _twoFactor,
            backupCodes: _backupCodes.text.trim(),
            securityNotes: _securityNotes.text.trim(),
            domain: VaultUrls.domain(website),
          ),
        );
      } else {
        final existing = state.vault.byId(widget.id!);
        if (existing == null) return;
        await state.updatePassword(
          existing.copyWith(
            title: _title.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            website: website,
            category: _category,
            notes: _notes.text.trim(),
            tags: _tags,
            updatedAt: DateTime.now(),
            recoveryEmail: _recoveryEmail.text.trim(),
            recoveryPhone: _recoveryPhone.text.trim(),
            twoFactorMethod: _twoFactor,
            backupCodes: _backupCodes.text.trim(),
            securityNotes: _securityNotes.text.trim(),
            domain: VaultUrls.domain(website),
          ),
        );
      }
      if (!mounted) return;
      showAppSnack(context, 'Password saved');
      context.pop();
    } on VaultException catch (error) {
      if (!mounted) return;
      showAppSnack(context, error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class PasswordGeneratorScreen extends StatefulWidget {
  const PasswordGeneratorScreen({super.key});

  @override
  State<PasswordGeneratorScreen> createState() => _PasswordGeneratorScreenState();
}

class _PasswordGeneratorScreenState extends State<PasswordGeneratorScreen> {
  double _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _numbers = true;
  bool _symbols = true;
  bool _excludeAmbiguous = true;
  String _generated = '';

  @override
  void initState() {
    super.initState();
    _generated = _generate();
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordGenerator.strength(_generated);
    return Scaffold(
      appBar: AppBar(title: const Text('Password generator')),
      body: ListView(
        padding: AppDimensions.pagePadding,
        children: [
          SelectableText(
            _generated,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            PasswordGenerator.label(strength),
            style: TextStyle(
              color: switch (strength) {
                PasswordStrength.strong => AppColors.success,
                PasswordStrength.medium => AppColors.warning,
                PasswordStrength.weak => AppColors.danger,
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Length ${_length.round()}'),
          Slider(
            min: 8,
            max: 64,
            divisions: 56,
            value: _length,
            onChanged: (value) => setState(() {
              _length = value;
              _generated = _generate();
            }),
          ),
          SwitchListTile(
            title: const Text('Uppercase'),
            value: _upper,
            onChanged: (value) => _toggle(() => _upper = value),
          ),
          SwitchListTile(
            title: const Text('Lowercase'),
            value: _lower,
            onChanged: (value) => _toggle(() => _lower = value),
          ),
          SwitchListTile(
            title: const Text('Numbers'),
            value: _numbers,
            onChanged: (value) => _toggle(() => _numbers = value),
          ),
          SwitchListTile(
            title: const Text('Symbols'),
            value: _symbols,
            onChanged: (value) => _toggle(() => _symbols = value),
          ),
          SwitchListTile(
            title: const Text('Exclude ambiguous characters'),
            value: _excludeAmbiguous,
            onChanged: (value) => _toggle(() => _excludeAmbiguous = value),
          ),
          const SizedBox(height: 12),
          AppPrimaryButton(
            label: 'Generate',
            onPressed: () => setState(() => _generated = _generate()),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => context.pop(_generated),
            child: const Text('Use password'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () async {
              await ClipboardGuard.copySecret(_generated);
              if (!context.mounted) return;
              showAppSnack(context, 'Generated password copied');
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _toggle(VoidCallback update) {
    setState(() {
      update();
      _generated = _generate();
    });
  }

  String _generate() {
    return PasswordGenerator.generate(
      length: _length.round(),
      upper: _upper,
      lower: _lower,
      numbers: _numbers,
      symbols: _symbols,
      excludeAmbiguous: _excludeAmbiguous,
    );
  }
}
