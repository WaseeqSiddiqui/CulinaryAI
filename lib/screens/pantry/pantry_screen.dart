import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/pantry_item_model.dart';
import '../../providers/pantry_provider.dart';
import '../../services/food_image_service.dart';
import '../../services/expiry_estimation_service.dart';
import '../scanner/expiry_label_scanner_screen.dart';
import '../scanner/fridge_scanner_screen.dart';
import '../scanner/receipt_scanner_screen.dart';

// ── Zone Metadata ─────────────────────────────────────────────────────────────

class _ZoneMeta {
  final Color color;
  final IconData icon;
  final String label;
  const _ZoneMeta({
    required this.color,
    required this.icon,
    required this.label,
  });
}

const Map<String, _ZoneMeta> _zoneMeta = {
  'Fridge': _ZoneMeta(
    color: AppTheme.zoneFridge,
    icon: Icons.kitchen_rounded,
    label: 'Fridge',
  ),
  'Freezer': _ZoneMeta(
    color: AppTheme.zoneFreezer,
    icon: Icons.ac_unit_rounded,
    label: 'Freezer',
  ),
  'Pantry Shelf': _ZoneMeta(
    color: AppTheme.zonePantry,
    icon: Icons.shelves,
    label: 'Pantry Shelf',
  ),
  'Spice Rack': _ZoneMeta(
    color: AppTheme.zoneSpice,
    icon: Icons.grass_rounded,
    label: 'Spice Rack',
  ),
};

// ── Pantry Screen ─────────────────────────────────────────────────────────────

