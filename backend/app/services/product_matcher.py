from __future__ import annotations

import json
import os
import re
from typing import Any

from fastapi import HTTPException

from app.models.schemas import (
    MatchProductRequest,
    MatchProductResponse,
    NormalizeShoppingQueryRequest,
    NormalizeShoppingQueryResponse,
)


DEFAULT_GEMINI_MODEL = "gemini-3.8-flash"
MATCH_RESPONSE_SCHEMA = MatchProductResponse.model_json_schema()
NORMALIZE_RESPONSE_SCHEMA = NormalizeShoppingQueryResponse.model_json_schema()


MATCH_PROMPT = """You match a wanted grocery item to store search results.
Return every field in the structured response. The candidates are a zero-based
array: chosen_index=0 means the first candidate, chosen_index=1 the second, and
so on. units_to_buy is the integer number of packs to add, from 1 through 10.

Never choose an out-of-stock result. Prefer the pack size and number of packs
that cover the wanted quantity with the smallest reasonable excess. Do not
silently substitute a materially different product. Return chosen_index=null
and units_to_buy=null when no candidate fits. Confidence must reflect ambiguity.
When the wanted name is a safe generic normalization of a brand, variety, or
misspelling, an equivalent generic product may be selected. Product form and
important dietary or safety modifiers must still match: for example juice is
not whole fruit, milk powder is not liquid milk, and baby formula is not milk.
"""


NORMALIZE_PROMPT = """Turn a shopping-list entry into a concise store search
query. Correct spelling and transliterated/common grocery wording, and remove a
brand or variety only when a generic grocery is an acceptable equivalent.

Examples:
- "Himalia aaples" -> "apples"
- "Olpers milkk" -> "milk"
- "Nestle dahi" -> "yogurt"

Never change the product form or silently broaden a safety-sensitive request.
Preserve words and meaning such as juice, powder, flour, oil, vinegar, sauce,
jam, syrup, detergent, soap, shampoo, formula, frozen, canned, dried, flavored,
baby, diet, zero/sugar-free, lactose-free, gluten-free, vegan, and halal. Thus
"apple juice" must remain apple juice and "milk powder" must remain milk
powder. Preserve the requested grocery itself; do not invent a substitute.
Return every structured field. Set changed=true only when search_query differs
meaningfully from the input. Confidence reflects certainty about the intended
grocery.
"""


_PROTECTED_FORM_PATTERNS: dict[str, re.Pattern[str]] = {
    "juice": re.compile(r"\bjuic(?:e|es)?\b", re.I),
    "powder": re.compile(r"\bpowd(?:er|r)?\b", re.I),
    "flour": re.compile(r"\bflou?r\b", re.I),
    "oil": re.compile(r"\boil\b", re.I),
    "vinegar": re.compile(r"\bvinegar\b", re.I),
    "sauce": re.compile(r"\bsauce\b", re.I),
    "jam": re.compile(r"\bjam\b", re.I),
    "syrup": re.compile(r"\bsyrup\b", re.I),
    "detergent": re.compile(r"\bdetergent\b", re.I),
    "soap": re.compile(r"\bsoap\b", re.I),
    "shampoo": re.compile(r"\bshampoo\b", re.I),
    "formula": re.compile(r"\bformula\b", re.I),
    "frozen": re.compile(r"\bfrozen\b", re.I),
    "canned": re.compile(r"\bcanned?\b", re.I),
    "dried": re.compile(r"\bdried\b", re.I),
    "flavored": re.compile(r"\bflavou?red\b", re.I),
    "baby": re.compile(r"\bbaby\b", re.I),
    "diet": re.compile(r"\bdiet\b", re.I),
    "zero": re.compile(r"\bzero\b", re.I),
    "sugar-free": re.compile(r"\bsugar[ -]?free\b", re.I),
    "lactose-free": re.compile(r"\blactose[ -]?free\b", re.I),
    "gluten-free": re.compile(r"\bgluten[ -]?free\b", re.I),
    "vegan": re.compile(r"\bvegan\b", re.I),
    "halal": re.compile(r"\bhalal\b", re.I),
}


