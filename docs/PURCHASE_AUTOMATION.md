# PandaMart purchase automation

Open **Restock ? Shopping list ? Buy from PandaMart**. Use **Set delivery
address** to confirm Foodpanda's delivery pin, select a nearby PandaMart, then
use **Sign in to Foodpanda**. These controls open the merchant's own forms in a
focused view with room for the keyboard. CulinaryAI and Foodpanda have separate
accounts; the merchant handles its own credentials and OTPs.

The checklist tracks address, branch and sign-in. It refreshes after navigation
and while the store page changes without a reload. **Use current location** asks
for device permission and opens Foodpanda's address/location flow without
throwing away the selected store. The user confirms the delivery pin. Selected
delivery coordinates remain attached to product-search URLs.

On Android, **Use current location** resolves a recent foreground GPS fix and
street address through the phone, then fills Foodpanda's visible address search.
Choose the matching suggestion, check the map pin and tap **Confirm delivery
address**. Typing or selecting a suggestion alone does not replace the saved
delivery address. Returning with an unconfirmed edit offers **Keep editing** or
**Discard changes**. The setup screen displays the actual selected address.
**Choose nearby PandaMart** opens the merchant's store picker with the full
screen available. Address and sign-in setup no longer reload the homepage when
a control is unavailable, and old page-readiness responses cannot overwrite a
newer address selection.

**Build my cart** becomes available when setup is ready. Review the entire cart,
including pre-existing items. Checkout selects cash on delivery and shows the
merchant's final cart, address and total including fees. **Place order** authorizes
one submission.

The app rechecks the cart before checkout and again after approval. The final
button also checks the same DOM snapshot immediately before clicking. Changed
items, pack sizes, quantities, prices, addresses, totals or payment methods stop
submission. Captchas, OTPs, unavailable payment options and unrecognized layouts
leave the store visible for manual completion. Credentials and card inputs are
not populated by automation.

An uncertain submission is never automatically repeated. **Check order status**
only checks confirmation. A household-scoped checkpoint is saved before the
final click; reopening an interrupted checkout requires reconciling that attempt.
If PandaMart shows success, use **I see PandaMart order confirmation**, select
the items actually ordered and enter the final order total. If no order exists,
check PandaMart order history before clearing the recovery record. Existing cart
items remain in PandaMart.

Confirmed orders are stored locally with a stable ID and, when readable, the
merchant reference. A failed local save exposes **Retry saving order** without
another store submission. Only ordered shopping rows are removed. Skipped rows,
rows edited during checkout and rows marked to remain are retained. Orders do
not increase pantry inventory; scan the delivered receipt to ingest groceries.
**Shopping list → Order history** displays recorded orders on this device.

## Implementation

On Flutter web, PandaMart opens in a separate browser tab. The app provides a
copyable list and lets the user record a completed order with the purchased rows
and final total. Browser security prevents inspecting or automating a merchant's
cross-origin page. The embedded automatic cart and checkout flow is for supported
native WebViews. Manual recording does not submit a purchase to the merchant.

- `store_checkout_service.dart`: approval, revalidation, cancellation and
  one-submission state machine with a testable page interface.
- `pandamart_checkout_page.dart`: visible-label cash and order controls,
  atomic checkout snapshot, final-click guard and confirmation polling.
- `pandamart_adapter.dart`: branch discovery, product search, verified quantity
  changes and strict cart reading.
- `purchase_session_store.dart`: durable interrupted-checkout recovery.
- `shopping_provider.dart` / `shopping_service.dart`: household checks,
  idempotent order recording and device order history.

Store selectors and English compatibility labels live in
`assets/store_selectors.json`. Cart/product selectors predate this completion;
checkout uses exact visible labels plus configurable address/summary selectors.
Compatibility defaults are **not evidence of a successful live checkout**.
If the merchant renders a different label or DOM, the app stops for manual
completion instead of guessing. Do not relax confirmation to generic page text
or use a button position as a purchase target.

`firestore.rules` now permits household members to read and save orders only
under their own household. This is a local rules change; deploy it through the
project's normal Firebase release process to enable cloud writes. Orders remain
available locally if Firebase denies the write. Cross-device order-history
synchronization is not implemented.

## Validation

```powershell
flutter analyze
flutter test
```

Regression coverage includes fee-inclusive approval, changed checkout details,
cash-only payment, cancellation, duplicate taps, ambiguous submissions,
checkpoint failures and recovery, partial cart reads, exact product quantities,
household changes, persistence retries, partial orders and history navigation.

Live acceptance still requires a signed-in Foodpanda WebView on a supported
device with a deliverable address. Check an empty and a filled cart, cash
selection, the final address and fee-inclusive total, and cancellation. A real
test order must be authorized separately with its items and spending limit.
Verify the merchant confirmation and local history afterwards; unit tests do
not verify the merchant's current authenticated checkout DOM.

Device verification on 10 November 2026 used a Vivo V2440 on Android 16. The
Lahore search returned Lahore suggestions; confirming a Lahore result and
reopening the store retained Lahore. Native GPS address resolution populated
the merchant search, and discarding that unconfirmed edit retained the previous
selection. These checks did not place a real order. Authenticated cart and
checkout acceptance still requires a signed-in Foodpanda session.
