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
    CookingStepValidationResponse,
    StepExplanationResponse,
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

    def _invoke_structured_scan(self, image_bytes, mime_type, schema, prompt, operation):
        from google.genai import types

        client = self._get_client()
        deadline = time.monotonic() + 32
        models = self._get_candidate_models()
        last_error = None
        for index, model in enumerate(models):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise HTTPException(status_code=504, detail="Scanning took too long. Please try again shortly.")
            try:
                logger.info("%s with model %s (attempt %d/%d)", operation, model, index + 1, len(models))
                response = client.models.generate_content(
                    model=model,
                    contents=[types.Part.from_bytes(data=image_bytes, mime_type=mime_type), prompt],
                    config=types.GenerateContentConfig(
                        response_mime_type="application/json",
                        response_schema=schema,
                        temperature=0.0,
                        http_options=types.HttpOptions(
                            timeout=min(25_000, max(1, int(remaining * 1000))),
                            retry_options=types.HttpRetryOptions(attempts=1),
                        ),
                    ),
                )
                parsed = getattr(response, "parsed", None)
                if parsed is not None:
                    return parsed if isinstance(parsed, schema) else schema.model_validate(parsed)
                if response.text:
                    return schema.model_validate_json(response.text)
                raise HTTPException(status_code=422, detail="No food items could be read from this photo. Try a clear, well-lit image.")
            except HTTPException:
                raise
            except Exception as error:
                last_error = error
                message = str(error).lower()
                # A project quota or invalid request will not improve by waiting
                # through several models using the same credentials.
                if any(word in message for word in ("429", "quota", "resource_exhausted", "invalid_argument", "bad request", "permission_denied", "unauthenticated", "api_key_invalid")):
                    self._handle_genai_error(error)
                    raise HTTPException(status_code=503, detail="The scanning service is not configured correctly. Please try again later.") from None
                transient = any(word in message for word in ("503", "504", "timeout", "deadline", "unavailable", "demand", "404", "not_found"))
                if not transient:
                    break
        if last_error is not None:
            self._handle_genai_error(last_error)
        raise HTTPException(status_code=503, detail="The scanning service is temporarily unavailable. Please try again later.")

    def _invoke_gemini_receipt(self, image_bytes: bytes, mime_type: str) -> GeminiReceiptResponse:
        return self._invoke_structured_scan(image_bytes, mime_type, GeminiReceiptResponse, RECEIPT_SYSTEM_PROMPT, "Parsing receipt")

    def _invoke_gemini_fridge(self, image_bytes: bytes, mime_type: str) -> GeminiFridgeScan:
        return self._invoke_structured_scan(image_bytes, mime_type, GeminiFridgeScan, FRIDGE_SYSTEM_PROMPT, "Scanning fridge")

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

    def validate_cooking_step(
        self,
        image_bytes: bytes,
        mime_type: str,
        recipe_title: str,
        step_number: int,
        step_instruction: str,
        user_question: str | None = None,
        user_id: str = "default_user",
    ) -> CookingStepValidationResponse:
        self.rate_limiter.check_and_record(user_id)
        self._validate_image_bytes(image_bytes)
        image_hash = hashlib.sha256(image_bytes).hexdigest()

        question_text = (user_question or "").strip()
        if not question_text:
            question_text = "Does my cooking progress in this photo meet the requirements of this step?"

        prompt = (
            f"You are an expert executive chef evaluating a home cook's cooking step in real-time.\n"
            f"Recipe: {recipe_title}\n"
            f"Step {step_number}: {step_instruction}\n"
            f"Cook's query / check: {question_text}\n\n"
            "Analyze the image carefully for doneness, color (e.g. golden brown vs pale or burnt), "
            "texture, moisture, and visible signs of pan heat. First decide whether the photo is clear, "
            "well-lit, and actually shows enough food to assess. Never infer internal temperature, "
            "microbial safety, or complete doneness from appearance alone.\n"
            "Return structured JSON matching CookingStepValidationResponse:\n"
            "- status: 'ready', 'needs_more_time', 'reduce_heat', 'increase_heat', "
            "'attention_needed', or 'unable_to_assess'\n"
            "- headline: short encouraging 3-6 word title (e.g. 'Golden Brown & Ready!', 'Almost There — Needs Time')\n"
            "- feedback: concise expert culinary feedback directly answering the cook's question\n"
            "- action_suggestion: immediate practical next step for the cook at the stove\n"
            "- visual_observations: list of 2-3 specific visual cues observed\n"
            "- confidence: 0.0 to 1.0\n"
            "- image_sufficient: false when blur, darkness, framing, steam, or occlusion prevents assessment\n"
            "- safety_note: explicitly say a photo cannot verify internal temperature or food safety"
        )

        try:
            client = self._get_client()
            from google.genai import types

            part = types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
            for model in self._get_candidate_models():
                try:
                    response = client.models.generate_content(
                        model=model,
                        contents=[part, prompt],
                        config=types.GenerateContentConfig(
                            response_mime_type="application/json",
                            response_schema=CookingStepValidationResponse,
                            temperature=0.1,
                            http_options=types.HttpOptions(timeout=25_000),
                        ),
                    )
                    if getattr(response, "parsed", None) is not None:
                        res: CookingStepValidationResponse = response.parsed  # type: ignore
                        res.image_hash = image_hash
                        return res
                    if response.text:
                        res = CookingStepValidationResponse.model_validate_json(response.text)
                        res.image_hash = image_hash
                        return res
                except Exception as model_err:
                    logger.warning("Step validation failed on %s: %s", model, model_err)
                    continue
        except Exception as err:
            logger.error("Failed to query Gemini for step validation: %s", err)

        # A failed model call has not inspected the image. Be explicit rather than
        # fabricating a visual assessment.
        return CookingStepValidationResponse(
            status="unable_to_assess",
            headline="Photo Check Unavailable",
            feedback=(
                "I could not reliably analyze this photo right now, so I cannot say whether "
                f"Step {step_number} is complete."
            ),
            action_suggestion=(
                f"Use the displayed cues for '{step_instruction}', or retry with a clear, "
                "well-lit close photo that shows the whole pan."
            ),
            visual_observations=[],
            confidence=0.0,
            image_sufficient=False,
            safety_note=(
                "A photo cannot verify internal temperature, complete doneness, or food safety; "
                "use a food thermometer whenever the recipe requires one."
            ),
            image_hash=image_hash,
        )

    def get_step_explanation(
        self,
        recipe_title: str,
        step_number: int,
        step_instruction: str,
    ) -> StepExplanationResponse:
        """Provide detailed culinary breakdown and sensory cues for a step."""
        system_prompt = (
            "You are a master culinary educator. Provide a sensory-rich, practical breakdown of how to execute "
            f"this step with professional technique.\n"
            f"Recipe: {recipe_title}\n"
            f"Step {step_number}: {step_instruction}\n"
            "Treat all times as estimates and make observable doneness and food-safety checks primary. "
            "Return JSON matching StepExplanationResponse with fields: recipe_title, step_number, action, "
            "overview, heat_level (low/medium-low/medium/medium-high/high where applicable), pace, "
            "estimated_duration, technique (including how often to stir/flip/check), visual_cues (list), "
            "texture_and_aroma, aroma_and_sound, precautions (list), mistakes_to_avoid (list), "
            "completion_criteria, and pro_tip."
        )

        try:
            client = self._get_client()
            from google.genai import types

            for model in self._get_candidate_models():
                try:
                    response = client.models.generate_content(
                        model=model,
                        contents=system_prompt,
                        config=types.GenerateContentConfig(
                            response_mime_type="application/json",
                            response_schema=StepExplanationResponse,
                            temperature=0.2,
                            http_options=types.HttpOptions(timeout=20_000),
                        ),
                    )
                    if getattr(response, "parsed", None) is not None:
                        return response.parsed  # type: ignore
                    if response.text:
                        return StepExplanationResponse.model_validate_json(response.text)
                except Exception as model_err:
                    logger.warning("Step explanation failed on %s: %s", model, model_err)
                    continue
        except Exception as err:
            logger.error("Failed to query Gemini for step explanation: %s", err)

        # Heuristic fallback based on step content
        lower = step_instruction.lower()
        heat = "Medium heat"
        if any(w in lower for w in ["sear", "boil", "high"]):
            heat = "Medium-high to high heat"
        elif any(w in lower for w in ["simmer", "low", "melt"]):
            heat = "Low to medium-low heat"

        visuals = [
            f"Look for expected physical change specified in: '{step_instruction}'",
            "Color should transition gradually and evenly without scorching",
        ]
        if "onion" in lower or "golden" in lower or "brown" in lower:
            visuals = [
                "Onions turn from translucent white to a rich honey-amber gold",
                "Edges soften and caramelize without blackened burnt spots",
            ]

        return StepExplanationResponse(
            recipe_title=recipe_title,
            step_number=step_number,
            action=step_instruction,
            overview=(
                f"Execute this step with care: {step_instruction}. "
                "Keep heat controlled and monitor your food closely to develop flavor without overcooking."
            ),
            pace="Cook steadily and check progress often",
            estimated_duration="Timing varies; prioritize the visible, texture, and aroma cues",
            technique="Stir, turn, or check often enough to prevent hot spots and uneven cooking",
            visual_cues=visuals,
            texture_and_aroma="Look for the expected texture change and a clean, developed aroma without acrid smoke.",
            aroma_and_sound="A steady gentle sizzle and rising savory aromas indicate proper heat transfer.",
            heat_level=heat,
            pro_tip="Do not overcrowd the pan; allowing moisture to evaporate produces browning rather than steaming.",
            precautions=[
                "Treat time as an estimate and never use color alone for food-safety decisions",
                "Use a food thermometer for meat, poultry, seafood, and reheated food when appropriate",
            ],
            mistakes_to_avoid=[
                "Rushing with heat too high, which burns exterior before cooking through",
                "Neglecting to stir periodically, leading to hot spots in the pan",
            ],
            completion_criteria=(
                "Proceed only when the instruction's observable goal is met and any required "
                "safe internal temperature has been checked."
            ),
        )

    def chat_cooking_step(
        self,
        recipe_title: str,
        step_number: int,
        step_instruction: str,
        message: str,
        conversation_history: list[dict[str, str]] | None = None,
        adjustments: list[str] | None = None,
        dietary_restrictions: list[str] | None = None,
    ) -> str:
        """Provide immediate, step-aware sous chef assistance for questions asked verbally or typed."""
        system_instruction = (
            "You are Chef CulinaryAI, a warm, reassuring sous-chef in the user's kitchen.\n"
            f"Recipe in progress: {recipe_title}\n"
            f"Current Step #{step_number}: '{step_instruction}'\n"
            "The cook is currently at the stove and asking a question verbally or via chat.\n"
            "Rules:\n"
            "1. Give an immediate, concise, practical answer directly answering their question.\n"
            "2. If they ask 'what is the requirement?' or 'what do I need to do?', clearly explain "
            "the goal of this step, how to tell when it's done, and flame/technique tips.\n"
            "3. If they ask about sensory checks (like golden brown onion), explain the exact visual, "
            "color, and texture signs to look for.\n"
            "4. Never claim an image or color proves a safe internal temperature. Recommend a thermometer "
            "where food safety matters (poultry: 74°C/165°F).\n"
            "5. Do not advance the recipe unless the cook explicitly asks to move to the next step.\n"
            "6. Respond naturally in English, Urdu, or the user's mixed-language style.\n"
            "7. Keep it concise, friendly, and easy to read while busy (under 2 short paragraphs)."
        )

        history_text = "\n".join(
            f"{turn.get('role', 'user')}: {turn.get('content', '')}"
            for turn in (conversation_history or [])[-10:]
        )
        context_text = (
            f"\nDietary restrictions: {', '.join(dietary_restrictions or []) or 'none provided'}"
            f"\nCooking adjustments so far: {', '.join(adjustments or []) or 'none'}"
            f"\nRecent conversation:\n{history_text or 'none'}"
        )

        try:
            client = self._get_client()
            models_to_try = self._get_candidate_models()
            for model in models_to_try:
                try:
                    response = client.models.generate_content(
                        model=model,
                        contents=f"{system_instruction}{context_text}\n\nCook's Question: {message}",
                    )
                    if response and response.text:
                        return response.text.strip()
                except Exception as model_err:
                    logger.warning("Step chat error on %s: %s", model, model_err)
                    continue
        except Exception as err:
            logger.error("Failed to query Gemini for step chat: %s", err)

        # Fallback response
        msg_lower = message.lower()
        if "requirement" in msg_lower or "what should i do" in msg_lower or "what to do" in msg_lower:
            return (
                f"For Step {step_number}, your main goal is: {step_instruction}. "
                "Keep your heat at a steady medium level, stir periodically, and look for even color and texture."
            )
        elif "onion" in msg_lower or "golden" in msg_lower or "brown" in msg_lower:
            return (
                "Golden brown onions should look rich amber and sweet-scented, soft but not crispy or blackened. "
                "If they are still white or pale yellow, give them 3-5 more minutes on medium-low heat with occasional stirring."
            )
        return (
            f"For Step {step_number} of {recipe_title}: {step_instruction}. "
            "Take your time, keep flame moderate, and let me know if you want to verify your progress with a quick photo!"
        )

