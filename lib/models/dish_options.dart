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
    this.linkType = 'website',
  });
  final String name;
  final Uri url;
  final String summary;
  final String source;
  final String linkType;
  String get orderLabel => switch (linkType) {
    'order' => 'Order on restaurant website',
    'menu' => 'View restaurant menu',
    _ => 'Visit restaurant website',
  };

  factory RestaurantOption.fromJson(Map<String, dynamic> json) {
    final value = json['url'];
    if (value is! String) {
      throw const FormatException('Missing restaurant website');
    }
    final uri = Uri.parse(value.trim());
    const blocked = {
      'foodpanda.pk',
      'foodpanda.com',
      'ubereats.com',
      'deliveroo.com',
      'doordash.com',
      'talabat.com',
      'grubhub.com',
      'tripadvisor.com',
      'tripadvisor.com.pk',
      'restaurantguru.com',
      'facebook.com',
      'instagram.com',
      'youtube.com',
      'tiktok.com',
      'google.com',
      'yelp.com',
      'zomato.com',
      'wikipedia.org',
      'reddit.com',
      'wheree.com',
      'wanderlog.com',
      'restaurantji.com',
      'foursquare.com',
      'snoonu.com',
      'apps.apple.com',
      'play.google.com',
      'snapchat.com',
      'mealdeals.app',
    };
    if (uri.scheme != 'https' ||
        !uri.host.contains('.') ||
        uri.host.contains(':') ||
        RegExp(r'^[\d.]+$').hasMatch(uri.host) ||
        RegExp(r'\.(local|localhost|internal|test|example)$')
            .hasMatch(uri.host) ||
        blocked.any(
          (host) => uri.host == host || uri.host.endsWith('.$host'),
        ) ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const FormatException('Unsupported restaurant menu URL');
    }
    if (RegExp(
      r'\.(jpe?g|png|webp|gif|svg|ico|pdf|js|css|zip)$',
      caseSensitive: false,
    ).hasMatch(uri.path)) {
      throw const FormatException('Restaurant link must open a website page');
    }
    return RestaurantOption(
      name: _restaurantText(json['name'], fallback: uri.host),
      url: uri,
      summary: _restaurantText(json['summary']),
      source: 'Restaurant website',
      linkType: {'order', 'menu', 'website'}.contains(json['link_type'])
          ? json['link_type'] as String
          : 'website',
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

  factory RestaurantResults.fromJson(Map<String, dynamic> json) {
    final restaurants = <RestaurantOption>[];
    final raw = json['restaurants'];
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        try {
          restaurants.add(
            RestaurantOption.fromJson(Map<String, dynamic>.from(item)),
          );
        } on FormatException {
          // A malformed result must not hide the other restaurant websites.
        }
      }
    }
    return RestaurantResults(
      restaurants: restaurants,
      area: _restaurantText(json['area']),
      message: restaurants.isEmpty
          ? 'No restaurant websites found. Try a different area or dish.'
          : _restaurantText(
              json['message'],
              fallback: 'Restaurant websites matching your search.',
            ),
      note: _restaurantText(
        json['availability_note'],
        fallback: 'Check the menu and delivery coverage before ordering.',
      ),
    );
  }
}

String _restaurantText(Object? raw, {String fallback = ''}) {
  if (raw is! String || raw.trim().isEmpty) return fallback;
  return raw
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (match) => match[1]!)
      .replaceAll(RegExp(r'[*_`#|]+'), ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll(r'\n', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
