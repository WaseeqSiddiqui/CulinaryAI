"""Find structured ingredient lists for named dishes absent from TheMealDB."""

from html import unescape
from html.parser import HTMLParser
import json
import os
import re
import time
from urllib.parse import urljoin, urlsplit

import httpx

from app.services.recipe_inventory import canonical_name

RECIPE_HOSTS = {"recipe52.com", "www.recipe52.com", "teaforturmeric.com", "www.teaforturmeric.com",
                "bbcgoodfood.com", "www.bbcgoodfood.com", "allrecipes.com", "www.allrecipes.com"}


class _RecipeScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = False
        self.scripts = []
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag == 'script' and dict(attrs).get('type', '').lower() == 'application/ld+json':
            self.active = True
            self.parts = []

    def handle_data(self, data):
        if self.active:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag == 'script' and self.active:
            self.scripts.append(''.join(self.parts))
            self.active = False


def _recipes(value, depth=0):
    if depth > 12:
        return
    if isinstance(value, dict):
        kind = value.get('@type', [])
        if kind == 'Recipe' or isinstance(kind, list) and 'Recipe' in kind:
            yield value
        for child in value.values():
            if isinstance(child, (dict, list)):
                yield from _recipes(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            yield from _recipes(child, depth + 1)


def ingredient_parts(line):
    text = re.sub(r'\s+', ' ', unescape(re.sub(r'<[^>]*>', '', line))).strip()
    def name_only(value):
        value = re.split(r'[,;(]', value, maxsplit=1)[0].strip()
        return re.sub(r'^(?:(?:small|medium|large)(?:-sized)?\s+)+', '', value, flags=re.I)[:160]
    ranged = re.match(r'^\d+(?:\.\d+)?\s*[-–]\s*\d+(?:\.\d+)?\s*'
        r'(?:kg|g|ml|l|tbsp|tsp|cups?|cloves?|pieces?)?\s+(.+)$', text, re.I)
    if ranged:
        return name_only(ranged.group(1)), ''
    # Keep uncertain quantities uncertain. Do not silently turn a range into an
    # exact amount, or assume that cups and grams are interchangeable.
    match = re.match(r'^(\d+(?:\.\d+)?(?:\s+\d+/\d+|/\d+)?|[½¼¾⅓⅔])\s*'
        r'(kilograms?|grams?|pounds?|ounces?|kg|g|lbs?|oz|milliliters?|liters?|ml|l|tbsp|tsp|tablespoons?|teaspoons?|cups?|cloves?|pcs|pieces?)?\s+(.+)$', text, re.I)
    if match and not re.search(r'^\s*[-–]\s*\d', match.group(3)):
        return name_only(match.group(3)), f'{match.group(1)} {match.group(2) or ""}'.strip()
    return re.sub(r'\s+(?:to taste|as needed|optional)$', '', text, flags=re.I)[:160], ''


class DishRecipeLookup:
    def __init__(self, client=None, api_key=None):
        self.client = client or httpx.Client(timeout=httpx.Timeout(8, connect=4), follow_redirects=False)
        self.api_key = api_key

    def lookup(self, dish):
        deadline = time.monotonic() + 18
        key = self.api_key or os.getenv('TAVILY_API_KEY', '')
        if not key or key.startswith('your_'):
            return None
        try:
            response = self.client.post('https://api.tavily.com/search', headers={'Authorization': f'Bearer {key}'}, json={
                'query': f'{dish} recipe ingredients', 'search_depth': 'basic', 'max_results': 4,
                'include_domains': ['recipe52.com', 'teaforturmeric.com', 'bbcgoodfood.com', 'allrecipes.com'],
                'include_answer': False, 'include_raw_content': False, 'auto_parameters': False,
            })
            response.raise_for_status()
            if len(response.content) > 1_000_000:
                return None
            records = response.json().get('results', [])
            if not isinstance(records, list):
                return None
            wanted = canonical_name(dish).split()
            for record in records[:4]:
                if time.monotonic() >= deadline:
                    break
                if not isinstance(record, dict) or not isinstance(record.get('url'), str):
                    continue
                url = record['url']
                try:
                    page = self._page(url, deadline)
                except (httpx.HTTPError, ValueError):
                    continue
                if page is None:
                    continue
                parser = _RecipeScripts()
                parser.feed(page)
                for script in parser.scripts:
                    try:
                        candidates = list(_recipes(json.loads(script)))
                    except (ValueError, RecursionError):
                        continue
                    for recipe in candidates:
                        name, ingredients = recipe.get('name'), recipe.get('recipeIngredient')
                        if not isinstance(name, str) or not wanted or not all(word in canonical_name(name).split() for word in wanted):
                            continue
                        if not isinstance(ingredients, list) or not ingredients or len(ingredients) > 60 or not all(isinstance(i, str) and len(i) < 500 for i in ingredients):
                            continue
                        return {'name': unescape(name)[:180], 'source_url': url,
                                'ingredients': [ingredient_parts(line) for line in ingredients]}
        except (httpx.HTTPError, ValueError, TypeError, AttributeError):
            return None
        return None

    def _page(self, url, deadline):
        for _ in range(3):
            if time.monotonic() >= deadline:
                return None
            uri = urlsplit(url)
            if uri.scheme != 'https' or uri.hostname not in RECIPE_HOSTS or uri.username or uri.password or uri.port not in (None, 443):
                return None
            with self.client.stream('GET', url, timeout=max(.25, min(6, deadline - time.monotonic())),
                    headers={'User-Agent': 'CulinaryAI/1.0 Recipe ingredient lookup'}) as response:
                if response.is_redirect:
                    url = urljoin(url, response.headers.get('location', ''))
                    continue
                response.raise_for_status()
                content = bytearray()
                for chunk in response.iter_bytes():
                    content.extend(chunk)
                    if len(content) > 2_000_000:
                        return None
                return content.decode('utf-8', errors='replace')
        return None
