import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/app_scope.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_dimensions.dart';
import '../../../../core/widgets/app_page.dart';
import '../../../../core/widgets/list_tile_card.dart';
import '../../../../core/widgets/info_row.dart';
import '../../../../shared/helpers/formatters.dart';
import '../../../../shared/helpers/confirm.dart';
import '../../../../shared/helpers/snack.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = AppScope.of(context).profile;
    return AppPage(
      title: 'More',
      children: [
        ListTileCard(
          icon: Icons.person_outline,
          title: profile.name,
          subtitle: profile.email,
          onTap: () => context.push(AppRoutes.profile),
          margin: AppDimensions.itemSpacing,
        ),
        ListTileCard(
          icon: Icons.security_outlined,
          title: 'Security',
          subtitle: 'MPIN and sensitive data',
          onTap: () => context.push(AppRoutes.security),
          margin: AppDimensions.itemSpacing,
        ),
        ListTileCard(
          icon: Icons.settings_outlined,
          title: 'Settings',
          subtitle: 'Theme and preferences',
          onTap: () => context.push(AppRoutes.settings),
          margin: AppDimensions.itemSpacing,
        ),
        ListTileCard(
          icon: Icons.logout,
          title: 'Log out',
          subtitle: 'Sign out of this device',
          onTap: () async {
            final confirmed = await showAppConfirm(
              context,
              title: 'Log out?',
              message: 'You will need to sign in again on this device.',
              confirmLabel: 'Log out',
            );
            if (!confirmed || !context.mounted) return;
            await AppScope.of(context).logout();
          },
          margin: AppDimensions.itemSpacing,
        ),
      ],
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

    return AppPage(
      title: 'Profile',
      children: [
          InfoRow(label: 'Name', value: profile.name),
          InfoRow(label: 'Date of birth', value: Formatters.date(profile.dateOfBirth)),
          InfoRow(label: 'Phone', value: profile.phone),
          InfoRow(label: 'Email', value: profile.email),
          InfoRow(label: 'Address', value: profile.address),
          InfoRow(label: 'Emergency contact', value: profile.emergencyContact),
          InfoRow(label: 'Blood group', value: profile.bloodGroup),
          InfoRow(label: 'Nationality', value: profile.nationality),
          const SizedBox(height: 12),
          Text('Identity', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          InfoRow(label: 'PAN', value: hide ? Formatters.maskId(profile.pan) : profile.pan),
          InfoRow(
            label: 'Aadhaar',
            value: hide ? Formatters.maskId(profile.aadhaar) : profile.aadhaar,
          ),
          InfoRow(
            label: 'Passport',
            value: hide ? Formatters.maskId(profile.passport) : profile.passport,
          ),
          InfoRow(
            label: 'Driving license',
            value: hide ? Formatters.maskId(profile.drivingLicense) : profile.drivingLicense,
          ),
          const SizedBox(height: 12),
          Text('Work', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          InfoRow(label: 'Company', value: profile.company),
          InfoRow(label: 'Employee ID', value: profile.employeeId),
          InfoRow(label: 'Designation', value: profile.designation),
          if (kDebugMode) ...[
            const SizedBox(height: 12),
            Text('Session', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            _CopyableTokenField(token: token),
          ],
        ],
    );
  }
}

class _CopyableTokenField extends StatelessWidget {
  const _CopyableTokenField({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final hasToken = token.isNotEmpty;
    return InfoRow(
      label: 'Token',
      value: hasToken ? token : 'Not signed in',
      action: hasToken
          ? IconButton(
              tooltip: 'Copy token',
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy),
            )
          : null,
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: token));
    if (!context.mounted) return;
    showAppSnack(context, 'Token copied');
  }
}
