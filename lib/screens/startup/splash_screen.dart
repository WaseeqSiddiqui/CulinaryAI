import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Branded first frame while the saved sign-in session is restored.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.primaryFlameDark,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  color: AppTheme.primaryFlame,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Icon(
                  Icons.spa_outlined,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'CulinaryAI',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your everyday kitchen companion',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.primaryFlameLight),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: AppTheme.accentVioletLight,
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Keeps the branding visible briefly without blocking session initialization.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.isInitializing,
    required this.child,
  });
  final bool isInitializing;
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  bool _introComplete = false;

  @override
  void initState() {
    super.initState();
    _intro =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            setState(() => _introComplete = true);
          }
        });
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_introComplete || widget.isInitializing
      ? const SplashScreen()
      : widget.child;
}
