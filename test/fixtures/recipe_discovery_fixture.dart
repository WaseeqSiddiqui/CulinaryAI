Map<String, dynamic> liveRecipeFixture({bool empty = false}) => {
  'planning_date': '2026-10-30',
  'message': empty
      ? 'No close matches were found.'
      : 'Your pantry covers the listed recipe quantities.',
  'pantry_item_count': 1,
  'retrieval_method': 'themealdb-live-ingredient-search',
  'checked_recipe_count': 12,
  'excluded_expired_items': <String>[],
  'source_quantities_note':
      'Check serving counts at the source. No staples are assumed.',
  'meals': empty
      ? []
      : [
          {
            'recipe_id': 'mealdb_100',
            'name': 'Live Rice Bowl',
            'cuisine': 'Pakistani',
            'category': 'Rice',
            'image_url': '',
            'source': 'TheMealDB',
            'source_url': 'https://www.themealdb.com/meal.php?c=100',
            'pantry_match_percent': 100,
            'can_cook_now': true,
            'ingredients': [
              {
                'name': 'Rice',
                'measure': '300g',
                'quantity': 300,
                'unit': 'g',
                'status': 'available',
                'available_quantity': 1000,
                'missing_quantity': 0,
              },
            ],
          },
        ],
};
