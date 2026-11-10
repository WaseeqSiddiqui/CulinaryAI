import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/scan_ui.dart';
import '../../models/fridge_vision_models.dart';
import '../../providers/pantry_provider.dart';
import '../../services/food_image_service.dart';
import '../../services/vision_api_service.dart';

class FridgeScannerScreen extends StatefulWidget {
  const FridgeScannerScreen({super.key});

  @override
  State<FridgeScannerScreen> createState() => _FridgeScannerScreenState();
}

class _FridgeScannerScreenState extends State<FridgeScannerScreen>
    with TickerProviderStateMixin {
  _ScanState _scanState = _ScanState.idle;
  final ImagePicker _imagePicker = ImagePicker();
  final VisionApiService _visionService = VisionApiService();

  Uint8List? _fridgeImage;
  FridgeScanResponse? _scanResponse;
  String? _scanError;
  bool _pickingImage = false;

  late AnimationController _scanLineController;
  late AnimationController _pulseController;
  late Animation<double> _scanLineAnim;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scanLineAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _pulseController.dispose();
    _visionService.close();
    super.dispose();
  }

  Future<void> _startScan(ImageSource source) async {
    if (_pickingImage) return;
    _pickingImage = true;
    late Uint8List bytes;
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
      if (image == null || !mounted) return;
      bytes = await image.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera access failed. Check app permissions.'),
        ),
      );
      return;
    } finally {
      _pickingImage = false;
    }
    if (!mounted) return;
    _scanLineController.repeat(reverse: true);
    _pulseController.repeat(reverse: true);
    setState(() {
      _scanState = _ScanState.scanning;
      _fridgeImage = bytes;
      _scanError = null;
    });

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _scanLineController.stop();
    _pulseController.stop();
    setState(() => _scanState = _ScanState.processing);

    try {
      final pantry = Provider.of<PantryProvider>(context, listen: false);
      final householdId = pantry.householdId ?? 'personal_demo_chef';

      final response = await _visionService.scanFridge(
        imageBytes: bytes,
        userId: householdId,
        existingItems: pantry.allItems,
      );

      if (!mounted) return;

      if (response.reconciledItems.isEmpty) {
        setState(() {
          _scanError = 'The scan finished but no visible food was returned. Items do not need to be arranged—step back to include the full open fridge, then scan again.';
          _scanState = _ScanState.error;
        });
        return;
      }

      setState(() {
        _scanResponse = response;
        _scanState = _ScanState.reconcile;
      });

      _showReconciliationSheet();
    } on VisionApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _scanError = e.message;
        _scanState = _ScanState.error;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanError = 'We could not read this shelf. Check your connection and try another photo.';
        _scanState = _ScanState.error;
      });
    }
  }

  void _resetScan() {
    setState(() {
      _scanState = _ScanState.idle;
      _fridgeImage = null;
      _scanResponse = null;
      _scanError = null;
    });
  }

  void _showReconciliationSheet() {
    final resp = _scanResponse;
    if (resp == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 760),
      useSafeArea: true,
      showDragHandle: false,
      isDismissible: false,
      builder: (_) => FridgeReviewSheet(
        response: resp,
        onConfirm: _applyReconciliation,
        onRescan: () {
          Navigator.pop(context);
          _resetScan();
        },
      ),
    ).whenComplete(() {
      if (mounted && _scanState == _ScanState.reconcile) _resetScan();
    });
  }

  Future<void> _applyReconciliation(
    List<ReconciledFridgeItem> confirmedItems,
  ) async {
    final pantry = Provider.of<PantryProvider>(context, listen: false);
    final householdId = pantry.householdId ?? 'personal_demo_chef';

    await pantry.reconcileFridgeItems(
      householdId: householdId,
      reconciledItems: confirmedItems,
    );

    if (!mounted) return;
    Navigator.pop(context);
    setState(() => _scanState = _ScanState.done);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text(
              'Fridge stock verified and reconciled!',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: AppTheme.zoneFridge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _loadDemoFridgeScan() {
    final demo = FridgeScanResponse(
      scanId: 'demo_scan_001',
      reconciledItems: [
        ReconciledFridgeItem(
          detectedName: 'Whole Milk',
          matchedPantryId: 'demo_milk',
          matchedName: 'Whole Milk',
          status: 'verified',
          currentQuantity: 2.0,
          suggestedQuantity: 2.0,
          unit: 'litres',
          confidence: 0.96,
          isAccepted: true,
        ),
        ReconciledFridgeItem(
          detectedName: 'Eggs',
          matchedPantryId: 'demo_eggs',
          matchedName: 'Eggs',
          status: 'mismatch',
          currentQuantity: 12.0,
          suggestedQuantity: 8.0,
          unit: 'pcs',
          confidence: 0.94,
          question: 'Pantry shows 12 pcs but only 8 seen. Update to 8?',
          isAccepted: false,
        ),
        ReconciledFridgeItem(
          detectedName: 'Greek Yogurt',
          status: 'new_item',
          currentQuantity: 0.0,
          suggestedQuantity: 1.0,
          unit: 'tub',
          confidence: 0.91,
          question: 'Found on shelf but not in pantry. Add Greek Yogurt?',
          isAccepted: true,
        ),
      ],
    );

    setState(() {
      _scanResponse = demo;
      _scanState = _ScanState.reconcile;
    });

    _showReconciliationSheet();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan your fridge'),
      actions: [
        if (_scanState == _ScanState.done)
          TextButton.icon(
            onPressed: _resetScan,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('New scan'),
          ),
        const SizedBox(width: 12),
      ],
    ),
    body: SafeArea(child: AppPageBody(child: _buildBody())),
  );

  Widget _buildBody() {
    return switch (_scanState) {
      _ScanState.idle => _IdleFridgeView(
        onCamera: () => _startScan(ImageSource.camera),
        onGallery: () => _startScan(ImageSource.gallery),
      ),
      _ScanState.scanning => _ScanningFridgeView(
        scanLineAnim: _scanLineAnim,
        pulseAnim: _pulseAnim,
        imageBytes: _fridgeImage,
      ),
      _ScanState.processing => const _ProcessingFridgeView(),
      _ScanState.reconcile => const _ProcessingFridgeView(),
      _ScanState.error => _FridgeErrorView(
        message: _scanError ?? 'The fridge photo could not be analyzed.',
        onRetry: _resetScan,
        onUseDemo: _loadDemoFridgeScan,
      ),
      _ScanState.done => _DoneFridgeView(onNewScan: _resetScan),
    };
  }
}

