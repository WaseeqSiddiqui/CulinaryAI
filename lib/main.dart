import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/household_provider.dart';
import 'providers/pantry_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_shell.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  runApp(const CulinaryAiApp());
}

class CulinaryAiApp extends StatelessWidget {
  const CulinaryAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, HouseholdProvider>(
          create: (_) => HouseholdProvider(),
          update: (_, auth, household) {
            final value = household ?? HouseholdProvider();
            value.bindUser(auth.currentUser);
            return value;
          },
        ),
        ChangeNotifierProxyProvider<HouseholdProvider, PantryProvider>(
          create: (_) => PantryProvider(),
          update: (_, household, pantry) {
            final value = pantry ?? PantryProvider();
            value.bindHousehold(household.pantryScopeId);
            return value;
          },
        ),
      ],
      child: Consumer2<AuthProvider, ThemeProvider>(
        builder: (context, authProvider, themeProvider, _) {
          return MaterialApp(
            title: 'CulinaryAI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: authProvider.isInitializing
                ? const _SessionLoadingScreen()
                : authProvider.isAuthenticated
                ? const MainShell()
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}

class _SessionLoadingScreen extends StatelessWidget {
  const _SessionLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
