from datetime import date
import json

from fastapi.testclient import TestClient
import httpx
import pytest

import app.main as main
from app.models.dish_options import DishOptionsRequest, RestaurantSearchRequest
from app.models.schemas import PantryItemInput
from app.services.dish_options import DishOptionsService
from app.services.restaurant_search import RestaurantSearchService, RestaurantSearchUnavailable


PASTA = {'idMeal': '123', 'strMeal': 'Tomato pasta', 'strIngredient1': 'Pasta',
         'strMeasure1': '200g', 'strIngredient2': 'Tomatoes', 'strMeasure2': '2'}


class Recipes:
    def __init__(self, records=None):
        self.records = [PASTA] if records is None else records
        self.queries = []

    def search_name(self, name):
        self.queries.append(name)
        return self.records


def request(items=(), dish='tomato pasta'):
    return DishOptionsRequest(dish=dish, pantry_items=list(items), reference_date=date(2026, 11, 13))


def test_named_dish_can_be_checked_with_completely_empty_inventory():
    result = DishOptionsService(Recipes()).check(request())
    assert result.status == 'missing'
    assert [item.name for item in result.recipe.ingredients] == ['Pasta', 'Tomatoes']
    assert all(item.status == 'missing' for item in result.recipe.ingredients)
    assert not result.recipe.can_cook_now


def test_quantity_shortage_and_expired_food_are_not_usable():
    result = DishOptionsService(Recipes()).check(request([
        PantryItemInput(name='Pasta', quantity=50, unit='g'),
        PantryItemInput(name='Tomatoes', quantity=3, expiry_date=date(2026, 11, 12)),
    ]))
    pasta, tomatoes = result.recipe.ingredients
    assert pasta.status == 'insufficient' and pasta.missing_quantity == 150
    assert tomatoes.status == 'missing'


def test_ready_and_unknown_quantities_remain_distinct():
    service = DishOptionsService(Recipes())
    ready = service.check(request([PantryItemInput(name='Pasta', quantity=1, unit='kg'),
        PantryItemInput(name='Tomatoes', quantity=2)]))
    assert ready.status == 'ready' and ready.recipe.can_cook_now
    uncertain = service.check(request([PantryItemInput(name='Pasta', quantity=1, unit='pack'),
        PantryItemInput(name='Tomatoes', quantity=2)]))
    assert uncertain.status == 'check_quantities' and not uncertain.recipe.can_cook_now


def test_unrelated_recipe_cannot_replace_requested_dish():
    assert DishOptionsService(Recipes()).check(request(dish='chicken biryani')).status == 'recipe_not_found'


def result(title='Biryani House delivery in Lahore | foodpanda', url='https://www.foodpanda.pk/restaurant/abc/biryani-house',
           content='Order chicken biryani from Biryani House in Johar Town Lahore.'):
    return dict(title=title, url=url, content=content)


def service_with(records, on_request=None):
    def handle(req):
        if on_request:
            on_request(req)
        return httpx.Response(200, json={'results': records})
    return RestaurantSearchService(httpx.Client(transport=httpx.MockTransport(handle)), api_key='test-key')


def test_search_sends_only_dish_and_area_not_inventory_or_generated_answers():
    def inspect(req):
        body = json.loads(req.content)
        assert req.url == 'https://api.tavily.com/search'
        assert req.headers['Authorization'] == 'Bearer test-key'
        assert body['include_domains'] == ['foodpanda.pk']
        assert body['include_answer'] is False and body['include_raw_content'] is False
        assert 'pantry' not in json.dumps(body)
        assert 'chicken biryani' in body['query'] and 'Johar Town, Lahore' in body['query']
    response = service_with([result()], inspect).search(
        RestaurantSearchRequest(dish='chicken biryani', area='Johar Town, Lahore'))
    assert len(response.restaurants) == 1
    assert response.restaurants[0].name == 'Biryani House'


def test_wrong_city_wrong_dish_articles_and_unsafe_links_are_excluded():
    records = [result(),
        result(content='Order chicken biryani in Karachi.', title='Biryani House Karachi'),
        result(content='Order pizza in Lahore.', title='Pizza House Lahore', url='https://www.foodpanda.pk/restaurant/a/pizza'),
        result(url='https://foodpanda.pk.evil.test/restaurant/a/biryani'),
        result(url='https://www.foodpanda.pk/restaurants/lahore'),
        result(url='https://www.foodpanda.pk/darkstore/a/groceries'),
        result(url='https://user:pass@www.foodpanda.pk/restaurant/a/biryani'),
        result(url='javascript:alert(1)'),
        result(url='https://www.foodpanda.pk:444/restaurant/a/biryani'),
        result(url='https://www.foodpanda.pk/restaurant/abc/biryani-house?tracking=1'),
    ]
    response = service_with(records).search(RestaurantSearchRequest(dish='chicken biryani', area='Lahore'))
    assert len(response.restaurants) == 1
    assert response.restaurants[0].url == 'https://www.foodpanda.pk/restaurant/abc/biryani-house'


def test_empty_results_are_not_an_outage_and_no_fake_fallback_is_used():
    response = service_with([]).search(RestaurantSearchRequest(dish='pizza', area='Lahore'))
    assert response.restaurants == [] and 'No matching' in response.message


@pytest.mark.parametrize('status', [401, 429, 500])
def test_provider_failures_hide_private_credentials_and_details(status):
    client = httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(status, json={'key': 'sensitive'})))
    with pytest.raises(RestaurantSearchUnavailable) as error:
        RestaurantSearchService(client, api_key='private-key').search(RestaurantSearchRequest(dish='pizza', area='Lahore'))
    assert 'sensitive' not in str(error.value) and 'private-key' not in str(error.value)


def test_endpoint_validates_blank_inputs_and_preserves_partial_inventory_result(monkeypatch):
    monkeypatch.setattr(main, 'dish_options', DishOptionsService(Recipes()))
    client = TestClient(main.app)
    result = client.post('/dish-options', json={'dish': 'tomato pasta', 'pantry_items': []})
    assert result.status_code == 200 and result.json()['status'] == 'missing'
    assert client.post('/dish-options', json={'dish': '  '}).status_code == 422
    assert client.post('/nearby-restaurants', json={'dish': 'pizza', 'area': '\n'}).status_code == 422


def test_unconfigured_search_is_retryable_without_exposing_settings(monkeypatch):
    monkeypatch.delenv('TAVILY_API_KEY', raising=False)
    monkeypatch.setattr(main, 'restaurant_search', RestaurantSearchService(api_key=''))
    response = TestClient(main.app).post('/nearby-restaurants', json={'dish': 'pizza', 'area': 'Lahore'})
    assert response.status_code == 503
    assert 'API' not in response.json()['detail']
