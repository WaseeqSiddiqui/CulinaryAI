from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Any

from app.models.vision_schemas import (
    ExistingPantryItem,
    FridgeScanResponse,
    GeminiFridgeScan,
    ReconciledFridgeItem,
)
from app.services.ingredient_catalog import IngredientCatalogService


class FridgeReconciler:
    def __init__(self, catalog: IngredientCatalogService | None = None) -> None:
        self.catalog = catalog or IngredientCatalogService()

    def reconcile(
        self,
        detected_scan: GeminiFridgeScan,
        pantry_items: list[ExistingPantryItem],
    ) -> FridgeScanResponse:
        now_iso = datetime.now(timezone.utc).isoformat()
        reconciled_items: list[ReconciledFridgeItem] = []
        matched_pantry_ids: set[str] = set()

        verified_count = 0
        mismatch_count = 0
        new_items_count = 0

        for detected in detected_scan.items:
            # Clean name
            detected_name = detected.name.strip()
            if not detected_name:
                continue

            # Find matching item in existing pantry items
            matched_item = self._find_matching_pantry_item(
                detected_name, pantry_items, matched_pantry_ids
            )

            if matched_item is not None:
                matched_pantry_ids.add(matched_item.id)
                reconciled = self._reconcile_matched(
                    detected=detected,
                    pantry_item=matched_item,
                    now_iso=now_iso,
                )
            else:
                # Item not found in household ledger
                reconciled = self._create_new_item_proposal(detected)

            if reconciled.status == "verified":
                verified_count += 1
            elif reconciled.status == "mismatch":
                mismatch_count += 1
            elif reconciled.status == "new_item":
                new_items_count += 1

            reconciled_items.append(reconciled)

        # Note: Unseen pantry items are explicitly NOT reduced or deleted (may be hidden)
        scan_id = f"fridge_{int(time.time())}"

        return FridgeScanResponse(
            scan_id=scan_id,
            detected_items=detected_scan.items,
            reconciled_items=reconciled_items,
            verified_count=verified_count,
            mismatch_count=mismatch_count,
            new_items_count=new_items_count,
        )

    def _find_matching_pantry_item(
        self,
        detected_name: str,
        pantry_items: list[ExistingPantryItem],
        already_matched_ids: set[str],
    ) -> ExistingPantryItem | None:
        cleaned_target = detected_name.lower().strip()

        # 1. Exact name match
        for item in pantry_items:
            if item.id in already_matched_ids:
                continue
            if item.name.lower().strip() == cleaned_target:
                return item

        # 2. Substring match
        for item in pantry_items:
            if item.id in already_matched_ids:
                continue
            iname = item.name.lower().strip()
            if iname in cleaned_target or cleaned_target in iname:
                return item

        # 3. Semantic match via catalog
        match = self.catalog.match(detected_name)
        if not match.needs_review:
            canonical = match.matched_name.lower().strip()
            for item in pantry_items:
                if item.id in already_matched_ids:
                    continue
                if item.name.lower().strip() == canonical:
                    return item

        return None

    def _reconcile_matched(
        self,
        detected: Any,
        pantry_item: ExistingPantryItem,
        now_iso: str,
    ) -> ReconciledFridgeItem:
        # Case 1: Countable item (e.g. eggs, lemons, cans)
        if detected.count is not None:
            detected_qty = float(detected.count)
            current_qty = pantry_item.quantity

            # Small tolerance: within 0.5 (or <= 10% for large quantities)
            tolerance = 0.5 if current_qty < 10 else current_qty * 0.10
            diff = abs(detected_qty - current_qty)

            if diff <= tolerance:
                # Matches within tolerance -> Mark verified with timestamp
                return ReconciledFridgeItem(
                    detected_name=detected.name,
                    matched_pantry_id=pantry_item.id,
                    matched_name=pantry_item.name,
                    detected_count=detected.count,
                    confidence=detected.confidence,
                    status="verified",
                    current_quantity=current_qty,
                    suggested_quantity=current_qty,
                    unit=pantry_item.unit,
                    estimated=False,
                    verified_at=now_iso,
                )
            else:
                # Mismatch -> Return as a question for the user (NEVER change stock silently)
                question = (
                    f"Camera detected {detected.count:g} {pantry_item.unit} of '{pantry_item.name}', "
                    f"but your pantry lists {current_qty:g} {pantry_item.unit}. "
                    f"Update stock to {detected.count:g} {pantry_item.unit}?"
                )
                return ReconciledFridgeItem(
                    detected_name=detected.name,
                    matched_pantry_id=pantry_item.id,
                    matched_name=pantry_item.name,
                    detected_count=detected.count,
                    confidence=detected.confidence,
                    status="mismatch",
                    question=question,
                    current_quantity=current_qty,
                    suggested_quantity=detected_qty,
                    unit=pantry_item.unit,
                    estimated=True,  # Camera-derived quantities marked estimated=True
                )

        # Case 2: Opened package with fill_level (e.g. milk, sauce, condiment)
        if detected.fill_level is not None:
            fill_fraction = float(detected.fill_level)
            # Estimate volume based on current unit / pack
            unit = pantry_item.unit.lower()
            current_qty = pantry_item.quantity

            # Base pack capacity
            base_pack = 1.0 if current_qty <= 1.0 else (current_qty if current_qty <= 2.0 else 1.0)
            suggested_qty = round(fill_fraction * base_pack, 2)

            if abs(current_qty - suggested_qty) <= 0.15:
                # Verified within 15% tolerance
                return ReconciledFridgeItem(
                    detected_name=detected.name,
                    matched_pantry_id=pantry_item.id,
                    matched_name=pantry_item.name,
                    detected_fill_level=detected.fill_level,
                    label_size_text=detected.label_size_text,
                    confidence=detected.confidence,
                    status="verified",
                    current_quantity=current_qty,
                    suggested_quantity=current_qty,
                    unit=pantry_item.unit,
                    estimated=False,
                    verified_at=now_iso,
                )
            else:
                # Fill mismatch question
                pct = int(fill_fraction * 100)
                question = (
                    f"'{pantry_item.name}' appears to be {pct}% full (~{suggested_qty:g} {pantry_item.unit}), "
                    f"while current stock shows {current_qty:g} {pantry_item.unit}. "
                    f"Adjust stock level to {suggested_qty:g} {pantry_item.unit}?"
                )
                return ReconciledFridgeItem(
                    detected_name=detected.name,
                    matched_pantry_id=pantry_item.id,
                    matched_name=pantry_item.name,
                    detected_fill_level=detected.fill_level,
                    label_size_text=detected.label_size_text,
                    confidence=detected.confidence,
                    status="mismatch",
                    question=question,
                    current_quantity=current_qty,
                    suggested_quantity=suggested_qty,
                    unit=pantry_item.unit,
                    estimated=True,
                )

        # Case 3: Visible without count or fill level -> Verified present
        return ReconciledFridgeItem(
            detected_name=detected.name,
            matched_pantry_id=pantry_item.id,
            matched_name=pantry_item.name,
            confidence=detected.confidence,
            status="verified",
            current_quantity=pantry_item.quantity,
            suggested_quantity=pantry_item.quantity,
            unit=pantry_item.unit,
            estimated=pantry_item.estimated,
            verified_at=now_iso,
        )

    def _create_new_item_proposal(self, detected: Any) -> ReconciledFridgeItem:
        match = self.catalog.match(detected.name)
        canonical_name = match.matched_name if not match.needs_review else detected.name.title()
        unit = match.unit if match.unit else "pcs"

        suggested_qty = float(detected.count) if detected.count is not None else 1.0
        question = (
            f"Spotted fresh '{canonical_name}' in the fridge, but it is not in your kitchen stock. "
            f"Would you like to add it?"
        )

        return ReconciledFridgeItem(
            detected_name=detected.name,
            matched_name=canonical_name,
            detected_count=detected.count,
            detected_fill_level=detected.fill_level,
            label_size_text=detected.label_size_text,
            confidence=detected.confidence,
            status="new_item",
            question=question,
            current_quantity=0.0,
            suggested_quantity=suggested_qty,
            unit=unit,
            estimated=True,
        )
