# CulinaryAI interface

The app uses a shared ivory and forest-green theme, locally bundled Plus Jakarta
Sans typography, quiet surface borders, and consistent form and button styles.
Light mode is the initial appearance; the appearance control also exposes a
matching dark theme.

Home, sign-in, pantry, shopping, chat and profile use the same visual system.
The secondary routes also share this system: recipe discovery and creation,
weekly plans, saved recipes, nutrition goals, cooking preferences, guided
cooking, registration, personal details, household management, scanner landing
pages and review sheets, order history and the app's PandaMart checkout controls.
Cooking keeps mobile step controls visible while instructions scroll. Scanner
review sheets use plain-language labels and preserve the user's confirmation
step before inventory changes. Saving temporarily locks those sheets to prevent
duplicate inventory updates. Meal logging also prevents duplicate taps and
persists nutrition history before displaying a successful save.
The main shell switches from bottom navigation to a sidebar at 1000 logical
pixels. Content stops growing at 1200 pixels. Sign-in and sign-up forms keep a
readable maximum width. Pantry search remains visible, and quantity controls
have tooltips and 44-pixel touch targets.

The font is bundled at `assets/fonts/PlusJakartaSans-Variable.ttf` and does not
require a network font download. Its original SIL Open Font License is retained
beside it and registered in Flutter's license registry.

## Verification and screenshots

```powershell
flutter analyze
flutter test
flutter build web --release
```

`test/app_ui_layout_test.dart` navigates all five main tabs at 320-pixel phone,
390-pixel phone, 768-pixel tablet and 1440-pixel desktop sizes. It also checks dark
mode and 130% text scaling. The tests load the actual bundled font and Material
icons so text measurements reflect the app's typography.

To save screen captures while running those checks:

```powershell
flutter test --dart-define=UI_CAPTURE_DIR=.tmp/ui_review test/app_ui_layout_test.dart
```

This writes PNGs for login, home, pantry, chat, shopping and profile. Test HTTP
requests are mocked by Flutter, so remote food images use their local fallback.
The secondary routes, populated review sheets and order details have their own
responsive checks:

```powershell
flutter test --dart-define=UI_CAPTURE_DIR=.tmp/remaining_ui test/secondary_screens_layout_test.dart
```

The embedded merchant page is replaced with an inert test widget for these
layout checks. They do not sign in to a store, request camera access or place an
order. The browser shopping alternative is checked at the same sizes, including
validation that a manually recorded order contains purchased items and a total.

`test/scanner_interaction_test.dart` covers failed-save recovery, repeated taps,
camera denial, meal logging, and manually correcting a scanned expiry date.
Cooking photos upload as bytes on both native and browser platforms. Expiry
label OCR uses the Android Tesseract integration; other platforms present the
manual date confirmation flow.

Release web artifacts are generated in `build/web`; hosting and production
service configuration remain separate release steps.
