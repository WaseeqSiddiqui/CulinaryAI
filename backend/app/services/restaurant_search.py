"""Source-backed menu links, never invented restaurants or delivery claims."""

import html
import ipaddress
import os
import re
from urllib.parse import parse_qsl, unquote, urlencode, urljoin, urlsplit, urlunsplit

import httpx

from app.models.dish_options import RestaurantOption, RestaurantSearchRequest, RestaurantSearchResponse


class RestaurantSearchUnavailable(Exception):
    pass


def words(text):
    return re.findall(r"[^\W_]+", text.casefold(), flags=re.UNICODE)


def clean_text(value, limit):
    if not isinstance(value, str):
        return ""
    value = html.unescape(value).replace('\\n', '\n')
    value = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', value)
    value = re.sub(r'\[([^\]]+)\]\([^)]*\)', r'\1', value)
    value = re.sub(r'<[^>]*>', ' ', value)
    value = re.sub(r'[*_`#|]+', ' ', value)
    return re.sub(r'\s+', ' ', value).strip()[:limit]


EXCLUDED_HOSTS = {
    'foodpanda.pk', 'foodpanda.com', 'ubereats.com', 'deliveroo.com',
    'doordash.com', 'talabat.com', 'grubhub.com', 'tripadvisor.com',
    'tripadvisor.com.pk', 'restaurantguru.com', 'facebook.com',
    'instagram.com', 'youtube.com', 'tiktok.com', 'google.com',
    'yelp.com', 'zomato.com', 'wikipedia.org',
    'reddit.com', 'wheree.com', 'wanderlog.com', 'restaurantji.com',
    'foursquare.com', 'snoonu.com', 'apps.apple.com', 'play.google.com',
    'snapchat.com', 'mealdeals.app',
}


def restaurant_url(value):
    """Validate displayed URLs; arbitrary restaurant sites are never fetched locally."""
    if not isinstance(value, str) or len(value) > 2048:
        return None
    try:
        uri = urlsplit(html.unescape(value.strip()))
        host = (uri.hostname or '').lower()
        if uri.scheme != 'https' or not host or '.' not in host or uri.username or uri.password or uri.port not in (None, 443):
            return None
        if host.endswith(('.local', '.localhost', '.internal', '.test', '.example')) or any(host == blocked or host.endswith('.' + blocked) for blocked in EXCLUDED_HOSTS):
            return None
        try:
            ipaddress.ip_address(host)
            return None
        except ValueError:
            pass
        if re.fullmatch(r'[\d.]+', host):
            return None
        if re.search(r'\.(?:jpe?g|png|webp|gif|svg|ico|pdf|js|css|zip)$', uri.path, re.I):
            return None
        query = [(key, val) for key, val in parse_qsl(uri.query, keep_blank_values=True)
                 if not key.lower().startswith('utm_') and key.lower() not in {'fbclid', 'gclid'}]
        return urlunsplit(('https', host, uri.path or '/', urlencode(query), uri.fragment))
    except ValueError:
        return None


def link_kind(url):
    uri = urlsplit(url)
    if (uri.hostname or '').startswith(('order.', 'orders.', 'ordering.')):
        return 'order'
    path = unquote(uri.path + '#' + uri.fragment).lower()
    if re.search(r'\b(order|ordering|checkout|delivery|buy)\b', path):
        return 'order'
    if re.search(r'\bmenus?\b', path):
        return 'menu'
    return 'website'


def order_link(website, markdown):
    host = urlsplit(website).hostname.removeprefix('www.')
    candidates = [(link_kind(website), website)]
    for label, target in re.findall(r'\[([^\]]+)\]\(([^\s)]+)(?:\s+"[^"]*")?\)', markdown):
        if not re.search(r'\b(order|menu|delivery|checkout)\b', clean_text(label, 100), re.I):
            continue
        url = restaurant_url(urljoin(website, target))
        if not url:
            continue
        target_host = urlsplit(url).hostname.removeprefix('www.')
        if target_host != host and not target_host.endswith('.' + host):
            continue
        kind = link_kind(url)
        if re.search(r'\border\b', label, re.I):
            kind = 'order'
        candidates.append((kind, url))
    return max(candidates, key=lambda item: {'website': 0, 'menu': 1, 'order': 2}[item[0]])


