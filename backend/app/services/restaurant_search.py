"""Source-backed menu links, never invented restaurants or delivery claims."""

import html
import os
import re
from urllib.parse import unquote, urlsplit, urlunsplit

import httpx

from app.models.dish_options import RestaurantOption, RestaurantSearchRequest, RestaurantSearchResponse


class RestaurantSearchUnavailable(Exception):
    pass


def words(text):
    return re.findall(r"[^\W_]+", text.casefold(), flags=re.UNICODE)


def clean_text(value, limit):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]*>", " ", value))).strip()[:limit]


class RestaurantSearchService:
    def __init__(self, client: httpx.Client | None = None, api_key: str | None = None):
        self.client = client or httpx.Client(timeout=httpx.Timeout(18, connect=4), follow_redirects=False)
        self.api_key = api_key

    def search(self, request: RestaurantSearchRequest) -> RestaurantSearchResponse:
        key = self.api_key or os.getenv("TAVILY_API_KEY", "")
        if not key or key.startswith("your_"):
            raise RestaurantSearchUnavailable("Restaurant search is not available right now. Please try again later.")
        try:
            response = self.client.post("https://api.tavily.com/search", headers={"Authorization": f"Bearer {key}"}, json={
                "query": f'{request.dish} restaurant menu order delivery in {request.area} Pakistan',
                "topic": "general", "search_depth": "basic", "max_results": 12,
                "include_domains": ["foodpanda.pk"], "country": "pakistan",
                "include_answer": False, "include_raw_content": False,
                "include_images": False, "auto_parameters": False,
            })
            response.raise_for_status()
            if len(response.content) > 2_000_000:
                raise ValueError("Response too large")
            payload = response.json()
            records = payload.get("results")
            if not isinstance(records, list):
                raise ValueError("Malformed search response")
        except (httpx.HTTPError, ValueError, AttributeError):
            # Never expose provider response bodies, request headers or keys.
            raise RestaurantSearchUnavailable("Restaurant search could not finish. Please try again.") from None
        options = []
        seen = set()
        dish_words = words(request.dish)
        area_words = [w for w in words(request.area) if w not in {"pakistan", "in", "near", "town", "phase", "sector", "road", "rd"}]
        for record in records:
            if not isinstance(record, dict):
                continue
            title, content, url = (record.get(k) for k in ("title", "content", "url"))
            if not all(isinstance(value, str) for value in (title, content, url)):
                continue
            try:
                uri = urlsplit(url)
                if uri.scheme != "https" or uri.hostname not in {"foodpanda.pk", "www.foodpanda.pk"} or uri.username or uri.password or uri.port not in (None, 443):
                    continue
                if not re.fullmatch(r"/restaurant/[a-zA-Z0-9_-]+/[^/]+/?", uri.path):
                    continue
            except ValueError:
                continue
            title = clean_text(title, 200)
            summary = clean_text(content, 420)
            evidence = set(words(title + " " + summary + " " + unquote(uri.path).replace("-", " ")))
            # Search bias alone cannot establish either a dish or a locality.
            if not dish_words or not all(w in evidence for w in dish_words) or not area_words or not all(w in evidence for w in area_words):
                continue
            safe_url = urlunsplit(("https", "www.foodpanda.pk", uri.path.rstrip("/"), "", ""))
            if safe_url in seen:
                continue
            seen.add(safe_url)
            name = re.split(r"\s+(?:delivery in|menu in|\||–| - )", title, maxsplit=1, flags=re.I)[0].strip()
            options.append(RestaurantOption(name=name or title, url=safe_url, summary=summary))
            if len(options) == 5:
                break
        return RestaurantSearchResponse(dish=request.dish, area=request.area, restaurants=options, message=
            "Menu pages matching your dish and area." if options else
            "No matching restaurant menu pages were found for this dish and area. Try a nearby neighbourhood or a broader dish name.")
