import 'recipe_discovery.dart';

class DishOptions {
  const DishOptions({
    required this.dish,
    required this.status,
    required this.message,
    required this.quantitiesNote,
    this.recipe,
  });
  final String dish;
  final String status;
  final String message;
  final String quantitiesNote;
  final DiscoveredRecipe? recipe;
  bool get hasMissingIngredients =>
      recipe?.ingredients.any(
        (item) => item.status == 'missing' || item.status == 'insufficient',
      ) ??
      false;

  factory DishOptions.fromJson(Map<String, dynamic> json) {
    final recipe = json['recipe'] == null
        ? null
        : DiscoveredRecipe.fromJson(
            Map<String, dynamic>.from(json['recipe'] as Map),
          );
    var status = json['status'] as String;
    if (status == 'ready' && recipe?.canCookNow != true) {
      status = 'check_quantities';
    }
    return DishOptions(
      dish: json['dish'] as String,
      status: status,
      message: json['message'] as String,
      quantitiesNote: json['quantities_note'] as String? ?? '',
      recipe: recipe,
    );
  }
}

class RestaurantOption {
  const RestaurantOption({
    required this.name,
    required this.url,
    required this.summary,
    required this.source,
  });
  final String name;
  final Uri url;
  final String summary;
  final String source;

  factory RestaurantOption.fromJson(Map<String, dynamic> json) {
    final uri = Uri.parse(json['url'] as String);
    if (uri.scheme != 'https' ||
        !{'foodpanda.pk', 'www.foodpanda.pk'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !RegExp(r'^/restaurant/[\w-]+/[^/]+/?$').hasMatch(uri.path)) {
      throw const FormatException('Unsupported restaurant menu URL');
    }
    return RestaurantOption(
      name: json['name'] as String,
      url: uri,
      summary: json['summary'] as String? ?? '',
      source: json['source'] as String? ?? 'Foodpanda',
    );
  }
}

class RestaurantResults {
  const RestaurantResults({
    required this.restaurants,
    required this.message,
    required this.area,
    required this.note,
  });
  final List<RestaurantOption> restaurants;
  final String message;
  final String area;
  final String note;

  factory RestaurantResults.fromJson(Map<String, dynamic> json) =>
      RestaurantResults(
        restaurants: (json['restaurants'] as List)
            .map(
              (item) => RestaurantOption.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        area: json['area'] as String,
        message: json['message'] as String,
        note:
            json['availability_note'] as String? ??
            'Check the menu and delivery coverage before ordering.',
      );
}