def restaurant_name(title, url):
    pieces = re.split(r'\s*[|–—]\s*|\s+-\s+', html.unescape(title))
    host = urlsplit(url).hostname.removeprefix('www.')
    brand = re.sub(r'[^a-z0-9]', '', host.split('.')[0].lower())
    cleaned = []
    for part in pieces:
        part = clean_text(part, 160)
        part = re.split(r'\s+(?:delivery in|menu in|official website)', part, maxsplit=1, flags=re.I)[0].strip()
        part = re.sub(r'\s+menu$', '', part, flags=re.I).rstrip(' .…')
        cleaned.append(part)
    for part in cleaned:
        normalized = re.sub(r'[^a-z0-9]', '', part.lower())
        if brand and brand in normalized and not re.match(r'^order\b', part, re.I):
            return part
    for part in cleaned:
        if part and not re.match(r'^(?:home|menu|order\b|online ordering|welcome\b|all restaurants\b|get the best\b|best .*deals\b)', part, re.I):
            return part
    return host


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
                "query": f'"{request.dish}" "{request.area}" Pakistan restaurant order online',
                "topic": "general", "search_depth": "advanced", "max_results": 12,
                "exclude_domains": sorted(EXCLUDED_HOSTS), "country": "pakistan",
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
        candidates = []
        seen = set()
        dish_words = words(request.dish)
        area_words = [w for w in words(request.area) if w not in {"pakistan", "in", "near", "town", "phase", "sector", "road", "rd"}]
        for record in records:
            if not isinstance(record, dict):
                continue
            title, content, url = (record.get(k) for k in ("title", "content", "url"))
            if not all(isinstance(value, str) for value in (title, content, url)):
                continue
            safe_url = restaurant_url(url)
            if safe_url is None:
                continue
            uri = urlsplit(safe_url)
            summary = clean_text(content, 420)
            evidence = set(words(clean_text(title, 200) + " " + summary + " " + unquote(uri.path).replace("-", " ")))
            # Search bias alone cannot establish either a dish or a locality.
            # A search snippet may omit a menu item. Keep likely candidates,
            # then check dish and locality against the extracted restaurant page.
            if not dish_words or not any(w in evidence for w in dish_words) or not area_words:
                continue
            if re.search(r'\b(recipe|recipes|review|reviews|blog|news|article)\b', uri.path, re.I):
                continue
            if re.search(r'\b(recipe|reviews|san jose|chicago|toronto|charlotte|secaucus)\b', clean_text(title, 200), re.I):
                continue
            other_cities = {'karachi', 'lahore', 'islamabad', 'rawalpindi', 'faisalabad', 'multan', 'peshawar', 'quetta', 'hyderabad', 'sialkot', 'gujranwala'} - set(area_words)
            if set(words(title)) & other_cities:
                continue
            host = uri.hostname.removeprefix('www.')
            if host in seen:
                continue
            seen.add(host)
            candidates.append((safe_url, title, content))
            if len(candidates) == 5:
                break
        # Extract through the search provider, never fetch arbitrary websites
        # from the backend. Only links actually present on the source are used.
        pages = {}
        if candidates:
            try:
                extracted = self.client.post('https://api.tavily.com/extract',
                    headers={'Authorization': f'Bearer {key}'},
                    json={'urls': [row[0] for row in candidates], 'extract_depth': 'basic', 'format': 'markdown', 'include_images': False},
                    timeout=httpx.Timeout(8, connect=3))
                extracted.raise_for_status()
                if len(extracted.content) <= 2_000_000:
                    for page in extracted.json().get('results', []):
                        if isinstance(page, dict) and isinstance(page.get('url'), str) and isinstance(page.get('raw_content'), str):
                            pages[restaurant_url(page['url'])] = page['raw_content'][:100000]
            except (httpx.HTTPError, ValueError, TypeError, AttributeError):
                pass
        options = []
        for website, title, content in candidates:
            page = pages.get(website, content)
            evidence = set(words(clean_text(title + ' ' + content + ' ' + page, 100000) + ' ' + unquote(urlsplit(website).path).replace('-', ' ')))
            confirmed = all(word in evidence for word in dish_words)
            area_confirmed = area_words[-1] in evidence
            country_confirmed = (urlsplit(website).hostname or '').endswith('.pk') or 'pakistan' in evidence
            if dish_words[-1] not in evidence or not (area_confirmed or country_confirmed):
                continue
            kind, target = order_link(website, page)
            if kind == 'website' and re.search(r'\border\b.*\bonline\b|\bonline ordering\b', clean_text(title, 200), re.I):
                kind = 'order'
            if any(option.url == target for option in options):
                continue
            options.append(RestaurantOption(name=restaurant_name(title, website), url=target,
                website_url=website, link_type=kind, dish_confirmed=confirmed, area_confirmed=area_confirmed,
                summary=f'The menu source mentions {request.dish}. Check current availability and delivery to {request.area} on the restaurant website.' if confirmed else
                    f'Check this restaurant menu for {request.dish}; the exact dish was not confirmed by the source.'))
        options.sort(key=lambda item: {'order': 0, 'menu': 1, 'website': 2}[item.link_type])
        return RestaurantSearchResponse(dish=request.dish, area=request.area, restaurants=options, message=
            "Restaurant websites to check for your dish and city." if options else
            "No matching restaurant websites were found. Try a nearby area or a broader dish name.")
