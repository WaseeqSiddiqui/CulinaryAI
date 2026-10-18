from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from collections import defaultdict
from datetime import datetime, timezone
from io import BytesIO
from typing import Any

from fastapi import HTTPException
from PIL import Image

from app.models.vision_schemas import (
    GeminiFridgeScan,
    GeminiReceiptItem,
    GeminiReceiptResponse,
    ValidatedReceiptItem,
    ValidatedReceiptResponse,
    MealNutritionEstimate,
)
from app.services.ingredient_catalog import IngredientCatalogService

logger = logging.getLogger(__name__)

# Free Flash model default – overridden by GEMINI_MODEL env var
DEFAULT_GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.5-flash")
FALLBACK_MODELS = ["gemini-3.5-flash", "gemini-3.1-flash-lite", "gemini-3.8-flash"]


class ScanRateLimiter:
    """In-memory rolling daily rate limiter per user/client."""

    def __init__(self, max_per_day: int = 20) -> None:
        self.max_per_day = max_per_day
        self._history: dict[str, list[float]] = defaultdict(list)

    def check_and_record(self, user_id: str) -> None:
        now = time.time()
        one_day_ago = now - 86400  # 24 hours

        # Clean old timestamps
        recent = [ts for ts in self._history[user_id] if ts > one_day_ago]
        self._history[user_id] = recent

        if len(recent) >= self.max_per_day:
            raise HTTPException(
                status_code=429,
                detail=f"Daily scan limit reached ({self.max_per_day} scans/day). Please try again tomorrow.",
            )

        self._history[user_id].append(now)

    def get_remaining(self, user_id: str) -> int:
        now = time.time()
        one_day_ago = now - 86400
        recent = [ts for ts in self._history[user_id] if ts > one_day_ago]
        return max(0, self.max_per_day - len(recent))

    def reset(self) -> None:
        self._history.clear()


RECEIPT_SYSTEM_PROMPT = """You are an expert grocery receipt parser.
Extract printed line items from grocery receipts and return structured data.

Rules:
1. The image may be in English, Urdu, or Roman Urdu, blurry or crumpled.
2. Extract only what is printed. NEVER guess, assume, or invent quantities, pack sizes, or prices. Use null when not visible.
3. raw_text: the line text exactly as printed on the receipt.
4. name: short generic English ingredient or food name with brand/merchant names removed (e.g. "TOM LOOSE" -> "tomato", "Olpers Milk 1L" -> "milk").
5. pack_size and unit: printed size or weight. Loose weighed produce: pack_size = weight (e.g. 1.25), count = 1.
6. count: number of packages/items purchased. If loose weighed, count = 1.
7. is_food: set to false for shopping bags, soap, detergent, shampoo, toiletries, tax lines, service charges, tips, or fees.
8. discounts: store total discounts in discounts_total. Do NOT include discounts as items in the items array.
9. Return valid JSON adhering strictly to the response schema.
"""

FRIDGE_SYSTEM_PROMPT = """You are an expert kitchen inventory visual auditor.
Analyze a real household fridge photo. It may show the full fridge, several shelves,
a door compartment, crisper, freezer section, or a cluttered pantry shelf. Food does
not need to be neatly arranged.

Rules:
1. Scan the entire visible image systematically: top-to-bottom and left-to-right.
2. Detect recognizable food from shape, packaging, label text, color, or container
   context even when partially occluded. Lower confidence when uncertain. Never
   invent a fully hidden item.
3. Use a useful generic English food name. A visible branded milk carton becomes
   "milk"; an egg tray becomes "eggs"; produce bags should name the visible produce.
4. Combine repeated examples of the same item into one result when practical.
5. count: report count only for visible countable items. Use null when an exact count
   is blocked or the product is not countable.
6. fill_level: estimate 0.0 to 1.0 only for opened liquids, jars, sauces, and similar
   containers whose contents are visible. Otherwise use null.
7. label_size_text: copy exact volume/weight only when readable on the package.
8. Ignore cookware, shelves, storage boxes with no visible food identity, and people.
9. Do not return an empty list merely because the fridge is cluttered. Return every
   reasonably recognizable food item with honest confidence.
10. Return valid JSON adhering strictly to the response schema.
"""

MEAL_NUTRITION_PROMPT = """You are a cautious food photo nutrition estimator.
Identify the visible meal and estimate nutrition for only the visible portion.
Return dish name, portion description, calories, protein, carbohydrates, fat,
fiber, confidence, and short assumptions. Do not claim medical precision. If
portion size or ingredients are unclear, lower confidence and state assumptions.
Never identify people or infer health conditions. Return structured JSON only.
"""


