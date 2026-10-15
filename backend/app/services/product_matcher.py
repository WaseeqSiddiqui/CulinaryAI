from __future__ import annotations

import json
import os
from typing import Any

from fastapi import HTTPException

from app.models.schemas import MatchProductRequest, MatchProductResponse


MATCH_PROMPT = """You match a wanted grocery item to store search results.
Return only the structured response. Never choose an out-of-stock result.
Prefer the pack size and number of packs that cover the wanted quantity with
the smallest reasonable excess. Do not silently substitute a materially
different product. Return chosen_index=null and units_to_buy=null when no
candidate fits. Confidence must reflect ambiguity.
"""


class ProductMatcher:
    def __init__(self, api_key: str | None = None, model_name: str | None = None):
        self.api_key = api_key or os.getenv("GEMINI_API_KEY", "")
        self.model_name = model_name or os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
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
            "candidates": [candidate.model_dump() for candidate in request.candidates],
        }
        try:
            response = self._get_client().models.generate_content(
                model=self.model_name,
                contents=[MATCH_PROMPT, json.dumps(payload)],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=MatchProductResponse,
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
