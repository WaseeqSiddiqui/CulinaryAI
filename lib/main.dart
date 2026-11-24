import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/household_provider.dart';
import 'providers/pantry_provider.dart';
import 'providers/shopping_provider.dart';
import 'providers/recipe_experience_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/main_shell.dart';
import 'screens/startup/splash_screen.dart';
import 'services/firebase_service.dart';
import 'services/server_config_service.dart';
import 'services/play_billing_service.dart';
import 'widgets/subscription_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Plus Jakarta Sans',
    ], await rootBundle.loadString('assets/fonts/OFL-PlusJakartaSans.txt'));
  });
  await FirebaseService.initialize();
  await ServerConfigService.init();
  runApp(const CulinaryAiApp());
}

class CulinaryAiApp extends StatelessWidget {
  const CulinaryAiApp({super.key});
  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PlayBillingController(),
          lazy: false,
        ),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => RecipeExperienceProvider()),
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
            value.bindHousehold(
              household.pantryScopeId,
              actorId: household.userId,
            );
            return value;
          },
        ),
        ChangeNotifierProxyProvider2<
          HouseholdProvider,
          PantryProvider,
          ShoppingProvider
        >(
          create: (_) => ShoppingProvider(),
          update: (_, household, pantry, shopping) {
            final value = shopping ?? ShoppingProvider();
            value.bindHousehold(
              household.pantryScopeId,
              pantry.allItems,
              pantryReady: pantry.hasLoaded,
            );
            return value;
          },
        ),
      ],
      child: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          return MaterialApp(
            navigatorKey: _navigatorKey,
            builder: (_, child) => SubscriptionNotifications(
              navigatorKey: _navigatorKey,
              child: child!,
            ),
            title: 'CulinaryAI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            themeMode: ThemeMode.light,
            home: StartupGate(
              isInitializing: authProvider.isInitializing,
              child: authProvider.isAuthenticated
                  ? const MainShell()
                  : const LoginScreen(),
            ),
          );
        },
      ),
    );
  }
}
