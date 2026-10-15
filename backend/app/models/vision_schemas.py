from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, Field


# ─────────────────────────────────────────────────────────────────────────────
# 1. RECEIPT SCHEMAS (Gemini Structured Output & API Output)
# ─────────────────────────────────────────────────────────────────────────────

class GeminiReceiptItem(BaseModel):
    raw_text: str = Field(
        ...,
        description="Line exactly as printed on the receipt, preserving original characters",
    )
    name: str = Field(
        ...,
        description="Short generic English ingredient or item name with brand removed (e.g., 'tomato' for 'TOM LOOSE', 'milk' for 'Olpers Full Cream Milk 1L')",
    )
    pack_size: float | None = Field(
        default=None,
        description="Printed size, weight, or volume per item. Null if not explicitly printed. Loose weighed items: weight goes here.",
    )
    unit: str | None = Field(
        default=None,
        description="Unit of measure: 'g', 'kg', 'ml', 'l', 'pcs', or null if not printed",
    )
    count: float | None = Field(
        default=None,
        description="Number of packs/items. Loose weighed produce should have count=1. Null if not visible.",
    )
    line_price: float | None = Field(
        default=None,
        description="Total price charged on this receipt line. Null if not printed or unreadable.",
    )
    is_food: bool = Field(
        default=True,
        description="False for non-food items such as shopping bags, detergent, soap, napkins, taxes, or service fees.",
    )
    confidence: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Confidence between 0.0 (unreadable/unclear) and 1.0 (crisp, clearly printed).",
    )


class GeminiReceiptResponse(BaseModel):
    store_name: str | None = Field(
        default=None,
        description="Name of the grocery store, market, or retailer if printed.",
    )
    date: str | None = Field(
        default=None,
        description="Date in YYYY-MM-DD format if visible on the receipt. Null otherwise.",
    )
    currency: str | None = Field(
        default=None,
        description="Currency symbol or code (e.g. PKR, Rs, USD, $, GBP, £, EUR) if printed.",
    )
    receipt_total: float | None = Field(
        default=None,
        description="Final total amount printed on the receipt. Null if unreadable or not printed.",
    )
    discounts_total: float | None = Field(
        default=0.0,
        description="Total amount saved via discounts/coupons. Must NOT be included as an item line.",
    )
    items: list[GeminiReceiptItem] = Field(
        default_factory=list,
        description="List of all extracted receipt line items.",
    )


class ValidatedReceiptItem(BaseModel):
    raw_text: str
    name: str
    matched_ingredient: str
    pack_size: float | None = None
    unit: str = "pcs"
    count: float | None = None
    total_qty: float = 1.0
    line_price: float | None = None
    is_food: bool = True
    confidence: float = 1.0
    needs_review: bool = False
    storage_zone: str = "Pantry Shelf"
    review_reasons: list[str] = Field(default_factory=list)


class ValidatedReceiptResponse(BaseModel):
    scan_id: str
    store_name: str | None = None
    date: str | None = None
    currency: str | None = None
    receipt_total: float | None = None
    discounts_total: float = 0.0
    calculated_items_total: float = 0.0
    total_difference_percent: float = 0.0
    total_mismatch_warning: bool = False
    items: list[ValidatedReceiptItem] = Field(default_factory=list)
    image_hash: str | None = None


# ─────────────────────────────────────────────────────────────────────────────
# 2. FRIDGE SCAN SCHEMAS (Gemini Structured Output & Reconciliation)
# ─────────────────────────────────────────────────────────────────────────────

class GeminiFridgeItem(BaseModel):
    name: str = Field(
        ...,
        description="Generic English ingredient name of the clearly visible item on the shelf/section.",
    )
    count: int | None = Field(
        default=None,
        description="Count of individually countable items (e.g. 4 eggs, 2 apples, 3 cans). Null if unsure or not countable.",
    )
    fill_level: float | None = Field(
        default=None,
        ge=0.0,
        le=1.0,
        description="Estimated fill fraction (0.0 to 1.0) strictly for opened packaged liquids/sauces/condiments. Null otherwise.",
    )
    label_size_text: str | None = Field(
        default=None,
        description="Printed net volume or weight strictly if visibly printed on label (e.g. '1L', '500g'). Null if not printed.",
    )
    confidence: float = Field(
        default=1.0,
        ge=0.0,
        le=1.0,
        description="Visual recognition confidence between 0.0 and 1.0.",
    )


class GeminiFridgeScan(BaseModel):
    items: list[GeminiFridgeItem] = Field(
        default_factory=list,
        description="List of detected food and beverage items on this fridge shelf/section.",
    )


class ExistingPantryItem(BaseModel):
    id: str
    name: str
    quantity: float
    unit: str
    location: str = "Fridge"
    estimated: bool = False


class ReconciledFridgeItem(BaseModel):
    detected_name: str
    matched_pantry_id: str | None = None
    matched_name: str | None = None
    detected_count: int | None = None
    detected_fill_level: float | None = None
    label_size_text: str | None = None
    confidence: float = 1.0
    status: Literal["verified", "mismatch", "new_item"]
    question: str | None = None
    current_quantity: float | None = None
    suggested_quantity: float | None = None
    unit: str = "pcs"
    estimated: bool = True
    verified_at: str | None = None


class FridgeScanResponse(BaseModel):
    scan_id: str
    detected_items: list[GeminiFridgeItem]
    reconciled_items: list[ReconciledFridgeItem]
    verified_count: int = 0
    mismatch_count: int = 0
    new_items_count: int = 0
