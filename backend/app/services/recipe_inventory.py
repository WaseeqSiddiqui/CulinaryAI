"""Conservative ingredient matching. Similar words alone never imply stock."""

import re
import unicodedata
from datetime import date, timedelta
from fractions import Fraction

from app.models.recipe_discovery import IngredientCheck, RecipeDiscoveryRequest
from app.models.schemas import PantryItemInput


_ALIASES = {
    "eggs": "egg", "egg yolks": "egg yolk", "egg whites": "egg white",
    "tomatoes": "tomato", "fresh tomatoes": "tomato",
    "onions": "onion", "yellow onion": "onion", "brown onion": "onion",
    "garlic cloves": "garlic", "clove garlic": "garlic", "cloves garlic": "garlic",
    "garlic clove": "garlic", "fresh garlic": "garlic",
    "potatoes": "potato", "white potatoes": "potato",
    "basmati rice": "rice", "long grain rice": "rice", "white rice": "rice",
    "long grain white rice": "rice", "uncooked rice": "rice",
    "whole milk": "milk", "full fat milk": "milk", "whole fat milk": "milk",
    "plain flour": "flour", "all purpose flour": "flour",
    "coriander leaves": "cilantro", "fresh coriander": "cilantro",
    "fresh cilantro": "cilantro", "coriander": "cilantro",
    "spring onions": "spring onion", "scallions": "spring onion",
    "chickpeas": "chickpea", "garbanzo beans": "chickpea",
    "red lentils": "red lentil", "lentils": "lentil",
    "chicken breasts": "chicken breast", "boneless chicken breast": "chicken breast",
    "boneless skinless chicken breast": "chicken breast",
    "skinless chicken breasts": "chicken breast",
    "skinless boneless chicken breasts": "chicken breast",
    "extra virgin olive oil": "olive oil", "virgin olive oil": "olive oil",
    "vegetable oil": "cooking oil", "canola oil": "cooking oil",
    "black pepper": "pepper", "ground black pepper": "pepper",
    "table salt": "salt", "sea salt": "salt",
    "bell peppers": "bell pepper", "green pepper": "green bell pepper",
    "red pepper": "red bell pepper", "yoghurt": "yogurt",
    "plain yoghurt": "yogurt", "plain yogurt": "yogurt",
    "cheddar cheese": "cheddar", "parmesan cheese": "parmesan",
}
_UNITS = {
    "g": ("mass", 1), "gram": ("mass", 1), "grams": ("mass", 1),
    "kg": ("mass", 1000), "kilogram": ("mass", 1000), "kilograms": ("mass", 1000),
    "oz": ("mass", 28.349523125), "ounce": ("mass", 28.349523125), "ounces": ("mass", 28.349523125),
    "lb": ("mass", 453.59237), "lbs": ("mass", 453.59237), "pound": ("mass", 453.59237), "pounds": ("mass", 453.59237),
    "ml": ("volume", 1), "millilitre": ("volume", 1), "millilitres": ("volume", 1),
    "milliliter": ("volume", 1), "milliliters": ("volume", 1),
    "l": ("volume", 1000), "litre": ("volume", 1000), "litres": ("volume", 1000),
    "liter": ("volume", 1000), "liters": ("volume", 1000),
    "tsp": ("volume", 5), "teaspoon": ("volume", 5), "teaspoons": ("volume", 5),
    "tbsp": ("volume", 15), "tbs": ("volume", 15), "tblsp": ("volume", 15), "tablespoon": ("volume", 15), "tablespoons": ("volume", 15),
    "pcs": ("count", 1), "pc": ("count", 1), "piece": ("count", 1), "pieces": ("count", 1),
    "clove": ("count", 1), "cloves": ("count", 1), "": ("count", 1),
    "dozen": ("count", 12),
}
_FRACTIONS = {"½": " 1/2", "¼": " 1/4", "¾": " 3/4", "⅓": " 1/3", "⅔": " 2/3", "⅛": " 1/8", "⅜": " 3/8", "⅝": " 5/8", "⅞": " 7/8"}
_NUMBER = r"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"
_COUNTABLE = {"egg", "egg yolk", "egg white", "onion", "tomato", "garlic", "potato", "lemon", "lime", "carrot", "spring onion", "bell pepper", "red bell pepper", "green bell pepper", "chili", "apple", "banana", "orange", "mushroom", "chicken breast"}


