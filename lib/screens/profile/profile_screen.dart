import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/household_provider.dart';
import '../household/household_screen.dart';
import 'personal_details_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppTheme.surfaceDark : Colors.white;
    final border = isDark ? AppTheme.borderDark : AppTheme.borderLight;
    final primaryText = isDark
        ? AppTheme.textDarkPrimary
        : AppTheme.textLightPrimary;
    final secondaryText = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('No profile available.')));
    }

    return Scaffold(
      backgroundColor: isDark ? AppTheme.bgDark : AppTheme.bgLight,
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          TextButton.icon(
            onPressed: () => _openPersonalDetails(context),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppTheme.heroDarkGradient
                  : AppTheme.heroGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryFlame.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                _ProfileAvatar(user: user),
                const SizedBox(height: 14),
                Text(
                  user.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ProfileSection(
            title: 'Contact information',
            surface: surface,
            border: border,
            primaryText: primaryText,
            children: [
              _DetailRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: user.email,
                secondaryText: secondaryText,
              ),
              _DetailRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: _display(user.phoneNumber),
                secondaryText: secondaryText,
              ),
              _DetailRow(
                icon: Icons.location_on_outlined,
                label: 'Location',
                value: _display(user.location),
                secondaryText: secondaryText,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProfileSection(
            title: 'Household',
            surface: surface,
            border: border,
            primaryText: primaryText,
            children: [
              Consumer<HouseholdProvider>(
                builder: (context, householdProvider, _) => ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(
                    householdProvider.household?.name ?? 'Set up a household',
                  ),
                  subtitle: Text(
                    householdProvider.household == null
                        ? 'Create one or join with an invite code'
                        : '${householdProvider.household!.memberIds.length} member(s)',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HouseholdScreen()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProfileSection(
            title: 'Personal details',
            surface: surface,
            border: border,
            primaryText: primaryText,
            children: [
              _DetailRow(
                icon: Icons.cake_outlined,
                label: 'Date of birth',
                value: user.dateOfBirth == null
                    ? 'Not added yet'
                    : DateFormat('d MMMM yyyy').format(user.dateOfBirth!),
                secondaryText: secondaryText,
              ),
              _DetailRow(
                icon: Icons.restaurant_outlined,
                label: 'Food preference',
                value: _display(user.dietaryPreference),
                secondaryText: secondaryText,
                showDivider: false,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ProfileSection(
            title: 'About me',
            surface: surface,
            border: border,
            primaryText: primaryText,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  _display(user.bio),
                  style: TextStyle(
                    color: secondaryText,
                    height: 1.5,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => _openPersonalDetails(context),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('Edit Personal Details'),
          ),
        ],
      ),
    );
  }

  String _display(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? 'Not added yet' : clean;
  }

  void _openPersonalDetails(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PersonalDetailsScreen()),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final UserModel user;

  const _ProfileAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoUrl?.trim();
    final initials = user.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return CircleAvatar(
      radius: 42,
      backgroundColor: Colors.white.withValues(alpha: 0.2),
      foregroundImage: photoUrl == null || photoUrl.isEmpty
          ? null
          : NetworkImage(photoUrl),
      child: Text(
        initials.isEmpty ? 'C' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final String title;
  final Color surface;
  final Color border;
  final Color primaryText;
  final List<Widget> children;

  const _ProfileSection({
    required this.title,
    required this.surface,
    required this.border,
    required this.primaryText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Text(
              title,
              style: TextStyle(
                color: primaryText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color secondaryText;
  final bool showDivider;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.secondaryText,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.primaryFlame.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: AppTheme.primaryFlame, size: 20),
          ),
          title: Text(
            label,
            style: TextStyle(fontSize: 12, color: secondaryText),
          ),
          subtitle: Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (showDivider) const Divider(indent: 70, endIndent: 16),
      ],
    );
  }
}
