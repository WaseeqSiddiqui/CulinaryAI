import 'package:culinary_ai/services/receipt_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptParserService', () {
    test('extracts grocery items, quantities, prices, and storage zones', () {
      final items = ReceiptParserService.parseLines([
        'FRESH MART',
        'Whole Milk 2 L 320.00',
        'Free Range Eggs 12 pcs 280.00',
        'Basmati Rice 5kg 950.00',
        'Cumin Seeds 100 g Rs. 80.00',
        'SUBTOTAL 1,630.00',
        'GST 16%',
        'TOTAL PKR 1,630.00',
        'Thank you',
      ]);

      expect(items, hasLength(4));

      final milk = items.firstWhere((item) => item.name == 'Whole Milk');
      expect(milk.quantity, 2);
      expect(milk.unit, 'L');
      expect(milk.price, 320);
      expect(milk.location, 'fridge');

      final rice = items.firstWhere((item) => item.name == 'Basmati Rice');
      expect(rice.quantity, 5);
      expect(rice.unit, 'kg');
      expect(rice.location, 'pantry_shelf');

      final cumin = items.firstWhere((item) => item.name == 'Cumin Seeds');
      expect(cumin.location, 'spice_rack');
    });

    test('supports an item name followed by its price on the next line', () {
      final items = ReceiptParserService.parseLines(['Olive Oil', 'Rs 450.00']);

      expect(items, hasLength(1));
      expect(items.single.name, 'Olive Oil');
      expect(items.single.quantity, 1);
      expect(items.single.unit, 'pcs');
      expect(items.single.price, 450);
    });

    test('supports a name followed by a numeric-only price line', () {
      final items = ReceiptParserService.parseLines(['Brown Bread', '220.00']);

      expect(items, hasLength(1));
      expect(items.single.name, 'Brown Bread');
      expect(items.single.price, 220);
    });

    test('supports leading item counts and merges duplicate lines', () {
      final items = ReceiptParserService.parseLines([
        '2 x Tomato Sauce 250.00',
        '1 x Tomato Sauce 125.00',
      ]);

      expect(items, hasLength(1));
      expect(items.single.name, 'Tomato Sauce');
      expect(items.single.quantity, 3);
      expect(items.single.price, 375);
    });

    test('parses barcode, quantity, unit price and total columns', () {
      final items = ReceiptParserService.parseLines([
        'ITEM DESCRIPTION QTY RATE AMOUNT',
        '2 8961008210074 NESTLE MILK 1L 310.00 620.00',
        '1 8901030895489 BASMATI RICE 5 KG 1850.00 1850.00',
        'GRAND TOTAL 2470.00',
      ]);

      expect(items, hasLength(2));
      final milk = items.firstWhere((item) => item.name == 'Nestle Milk');
      expect(milk.quantity, 2);
      expect(milk.unit, 'L');
      expect(milk.price, 620);

      final rice = items.firstWhere((item) => item.name == 'Basmati Rice');
      expect(rice.quantity, 5);
      expect(rice.unit, 'kg');
      expect(rice.price, 1850);
    });

    test('joins product names with split quantity and price lines', () {
      final items = ReceiptParserService.parseLines([
        'Olper Milk',
        '2 x 1 L',
        'Rs 640.00',
        'Shan Tikka Masala',
        '1 x 180.00 180.00',
      ]);

      expect(items, hasLength(2));
      final milk = items.firstWhere((item) => item.name == 'Olper Milk');
      expect(milk.quantity, 2);
      expect(milk.unit, 'L');
      expect(milk.price, 640);

      final masala = items.firstWhere(
        (item) => item.name == 'Shan Tikka Masala',
      );
      expect(masala.quantity, 1);
      expect(masala.price, 180);
      expect(masala.location, 'spice_rack');
    });

    test('returns no items for headings and receipt totals', () {
      final items = ReceiptParserService.parseLines([
        'WELCOME TO FRESH MART',
        'Receipt 123456',
        'Date 12/10/2026',
        'Subtotal 900.00',
        'Tax 10.00',
        'Total 910.00',
      ]);

      expect(items, isEmpty);
    });

    test('parses wrapped UK grocery receipt rows and weighted produce', () {
      final items = ReceiptParserService.parseLines([
        'KTC CHICK PEAS CASE 12x400G 1 4.75',
        'ONION INDIAN BAG 1 2.99',
        'SHANA ORIGINAL',
        'PARATHA MULTIPK 15PCS 1 4.99',
        'SOFRA CHICKEN',
        'STOCK 24X20G 1 2.99',
        'SHAN SINDHI BIRYANI 50G 1 0.99',
        'SHAN NIHARI CURRY 60G 1 0.99',
        'SHAN TIKKA BOTI MIX 50G 1 0.99',
        'SATCO MICRO FOOD',
        'CONT 500CC@£1.29 2 2.58',
        'TRS CHANA DAL@£4.29 2KG 4 17.16',
        'REGAL PETIT 5PCS 2 2.98',
        'ROLLS@£1.49',
        'ARBI PER KG 1 3.73',
        '0.622kg @ £5.99/kg',
        'TRS DHANIA WHOLE 250G 1 1.49',
        'HOT CHILLIES PER KG 1 1.57',
        '0.314kg @ £4.99/kg',
        'LIME GREEN@£0.29 each 10 2.90',
        '**Buy 5@£0.99 (-0.92)',
        'OKRA (BHINDI) PER KILO 1 3.48',
        '0.498kg @ £6.99/kg',
        'TOMATOES (FRESH) PER KG 1 2.11',
        '1.386kg @ £1.52/kg',
        'ELEPHANT ATTA',
        'MEDIUM 10KG 1 9.99',
        'PILLSBURY ATTA 10KG 10KG 1 15.99',
        'Total Item(s) Sold 38',
      ]);

      expect(items, hasLength(18));

      final chickPeas = items.firstWhere(
        (item) => item.name == 'KTC Chick Peas Case',
      );
      expect(chickPeas.quantity, 4800);
      expect(chickPeas.unit, 'g');
      expect(chickPeas.price, 4.75);

      final paratha = items.firstWhere(
        (item) => item.name == 'Shana Original Paratha Multipk',
      );
      expect(paratha.quantity, 15);
      expect(paratha.unit, 'pcs');

      final satco = items.firstWhere(
        (item) => item.name == 'Satco Micro Food Cont',
      );
      expect(satco.quantity, 1000);
      expect(satco.unit, 'ml');
      expect(satco.price, 2.58);

      final chanaDal = items.firstWhere((item) => item.name == 'TRS Chana Dal');
      expect(chanaDal.quantity, 8);
      expect(chanaDal.unit, 'kg');
      expect(chanaDal.price, 17.16);

      final rolls = items.firstWhere(
        (item) => item.name == 'Regal Petit Rolls',
      );
      expect(rolls.quantity, 10);
      expect(rolls.unit, 'pcs');
      expect(rolls.price, 2.98);

      final arbi = items.firstWhere((item) => item.name == 'Arbi');
      expect(arbi.quantity, 0.622);
      expect(arbi.unit, 'kg');

      final chillies = items.firstWhere((item) => item.name == 'Hot Chillies');
      expect(chillies.quantity, 0.314);
      expect(chillies.unit, 'kg');

      final limes = items.firstWhere((item) => item.name == 'Lime Green');
      expect(limes.quantity, 10);
      expect(limes.unit, 'pcs');

      final elephant = items.firstWhere(
        (item) => item.name == 'Elephant Atta Medium',
      );
      expect(elephant.quantity, 10);
      expect(elephant.unit, 'kg');

      final pillsbury = items.firstWhere(
        (item) => item.name == 'Pillsbury Atta',
      );
      expect(pillsbury.quantity, 10);
      expect(pillsbury.unit, 'kg');
    });
  });
}