def canonical_name(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    value = re.sub(r"[^a-z0-9 ]", " ", value)
    value = re.sub(r"\b(freshly|chopped|diced|minced|sliced|peeled|crushed|grated|boneless|skinless)\b", " ", value)
    value = " ".join(value.split())
    if value in _ALIASES:
        return _ALIASES[value]
    if value.endswith("s") and not value.endswith(("ss", "ous")):
        value = value[:-1]
    return _ALIASES.get(value, value)


def plan_date(request: RecipeDiscoveryRequest) -> date:
    if request.requested_date:
        return request.requested_date
    text = request.question.lower()
    explicit = re.search(r"\b\d{4}-\d{2}-\d{2}\b", text)
    if explicit:
        try:
            return date.fromisoformat(explicit.group())
        except ValueError:
            raise ValueError("Please use a valid date in YYYY-MM-DD format.") from None
    if "day after tomorrow" in text:
        return request.reference_date + timedelta(days=2)
    if re.search(r"\b(tomorrow|kal)\b", text):
        return request.reference_date + timedelta(days=1)
    offset = re.search(r"\bin (\d{1,2}) days?\b", text)
    if offset:
        return request.reference_date + timedelta(days=int(offset.group(1)))
    for weekday, name in enumerate(("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")):
        if re.search(rf"\b{name}\b", text):
            delta = (weekday - request.reference_date.weekday()) % 7
            if delta == 0 and f"next {name}" in text:
                delta = 7
            return request.reference_date + timedelta(days=delta)
    return request.reference_date


def parse_measure(measure: str) -> tuple[float | None, str]:
    """Keep unknown/ranged/pack measures uncertain rather than inventing amounts."""
    value = measure.strip().lower().replace("⁄", "/")
    for symbol, fraction in _FRACTIONS.items():
        value = value.replace(symbol, fraction)
    value = re.sub(r"\b(finely|chopped|minced|peeled|crushed|diced|sliced|beaten)\b", "", value)
    value = " ".join(value.split())
    match = re.fullmatch(rf"({_NUMBER})\s*([a-z]*)\.?", value)
    if not match:
        return None, ""
    try:
        quantity = sum(float(Fraction(part)) for part in match.group(1).split())
    except (ValueError, ZeroDivisionError):
        return None, ""
    if quantity <= 0:
        return None, ""
    unit = match.group(2)
    # A cup varies by recipe locale. Compare cup-to-cup only; don't invent ml.
    if unit in ("cup", "cups"):
        return quantity, "cup"
    if unit not in _UNITS:
        return None, unit
    return quantity, unit or "pcs"


def convert(quantity: float, source: str, target: str) -> float | None:
    source, target = source.strip().lower(), target.strip().lower()
    if source == target or {source, target} <= {"cup", "cups"}:
        return quantity
    left, right = _UNITS.get(source), _UNITS.get(target)
    if left and right and left[0] == right[0]:
        return quantity * left[1] / right[1]
    return None


def check_ingredients(raw: list[tuple[str, str]], pantry: list[PantryItemInput]) -> list[IngredientCheck]:
    # Reserve each pantry amount as it is matched. Duplicate recipe rows cannot
    # spend the same stock twice (for example, eggs in batter and in filling).
    remaining = [item.quantity for item in pantry]
    result = []
    for name, measure in raw:
        quantity, unit = parse_measure(measure)
        if unit == "pcs" and re.fullmatch(rf"\s*{_NUMBER}\s*", measure) and canonical_name(name) not in _COUNTABLE:
            # A source that says only "0.5 salt" did not specify grams,
            # teaspoons or any other usable unit. It is not half a piece.
            quantity, unit = None, ""
        indexes = [i for i, item in enumerate(pantry) if canonical_name(item.name) == canonical_name(name) and remaining[i] > 0]
        status, available, missing = "missing", None, None
        if indexes:
            compatible = [(i, convert(remaining[i], pantry[i].unit, unit)) for i in indexes] if quantity is not None else []
            known = [(i, amount) for i, amount in compatible if amount is not None]
            if quantity is None or not known:
                status = "check_quantity"
            else:
                available = sum(amount for _, amount in known)
                missing = max(0.0, quantity - available)
                status = "available" if missing < 1e-6 else "insufficient"
                if status == "insufficient" and len(known) < len(indexes):
                    status, missing = "check_quantity", None
                left = quantity
                for i, amount in known:
                    used = min(amount, left)
                    consumed = convert(used, unit, pantry[i].unit)
                    remaining[i] = max(0, remaining[i] - (consumed or 0))
                    left -= used
        if status == "missing" and quantity is not None:
            missing = quantity
        result.append(IngredientCheck(name=name, measure=measure or "Amount not specified", quantity=quantity, unit=unit, status=status, available_quantity=available, missing_quantity=missing))
    return result


_MEAT = {"chicken", "beef", "pork", "bacon", "ham", "lamb", "turkey", "duck", "sausage", "gelatin", "lard", "prosciutto", "chorizo"}
_FISH = {"fish", "salmon", "tuna", "prawn", "shrimp", "anchovy", "sardine", "cod", "haddock", "crab", "lobster", "mussel", "oyster", "clam", "squid", "scallop"}
_DAIRY = {"milk", "cream", "butter", "cheese", "cheddar", "parmesan", "yogurt", "ghee", "mozzarella", "feta", "ricotta", "paneer"}
_NUTS = {"nut", "almond", "peanut", "cashew", "walnut", "pecan", "pistachio", "hazelnut", "pesto", "marzipan", "praline"}
_GLUTEN = {"flour", "wheat", "bread", "pasta", "spaghetti", "noodle", "couscous", "barley", "bulgur", "semolina", "soy sauce", "breadcrumb"}


def allowed_by_diet(raw: list[tuple[str, str]], request: RecipeDiscoveryRequest) -> bool:
    names = [canonical_name(name) for name, _ in raw]
    words = set(" ".join(names).split())
    diet = " ".join(request.dietary_preferences).lower() + " " + request.question.lower()
    banned: set[str] = set()
    if "vegetarian" in diet or "vegan" in diet:
        banned |= _MEAT | _FISH
        if any("stock" in name or "broth" in name for name in names) and not any("vegetable" in name for name in names):
            return False
    if "vegan" in diet:
        banned |= _DAIRY | {"egg", "honey", "mayonnaise"}
    if "pescatarian" in diet:
        banned |= _MEAT
    if "halal" in diet:
        banned |= {"pork", "bacon", "ham", "lard", "wine", "beer", "vodka", "rum", "brandy", "whisky", "whiskey", "gelatin"}
    for avoid in request.avoid_ingredients:
        clean = canonical_name(avoid)
        if "nut" in clean or "peanut" in clean:
            banned |= _NUTS
        elif "dairy" in clean or clean == "milk":
            banned |= _DAIRY
        elif "gluten" in clean or "wheat" in clean:
            banned |= _GLUTEN
        elif "shellfish" in clean:
            banned |= {"prawn", "shrimp", "crab", "lobster", "mussel", "oyster", "clam", "scallop"}
        elif clean:
            banned.add(clean)
    if "gluten-free" in diet or "gluten free" in diet:
        banned |= _GLUTEN
    if "dairy-free" in diet or "dairy free" in diet:
        banned |= _DAIRY
    return not any((term in words if " " not in term else any(term in name for name in names)) for term in banned)
