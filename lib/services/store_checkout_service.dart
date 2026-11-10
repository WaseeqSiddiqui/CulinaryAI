import '../models/store_models.dart';

/// The page implementation only operates visible store controls. Keeping the
/// transaction sequence here makes cancellation and ambiguous outcomes testable.
abstract class StoreCheckoutPage {
  Future<bool> openCheckout();
  Future<String?> interruptionReason();
  Future<bool> selectCashOnDelivery();
  Future<CheckoutSummary?> readSummary();
  Future<bool> submitOrder();
  Future<bool> waitForConfirmation();
  Future<String?> readOrderReference();
}

class StoreCheckoutService {
  bool _busy = false;
  bool _submitted = false;
  int _generation = 0;
  CheckoutSummary? _submittedSummary;

  bool get hasSubmitted => _submitted;
  void cancel() => _generation++;

  Future<CheckoutResult> placeOrder({
    required StoreCheckoutPage page,
    required List<CartLine> expectedCart,
    required CheckoutApproval approve,
    Future<void> Function(CheckoutSummary summary)? beforeSubmit,
  }) async {
    if (_busy) {
      return const CheckoutResult(
        CheckoutState.failed,
        'Checkout is already running.',
      );
    }
    _busy = true;
    final generation = _generation;
    bool cancelled() => generation != _generation;
    CheckoutResult manual(String message) => CheckoutResult(
      CheckoutState.needsManualCompletion,
      message,
      summary: _submittedSummary,
    );
    try {
      // A timeout or lost connection after clicking must never cause a retry of
      // the final button. A second call can only observe the existing order.
      if (_submitted) return await _confirmation(page);
      if (expectedCart.isEmpty) {
        return manual('Verify the cart before checkout.');
      }
      if (!await page.openCheckout() || cancelled()) {
        return manual(
          'Checkout is not ready. Check the address and minimum order.',
        );
      }
      final interruption = await page.interruptionReason();
      if (interruption != null || cancelled()) {
        return manual(interruption ?? 'Checkout cancelled.');
      }
      if (!await page.selectCashOnDelivery() || cancelled()) {
        return manual(
          'Choose cash on delivery in PandaMart, then review checkout again.',
        );
      }
      final summary = await page.readSummary();
      if (cancelled()) return manual('Checkout cancelled.');
      if (summary == null || !summary.isComplete) {
        return manual(
          'The final cart, delivery address, payment and total could not all be verified.',
        );
      }
      if (!sameCart(expectedCart, summary.lines)) {
        return manual(
          'The cart changed during checkout. Review it again before purchasing.',
        );
      }
      if (!await approve(summary) || cancelled()) {
        return manual('Purchase cancelled. Your cart is still available.');
      }
      if (beforeSubmit != null) await beforeSubmit(summary);
      if (cancelled()) return manual('Checkout cancelled.');
      final latest = await page.readSummary();
      final finalInterruption = await page.interruptionReason();
      if (cancelled()) return manual('Checkout cancelled.');
      if (finalInterruption != null) return manual(finalInterruption);
      if (latest == null || !sameSummary(summary, latest)) {
        return manual(
          'Checkout changed after approval. Review the updated order before purchasing.',
        );
      }
      // Set this before awaiting the click: an exception may arrive after the
      // merchant has accepted the order. Retrying would risk a duplicate.
      _submitted = true;
      _submittedSummary = summary;
      if (!await page.submitOrder()) {
        return manual(
          'The order button was unavailable. Check PandaMart before continuing manually.',
        );
      }
      return await _confirmation(page);
    } catch (_) {
      return manual(
        _submitted
            ? 'The order outcome is unknown. Check PandaMart order confirmation before doing anything else.'
            : 'Checkout could not continue. Complete the visible step in PandaMart.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<CheckoutResult> _confirmation(StoreCheckoutPage page) async {
    final confirmed = await page.waitForConfirmation();
    String? reference;
    if (confirmed) {
      // A missing optional reference must not turn a confirmed order into an
      // unknown outcome or invite a second purchase.
      try {
        reference = await page.readOrderReference();
      } catch (_) {}
    }
    return CheckoutResult(
      confirmed ? CheckoutState.placed : CheckoutState.needsManualCompletion,
      confirmed ? 'PandaMart confirmed the order.' : 'PandaMart has not confirmed the order yet. Check the visible order status; do not place it again.',
      summary: _submittedSummary,
      orderReference: reference,
    );
  }

  static bool sameSummary(CheckoutSummary left, CheckoutSummary right) =>
      right.isComplete &&
      (left.total - right.total).abs() < 0.005 &&
      left.deliveryAddress.trim() == right.deliveryAddress.trim() &&
      left.cashOnDeliverySelected == right.cashOnDeliverySelected &&
      sameCart(left.lines, right.lines);

  static bool sameCart(List<CartLine> left, List<CartLine> right) {
    if (left.length != right.length) return false;
    final remaining = List.of(right);
    for (final line in left) {
      final index = remaining.indexWhere(
        (candidate) =>
            line.name.trim().toLowerCase() ==
                candidate.name.trim().toLowerCase() &&
            line.quantity == candidate.quantity &&
            line.price.isFinite &&
            candidate.price.isFinite &&
            (line.price - candidate.price).abs() < 0.005,
      );
      if (index < 0) return false;
      remaining.removeAt(index);
    }
    return remaining.isEmpty;
  }
}