enum _ScanState { idle, scanning, processing, reconcile, error, done }

// ── Idle Fridge View ─────────────────────────────────────────────────────────

class _IdleFridgeView extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _IdleFridgeView({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) => ScanLanding(
    title: 'See what is fresh.',
    description: 'Photograph a shelf and compare what is there with your pantry. You choose which changes to keep.',
    icon: Icons.kitchen_outlined,
    photoAsset: 'assets/images/pantry_basket.jpg',
    onCamera: onCamera,
    onGallery: onGallery,
    tip: 'Use good light and photograph one shelf at a time. Keep packaging and labels visible.',
  );
}

class _ScanningFridgeView extends StatelessWidget {
  final Animation<double> scanLineAnim;
  final Animation<double> pulseAnim;
  final Uint8List? imageBytes;

  const _ScanningFridgeView({
    required this.scanLineAnim,
    required this.pulseAnim,
    required this.imageBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (imageBytes != null)
          Positioned.fill(child: Image.memory(imageBytes!, fit: BoxFit.cover)),
        Container(color: Colors.black.withValues(alpha: 0.45)),
        Center(
          child: ScaleTransition(
            scale: pulseAnim,
            child: Container(
              width: (MediaQuery.sizeOf(context).width - 48).clamp(
                180.0,
                320.0,
              ),
              height: 400,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.zoneFridge, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AnimatedBuilder(
                  animation: scanLineAnim,
                  builder: (_, _) {
                    return Align(
                      alignment: Alignment(0, (scanLineAnim.value * 2) - 1),
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppTheme.zoneFridge,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.zoneFridge.withValues(alpha: 0.8),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProcessingFridgeView extends StatelessWidget {
  const _ProcessingFridgeView();

  @override
  Widget build(BuildContext context) => const ScanStatusView(
    busy: true,
    title: 'Getting to know your shelf.',
    message: 'Matching visible ingredients to your pantry and preparing the changes for your review.',
  );
}

class _FridgeErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onUseDemo;

  const _FridgeErrorView({
    required this.message,
    required this.onRetry,
    required this.onUseDemo,
  });

  @override
  Widget build(BuildContext context) => ScanStatusView(
    icon: Icons.document_scanner_outlined,
    title: 'Let us try that again.',
    message: message,
    actions: [
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Try another photo'),
      ),
      TextButton(
        onPressed: onUseDemo,
        child: const Text('Explore a sample fridge scan'),
      ),
    ],
  );
}

class _DoneFridgeView extends StatelessWidget {
  final VoidCallback onNewScan;
  const _DoneFridgeView({required this.onNewScan});

  @override
  Widget build(BuildContext context) => ScanStatusView(
    icon: Icons.check_rounded,
    title: 'Your pantry is up to date.',
    message: 'Your confirmed stock changes have been saved. The next good meal starts here.',
    actions: [
      FilledButton.icon(
        onPressed: onNewScan,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Scan another shelf'),
      ),
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back to your kitchen'),
      ),
    ],
  );
}

class FridgeReviewSheet extends StatefulWidget {
  final FridgeScanResponse response;
  final FutureOr<void> Function(List<ReconciledFridgeItem>) onConfirm;
  final VoidCallback onRescan;

  const FridgeReviewSheet({
    super.key,
    required this.response,
    required this.onConfirm,
    required this.onRescan,
  });

  @override
  State<FridgeReviewSheet> createState() => _FridgeReviewSheetState();
}

class _FridgeReviewSheetState extends State<FridgeReviewSheet> {
  late List<ReconciledFridgeItem> _items;
  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    try {
      await widget.onConfirm(_items);
      if (mounted) setState(() => _saved = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes could not be saved. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.response.reconciledItems);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final mismatches = _items.where((i) => i.status == 'mismatch').toList();
    final newItems = _items.where((i) => i.status == 'new_item').toList();
    final verified = _items.where((i) => i.status == 'verified').toList();

    return PopScope(
      canPop: !_saving,
      child: AbsorbPointer(
        absorbing: _saving || _saved,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, controller) => Material(
            color: Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Review your fridge',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _statusChip(
                            '${verified.length} Verified',
                            AppTheme.primaryEmerald,
                          ),
                          const SizedBox(width: 8),
                          if (mismatches.isNotEmpty) ...[
                            _statusChip(
                              '${mismatches.length} ${mismatches.length == 1 ? 'Question' : 'Questions'}',
                              AppTheme.warmAmber,
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (newItems.isNotEmpty)
                            _statusChip(
                              '${newItems.length} New',
                              AppTheme.zoneFridge,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (mismatches.isNotEmpty) ...[
                        _sectionHeader('A few things to check'),
                        ...mismatches.map(
                          (item) => _buildMismatchTile(item, isDark),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (newItems.isNotEmpty) ...[
                        _sectionHeader('New to your pantry'),
                        ...newItems.map(
                          (item) => _buildNewItemTile(item, isDark),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (verified.isNotEmpty) ...[
                        _sectionHeader('Already up to date'),
                        ...verified.map(
                          (item) => _buildVerifiedTile(item, isDark),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : Colors.white,
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? AppTheme.borderDark
                            : AppTheme.borderLight,
                      ),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving ? null : widget.onRescan,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Retake'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: _saving || _saved ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.zoneFridge,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              _saving
                                  ? 'Saving…'
                                  : _saved
                                  ? 'Saved'
                                  : 'Save changes',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _buildMismatchTile(ReconciledFridgeItem item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warmAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warmAmber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  FoodImageService.resolveImageUrl(
                    item.matchedName ?? item.detectedName,
                  ),
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.kitchen_rounded,
                    color: AppTheme.warmAmber,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.matchedName ?? item.detectedName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'In pantry: ${_formatFridgeQty(item.currentQuantity)} ${item.unit} · In photo: ${_formatFridgeQty(item.suggestedQuantity)} ${item.unit}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: item.isAccepted,
                activeThumbColor: AppTheme.warmAmber,
                onChanged: (val) => setState(() => item.isAccepted = val),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.question ?? 'Stock differs. Would you like to update?',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.estimated
                  ? 'Photo estimate · check the quantity'
                  : 'Detected quantity',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'PlusJakartaSans',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewItemTile(ReconciledFridgeItem item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.zoneFridge.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.zoneFridge.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              FoodImageService.resolveImageUrl(
                item.matchedName ?? item.detectedName,
              ),
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.add_box_rounded, color: AppTheme.zoneFridge),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.matchedName ?? item.detectedName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  item.question ?? 'Found on shelf. Add to pantry?',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: item.isAccepted,
            activeThumbColor: AppTheme.zoneFridge,
            onChanged: (val) => setState(() => item.isAccepted = val),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedTile(ReconciledFridgeItem item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryEmerald.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item.matchedName ?? item.detectedName} (${_formatFridgeQty(item.currentQuantity)} ${item.unit})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Text(
            'Verified',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).brightness == Brightness.dark
              ? Theme.of(context).colorScheme.onSurface
              : color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _formatFridgeQty(double? value) =>
    value == null ? '—' : NumberFormat('0.###').format(value);
