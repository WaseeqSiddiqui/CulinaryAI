"""Country preferences guide retrieval and ranking, never inventory or diet checks."""

import re

# Cuisine labels plus familiar dish searches. Searches still need live sources.
REGIONS = {
    "pakistan": ("Pakistani", ("biryani", "karahi", "dal", "chapati")),
    "india": ("Indian", ("dal", "masala", "idli")),
    "bangladesh": ("Bangladeshi", ("khichuri", "bhuna")),
    "sri lanka": ("Sri Lankan", ("kottu", "dhal")),
    "afghanistan": ("Afghan", ("kabuli", "mantu")),
    "nepal": ("Nepalese", ("momo", "dal bhat")),
    "united kingdom": ("British", ("shepherd", "fish pie")),
    "united states": ("American", ("chili", "burger")),
    "canada": ("Canadian", ("poutine",)),
    "australia": ("Australian", ("meat pie",)),
    "new zealand": ("New Zealand", ("kumara",)),
    "united arab emirates": ("Emirati", ("machboos", "harees")),
    "saudi arabia": ("Saudi Arabian", ("kabsa", "saleeg")),
    "turkey": ("Turkish", ("kofte", "menemen")),
    "iran": ("Persian", ("tahdig", "ghormeh")),
    "egypt": ("Egyptian", ("koshari",)),
    "morocco": ("Moroccan", ("tagine", "couscous")),
    "lebanon": ("Lebanese", ("tabbouleh", "mujadara")),
    "italy": ("Italian", ("risotto", "pasta")),
    "france": ("French", ("ratatouille", "quiche")),
    "germany": ("German", ("schnitzel",)),
    "spain": ("Spanish", ("paella", "tortilla")),
    "portugal": ("Portuguese", ("bacalhau",)),
    "greece": ("Greek", ("moussaka",)),
    "china": ("Chinese", ("fried rice", "stir fry")),
    "japan": ("Japanese", ("donburi", "teriyaki")),
    "south korea": ("Korean", ("bibimbap", "bulgogi")),
    "thailand": ("Thai", ("pad thai",)),
    "vietnam": ("Vietnamese", ("pho",)),
    "malaysia": ("Malaysian", ("nasi lemak",)),
    "indonesia": ("Indonesian", ("nasi goreng",)),
    "philippines": ("Filipino", ("adobo",)),
    "mexico": ("Mexican", ("tacos", "enchiladas")),
    "brazil": ("Brazilian", ("feijoada",)),
    "nigeria": ("Nigerian", ("jollof", "egusi")),
    "south africa": ("South African", ("bobotie",)),
    "kenya": ("Kenyan", ("ugali",)),
    "ethiopia": ("Ethiopian", ("injera",)),
    "ireland": ("Irish", ("irish stew",)),
    "sweden": ("Swedish", ("meatballs",)),
    "poland": ("Polish", ("pierogi",)),
    "ukraine": ("Ukrainian", ("borscht",)),
    "russia": ("Russian", ("stroganoff",)),
    "jamaica": ("Jamaican", ("jerk chicken",)),
}
ALIASES = {"pk": "pakistan", "in": "india", "uk": "united kingdom", "gb": "united kingdom", "usa": "united states", "us": "united states", "uae": "united arab emirates"}


def regional_preference(country: str, question: str = "") -> tuple[str, tuple[str, ...]]:
    # Explicit cuisine requests take precedence over the country default.
    for cuisine, dishes in REGIONS.values():
        if re.search(rf"\b{re.escape(cuisine)}\b", question, re.I):
            return cuisine, dishes
    key = country.strip().lower()
    key = ALIASES.get(key, key)
    return REGIONS.get(key, (country.strip(), ()))


def regional_match(name: str, area: str, cuisine: str, dishes: tuple[str, ...]) -> bool:
    if not cuisine:
        return False
    return area.casefold() == cuisine.casefold() or any(
        re.search(rf"\b{re.escape(dish)}\b", name, re.I) for dish in dishes
    )
