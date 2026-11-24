import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pantry_item_model.dart';
import '../../providers/pantry_provider.dart';
import '../../widgets/app_ui.dart';
import 'pantry_screen.dart';

enum _ExpiryView { calendar, useSoon, expired, missing }

class ExpiryOverviewScreen extends StatefulWidget {
  const ExpiryOverviewScreen({super.key});

  @override
  State<ExpiryOverviewScreen> createState() => _ExpiryOverviewScreenState();
}

class _ExpiryOverviewScreenState extends State<ExpiryOverviewScreen> {
  _ExpiryView _view = _ExpiryView.calendar;
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  late DateTime _month = DateTime(_selectedDay.year, _selectedDay.month);

  void _changeMonth(int offset) {
    setState(() {
      _month = DateTime(_month.year, _month.month + offset);
      _selectedDay = _month;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final items =
        pantry.allItems
            .where(
              (item) => switch (_view) {
                _ExpiryView.calendar => DateUtils.isSameDay(
                  item.expiryDate,
                  _selectedDay,
                ),
                _ExpiryView.useSoon =>
                  item.expiryStatus == ExpiryStatus.useSoon,
                _ExpiryView.expired =>
                  item.expiryStatus == ExpiryStatus.expired,
                _ExpiryView.missing => item.expiryDate == null,
              },
            )
            .toList()
          ..sort(
            (a, b) => (a.daysUntilExpiry ?? 100000).compareTo(
              b.daysUntilExpiry ?? 100000,
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Check expiry')),
      body: AppPageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            Text(
              'Your expiry calendar',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap a date to see what expires that day. Select an ingredient to update or scan its expiry date.',
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in <(_ExpiryView, String)>[
                  (_ExpiryView.calendar, 'Calendar'),
                  (_ExpiryView.useSoon, 'Use soon (${pantry.useSoonCount})'),
                  (_ExpiryView.expired, 'Expired (${pantry.expiredCount})'),
                  (_ExpiryView.missing, 'No date'),
                ])
                  ChoiceChip(
                    label: Text(entry.$2),
                    selected: _view == entry.$1,
                    onSelected: (_) => setState(() => _view = entry.$1),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_view == _ExpiryView.calendar) ...[
              _ExpiryCalendar(
                month: _month,
                selectedDay: _selectedDay,
                items: pantry.allItems,
                onMonthChanged: _changeMonth,
                onSelected: (day) => setState(() => _selectedDay = day),
                onChooseDate: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: _selectedDay,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200, 12, 31),
                  );
                  if (day == null || !mounted) return;
                  setState(() {
                    _selectedDay = day;
                    _month = DateTime(day.year, day.month);
                  });
                },
                onToday: () => setState(() {
                  _selectedDay = DateUtils.dateOnly(DateTime.now());
                  _month = DateTime(_selectedDay.year, _selectedDay.month);
                }),
              ),
              const SizedBox(height: 20),
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(_selectedDay),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
            ],
            if (pantry.isLoading)
              const Center(child: CircularProgressIndicator())
            else if (items.isEmpty)
              KitchenEmptyState(
                icon: Icons.event_available_outlined,
                title: pantry.allItems.isEmpty
                    ? 'Add your first ingredient'
                    : _view == _ExpiryView.calendar
                    ? 'Nothing expires on this date'
                    : 'No ingredients in this group',
                message: pantry.allItems.isEmpty
                    ? 'Add food to your pantry to keep track of its expiry date.'
                    : _view == _ExpiryView.calendar
                    ? 'Choose a marked date, or check Expired and No date for other ingredients.'
                    : 'Choose another date filter to see the rest of your pantry.',
                action: pantry.allItems.isEmpty
                    ? FilledButton.icon(
                        onPressed: () => PantryScreen.showItemEditor(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add food'),
                      )
                    : null,
              )
            else
              SurfacePanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _ExpiryItem(item: items[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExpiryCalendar extends StatelessWidget {
  const _ExpiryCalendar({
    required this.month,
    required this.selectedDay,
    required this.items,
    required this.onMonthChanged,
    required this.onSelected,
    required this.onToday,
    required this.onChooseDate,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<PantryItemModel> items;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onToday;
  final VoidCallback onChooseDate;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final byDay = <DateTime, List<PantryItemModel>>{};
    for (final item in items) {
      final expiry = item.expiryDate;
      if (expiry != null) {
        byDay.putIfAbsent(DateUtils.dateOnly(expiry), () => []).add(item);
      }
    }
    final offset = month.weekday - 1;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = ((offset + days) / 7).ceil() * 7;
    return SurfacePanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => onMonthChanged(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: onChooseDate,
                  child: Text(
                    DateFormat('MMMM yyyy').format(month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () => onMonthChanged(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          TextButton(onPressed: onToday, child: const Text('Today')),
          Row(
            children: [
              for (final label in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                Expanded(child: Center(child: Text(label))),
            ],
          ),
          const SizedBox(height: 8),
          for (var row = 0; row < cells ~/ 7; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final dayNumber = row * 7 + col - offset + 1;
                        if (dayNumber < 1 || dayNumber > days) {
                          return const SizedBox(height: 52);
                        }
                        final day = DateTime(
                          month.year,
                          month.month,
                          dayNumber,
                        );
                        final entries = byDay[day] ?? const <PantryItemModel>[];
                        final selected = DateUtils.isSameDay(day, selectedDay);
                        final isToday = DateUtils.isSameDay(day, today);
                        final marker = day.isBefore(today)
                            ? colors.error
                            : day.difference(today).inDays <= 3
                            ? const Color(0xFF946000)
                            : colors.primary;
                        return Semantics(
                          label:
                              '${DateFormat('d MMMM yyyy').format(day)}, '
                              '${entries.length} items${day.isBefore(today) && entries.isNotEmpty ? ', expired' : ''}',
                          selected: selected,
                          button: true,
                          child: InkWell(
                            key: ValueKey(
                              'expiry-day-${DateFormat('yyyy-MM-dd').format(day)}',
                            ),
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onSelected(day),
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 48),
                              margin: const EdgeInsets.all(2),
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primaryContainer
                                    : null,
                                borderRadius: BorderRadius.circular(10),
                                border: isToday
                                    ? Border.all(color: colors.primary)
                                    : null,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '$dayNumber',
                                    style: TextStyle(
                                      fontWeight: selected || isToday
                                          ? FontWeight.w600
                                          : null,
                                      color: selected
                                          ? colors.onPrimaryContainer
                                          : colors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if (entries.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: marker,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${entries.length}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final entry in [
                (colors.error, 'Expired'),
                (const Color(0xFF946000), 'Use soon'),
                (colors.primary, 'Upcoming'),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 8, color: entry.$1),
                    const SizedBox(width: 5),
                    Text(
                      entry.$2,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpiryItem extends StatelessWidget {
  const _ExpiryItem({required this.item});
  final PantryItemModel item;

  @override
  Widget build(BuildContext context) {
    final date = item.expiryDate;
    final status = switch (item.expiryStatus) {
      ExpiryStatus.expired => 'Expired',
      ExpiryStatus.useSoon => 'Use soon',
      ExpiryStatus.fresh => 'Fresh',
      ExpiryStatus.unknown => 'No expiry date',
    };
    return ListTile(
      key: ValueKey('expiry-item-${item.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        item.expiryStatus == ExpiryStatus.expired
            ? Icons.error_outline
            : Icons.event_outlined,
        color: item.expiryStatus == ExpiryStatus.expired
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(item.name),
      subtitle: Text(
        [
          status,
          if (date != null) DateFormat('d MMM yyyy').format(date),
          if (item.hasEstimatedExpiry) 'Estimated',
          '${item.quantity} ${item.unit} · ${item.location}',
        ].join('\n'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () =>
          PantryScreen.showItemEditor(context, item: item, focusExpiry: true),
    );
  }
}