class PantryScreen extends StatefulWidget {
  const PantryScreen({super.key});

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _isSearching = false;
  late AnimationController _fabAnim;

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnim.forward();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabAnim.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        context.read<PantryProvider>().setSearch('');
      }
    });
  }

  void _showAddEditSheet({PantryItemModel? item}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddEditSheet(item: item),
    );
  }

  void _confirmDelete(BuildContext context, PantryItemModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "${item.name}" from your pantry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<PantryProvider>().deleteItem(item.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"${item.name}" removed'),
                  action: SnackBarAction(
                    label: 'Undo',
                    textColor: AppTheme.primaryLight,
                    onPressed: () {
                      context.read<PantryProvider>().addItem(
                        householdId: item.householdId,
                        name: item.name,
                        quantity: item.quantity,
                        unit: item.unit,
                        location: item.location,
                        lowStockThreshold: item.lowStockThreshold,
                        purchaseDate: item.purchaseDate,
                        expiryDate: item.expiryDate,
                        openedDate: item.openedDate,
                        expirySource: item.expirySource,
                        expiryConfidence: item.expiryConfidence,
                        expiryUserConfirmed: item.expiryUserConfirmed,
                      );
                    },
                  ),
                ),
              );
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pantry = context.watch<PantryProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grouped = pantry.itemsByZone;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildSliverAppBar(context, pantry, isDark, innerBoxIsScrolled),
        ],
        body: pantry.allItems.isEmpty
            ? _buildEmptyState(context)
            : _buildContent(context, pantry, grouped, isDark),
      ),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(parent: _fabAnim, curve: Curves.easeOut),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddEditSheet(),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Add Item',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
    );
  }

  SliverAppBar _buildSliverAppBar(
    BuildContext context,
    PantryProvider pantry,
    bool isDark,
    bool innerBoxIsScrolled,
  ) {
    return SliverAppBar(
      pinned: true,
      floating: false,
      elevation: innerBoxIsScrolled ? 1 : 0,
      backgroundColor: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
      title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search pantry...',
                hintStyle: TextStyle(
                  color: isDark
                      ? AppTheme.textDarkSecondary
                      : AppTheme.textLightSecondary,
                  fontSize: 15,
                ),
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.textDarkPrimary
                    : AppTheme.textLightPrimary,
              ),
              onChanged: pantry.setSearch,
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Pantry Inventory',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: isDark
                                  ? AppTheme.textDarkPrimary
                                  : AppTheme.textLightPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.freshHerb.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${pantry.totalCount}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.freshHerb,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        pantry.lowStockCount > 0
                            ? '${pantry.lowStockCount} items need restock'
                            : 'All items well-stocked',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: pantry.lowStockCount > 0
                              ? AppTheme.warmAmber
                              : (isDark
                                    ? AppTheme.textDarkSecondary
                                    : AppTheme.textLightSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.document_scanner_outlined),
          tooltip: 'Scan fridge',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FridgeScannerScreen()),
          ),
        ),
        IconButton(
          icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
          tooltip: _isSearching ? 'Close Search' : 'Search',
          onPressed: _toggleSearch,
        ),
        IconButton(
          icon: const Icon(Icons.filter_list_rounded),
          tooltip: 'Filter by Zone',
          onPressed: () => _showZoneFilterSheet(context, pantry),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: Column(
          children: [
            _buildZoneChips(pantry, isDark),
            _buildExpiryChips(pantry),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiryChips(PantryProvider pantry) {
    final entries = <(PantryExpiryFilter, String, IconData, int?)>[
      (
        PantryExpiryFilter.all,
        'All dates',
        Icons.event_available_outlined,
        null,
      ),
      (
        PantryExpiryFilter.useSoon,
        'Use soon',
        Icons.schedule_rounded,
        pantry.useSoonCount,
      ),
      (
        PantryExpiryFilter.expired,
        'Expired',
        Icons.error_outline_rounded,
        pantry.expiredCount,
      ),
      (
        PantryExpiryFilter.estimated,
        'Estimated',
        Icons.auto_awesome_outlined,
        null,
      ),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final entry = entries[index];
          final selected = pantry.expiryFilter == entry.$1;
          return FilterChip(
            selected: selected,
            showCheckmark: false,
            avatar: Icon(entry.$3, size: 15),
            label: Text(
              entry.$4 == null ? entry.$2 : '${entry.$2} ${entry.$4}',
            ),
            onSelected: (_) => pantry.setExpiryFilter(entry.$1),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildZoneChips(PantryProvider pantry, bool isDark) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _ZoneChip(
            label: 'All',
            icon: Icons.grid_view_rounded,
            color: AppTheme.primaryEmerald,
            isSelected: pantry.selectedZone == null,
            onTap: () => pantry.setZoneFilter(null),
          ),
          const SizedBox(width: 8),
          ...PantryProvider.zones.map((zone) {
            final meta = _zoneMeta[zone]!;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ZoneChip(
                label: meta.label,
                icon: meta.icon,
                color: meta.color,
                isSelected: pantry.selectedZone == zone,
                onTap: () => pantry.setZoneFilter(
                  pantry.selectedZone == zone ? null : zone,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PantryProvider pantry,
    Map<String, List<PantryItemModel>> grouped,
    bool isDark,
  ) {
    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
            ),
            const SizedBox(height: 12),
            const Text('No items found', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount:
          grouped.keys.length +
          (pantry.useSoonCount + pantry.expiredCount > 0 ? 1 : 0),
      itemBuilder: (context, index) {
        final hasReminder = pantry.useSoonCount + pantry.expiredCount > 0;
        if (hasReminder && index == 0) {
          return _ExpiryReminderCard(
            useSoon: pantry.useSoonCount,
            expired: pantry.expiredCount,
            onTap: () => pantry.setExpiryFilter(
              pantry.expiredCount > 0
                  ? PantryExpiryFilter.expired
                  : PantryExpiryFilter.useSoon,
            ),
          );
        }
        final zone = grouped.keys.elementAt(index - (hasReminder ? 1 : 0));
        final items = grouped[zone]!;
        return _ZoneSection(
          zone: zone,
          items: items,
          isDark: isDark,
          onEdit: (item) => _showAddEditSheet(item: item),
          onDelete: (item) => _confirmDelete(context, item),
          onAdjust: (item, delta) =>
              context.read<PantryProvider>().adjustQuantity(item.id, delta),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.network(
                'https://images.unsplash.com/photo-1547592180-85f173990554?w=400&q=80',
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/images/pantry_basket.jpg',
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your Pantry is Empty',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Add an item, scan your fridge, or import a grocery receipt.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? AppTheme.textDarkSecondary
                    : AppTheme.textLightSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FridgeScannerScreen()),
              ),
              icon: const Icon(Icons.kitchen_rounded),
              label: const Text('Scan fridge'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiptScannerScreen()),
              ),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Scan receipt'),
            ),
          ],
        ),
      ),
    );
  }

  void _showZoneFilterSheet(BuildContext context, PantryProvider pantry) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by Zone',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(
                  Icons.grid_view_rounded,
                  color: AppTheme.primaryEmerald,
                ),
                title: const Text('All Zones'),
                trailing: pantry.selectedZone == null
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTheme.primaryEmerald,
                      )
                    : null,
                onTap: () {
                  pantry.setZoneFilter(null);
                  Navigator.pop(context);
                },
              ),
              ...PantryProvider.zones.map((zone) {
                final meta = _zoneMeta[zone]!;
                return ListTile(
                  leading: Icon(meta.icon, color: meta.color),
                  title: Text(meta.label),
                  trailing: pantry.selectedZone == zone
                      ? Icon(Icons.check_rounded, color: meta.color)
                      : null,
                  onTap: () {
                    pantry.setZoneFilter(zone);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

// ── Zone Section ──────────────────────────────────────────────────────────────

class _ExpiryReminderCard extends StatelessWidget {
  final int useSoon;
  final int expired;
  final VoidCallback onTap;

  const _ExpiryReminderCard({
    required this.useSoon,
    required this.expired,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final urgent = expired > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: (urgent ? AppTheme.errorRed : AppTheme.warmAmber).withValues(
        alpha: .10,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          urgent ? Icons.error_outline_rounded : Icons.schedule_rounded,
          color: urgent ? AppTheme.errorRed : AppTheme.warmAmber,
        ),
        title: Text(
          urgent
              ? '$expired expired item${expired == 1 ? '' : 's'} need review'
              : '$useSoon item${useSoon == 1 ? '' : 's'} should be used soon',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          urgent
              ? 'Do not use automatically in recipes.'
              : 'Recipes using these ingredients are prioritized.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

class _ZoneSection extends StatefulWidget {
  final String zone;
  final List<PantryItemModel> items;
  final bool isDark;
  final void Function(PantryItemModel) onEdit;
  final void Function(PantryItemModel) onDelete;
  final void Function(PantryItemModel, double) onAdjust;

  const _ZoneSection({
    required this.zone,
    required this.items,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
    required this.onAdjust,
  });

  @override
  State<_ZoneSection> createState() => _ZoneSectionState();
}

class _ZoneSectionState extends State<_ZoneSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final meta = _zoneMeta[widget.zone]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Zone header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(meta.icon, color: meta.color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                meta.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: meta.color,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.items.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: meta.color,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                _expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: meta.color.withValues(alpha: 0.7),
                size: 20,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_expanded)
          ...widget.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PantryItemCard(
                item: item,
                zoneColor: meta.color,
                isDark: widget.isDark,
                onEdit: () => widget.onEdit(item),
                onDelete: () => widget.onDelete(item),
                onDecrement: () => widget.onAdjust(item, -1),
                onIncrement: () => widget.onAdjust(item, 1),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Pantry Item Card ──────────────────────────────────────────────────────────

class _PantryItemCard extends StatelessWidget {
  final PantryItemModel item;
  final Color zoneColor;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _PantryItemCard({
    required this.item,
    required this.zoneColor,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceColor = isDark ? AppTheme.surfaceDark : Colors.white;
    final borderColor = item.isLowStock
        ? AppTheme.warmAmber.withValues(alpha: 0.5)
        : (isDark ? AppTheme.borderDark : AppTheme.borderLight);

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: _swipeBackground(),
      confirmDismiss: (_) async => false, // Handled by onDelete
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: () => _showItemDetailSheet(context, item, zoneColor, isDark),
        onLongPress: onEdit,
        child: Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Row(
              children: [
                // Zone color vertical accent pill
                Container(width: 4, height: 64, color: zoneColor),
                const SizedBox(width: 10),
                // Food Photo Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.displayImageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: zoneColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.restaurant, color: zoneColor, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Item info
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? AppTheme.textDarkPrimary
                                      : AppTheme.textLightPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.isLowStock)
                              Container(
                                margin: const EdgeInsets.only(
                                  left: 6,
                                  right: 4,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.warmAmber.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.warmAmber.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 11,
                                      color: AppTheme.warmAmber,
                                    ),
                                    SizedBox(width: 3),
                                    Text(
                                      'Low',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.warmAmber,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${_formatQty(item.quantity)} ${item.unit}',
                              style: TextStyle(
                                fontSize: 13,
                                color: item.isLowStock
                                    ? AppTheme.warmAmber
                                    : (isDark
                                          ? AppTheme.textDarkSecondary
                                          : AppTheme.textLightSecondary),
                                fontWeight: item.isLowStock
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '• ${item.location}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? AppTheme.textDarkMuted
                                    : AppTheme.textLightMuted,
                              ),
                            ),
                          ],
                        ),
                        if (item.expiryDate != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Icon(
                                item.expiryStatus == ExpiryStatus.expired
                                    ? Icons.error_outline_rounded
                                    : Icons.schedule_rounded,
                                size: 13,
                                color: item.expiryStatus == ExpiryStatus.expired
                                    ? AppTheme.errorRed
                                    : item.expiryStatus == ExpiryStatus.useSoon
                                    ? AppTheme.warmAmber
                                    : AppTheme.freshHerb,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.expiryStatus == ExpiryStatus.expired
                                      ? 'Expired ${DateFormat('d MMM').format(item.expiryDate!)}'
                                      : 'Use by ${DateFormat('d MMM').format(item.expiryDate!)}${item.hasEstimatedExpiry ? ' · estimated' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color:
                                        item.expiryStatus ==
                                            ExpiryStatus.expired
                                        ? AppTheme.errorRed
                                        : item.expiryStatus ==
                                              ExpiryStatus.useSoon
                                        ? AppTheme.warmAmber
                                        : AppTheme.freshHerb,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Quantity controls
                _QuantityControls(
                  onDecrement: onDecrement,
                  onIncrement: onIncrement,
                  isDark: isDark,
                ),
                // Actions menu
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: isDark
                        ? AppTheme.textDarkMuted
                        : AppTheme.textLightSecondary,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (val) {
                    if (val == 'edit') onEdit();
                    if (val == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.errorRed,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Remove',
                            style: TextStyle(color: AppTheme.errorRed),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.errorRed,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
          SizedBox(height: 2),
          Text(
            'Remove',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatQty(double qty) {
    if (qty == qty.truncateToDouble()) return qty.toInt().toString();
    return qty.toStringAsFixed(1);
  }

  void _showItemDetailSheet(
    BuildContext context,
    PantryItemModel item,
    Color zoneColor,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ItemDetailModal(
        item: item,
        zoneColor: zoneColor,
        isDark: isDark,
        onEdit: onEdit,
        onDelete: onDelete,
        onDecrement: onDecrement,
        onIncrement: onIncrement,
      ),
    );
  }
}

// ── Quantity Controls ─────────────────────────────────────────────────────────

class _QuantityControls extends StatelessWidget {
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final bool isDark;

  const _QuantityControls({
    required this.onDecrement,
    required this.onIncrement,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _QtyBtn(icon: Icons.remove_rounded, onTap: onDecrement, isDark: isDark),
        const SizedBox(width: 4),
        _QtyBtn(icon: Icons.add_rounded, onTap: onIncrement, isDark: isDark),
      ],
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _QtyBtn({
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark2 : AppTheme.bgLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isDark
              ? AppTheme.textDarkSecondary
              : AppTheme.textLightSecondary,
        ),
      ),
    );
  }
}

// ── Zone Chip ─────────────────────────────────────────────────────────────────

class _ZoneChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ZoneChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.2 : 0.14)
              : (isDark ? AppTheme.surfaceDark2 : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color
                : (isDark ? AppTheme.borderDark : AppTheme.borderLight),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? color
                  : (isDark
                        ? AppTheme.textDarkSecondary
                        : AppTheme.textLightSecondary),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? color
                    : (isDark
                          ? AppTheme.textDarkSecondary
                          : AppTheme.textLightSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stat Chip ─────────────────────────────────────────────────────────────────

// ── Add / Edit Sheet ──────────────────────────────────────────────────────────

class _AddEditSheet extends StatefulWidget {
  final PantryItemModel? item;
  const _AddEditSheet({this.item});

  @override
  State<_AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends State<_AddEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _customImageCtrl;

  late String _selectedUnit;
  late String _selectedLocation;
  bool _showCustomImageField = false;
  DateTime? _purchaseDate;
  DateTime? _expiryDate;
  DateTime? _openedDate;
  ExpirySource _expirySource = ExpirySource.unknown;
  ExpiryConfidence _expiryConfidence = ExpiryConfidence.low;
  bool _expiryConfirmed = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _qtyCtrl = TextEditingController(
      text: item != null ? _fmt(item.quantity) : '',
    );
    _thresholdCtrl = TextEditingController(
      text: item != null ? _fmt(item.lowStockThreshold) : '1',
    );
    _customImageCtrl = TextEditingController(text: item?.customImageUrl ?? '');
    _showCustomImageField =
        item?.customImageUrl != null && item!.customImageUrl!.isNotEmpty;

    _selectedUnit = item?.unit ?? PantryProvider.units.first;
    _selectedLocation = item?.location ?? PantryProvider.zones.first;
    _purchaseDate = item?.purchaseDate;
    _expiryDate = item?.expiryDate;
    _openedDate = item?.openedDate;
    _expirySource = item?.expirySource ?? ExpirySource.unknown;
    _expiryConfidence = item?.expiryConfidence ?? ExpiryConfidence.low;
    _expiryConfirmed = item?.expiryUserConfirmed ?? false;

    _nameCtrl.addListener(_onFieldChanged);
    _customImageCtrl.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onFieldChanged);
    _customImageCtrl.removeListener(_onFieldChanged);
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _thresholdCtrl.dispose();
    _customImageCtrl.dispose();
    super.dispose();
  }

  String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  void _applyPreset(Map<String, String> preset) {
    _nameCtrl.text = preset['name']!;
    _selectedUnit = preset['unit']!;
    _selectedLocation = preset['location']!;
    if (_qtyCtrl.text.isEmpty) {
      _qtyCtrl.text = '1';
    }
    setState(() {});
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final pantry = context.read<PantryProvider>();
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    final threshold = double.tryParse(_thresholdCtrl.text) ?? 1;
    final customUrl = _customImageCtrl.text.trim().isNotEmpty
        ? _customImageCtrl.text.trim()
        : null;

    if (_isEditing) {
      pantry.updateItem(
        widget.item!.copyWith(
          name: _nameCtrl.text.trim(),
          quantity: qty,
          unit: _selectedUnit,
          location: _selectedLocation,
          lowStockThreshold: threshold,
          customImageUrl: customUrl,
          purchaseDate: _purchaseDate,
          expiryDate: _expiryDate,
          openedDate: _openedDate,
          expirySource: _expirySource,
          expiryConfidence: _expiryConfidence,
          expiryUserConfirmed: _expiryConfirmed,
        ),
      );
    } else {
      pantry.addItem(
        householdId: 'hh_demo',
        name: _nameCtrl.text.trim(),
        quantity: qty,
        unit: _selectedUnit,
        location: _selectedLocation,
        lowStockThreshold: threshold,
        customImageUrl: customUrl,
        purchaseDate: _purchaseDate,
        expiryDate: _expiryDate,
        openedDate: _openedDate,
        expirySource: _expirySource,
        expiryConfidence: _expiryConfidence,
        expiryUserConfirmed: _expiryConfirmed,
      );
    }
    Navigator.pop(context);
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (selected != null && mounted) {
      setState(() {
        _expiryDate = selected;
        _expirySource = ExpirySource.manual;
        _expiryConfidence = ExpiryConfidence.high;
        _expiryConfirmed = true;
      });
    }
  }

  Future<void> _pickPurchaseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now,
      helpText: 'Purchase date',
    );
    if (selected != null && mounted) {
      setState(() => _purchaseDate = selected);
    }
  }

  Future<void> _scanExpiry() async {
    final result = await Navigator.push<ConfirmedExpiry>(
      context,
      MaterialPageRoute(builder: (_) => const ExpiryLabelScannerScreen()),
    );
    if (result != null && mounted) {
      setState(() {
        _expiryDate = result.date;
        _expirySource = result.source;
        _expiryConfidence = result.confidence;
        _expiryConfirmed = true;
      });
    }
  }

  void _estimateExpiry() {
    final purchasedAt = _purchaseDate ?? DateTime.now();
    final estimate = ExpiryEstimationService.estimate(
      itemName: _nameCtrl.text.trim(),
      storageZone: _selectedLocation,
      purchasedAt: purchasedAt,
    );
    if (estimate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No safe estimate is available for this item.'),
        ),
      );
      return;
    }
    setState(() {
      _purchaseDate = purchasedAt;
      _expiryDate = estimate.date;
      _expirySource = ExpirySource.receiptEstimate;
      _expiryConfidence = estimate.confidence;
      _expiryConfirmed = false;
    });
  }

  void _markOpened() {
    final opened = DateTime.now();
    final estimate = ExpiryEstimationService.estimateAfterOpening(
      itemName: _nameCtrl.text.trim(),
      openedAt: opened,
      printedExpiry: _expiryDate,
    );
    setState(() {
      _openedDate = opened;
      _expiryDate = estimate.date;
      _expirySource = ExpirySource.openedEstimate;
      _expiryConfidence = estimate.confidence;
      _expiryConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meta = _zoneMeta[_selectedLocation]!;

    final resolvedImageUrl = FoodImageService.resolveImageUrl(
      _nameCtrl.text,
      storageZone: _selectedLocation,
      customImageUrl: _customImageCtrl.text.trim().isNotEmpty
          ? _customImageCtrl.text.trim()
          : null,
    );

    final detectedCategory = FoodImageService.detectCategory(
      _nameCtrl.text,
      defaultZone: _selectedLocation,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: meta.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(meta.icon, color: meta.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isEditing ? 'Edit Item' : 'Add to Pantry',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Live Dynamic Photo Preview Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark2 : AppTheme.bgLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        resolvedImageUrl,
                        width: 58,
                        height: 58,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 58,
                          height: 58,
                          color: meta.color.withValues(alpha: 0.2),
                          child: Icon(meta.icon, color: meta.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.freshHerb.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'DYNAMIC PHOTO',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: AppTheme.freshHerb,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                detectedCategory,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppTheme.textDarkSecondary
                                      : AppTheme.textLightSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _nameCtrl.text.trim().isEmpty
                                ? 'Auto-matching food photo...'
                                : _nameCtrl.text.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppTheme.textDarkPrimary
                                  : AppTheme.textLightPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _customImageCtrl.text.isNotEmpty
                                ? 'Custom photo URL active'
                                : 'Auto-detected via Culinary AI',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppTheme.textDarkSecondary
                                  : AppTheme.textLightSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Quick Presets (when adding new stock)
              if (!_isEditing) ...[
                Row(
                  children: [
                    Text(
                      'Popular Ingredients',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: isDark
                            ? AppTheme.textDarkSecondary
                            : AppTheme.textLightSecondary,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'Tap to auto-fill',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.warmSaffron,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: FoodImageService.popularPresets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final p = FoodImageService.popularPresets[index];
                      final isCurrent = _nameCtrl.text == p['name'];
                      return GestureDetector(
                        onTap: () => _applyPreset(p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? AppTheme.primaryFlame.withValues(alpha: 0.15)
                                : (isDark
                                      ? AppTheme.surfaceDark2
                                      : AppTheme.bgLight),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isCurrent
                                  ? AppTheme.primaryFlame
                                  : (isDark
                                        ? AppTheme.borderDark
                                        : AppTheme.borderLight),
                            ),
                          ),
                          child: Text(
                            p['name']!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrent
                                  ? AppTheme.primaryFlame
                                  : (isDark
                                        ? AppTheme.textDarkPrimary
                                        : AppTheme.textLightPrimary),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Name
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Item Name',
                  prefixIcon: const Icon(Icons.label_outline_rounded),
                  hintText: 'e.g. Whole Milk, Salmon, Avocado',
                  suffixIcon: _nameCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _nameCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),

              // Qty + Unit row
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _qtyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        prefixIcon: Icon(Icons.numbers_rounded),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: PantryProvider.units
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedUnit = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Storage zone
              DropdownButtonFormField<String>(
                initialValue: _selectedLocation,
                decoration: InputDecoration(
                  labelText: 'Storage Zone',
                  prefixIcon: Icon(meta.icon, color: meta.color),
                ),
                items: PantryProvider.zones.map((zone) {
                  final m = _zoneMeta[zone]!;
                  return DropdownMenuItem(
                    value: zone,
                    child: Row(
                      children: [
                        Icon(m.icon, size: 16, color: m.color),
                        const SizedBox(width: 8),
                        Text(zone),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _selectedLocation = v!),
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.surfaceDark2 : AppTheme.bgLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Freshness & expiry',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _pickPurchaseDate,
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _purchaseDate == null
                                  ? 'Add purchase date'
                                  : 'Purchased ${DateFormat('d MMM yyyy').format(_purchaseDate!)}',
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                    const Divider(height: 20),
                    InkWell(
                      onTap: _pickExpiry,
                      child: Row(
                        children: [
                          const Icon(Icons.event_outlined, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _expiryDate == null
                                  ? 'Add expiry date'
                                  : 'Expires ${DateFormat('d MMM yyyy').format(_expiryDate!)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_expiryDate != null)
                            Text(
                              _expiryConfirmed ? 'Confirmed' : 'Estimated',
                              style: TextStyle(
                                fontSize: 11,
                                color: _expiryConfirmed
                                    ? AppTheme.freshHerb
                                    : AppTheme.warmAmber,
                              ),
                            ),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _scanExpiry,
                          icon: const Icon(
                            Icons.document_scanner_outlined,
                            size: 17,
                          ),
                          label: const Text('Scan label'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _estimateExpiry,
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 17,
                          ),
                          label: const Text('Estimate'),
                        ),
                        if (_isEditing && _openedDate == null)
                          OutlinedButton.icon(
                            onPressed: _markOpened,
                            icon: const Icon(Icons.lock_open_rounded, size: 17),
                            label: const Text('Mark opened'),
                          ),
                        if (_expiryDate != null)
                          TextButton(
                            onPressed: () => setState(() {
                              _expiryDate = null;
                              _openedDate = null;
                              _expirySource = ExpirySource.unknown;
                              _expiryConfidence = ExpiryConfidence.low;
                              _expiryConfirmed = false;
                            }),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    if (_openedDate != null)
                      Text(
                        'Opened ${DateFormat('d MMM yyyy').format(_openedDate!)} · expiry adjusted',
                        style: const TextStyle(fontSize: 11),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Low stock threshold
              TextFormField(
                controller: _thresholdCtrl,
                decoration: const InputDecoration(
                  labelText: 'Low Stock Alert (threshold)',
                  prefixIcon: Icon(
                    Icons.warning_amber_rounded,
                    color: AppTheme.warmAmber,
                  ),
                  hintText: 'e.g. 0.5',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 10),

              // Toggle custom image url field
              InkWell(
                onTap: () => setState(
                  () => _showCustomImageField = !_showCustomImageField,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _showCustomImageField
                            ? Icons.expand_less_rounded
                            : Icons.add_photo_alternate_outlined,
                        size: 16,
                        color: AppTheme.primaryFlame,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showCustomImageField
                            ? 'Hide Custom Image URL'
                            : 'Provide Custom Image URL (Optional)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryFlame,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showCustomImageField) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _customImageCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Custom Image URL',
                    prefixIcon: Icon(Icons.image_outlined),
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],

              const SizedBox(height: 22),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _save,
                      icon: Icon(
                        _isEditing ? Icons.save_rounded : Icons.add_rounded,
                      ),
                      label: Text(
                        _isEditing ? 'Save Changes' : 'Add to Pantry',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Interactive Food Item Detail Modal Sheet ──────────────────────────────────

class _ItemDetailModal extends StatelessWidget {
  final PantryItemModel item;
  final Color zoneColor;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _ItemDetailModal({
    required this.item,
    required this.zoneColor,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Image with gradient and close icon
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Image.network(
                  item.displayImageUrl,
                  height: 190,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 190,
                    color: zoneColor.withValues(alpha: 0.2),
                    child: Icon(Icons.restaurant, size: 50, color: zoneColor),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.2),
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 14,
                right: 14,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 16,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: zoneColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.location,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (item.isLowStock) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.warmAmber,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Restock Needed',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Real-time stock control card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark2 : AppTheme.bgLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.borderDark
                          : AppTheme.borderLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Current Stock',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? AppTheme.textDarkSecondary
                                  : AppTheme.textLightSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 1)} ${item.unit}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: item.isLowStock
                                  ? AppTheme.warmAmber
                                  : (isDark
                                        ? AppTheme.textDarkPrimary
                                        : AppTheme.textLightPrimary),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Big Interactive Stepper
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.borderDark
                                : AppTheme.borderLight,
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: onDecrement,
                              icon: const Icon(Icons.remove_rounded),
                              color: isDark
                                  ? AppTheme.textDarkPrimary
                                  : AppTheme.textLightPrimary,
                              tooltip: 'Decrease',
                            ),
                            Container(
                              height: 24,
                              width: 1,
                              color: isDark
                                  ? AppTheme.borderDark
                                  : AppTheme.borderLight,
                            ),
                            IconButton(
                              onPressed: onIncrement,
                              icon: const Icon(Icons.add_rounded),
                              color: AppTheme.primaryFlame,
                              tooltip: 'Increase',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (item.expiryDate != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:
                          (item.expiryStatus == ExpiryStatus.expired
                                  ? AppTheme.errorRed
                                  : item.expiryStatus == ExpiryStatus.useSoon
                                  ? AppTheme.warmAmber
                                  : AppTheme.freshHerb)
                              .withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.event_available_outlined,
                          color: item.expiryStatus == ExpiryStatus.expired
                              ? AppTheme.errorRed
                              : item.expiryStatus == ExpiryStatus.useSoon
                              ? AppTheme.warmAmber
                              : AppTheme.freshHerb,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.expiryStatus == ExpiryStatus.expired
                                    ? 'Expired'
                                    : item.expiryStatus == ExpiryStatus.useSoon
                                    ? 'Use soon'
                                    : 'Freshness date',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${DateFormat('d MMMM yyyy').format(item.expiryDate!)} · ${item.hasEstimatedExpiry ? 'estimated, please verify' : 'confirmed'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Recipes using this item preview
                Text(
                  'Recipes You Can Cook With ${item.name}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.textDarkPrimary
                        : AppTheme.textLightPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _RecipeMiniChip(
                        title: 'Skillet Dinner',
                        time: '20m',
                        imageUrl: 'https://images.unsplash.com/photo-1598515214211-89d3c73ae83b?w=200&q=80',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RecipeMiniChip(
                        title: 'Quick Sauté',
                        time: '12m',
                        imageUrl: 'https://images.unsplash.com/photo-1510693206972-df098062cb71?w=200&q=80',
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Modal Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onEdit();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Details'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorRed,
                      foregroundColor: Colors.white,
                    ).let(
                      (style) => ElevatedButton.icon(
                        style: style,
                        onPressed: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: const Text('Remove'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecipeMiniChip extends StatelessWidget {
  final String title;
  final String time;
  final String imageUrl;
  final bool isDark;

  const _RecipeMiniChip({
    required this.title,
    required this.time,
    required this.imageUrl,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark2 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              imageUrl,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.textDarkPrimary
                        : AppTheme.textLightPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? AppTheme.textDarkMuted
                        : AppTheme.textLightMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _ScopeExt<T> on T {
  R let<R>(R Function(T) op) => op(this);
}
