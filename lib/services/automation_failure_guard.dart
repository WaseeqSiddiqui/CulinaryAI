class AutomationFailureGuard {
  AutomationFailureGuard({this.maximumConsecutiveFailures = 3});
  final int maximumConsecutiveFailures;
  int _consecutiveFailures = 0;

  bool record({required bool selectorSucceeded}) {
    _consecutiveFailures = selectorSucceeded ? 0 : _consecutiveFailures + 1;
    return _consecutiveFailures >= maximumConsecutiveFailures;
  }

  int get consecutiveFailures => _consecutiveFailures;
}
