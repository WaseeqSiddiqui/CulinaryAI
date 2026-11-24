import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/subscription/plus_screen.dart';
import '../services/authenticated_api_client.dart';

class SubscriptionNotifications extends StatefulWidget {
  const SubscriptionNotifications({
    super.key,
    required this.navigatorKey,
    required this.child,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  @override
  State<SubscriptionNotifications> createState() =>
      _SubscriptionNotificationsState();
}

class _SubscriptionNotificationsState extends State<SubscriptionNotifications> {
  late final StreamSubscription<QuotaLimitNotice> _subscription;
  bool _showing = false;
  @override
  void initState() {
    super.initState();
    _subscription = SubscriptionEvents.limits.stream.listen(_show);
  }

  Future<void> _show(QuotaLimitNotice notice) async {
    final context = widget.navigatorKey.currentContext;
    if (_showing || context == null || !context.mounted) return;
    _showing = true;
    final view = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Monthly allowance reached'),
        content: Text(
          '${notice.message}${notice.resetsAt == null ? '' : '\n\nResets ${DateFormat('d MMM yyyy').format(notice.resetsAt!.toLocal())}.'}${notice.plan == 'free' ? '\n\nPlus includes a larger monthly allowance. Payments are coming soon.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('View plans'),
          ),
        ],
      ),
    );
    _showing = false;
    if (view == true && mounted) {
      widget.navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const PlusScreen()),
      );
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