class ProductMatcher:
    def __init__(self, api_key: str | None = None, model_name: str | None = None):
        self.api_key = api_key or os.getenv("GEMINI_API_KEY", "")
        self.model_name = (
            model_name or os.getenv("GEMINI_MODEL", "") or DEFAULT_GEMINI_MODEL
        )
        self._client: Any = None

    def _get_client(self):
        if self._client is not None:
            return self._client
        if not self.api_key:
            raise HTTPException(status_code=500, detail="GEMINI_API_KEY is not configured")
        from google import genai

        self._client = genai.Client(api_key=self.api_key)
        return self._client

    def match(self, request: MatchProductRequest) -> MatchProductResponse:
        from google.genai import types

        payload = {
            "wanted": {
                "name": request.name,
                "quantity": request.quantity,
                "unit": request.unit,
            },
            "candidates": [
                {"index": index, **candidate.model_dump()}
                for index, candidate in enumerate(request.candidates)
            ],
        }
        try:
            response = self._get_client().models.generate_content(
                model=self.model_name,
                contents=[MATCH_PROMPT, json.dumps(payload)],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=MATCH_RESPONSE_SCHEMA,
                    temperature=0.0,
                ),
            )
            result = getattr(response, "parsed", None)
            if result is None:
                result = MatchProductResponse.model_validate_json(response.text)
            elif not isinstance(result, MatchProductResponse):
                result = MatchProductResponse.model_validate(result)
        except HTTPException:
            raise
        except Exception as error:
            raise HTTPException(status_code=502, detail=f"Product matching failed: {error}") from error

        return self.validate_result(request, result)

    def normalize_query(
        self, request: NormalizeShoppingQueryRequest
    ) -> NormalizeShoppingQueryResponse:
        from google.genai import types

        payload = request.model_dump()
        try:
            response = self._get_client().models.generate_content(
                model=self.model_name,
                contents=[NORMALIZE_PROMPT, json.dumps(payload)],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=NORMALIZE_RESPONSE_SCHEMA,
                    temperature=0.0,
                ),
            )
            result = getattr(response, "parsed", None)
            if result is None:
                result = NormalizeShoppingQueryResponse.model_validate_json(response.text)
            elif not isinstance(result, NormalizeShoppingQueryResponse):
                result = NormalizeShoppingQueryResponse.model_validate(result)
        except HTTPException:
            raise
        except Exception as error:
            raise HTTPException(
                status_code=502, detail=f"Shopping query normalization failed: {error}"
            ) from error

        return self.validate_normalization(request, result)

    @staticmethod
    def validate_normalization(
        request: NormalizeShoppingQueryRequest,
        result: NormalizeShoppingQueryResponse,
    ) -> NormalizeShoppingQueryResponse:
        source = request.name.strip()
        query = result.search_query.strip()
        canonical = result.canonical_name.strip()
        if not query or not canonical:
            raise HTTPException(status_code=502, detail="Normalizer returned a blank query")

        for label, pattern in _PROTECTED_FORM_PATTERNS.items():
            if pattern.search(source) and not pattern.search(query):
                return NormalizeShoppingQueryResponse(
                    search_query=source,
                    canonical_name=source,
                    confidence=0.0,
                    changed=False,
                    reason=f"Kept original because normalization dropped '{label}'",
                )

        changed = query.casefold() != source.casefold()
        return result.model_copy(update={"changed": changed})

    @staticmethod
    def validate_result(
        request: MatchProductRequest, result: MatchProductResponse
    ) -> MatchProductResponse:
        if result.chosen_index is None:
            if result.units_to_buy is not None:
                raise HTTPException(status_code=502, detail="Matcher returned units without a choice")
            return result
        if result.chosen_index < 0 or result.chosen_index >= len(request.candidates):
            raise HTTPException(status_code=502, detail="Matcher returned an invalid candidate index")
        if result.units_to_buy is None or result.units_to_buy <= 0:
            raise HTTPException(status_code=502, detail="Matcher returned an invalid quantity")
        if not request.candidates[result.chosen_index].in_stock:
            raise HTTPException(status_code=502, detail="Matcher selected an out-of-stock product")
        return result
