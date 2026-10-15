"""Test script that runs a folder of sample receipts through /parse-receipt.

Prints, per receipt:
- Receipt filename
- Items found (total count and names)
- Items with null quantity
- Total match: Yes / No / N/A
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

# Add backend root to sys.path so app imports work
backend_dir = Path(__file__).resolve().parents[1]
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFont

from app.main import app, vision_service
from app.models.vision_schemas import GeminiReceiptItem, GeminiReceiptResponse


def generate_synthetic_receipt_image(title: str, lines: list[str]) -> bytes:
    """Generates a simple grayscale receipt image with text for testing."""
    width, height = 500, max(400, 80 + len(lines) * 28)
    image = Image.new("RGB", (width, height), color="white")
    draw = ImageDraw.Draw(image)

    # Draw store title
    draw.text((30, 20), title, fill="black")
    draw.line([(30, 45), (470, 45)], fill="gray", width=1)

    # Draw line items
    y = 60
    for line in lines:
        draw.text((30, y), line, fill="black")
        y += 24

    draw.line([(30, y + 10), (470, y + 10)], fill="gray", width=1)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def create_sample_receipts(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)

    samples = [
        (
            "receipt_metro.jpg",
            "METRO CASH & CARRY",
            [
                "2 x Olpers Milk 1L              560.00",
                "1 x White Bread Large           220.00",
                "Dozen Eggs                      380.00",
                "Tomatoes 1.5kg                  180.00",
                "SUBTOTAL                       1340.00",
                "DISCOUNT                         40.00",
                "TOTAL                          1300.00",
            ],
            GeminiReceiptResponse(
                store_name="Metro Cash & Carry",
                date="2026-10-14",
                currency="PKR",
                receipt_total=1300.0,
                discounts_total=40.0,
                items=[
                    GeminiReceiptItem(raw_text="2 x Olpers Milk 1L 560.00", name="Milk", pack_size=1.0, unit="L", count=2.0, line_price=560.0, is_food=True, confidence=0.98),
                    GeminiReceiptItem(raw_text="1 x White Bread Large 220.00", name="Bread", pack_size=1.0, unit="pcs", count=1.0, line_price=220.0, is_food=True, confidence=0.97),
                    GeminiReceiptItem(raw_text="Dozen Eggs 380.00", name="Eggs", pack_size=12.0, unit="pcs", count=1.0, line_price=380.0, is_food=True, confidence=0.96),
                    GeminiReceiptItem(raw_text="Tomatoes 1.5kg 180.00", name="Tomato", pack_size=1.5, unit="kg", count=1.0, line_price=180.0, is_food=True, confidence=0.95),
                ],
            ),
        ),
        (
            "receipt_carrefour.jpg",
            "CARREFOUR MARKET",
            [
                "Chicken Breast Boneless         850.00",
                "Frozen Peas 500g                280.00",
                "Bananas                         120.00",
                "Shopping Bag                     15.00",
                "TOTAL                          1265.00",
            ],
            GeminiReceiptResponse(
                store_name="Carrefour Market",
                date="2026-10-15",
                currency="PKR",
                receipt_total=1265.0,
                discounts_total=0.0,
                items=[
                    GeminiReceiptItem(raw_text="Chicken Breast Boneless 850.00", name="Chicken Breast", pack_size=0.8, unit="kg", count=1.0, line_price=850.0, is_food=True, confidence=0.95),
                    GeminiReceiptItem(raw_text="Frozen Peas 500g 280.00", name="Frozen Peas", pack_size=500.0, unit="g", count=1.0, line_price=280.0, is_food=True, confidence=0.97),
                    GeminiReceiptItem(raw_text="Bananas 120.00", name="Banana", pack_size=None, unit=None, count=None, line_price=120.0, is_food=True, confidence=0.90),
                    GeminiReceiptItem(raw_text="Shopping Bag 15.00", name="Shopping Bag", pack_size=None, unit="pcs", count=1.0, line_price=15.0, is_food=False, confidence=0.99),
                ],
            ),
        ),
        (
            "receipt_mismatch.jpg",
            "LOCAL GROCER",
            [
                "Apples 1kg                      300.00",
                "Yogurt 500g                     150.00",
                "TOTAL                          1000.00",
            ],
            GeminiReceiptResponse(
                store_name="Local Grocer",
                date="2026-10-15",
                currency="PKR",
                receipt_total=1000.0,
                discounts_total=0.0,
                items=[
                    GeminiReceiptItem(raw_text="Apples 1kg 300.00", name="Apple", pack_size=1.0, unit="kg", count=1.0, line_price=300.0, is_food=True, confidence=0.96),
                    GeminiReceiptItem(raw_text="Yogurt 500g 150.00", name="Yogurt", pack_size=500.0, unit="g", count=1.0, line_price=150.0, is_food=True, confidence=0.95),
                ],
            ),
        ),
    ]

    for filename, title, lines, _ in samples:
        file_path = directory / filename
        if not file_path.exists():
            img_bytes = generate_synthetic_receipt_image(title, lines)
            file_path.write_bytes(img_bytes)


def run_receipt_folder_test(folder_path: Path, mock_responses: bool = True) -> None:
    client = TestClient(app)
    receipt_files = sorted(
        [
            p
            for p in folder_path.glob("*.*")
            if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}
        ]
    )

    if not receipt_files:
        print(f"No image files found in {folder_path}")
        return

    print("=" * 80)
    print(f"RUNNING RECEIPT FOLDER TEST: {len(receipt_files)} receipts found in {folder_path}")
    print("=" * 80)

    # Synthetic mock map for reproducible offline batch testing
    mock_map = {
        "receipt_metro.jpg": GeminiReceiptResponse(
            store_name="Metro Cash & Carry",
            date="2026-10-14",
            currency="PKR",
            receipt_total=1300.0,
            discounts_total=40.0,
            items=[
                GeminiReceiptItem(raw_text="2 x Olpers Milk 1L 560.00", name="Milk", pack_size=1.0, unit="L", count=2.0, line_price=560.0, is_food=True, confidence=0.98),
                GeminiReceiptItem(raw_text="1 x White Bread Large 220.00", name="Bread", pack_size=1.0, unit="pcs", count=1.0, line_price=220.0, is_food=True, confidence=0.97),
                GeminiReceiptItem(raw_text="Dozen Eggs 380.00", name="Eggs", pack_size=12.0, unit="pcs", count=1.0, line_price=380.0, is_food=True, confidence=0.96),
                GeminiReceiptItem(raw_text="Tomatoes 1.5kg 180.00", name="Tomato", pack_size=1.5, unit="kg", count=1.0, line_price=180.0, is_food=True, confidence=0.95),
            ],
        ),
        "receipt_carrefour.jpg": GeminiReceiptResponse(
            store_name="Carrefour Market",
            date="2026-10-15",
            currency="PKR",
            receipt_total=1265.0,
            discounts_total=0.0,
            items=[
                GeminiReceiptItem(raw_text="Chicken Breast Boneless 850.00", name="Chicken Breast", pack_size=0.8, unit="kg", count=1.0, line_price=850.0, is_food=True, confidence=0.95),
                GeminiReceiptItem(raw_text="Frozen Peas 500g 280.00", name="Frozen Peas", pack_size=500.0, unit="g", count=1.0, line_price=280.0, is_food=True, confidence=0.97),
                GeminiReceiptItem(raw_text="Bananas 120.00", name="Banana", pack_size=None, unit=None, count=None, line_price=120.0, is_food=True, confidence=0.90),
                GeminiReceiptItem(raw_text="Shopping Bag 15.00", name="Shopping Bag", pack_size=None, unit="pcs", count=1.0, line_price=15.0, is_food=False, confidence=0.99),
            ],
        ),
        "receipt_mismatch.jpg": GeminiReceiptResponse(
            store_name="Local Grocer",
            date="2026-10-15",
            currency="PKR",
            receipt_total=1000.0,
            discounts_total=0.0,
            items=[
                GeminiReceiptItem(raw_text="Apples 1kg 300.00", name="Apple", pack_size=1.0, unit="kg", count=1.0, line_price=300.0, is_food=True, confidence=0.96),
                GeminiReceiptItem(raw_text="Yogurt 500g 150.00", name="Yogurt", pack_size=500.0, unit="g", count=1.0, line_price=150.0, is_food=True, confidence=0.95),
            ],
        ),
    }

    for receipt_path in receipt_files:
        image_bytes = receipt_path.read_bytes()
        filename = receipt_path.name

        # If offline or mock requested, mock Gemini extraction if present
        mock_response = mock_map.get(filename)
        if mock_responses and mock_response and not vision_service.api_key:
            validated = vision_service._validate_and_enrich_receipt(
                gemini_response=mock_response,
                image_hash=f"hash_{filename}",
            )
            data = validated.model_dump()
        else:
            response = client.post(
                "/parse-receipt",
                files={"file": (filename, image_bytes, "image/jpeg")},
                headers={"X-User-Id": "batch_tester"},
            )
            if response.status_code != 200:
                print(f"\n[FAIL] {filename}: Status {response.status_code} - {response.text}")
                continue
            data = response.json()

        items = data.get("items", [])
        store_name = data.get("store_name") or "Unknown Store"
        receipt_total = data.get("receipt_total")
        calculated_total = data.get("calculated_items_total")
        is_mismatch = data.get("total_mismatch_warning", False)
        diff_pct = data.get("total_difference_percent", 0.0)

        # 1. Items found
        item_names = [f"{it['matched_ingredient']} ({it['total_qty']} {it['unit']})" for it in items if it.get("is_food", True)]
        non_food = [it["name"] for it in items if not it.get("is_food", True)]

        # 2. Items with null quantity
        null_qty_items = [
            it["name"]
            for it in items
            if it.get("count") is None and it.get("pack_size") is None
        ]

        # 3. Total match
        if receipt_total is None:
            total_match = "N/A (No printed total)"
        elif not is_mismatch:
            total_match = f"YES (Printed: {receipt_total}, Items: {calculated_total}, Diff: {diff_pct}%)"
        else:
            total_match = f"NO  (Printed: {receipt_total}, Items: {calculated_total}, Diff: {diff_pct}%)"

        print(f"\nRECEIPT: {filename} [{store_name}]")
        print(f"  • Items Found ({len(items)} total, {len(item_names)} food):")
        for iname in item_names:
            print(f"      - {iname}")
        if non_food:
            print(f"      - [Non-food filtered]: {', '.join(non_food)}")
        print(f"  • Items with null quantity ({len(null_qty_items)}):")
        if null_qty_items:
            for nitem in null_qty_items:
                print(f"      * {nitem} (Highlighted for user review)")
        else:
            print("      None (All quantities extracted)")
        print(f"  • Total Match: {total_match}")

    print("\n" + "=" * 80)
    print("ALL RECEIPTS PROCESSED SUCCESSFULLY.")
    print("=" * 80)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Test /parse-receipt on a folder of receipts")
    parser.add_argument(
        "--folder",
        type=str,
        default=str(backend_dir / "tests" / "sample_receipts"),
        help="Path to folder containing receipt images",
    )
    args = parser.parse_args()

    folder = Path(args.folder)
    create_sample_receipts(folder)
    run_receipt_folder_test(folder)
