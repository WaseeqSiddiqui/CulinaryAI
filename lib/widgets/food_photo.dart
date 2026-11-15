import 'package:flutter/material.dart';

/// Bundled photographs keep food visible while remote images load or fail.
class FoodPhoto extends StatelessWidget {
  const FoodPhoto({
    super.key,
    required this.name,
    this.url,
    this.height,
    this.width,
    this.recipeId,
    this.ingredient = false,
    this.fit = BoxFit.cover,
  });
  final String name;
  final String? url;
  final String? recipeId;
  final bool ingredient;
  final double? height;
  final double? width;
  final BoxFit fit;

  static String assetFor(String name, {String? recipeId}) {
    final text = name.toLowerCase();
    if (RegExp(r'pasta|spaghetti|penne|noodle|macaroni').hasMatch(text)) {
      return 'assets/images/pasta.jpg';
    }
    if (RegExp(r'salmon|fish|seafood').hasMatch(text)) {
      return 'assets/images/salmon.jpg';
    }
    if (RegExp(r'lentil|\bdal\b|\bdaal\b|curry').hasMatch(text)) {
      return 'assets/images/lentils.jpg';
    }
    if (RegExp(r'egg|toast|frittata|omelette|breakfast').hasMatch(text)) {
      return 'assets/images/egg_breakfast.jpg';
    }
    if (RegExp(r'risotto|parmesan rice|rice skillet').hasMatch(text)) {
      return 'assets/images/rice.jpg';
    }
    if (RegExp(r'chicken|biryani|pilaf|pulao').hasMatch(text)) {
      return 'assets/images/hero_dish.jpg';
    }
    return 'assets/images/pantry_basket.jpg';
  }

  static String ingredientAssetFor(String name) {
    final text = name.toLowerCase();
    for (final entry in {
      r'milk': 'milk',
      r'chicken': 'chicken',
      r'\beggs?\b': 'eggs',
      r'spinach': 'spinach',
      r'\brice\b': 'rice_grains',
      r'onion': 'onions',
      r'tomato': 'tomatoes',
    }.entries) {
      if (RegExp(entry.key).hasMatch(text)) {
        return 'assets/images/${entry.value}.jpg';
      }
    }
    return 'assets/images/pantry_basket.jpg';
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Image.asset(
      ingredient
          ? ingredientAssetFor(name)
          : assetFor(name, recipeId: recipeId),
      height: height,
      width: width,
      fit: fit,
      semanticLabel: name,
    );
    if (recipeId?.startsWith('rec_') == true || url == null || url!.isEmpty) {
      return fallback;
    }
    return Image.network(
      url!,
      height: height,
      width: width,
      fit: fit,
      semanticLabel: name,
      frameBuilder: (_, child, frame, _) => frame == null ? fallback : child,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}
