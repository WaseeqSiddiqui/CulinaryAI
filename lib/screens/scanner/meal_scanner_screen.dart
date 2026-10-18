import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/meal_nutrition_estimate.dart';
import '../../providers/auth_provider.dart';
import '../../providers/recipe_experience_provider.dart';
import '../../services/meal_nutrition_service.dart';


class MealScannerScreen extends StatefulWidget {
  const MealScannerScreen({super.key});

  @override
  State<MealScannerScreen> createState() => _MealScannerScreenState();
}

class _MealScannerScreenState extends State<MealScannerScreen> {
  final _picker = ImagePicker();
  final _service = MealNutritionService();
  Uint8List? _image;
  MealNutritionEstimate? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final image = await _picker.pickImage(source: source, imageQuality: 92);
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _image = bytes;
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await _service.analyze(
        imageBytes: bytes,
        userId: context.read<AuthProvider>().currentUser?.id ?? 'local_user',
      );
      if (mounted) setState(() => _result = result);
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
    if (result == null) return;
    await context.read<RecipeExperienceProvider>().recordNutrition(
      title: result.dishName,
      nutrition: result.nutrition,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a meal'),
      ),

      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: _image == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 52),
                      SizedBox(height: 10),
                      Text('Photograph one plate from above'),
                    ],
                  )
                : Image.memory(_image!, fit: BoxFit.cover),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 26),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 10),
            const Center(child: Text('Estimating the visible portion...')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.errorRed.withValues(alpha: 0.3)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.errorRed, fontSize: 13),
              ),

            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 20),
            Text(
              result.dishName,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              '${result.portionDescription} · ${(result.confidence * 100).round()}% confidence',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Nutrient(
                  label: 'Calories',
                  value: '${result.nutrition.calories.round()} kcal',
                ),
                _Nutrient(
                  label: 'Protein',
                  value: '${result.nutrition.proteinGrams.round()} g',
                ),
                _Nutrient(
                  label: 'Carbs',
                  value: '${result.nutrition.carbohydrateGrams.round()} g',
                ),
                _Nutrient(
                  label: 'Fat',
                  value: '${result.nutrition.fatGrams.round()} g',
                ),
              ],
            ),
            if (result.assumptions.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Assumptions',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              ...result.assumptions.map((value) => Text('• $value')),
            ],
            const SizedBox(height: 12),
            const Text(
              'Photo nutrition is an estimate, not medical or dietary advice. Retake the photo if the visible portion is incorrect.',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _log,
              icon: const Icon(Icons.add_chart_rounded),
              label: const Text('Add to today'),
            ),
          ],
        ],
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
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}
