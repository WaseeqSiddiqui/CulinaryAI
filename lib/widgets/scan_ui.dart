import 'package:flutter/material.dart';

import 'app_ui.dart';

class PhotoSourceActions extends StatelessWidget {
  const PhotoSourceActions({
    super.key,
    required this.onCamera,
    required this.onGallery,
    this.busy = false,
  });
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final bool busy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final camera = FilledButton.icon(
        onPressed: busy ? null : onCamera,
        icon: const Icon(Icons.camera_alt_outlined, size: 20),
        label: const Text('Take a photo'),
      );
      final gallery = OutlinedButton.icon(
        onPressed: busy ? null : onGallery,
        icon: const Icon(Icons.photo_library_outlined, size: 20),
        label: const Text('Choose a photo'),
      );
      if (constraints.maxWidth < 440) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [camera, const SizedBox(height: 10), gallery],
        );
      }
      return Row(
        children: [
          Expanded(child: camera),
          const SizedBox(width: 12),
          Expanded(child: gallery),
        ],
      );
    },
  );
}

class ScanLanding extends StatelessWidget {
  const ScanLanding({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onCamera,
    required this.onGallery,
    required this.tip,
    this.photoAsset,
    this.busy = false,
    this.embedded = false,
  });
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final String tip;
  final String? photoAsset;
  final bool busy;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final intro = PageIntro(
          eyebrow: 'SCAN · REVIEW · CONFIRM',
          title: title,
          subtitle: description,
        );
        final preview = _ScanIllustration(icon: icon, photoAsset: photoAsset);
        final actions = PhotoSourceActions(
          onCamera: onCamera,
          onGallery: onGallery,
          busy: busy,
        );
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    intro,
                    const SizedBox(height: 28),
                    actions,
                    const SizedBox(height: 18),
                    StatusNotice(message: tip, icon: Icons.light_mode_outlined),
                  ],
                ),
              ),
              const SizedBox(width: 40),
              Expanded(child: preview),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            intro,
            const SizedBox(height: 26),
            preview,
            const SizedBox(height: 24),
            actions,
            const SizedBox(height: 18),
            StatusNotice(message: tip, icon: Icons.light_mode_outlined),
          ],
        );
      },
    );
    if (embedded) return content;
    return AppPageBody(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: content,
      ),
    );
  }
}

class _ScanIllustration extends StatelessWidget {
  const _ScanIllustration({required this.icon, this.photoAsset});
  final IconData icon;
  final String? photoAsset;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photoAsset != null) ...[
            Image.asset(photoAsset!, fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x11132D20), Color(0x99132D20)],
                ),
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .75),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 42),
              ),
            ),
          ] else
            Center(
              child: Container(
                width: 160,
                height: 184,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: colors.onSurface.withValues(alpha: .06),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: colors.primary, size: 34),
                    const SizedBox(height: 22),
                    for (final width in [90.0, 68.0, 100.0, 54.0]) ...[
                      Container(
                        width: width,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                'You review every result',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScanStatusView extends StatelessWidget {
  const ScanStatusView({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.check_rounded,
    this.busy = false,
    this.actions = const [],
  });
  final String title;
  final String message;
  final IconData icon;
  final bool busy;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(26),
              ),
              child: busy
                  ? const CircularProgressIndicator()
                  : Icon(
                      icon,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 28),
              for (final action in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(width: double.infinity, child: action),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
