import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../widgets/app_ui.dart';
import '../../widgets/scan_ui.dart';
import '../../models/meal_nutrition_estimate.dart';
import '../../providers/auth_provider.dart';
import '../../providers/recipe_experience_provider.dart';
import '../../services/meal_nutrition_service.dart';

class MealScannerScreen extends StatefulWidget {
  const MealScannerScreen({super.key, this.imagePicker, this.nutritionService});

  final ImagePicker? imagePicker;
  final MealNutritionService? nutritionService;

  @override
  State<MealScannerScreen> createState() => _MealScannerScreenState();
}

class _MealScannerScreenState extends State<MealScannerScreen> {
  late final _picker = widget.imagePicker ?? ImagePicker();
  late final _service = widget.nutritionService ?? MealNutritionService();
  Uint8List? _image;
  MealNutritionEstimate? _result;
  String? _error;
  bool _busy = false;
  bool _logging = false;

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy || _logging) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 92);
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _image = bytes;
        _result = null;
      });
      final result = await _service.analyze(
        imageBytes: bytes,
        userId: context.read<AuthProvider>().currentUser?.id ?? 'local_user',
      );
      if (mounted) setState(() => _result = result);
    } on PlatformException {
      if (mounted) {
        setState(
          () => _error = 'That photo could not be opened. Check camera permissions or choose another photo.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _log() async {
    final result = _result;
    if (result == null || _logging || _busy) return;
    setState(() => _logging = true);
    try {
      await context.read<RecipeExperienceProvider>().recordNutrition(
        title: result.dishName,
        nutrition: result.nutrition,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _logging = false;
          _error = 'Your meal could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final landing = _image == null && !_busy && _error == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a meal')),
      body: SafeArea(
        child: landing
            ? ScanLanding(
                title: 'A closer look at your plate.',
                description: 'Get an estimate of the calories and nutrients in your meal, then choose whether to log it.',
                icon: Icons.restaurant_outlined,
                photoAsset: 'assets/images/hero_dish.jpg',
                onCamera: () => _pick(ImageSource.camera),
                onGallery: () => _pick(ImageSource.gallery),
                tip: 'Photograph one plate from above. Include the whole portion and use natural light.',
              )
            : AppPageBody(
                maxWidth: 760,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
                  children: [
                    const PageIntro(
                      title: 'Your plate, in perspective.',
                      subtitle:
                          'Review the visible portion and the estimate below.',
                    ),
                    const SizedBox(height: 24),
                    if (_image != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Image.memory(_image!, fit: BoxFit.cover),
                        ),
                      ),
                    const SizedBox(height: 20),
                    PhotoSourceActions(
                      busy: _busy || _logging,
                      onCamera: () => _pick(ImageSource.camera),
                      onGallery: () => _pick(ImageSource.gallery),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 24),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('Estimating the visible portion…'),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      StatusNotice(message: _error!, isError: true),
                    ],
                    if (result != null) ...[
                      const SizedBox(height: 28),
                      FormSection(
                        title: result.dishName,
                        description:
                            '${result.portionDescription} · ${(result.confidence * 100).round()}% confidence',
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _Nutrient(
                                label: 'Calories',
                                value:
                                    '${result.nutrition.calories.round()} kcal',
                              ),
                              _Nutrient(
                                label: 'Protein',
                                value:
                                    '${result.nutrition.proteinGrams.round()} g',
                              ),
                              _Nutrient(
                                label: 'Carbs',
                                value:
                                    '${result.nutrition.carbohydrateGrams.round()} g',
                              ),
                              _Nutrient(
                                label: 'Fat',
                                value: '${result.nutrition.fatGrams.round()} g',
                              ),
                            ],
                          ),
                          if (result.assumptions.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Text(
                              'What this estimate assumes',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            for (final assumption in result.assumptions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('• $assumption'),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 18),
                      const StatusNotice(
                        message: 'Photo nutrition is an estimate. Retake the photo if the portion is incorrect, and review it before adding it to your day.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _busy || _logging ? null : _log,
                        icon: const Icon(Icons.add_chart_rounded),
                        label: Text(_logging ? 'Saving meal…' : 'Add to today'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _Nutrient extends StatelessWidget {
  final String label;
  final String value;
  const _Nutrient({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    width: 105,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleSmall),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
