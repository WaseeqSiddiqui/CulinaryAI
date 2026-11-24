import 'package:flutter/material.dart';

import '../../widgets/app_ui.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About CulinaryAI')),
      body: AppPageBody(
        maxWidth: 600,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            SurfacePanel(
              color: colors.primaryContainer,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BrandIcon(size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'CulinaryAI',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Find recipes for the food you have, keep track of expiry dates, and plan what to buy.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Developer', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            SurfacePanel(
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.code_rounded,
                        color: colors.secondary,
                        size: 25,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Waseeq Ahmed Siddiqui',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SurfacePanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Open source licenses'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'CulinaryAI',
                  applicationIcon: const BrandIcon(size: 48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
