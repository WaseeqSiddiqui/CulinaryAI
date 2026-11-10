import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../widgets/app_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/household_provider.dart';

class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final provider = context.read<HouseholdProvider>();
    final success = await provider.create(_nameController.text);
    if (!mounted) return;
    _showResult(success, provider.errorMessage);
  }

  Future<void> _join() async {
    final provider = context.read<HouseholdProvider>();
    final success = await provider.join(_codeController.text);
    if (!mounted) return;
    _showResult(success, provider.errorMessage);
  }

  void _showResult(bool success, String? error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Household connected.' : error ?? 'Try again.'),
      ),
    );
  }

  Future<void> _rename(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename household'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Household name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    final provider = context.read<HouseholdProvider>();
    _showResult(await provider.rename(name), provider.errorMessage);
  }

  Future<void> _regenerateInvite() async {
    final provider = context.read<HouseholdProvider>();
    _showResult(await provider.regenerateInvite(), provider.errorMessage);
  }

  Future<void> _manageMember(String memberId, String currentRole) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(
                currentRole == 'admin' ? 'Make member' : 'Make admin',
              ),
              onTap: () => Navigator.pop(
                context,
                currentRole == 'admin' ? 'member' : 'admin',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('Remove member'),
              textColor: AppTheme.errorRed,
              iconColor: AppTheme.errorRed,
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final provider = context.read<HouseholdProvider>();
    final success = action == 'remove'
        ? await provider.removeMember(memberId)
        : await provider.setMemberRole(memberId, action);
    if (!mounted) return;
    _showResult(success, provider.errorMessage);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HouseholdProvider>();
    final household = provider.household;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your household')),
      body: provider.isLoading && household == null
          ? const Center(child: CircularProgressIndicator())
          : AppPageBody(
              maxWidth: 760,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                children: [
                  PageIntro(
                    eyebrow: 'BETTER, TOGETHER',
                    title: household == null
                        ? 'One kitchen. Your people.'
                        : 'A kitchen you share.',
                    subtitle: household == null
                        ? 'Share a pantry with the people you cook for. Keep everyone on the same page.'
                        : 'Your household, its members and the ingredients you share.',
                  ),
                  const SizedBox(height: 26),
                  if (household != null) ...[
                    SurfacePanel(
                      color: colors.primaryContainer,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cottage_outlined,
                            color: colors.primary,
                            size: 28,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            household.name,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${household.memberIds.length} ${household.memberIds.length == 1 ? 'member' : 'members'} · You are ${provider.currentRole}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (provider.currentRole == 'owner' ||
                              provider.currentRole == 'admin') ...[
                            const SizedBox(height: 18),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: provider.isLoading
                                      ? null
                                      : () => _rename(household.name),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Rename'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: provider.isLoading
                                      ? null
                                      : _regenerateInvite,
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('New invite'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    FormSection(
                      title: 'A place at your table',
                      description:
                          'Share this code with someone you want to invite.',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                household.inviteCode,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      letterSpacing: 3,
                                      color: colors.primary,
                                    ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy invite code',
                              icon: const Icon(Icons.copy_outlined, size: 21),
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: household.inviteCode),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invite code copied.'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        if (household.inviteExpiresAt != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Valid until ${MaterialLocalizations.of(context).formatMediumDate(household.inviteExpiresAt!)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 26),
                    Text(
                      'Around your table',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 14),
                    SurfacePanel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final memberId in household.memberIds)
                            Builder(
                              builder: (context) {
                                final role =
                                    household.memberRoles[memberId] ??
                                    (memberId == household.ownerId
                                        ? 'owner'
                                        : 'member');
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: colors.primaryContainer,
                                    foregroundColor: colors.primary,
                                    child: Text(
                                      memberId == provider.userId
                                          ? 'Y'
                                          : memberId
                                                .substring(
                                                  0,
                                                  memberId.length.clamp(0, 2),
                                                )
                                                .toUpperCase(),
                                    ),
                                  ),
                                  title: Text(
                                    memberId == provider.userId
                                        ? 'You'
                                        : memberId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(role),
                                  trailing: provider.isOwner && role != 'owner'
                                      ? IconButton(
                                          tooltip: 'Manage member',
                                          onPressed: () =>
                                              _manageMember(memberId, role),
                                          icon: const Icon(
                                            Icons.more_horiz_rounded,
                                          ),
                                        )
                                      : null,
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                  ] else ...[
                    FormSection(
                      title: 'Start a household',
                      description: 'Give your shared kitchen a name.',
                      children: [
                        TextField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Household name',
                            hintText: 'e.g. Khan Family Kitchen',
                            prefixIcon: Icon(Icons.home_outlined),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: provider.isLoading ? null : _create,
                          icon: const Icon(Icons.add_rounded, size: 19),
                          label: const Text('Create household'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  FormSection(
                    title: household == null
                        ? 'Already invited?'
                        : 'Join another kitchen',
                    description: household == null
                        ? 'Enter the code your household shared with you.'
                        : 'An invite code lets you switch to a different shared pantry.',
                    children: [
                      TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp('[A-Za-z0-9]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Invite code',
                          prefixIcon: Icon(Icons.group_add_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: provider.isLoading ? null : _join,
                        child: const Text('Join household'),
                      ),
                    ],
                  ),
                  if (provider.errorMessage != null) ...[
                    const SizedBox(height: 18),
                    StatusNotice(
                      message: provider.errorMessage!,
                      isError: true,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
