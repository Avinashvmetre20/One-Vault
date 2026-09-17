import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../core/widgets/hub_card.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/snack.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).profile;
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          HubCard(
            icon: Icons.person_outline,
            title: profile.name,
            subtitle: profile.email,
            onTap: () => context.push(AppRoutes.profile),
          ),
          HubCard(
            icon: Icons.security_outlined,
            title: 'Security',
            subtitle: 'PIN and sensitive data',
            onTap: () => context.push(AppRoutes.security),
          ),
          HubCard(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Theme and preferences',
            onTap: () => context.push(AppRoutes.settings),
          ),
          HubCard(
            icon: Icons.logout,
            title: 'Log out',
            subtitle: 'Sign out of this device',
            onTap: () async {
              await AppScope.of(context).logout();
            },
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final profile = state.profile;
    final hide = state.security.hideSensitiveData;
    final token = state.accessToken?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _Field(label: 'Name', value: profile.name),
          _Field(label: 'Date of birth', value: Formatters.date(profile.dateOfBirth)),
          _Field(label: 'Phone', value: profile.phone),
          _Field(label: 'Email', value: profile.email),
          _Field(label: 'Address', value: profile.address),
          _Field(label: 'Emergency contact', value: profile.emergencyContact),
          _Field(label: 'Blood group', value: profile.bloodGroup),
          _Field(label: 'Nationality', value: profile.nationality),
          const SizedBox(height: 12),
          Text('Identity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _Field(label: 'PAN', value: hide ? Formatters.maskId(profile.pan) : profile.pan),
          _Field(
            label: 'Aadhaar',
            value: hide ? Formatters.maskId(profile.aadhaar) : profile.aadhaar,
          ),
          _Field(
            label: 'Passport',
            value: hide ? Formatters.maskId(profile.passport) : profile.passport,
          ),
          _Field(
            label: 'Driving license',
            value: hide ? Formatters.maskId(profile.drivingLicense) : profile.drivingLicense,
          ),
          const SizedBox(height: 12),
          Text('Work', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _Field(label: 'Company', value: profile.company),
          _Field(label: 'Employee ID', value: profile.employeeId),
          _Field(label: 'Designation', value: profile.designation),
          const SizedBox(height: 12),
          Text('Session', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _CopyableTokenField(token: token),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      ),
    );
  }
}

class _CopyableTokenField extends StatelessWidget {
  const _CopyableTokenField({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final hasToken = token.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: hasToken ? () => _copy(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Token', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      hasToken ? token : 'Not signed in',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ],
                ),
              ),
              if (hasToken)
                IconButton(
                  tooltip: 'Copy token',
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: token));
    if (!context.mounted) return;
    showAppSnack(context, 'Token copied');
  }
}
