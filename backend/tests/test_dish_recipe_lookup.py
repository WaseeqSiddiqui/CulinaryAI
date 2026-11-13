import json

import httpx
import pytest

from app.models.dish_options import DishOptionsRequest
from app.services.dish_options import DishOptionsService
from app.services.dish_recipe_lookup import DishRecipeLookup, ingredient_parts


def client_for(page, redirect=None):
    def handle(req):
        if req.method == 'POST':
            assert 'pantry' not in req.content.decode()
            return httpx.Response(200, json={'results': [{'url': 'https://www.bbcgoodfood.com/recipes/chicken-biryani'}]})
        if redirect:
            return httpx.Response(302, headers={'location': redirect})
        return httpx.Response(200, text=page)
    return httpx.Client(transport=httpx.MockTransport(handle))


def page(name='Chicken biryani'):
    return '<html><script type="application/ld+json">' + json.dumps({
        '@graph': [{'@type': ['Recipe'], 'name': name,
                    'recipeIngredient': ['500g chicken', '200 g rice', 'Salt to taste']}],
    }) + '</script></html>'


def test_tavily_recipe_fallback_uses_actual_structured_ingredients():
    lookup = DishRecipeLookup(client_for(page()), api_key='test')
    recipe = lookup.lookup('chicken biryani')
    assert recipe['name'] == 'Chicken biryani'
    assert recipe['ingredients'] == [('chicken', '500 g'), ('rice', '200 g'), ('Salt', '')]
    assert recipe['source_url'].startswith('https://www.bbcgoodfood.com/')


def test_wrong_recipe_is_not_substituted():
    assert DishRecipeLookup(client_for(page('Lamb biryani')), api_key='test').lookup('chicken biryani') is None


@pytest.mark.parametrize('redirect', ['http://127.0.0.1/internal', 'https://evil.test/recipe',
    'https://www.bbcgoodfood.com:444/recipe', 'https://user:pass@www.bbcgoodfood.com/recipe'])
def test_recipe_redirects_cannot_fetch_untrusted_destinations(redirect):
    assert DishRecipeLookup(client_for('', redirect), api_key='test').lookup('chicken biryani') is None


def test_recipe_html_without_structured_ingredients_is_not_guessed():
    assert DishRecipeLookup(client_for('<h1>Chicken biryani</h1>'), api_key='test').lookup('chicken biryani') is None


def test_recipe_ranges_preserve_unknown_quantities():
    assert ingredient_parts('1-2 cups milk') == ('milk', '')
    assert ingredient_parts('Salt to taste') == ('Salt', '')
    assert ingredient_parts('1 tbsp olive oil, for frying') == ('olive oil', '1 tbsp')
    assert ingredient_parts('1 large onion, finely sliced') == ('onion', '1')


def test_fallback_still_checks_empty_inventory_without_fake_source():
    class Empty:
        def search_name(self, _):
            return []
    service = DishOptionsService(Empty(), fallback=DishRecipeLookup(client_for(page()), api_key='test'))
    result = service.check(DishOptionsRequest(dish='chicken biryani'))
    assert result.status == 'missing'
    assert result.recipe.source == 'Recipe website'
    assert result.recipe.source_url == 'https://www.bbcgoodfood.com/recipes/chicken-biryani'
    assert len(result.recipe.ingredients) == 3