class GeminiVisionService:
    def __init__(
        self,
        api_key: str | None = None,
        model_name: str | None = None,
        catalog_service: IngredientCatalogService | None = None,
        rate_limiter: ScanRateLimiter | None = None,
    ) -> None:
        self.api_key = api_key or os.getenv("GEMINI_API_KEY", "")
        self.model_name = model_name or os.getenv("GEMINI_MODEL", DEFAULT_GEMINI_MODEL)
        self.catalog = catalog_service or IngredientCatalogService()
        self.rate_limiter = rate_limiter or ScanRateLimiter(max_per_day=20)
        self._client: Any = None

    def _get_client(self) -> Any:
        if self._client is not None:
            return self._client
        if not self.api_key:
            raise HTTPException(
                status_code=500,
                detail="GEMINI_API_KEY is not configured on the server. Please set the GEMINI_API_KEY environment variable.",
            )
        try:
            from google import genai

            self._client = genai.Client(api_key=self.api_key)
            return self._client
        except Exception as err:
            logger.error("Failed to initialize Google GenAI client: %s", err)
            raise HTTPException(
                status_code=500,
                detail=f"Failed to initialize Gemini Vision client: {err}",
            ) from err

    def parse_receipt(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
        user_id: str = "default_user",
        household_aliases: dict[str, str] | None = None,
    ) -> ValidatedReceiptResponse:
        # 1. Rate Limit
        self.rate_limiter.check_and_record(user_id)

        # 2. Validate image format
        self._validate_image_bytes(image_bytes)

        # 3. Compute image hash for duplicate detection
        image_hash = hashlib.sha256(image_bytes).hexdigest()

        # 4. Invoke Gemini with structured output
        gemini_response = self._invoke_gemini_receipt(image_bytes, mime_type)

        # 5. Backend Validation & Catalog Matching
        return self._validate_and_enrich_receipt(
            gemini_response=gemini_response,
            image_hash=image_hash,
            household_aliases=household_aliases,
        )

    def scan_fridge(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
        user_id: str = "default_user",
    ) -> GeminiFridgeScan:
        # 1. Rate Limit
        self.rate_limiter.check_and_record(user_id)

        # 2. Validate image format
        self._validate_image_bytes(image_bytes)

        # 3. Invoke Gemini
        return self._invoke_gemini_fridge(image_bytes, mime_type)

    def analyze_meal(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
        user_id: str = "default_user",
    ) -> MealNutritionEstimate:
        self.rate_limiter.check_and_record(user_id)
        self._validate_image_bytes(image_bytes)
        client = self._get_client()
        from google.genai import types

        part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
        last_error: Exception | None = None
        for model in self._get_candidate_models():
            try:
                response = client.models.generate_content(
                    model=model,
                    contents=[part, MEAL_NUTRITION_PROMPT],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=MealNutritionEstimate,
                        temperature=0.0,
                        http_options=types.HttpOptions(timeout=25_000),
                    ),
                )
                if getattr(response, "parsed", None) is not None:
                    return response.parsed  # type: ignore
                if response.text:
                    return MealNutritionEstimate.model_validate_json(response.text)
            except Exception as err:
                last_error = err
                continue
        if last_error:
            self._handle_genai_error(last_error)
        raise HTTPException(status_code=422, detail="The meal could not be estimated from this photo.")

    def _validate_image_bytes(self, image_bytes: bytes) -> None:
        if not image_bytes or len(image_bytes) < 10:
            raise HTTPException(
                status_code=400,
                detail="The provided image file is empty or corrupted.",
            )
        try:
            with Image.open(BytesIO(image_bytes)) as img:
                img.verify()
        except Exception as err:
            raise HTTPException(
                status_code=400,
                detail="The provided file is not a valid or readable image. Please upload a clear JPEG or PNG.",
            ) from err

    def _get_candidate_models(self) -> list[str]:
        candidates = [self.model_name]
        for fallback in FALLBACK_MODELS:
            if fallback not in candidates:
                candidates.append(fallback)
        return candidates

    def _invoke_gemini_receipt(
        self, image_bytes: bytes, mime_type: str
    ) -> GeminiReceiptResponse:
        client = self._get_client()
        from google.genai import types

        candidate_models = self._get_candidate_models()
        last_error: Exception | None = None

        for idx, model in enumerate(candidate_models):
            try:
                logger.info("Parsing receipt with model: %s (attempt %d/%d)", model, idx + 1, len(candidate_models))
                part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
                response = client.models.generate_content(
                    model=model,
                    contents=[part, RECEIPT_SYSTEM_PROMPT],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=GeminiReceiptResponse,
                        temperature=0.0,
                        http_options=types.HttpOptions(timeout=25_000),  # 25s timeout per attempt
                    ),
                )

                if getattr(response, "parsed", None) is not None:
                    return response.parsed  # type: ignore

                if response.text:
                    return GeminiReceiptResponse.model_validate_json(response.text)

                raise HTTPException(
                    status_code=422,
                    detail="Gemini returned an empty response. The receipt may be unreadable.",
                )
            except HTTPException:
                raise
            except Exception as err:
                last_error = err
                err_str = str(err).lower()
                is_transient = any(kw in err_str for kw in ["503", "504", "deadline", "timeout", "unavailable", "demand", "resource_exhausted", "quota", "429", "404", "not_found"])
                if is_transient and idx + 1 < len(candidate_models):
                    logger.warning("Model %s transient error: %s. Trying fallback model %s...", model, err, candidate_models[idx + 1])
                    continue
                break

        if last_error:
            self._handle_genai_error(last_error)
            raise HTTPException(status_code=500, detail=str(last_error)) from last_error

        raise HTTPException(status_code=500, detail="Failed to parse receipt after all model attempts.")

    def _invoke_gemini_fridge(
        self, image_bytes: bytes, mime_type: str
    ) -> GeminiFridgeScan:
        client = self._get_client()
        from google.genai import types

        candidate_models = self._get_candidate_models()
        last_error: Exception | None = None

        for idx, model in enumerate(candidate_models):
            try:
                logger.info("Scanning fridge with model: %s (attempt %d/%d)", model, idx + 1, len(candidate_models))
                part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
                response = client.models.generate_content(
                    model=model,
                    contents=[part, FRIDGE_SYSTEM_PROMPT],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=GeminiFridgeScan,
                        temperature=0.0,
                        http_options=types.HttpOptions(timeout=25_000),  # 25s timeout per attempt
                    ),
                )

                if getattr(response, "parsed", None) is not None:
                    return response.parsed  # type: ignore

                if response.text:
                    return GeminiFridgeScan.model_validate_json(response.text)

                return GeminiFridgeScan(items=[])
            except HTTPException:
                raise
            except Exception as err:
                last_error = err
                err_str = str(err).lower()
                is_transient = any(kw in err_str for kw in ["503", "504", "deadline", "timeout", "unavailable", "demand", "resource_exhausted", "quota", "429", "404", "not_found"])
                if is_transient and idx + 1 < len(candidate_models):
                    logger.warning("Model %s transient error: %s. Trying fallback model %s...", model, err, candidate_models[idx + 1])
                    continue
                break

        if last_error:
            self._handle_genai_error(last_error)
            raise HTTPException(status_code=500, detail=str(last_error)) from last_error

        return GeminiFridgeScan(items=[])

    def _handle_genai_error(self, err: Exception) -> None:
        err_msg = str(err).lower()
        if "503" in err_msg or "unavailable" in err_msg or "demand" in err_msg:
            raise HTTPException(
                status_code=503,
                detail="Gemini Vision models are currently experiencing high demand. Please try again shortly.",
            )
        if "quota" in err_msg or "resource_exhausted" in err_msg or "429" in err_msg:
            raise HTTPException(
                status_code=429,
                detail="Gemini API quota exceeded. Please check your API limits or try again later.",
            )
        if "deadline" in err_msg or "timeout" in err_msg:
            raise HTTPException(
                status_code=504,
                detail="Gemini vision request timed out. Please try again with a clearer or cropped image.",
            )
        if "bad request" in err_msg or "invalid_argument" in err_msg:
            raise HTTPException(
                status_code=400,
                detail=f"Gemini API rejected the image request: {err}",
            )

    def _validate_and_enrich_receipt(
        self,
        gemini_response: GeminiReceiptResponse,
        image_hash: str,
        household_aliases: dict[str, str] | None = None,
    ) -> ValidatedReceiptResponse:
        validated_items: list[ValidatedReceiptItem] = []
        calculated_total = 0.0

        for raw_item in gemini_response.items:
            reasons: list[str] = []
            needs_review = False

            # Rule: Sanitize name
            clean_name = raw_item.name.strip()
            if not clean_name:
                clean_name = raw_item.raw_text.strip() or "Unknown Item"
                needs_review = True
                reasons.append("Item name was blank")

            # Rule: Reject negative values
            line_price = raw_item.line_price
            if line_price is not None:
                if line_price < 0:
                    line_price = abs(line_price)
                    needs_review = True
                    reasons.append("Negative price detected and corrected")
                elif line_price > 1000000:
                    needs_review = True
                    reasons.append("Absurdly high price detected")

            count = raw_item.count
            if count is not None:
                if count < 0:
                    count = abs(count)
                    needs_review = True
                    reasons.append("Negative count detected and corrected")
                elif count > 500:
                    needs_review = True
                    reasons.append("Absurdly high item count detected")

            pack_size = raw_item.pack_size
            if pack_size is not None:
                if pack_size < 0:
                    pack_size = abs(pack_size)
                    needs_review = True
                    reasons.append("Negative pack size detected and corrected")
                elif pack_size > 50000:
                    needs_review = True
                    reasons.append("Absurdly high pack size detected")

            # Rule: Calculate total_qty
            # total_qty = count (default 1 if null but pack_size exists) * pack_size
            unit = (raw_item.unit or "").strip()
            if unit.lower() == "l":
                unit = "L"
            else:
                unit = unit.lower()

            if count is not None and pack_size is not None:
                total_qty = round(count * pack_size, 2)
            elif count is None and pack_size is not None:
                count = 1.0
                total_qty = round(pack_size, 2)
            elif count is not None and pack_size is None:
                total_qty = round(count, 2)
                if not unit:
                    unit = "pcs"
            else:
                # Both count and pack_size are null
                total_qty = 1.0
                needs_review = True
                reasons.append("Missing quantity: count and pack size are both null")
                if not unit:
                    unit = "pcs"

            # Match against ingredient catalog
            match = self.catalog.match(
                name=clean_name,
                raw_text=raw_item.raw_text,
                household_aliases=household_aliases,
            )

            if match.needs_review:
                needs_review = True
                reasons.append(f"Catalog match confidence low ({match.confidence:.2f})")

            # Low confidence check
            confidence = min(raw_item.confidence, match.confidence)
            if raw_item.confidence < 0.65:
                needs_review = True
                reasons.append(f"Vision confidence low ({raw_item.confidence:.2f})")

            # Determine storage zone
            storage_zone = match.storage_zone

            # Sum line prices for food items
            if line_price is not None:
                calculated_total += line_price

            validated_items.append(
                ValidatedReceiptItem(
                    raw_text=raw_item.raw_text,
                    name=clean_name,
                    matched_ingredient=match.matched_name,
                    pack_size=pack_size,
                    unit=unit or match.unit,
                    count=count,
                    total_qty=total_qty,
                    line_price=line_price,
                    is_food=raw_item.is_food,
                    confidence=round(confidence, 2),
                    needs_review=needs_review,
                    storage_zone=storage_zone,
                    review_reasons=reasons,
                )
            )

        # Flag if sum(line_price) - discounts differs from receipt_total by > 5%
        discounts = gemini_response.discounts_total or 0.0
        receipt_total = gemini_response.receipt_total
        total_mismatch = False
        diff_percent = 0.0

        if receipt_total is not None and receipt_total > 0:
            expected_total = calculated_total - discounts
            diff_percent = round(
                abs(expected_total - receipt_total) / receipt_total * 100, 2
            )
            if diff_percent > 5.0:
                total_mismatch = True

        scan_id = f"rcpt_{int(time.time())}_{image_hash[:8]}"

        return ValidatedReceiptResponse(
            scan_id=scan_id,
            store_name=gemini_response.store_name,
            date=gemini_response.date,
            currency=gemini_response.currency,
            receipt_total=receipt_total,
            discounts_total=discounts,
            calculated_items_total=round(calculated_total, 2),
            total_difference_percent=diff_percent,
            total_mismatch_warning=total_mismatch,
            items=validated_items,
            image_hash=image_hash,
        )

    def ask_chef(
        self,
        prompt: str,
        pantry_items: list[dict[str, Any]] | None = None,
    ) -> str:
        """Provide friendly, expert culinary and meal planning guidance using Gemini."""
        pantry_context = ""
        if pantry_items:
            items_str = ", ".join(
                f"{it.get('name')} ({it.get('quantity')} {it.get('unit')})"
                for it in pantry_items
            )
            pantry_context = f"\nThe user currently has these items in their kitchen inventory: {items_str}."
        else:
            pantry_context = "\nThe user's kitchen inventory is currently empty."

        system_instruction = (
            "You are Chef CulinaryAI, an encouraging, expert, and practical kitchen companion. "
            f"{pantry_context} "
            "Answer culinary and cooking questions concisely. Suggest meals, step-by-step guidance, "
            "substitutions, or tips matching their pantry ingredients. Keep your tone encouraging, "
            "clear, and under 3 short paragraphs."
        )

        try:
            client = self._get_client()
            models_to_try = [self.model_name] + [m for m in FALLBACK_MODELS if m != self.model_name]
            for model in models_to_try:
                try:
                    response = client.models.generate_content(
                        model=model,
                        contents=f"{system_instruction}\n\nUser Question: {prompt}",
                    )
                    if response and response.text:
                        return response.text.strip()
                except Exception as model_err:
                    logger.warning("Chef chat error on %s: %s", model, model_err)
                    continue
        except Exception as err:
            logger.error("Failed to query Gemini for chef chat: %s", err)

        return (
            "I'm Chef CulinaryAI! I can help you choose what to cook, find ingredient substitutes, "
            "and guide you through any recipe. Tell me what flavors you are in the mood for!"
        )

