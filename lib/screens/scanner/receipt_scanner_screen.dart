import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/app_ui.dart';
import '../../widgets/scan_ui.dart';
import '../../models/receipt_vision_models.dart';
import '../../providers/pantry_provider.dart';
import '../../services/household_alias_service.dart';
import '../../services/vision_api_service.dart';

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen>
    with TickerProviderStateMixin {
  _ScanState _scanState = _ScanState.idle;
  List<ValidatedReceiptItem> _scannedItems = [];
  final ImagePicker _imagePicker = ImagePicker();
  final VisionApiService _visionService = VisionApiService();
  final HouseholdAliasService _aliasService = HouseholdAliasService();

  Uint8List? _receiptImage;
  ValidatedReceiptResponse? _validatedResponse;
  bool _isDuplicateReceipt = false;
  String? _receiptKey;
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
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      bytes = await image.readAsBytes();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera access failed. Check the app permissions.'),
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
      _receiptImage = bytes;
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

      // 1. Load household aliases to enhance vision matching
      final aliases = await _aliasService.getAliases(householdId);

      // 2. Upload downscaled image to /parse-receipt backend
      final validatedResponse = await _visionService.parseReceipt(
        imageBytes: bytes,
        userId: householdId,
        householdAliases: aliases,
      );

      // 3. Duplicate check using SHA-256 hash or metadata
      final receiptKey =
          validatedResponse.imageHash ??
          '${validatedResponse.storeName ?? "store"}_${validatedResponse.date ?? "nodate"}_${validatedResponse.receiptTotal ?? 0}';
      final isDuplicate = await VisionApiService.isDuplicate(
        householdId,
        receiptKey,
      );

      if (!mounted) return;

      if (validatedResponse.items.isEmpty) {
        setState(() {
          _validatedResponse = validatedResponse;
          _scanError = 'No grocery items were recognized on this receipt. Please ensure good lighting and alignment.';
          _scanState = _ScanState.error;
        });
        return;
      }

      setState(() {
        _validatedResponse = validatedResponse;
        _scannedItems = validatedResponse.items;
        _isDuplicateReceipt = isDuplicate;
        _receiptKey = receiptKey;
        _scanState = _ScanState.review;
      });

      _showReviewSheet();
    } on VisionApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _scanError = e.message;
        _scanState = _ScanState.error;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanError = 'We could not read this receipt. Check your connection and try another photo.';
        _scanState = _ScanState.error;
      });
    }
  }

  void _resetScan() {
    setState(() {
      _scanState = _ScanState.idle;
      _scannedItems = [];
      _receiptImage = null;
      _validatedResponse = null;
      _isDuplicateReceipt = false;
      _receiptKey = null;
      _scanError = null;
    });
  }

  void _showReviewSheet() {
    final resp = _validatedResponse;
    if (resp == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 760),
      useSafeArea: true,
      showDragHandle: false,
      isDismissible: false,
      builder: (_) => ReceiptReviewSheet(
        response: resp,
        items: _scannedItems,
        isDuplicate: _isDuplicateReceipt,
        receiptImage: _receiptImage,
        onAliasCorrection: (rawText, newName) async {
          final pantry = Provider.of<PantryProvider>(context, listen: false);
          final householdId = pantry.householdId ?? 'personal_demo_chef';
          await _aliasService.saveAlias(householdId, rawText, newName);
        },
        onConfirm: _confirmItems,
        onRescan: () {
          Navigator.pop(context);
          _resetScan();
        },
      ),
    ).whenComplete(() {
      if (mounted && _scanState == _ScanState.review) _resetScan();
    });
  }

  Future<void> _confirmItems(List<ValidatedReceiptItem> confirmed) async {
    final pantry = Provider.of<PantryProvider>(context, listen: false);
    final householdId = pantry.householdId ?? 'personal_demo_chef';
    final resp = _validatedResponse;

    // Ingest confirmed items into pantry inventory & write purchase events to ledger
    await pantry.ingestReceiptItems(
      householdId: householdId,
      items: confirmed,
      storeName: resp?.storeName,
      receiptDate: resp?.date,
      receiptTotal: resp?.receiptTotal,
      receiptHash: _receiptKey,
    );

    // Record receipt as processed
    if (_receiptKey != null) {
      await VisionApiService.markProcessed(householdId, _receiptKey!);
    }

    if (!mounted) return;
    Navigator.pop(context); // close review sheet
    setState(() => _scanState = _ScanState.done);

    final addedCount = confirmed.where((i) => i.isSelected).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              '$addedCount items added to pantry & ledger!',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: AppTheme.primaryEmerald,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _loadDemoReceipt() {
    final demoResponse = ValidatedReceiptResponse(
      scanId: 'demo_receipt_001',
      storeName: 'Carrefour Market',
      date: '2026-10-18',
      receiptTotal: 1850.0,
      totalMismatchWarning: false,
      items: [
        ValidatedReceiptItem(
          rawText: 'WHOLE MILK 1L X 2',
          name: 'Whole Milk',
          matchedIngredient: 'Whole Milk',
          totalQty: 2.0,
          unit: 'litres',
          linePrice: 580.0,
          confidence: 0.98,
          storageZone: 'Fridge',
          isFood: true,
          isSelected: true,
        ),
        ValidatedReceiptItem(
          rawText: 'FARM EGGS 12 PK',
          name: 'Eggs',
          matchedIngredient: 'Eggs',
          totalQty: 12.0,
          unit: 'pcs',
          linePrice: 360.0,
          confidence: 0.95,
          storageZone: 'Fridge',
          isFood: true,
          isSelected: true,
        ),
        ValidatedReceiptItem(
          rawText: 'BASMATI RICE 1KG',
          name: 'Basmati Rice',
          matchedIngredient: 'Basmati Rice',
          totalQty: 1.0,
          unit: 'kg',
          linePrice: 450.0,
          confidence: 0.97,
          storageZone: 'Pantry Shelf',
          isFood: true,
          isSelected: true,
        ),
        ValidatedReceiptItem(
          rawText: 'FRESH TOMATOES 500G',
          name: 'Tomato',
          matchedIngredient: 'Tomato',
          totalQty: 4.0,
          unit: 'pcs',
          linePrice: 160.0,
          confidence: 0.94,
          storageZone: 'Fridge',
          isFood: true,
          isSelected: true,
        ),
        ValidatedReceiptItem(
          rawText: 'BONELESS CHICKEN 500G',
          name: 'Chicken',
          matchedIngredient: 'Chicken',
          totalQty: 500.0,
          unit: 'g',
          linePrice: 520.0,
          confidence: 0.96,
          storageZone: 'Freezer',
          isFood: true,
          isSelected: true,
        ),
      ],
    );

    setState(() {
      _validatedResponse = demoResponse;
      _scannedItems = demoResponse.items;
      _isDuplicateReceipt = false;
      _receiptKey = 'demo_receipt_preview';
      _scanState = _ScanState.review;
    });

    _showReviewSheet();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan a receipt'),
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
      _ScanState.idle => _IdleView(
        onCamera: () => _startScan(ImageSource.camera),
        onGallery: () => _startScan(ImageSource.gallery),
      ),
      _ScanState.scanning => _ScanningView(
        scanLineAnim: _scanLineAnim,
        pulseAnim: _pulseAnim,
        imageBytes: _receiptImage,
      ),
      _ScanState.processing => const _ProcessingView(),
      _ScanState.review => const _ProcessingView(),
      _ScanState.error => _ScanErrorView(
        message: _scanError ?? 'The receipt could not be read.',
        onRetry: _resetScan,
        onUseDemo: _loadDemoReceipt,
      ),
      _ScanState.done => _DoneView(
        itemCount: _scannedItems.where((i) => i.isSelected).length,
        onNewScan: _resetScan,
      ),
    };
  }
}

enum _ScanState { idle, scanning, processing, review, error, done }

// ── Idle View ────────────────────────────────────────────────────────────────

class _IdleView extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _IdleView({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) => ScanLanding(
    title: 'A fresh start, one receipt at a time.',
    description: 'Turn your grocery receipt into a tidy pantry. Review the items and quantities before saving.',
    icon: Icons.receipt_long_outlined,

    onCamera: onCamera,
    onGallery: onGallery,
    tip: 'Lay the receipt flat in good light. Keep the shop name, item lines and total in the frame.',
  );
}

class _ScanningView extends StatelessWidget {
  final Animation<double> scanLineAnim;
  final Animation<double> pulseAnim;
  final Uint8List? imageBytes;

  const _ScanningView({
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
              height: 420,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryEmerald, width: 2),
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
                          color: AppTheme.primaryEmerald,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryEmerald.withValues(
                                alpha: 0.8,
                              ),
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

// ── Processing View ───────────────────────────────────────────────────────────

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) => const ScanStatusView(
    busy: true,
    title: 'Reading your receipt.',
    message: 'Finding the groceries, quantities and prices. You can check everything before adding it to your pantry.',
  );
}

class _ScanErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onUseDemo;

  const _ScanErrorView({
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
        child: const Text('Explore a sample receipt'),
      ),
    ],
  );
}

class _DoneView extends StatelessWidget {
  final int itemCount;
  final VoidCallback onNewScan;

  const _DoneView({required this.itemCount, required this.onNewScan});

  @override
  Widget build(BuildContext context) => ScanStatusView(
    icon: Icons.check_rounded,
    title: 'Your pantry is up to date.',
    message:
        "$itemCount reviewed items were added to your pantry and purchase history.",
    actions: [
      FilledButton.icon(
        onPressed: onNewScan,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Scan another receipt'),
      ),
      OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back to your kitchen'),
      ),
    ],
  );
}

class ReceiptReviewSheet extends StatefulWidget {
  final ValidatedReceiptResponse response;
  final List<ValidatedReceiptItem> items;
  final bool isDuplicate;
  final Uint8List? receiptImage;
  final void Function(String rawText, String newName) onAliasCorrection;
  final FutureOr<void> Function(List<ValidatedReceiptItem>) onConfirm;
  final VoidCallback onRescan;

  const ReceiptReviewSheet({
    super.key,
    required this.response,
    required this.items,
    required this.isDuplicate,
    required this.receiptImage,
    required this.onAliasCorrection,
    required this.onConfirm,
    required this.onRescan,
  });

  @override
  State<ReceiptReviewSheet> createState() => _ReceiptReviewSheetState();
}

class _ReceiptReviewSheetState extends State<ReceiptReviewSheet> {
  late List<ValidatedReceiptItem> _items;
  bool _saving = false;
  bool _saved = false;
  final _zones = PantryProvider.zones;
  final _zoneIcons = {
    'Fridge': Icons.kitchen_rounded,
    'Freezer': Icons.ac_unit_rounded,
    'Pantry Shelf': Icons.shelves,
    'Spice Rack': Icons.spa_rounded,
  };

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  int get _selectedCount => _items.where((i) => i.isSelected).length;

  double get _totalPrice => _items
      .where((i) => i.isSelected && i.linePrice != null)
      .fold(0.0, (sum, i) => sum + i.linePrice!);

  Future<void> _save() async {
    if (_saving || _saved || _selectedCount == 0) return;
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

  Future<bool> _editItem(int index) async {
    final item = _items[index];
    final originalRaw = item.rawText;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: item.matchedIngredient.isNotEmpty
          ? item.matchedIngredient
          : item.name,
    );
    final quantityController = TextEditingController(
      text: item.totalQty.toStringAsFixed(
        item.totalQty.truncateToDouble() == item.totalQty ? 0 : 2,
      ),
    );
    final priceController = TextEditingController(
      text: item.linePrice != null ? item.linePrice!.toStringAsFixed(2) : '',
    );
    var selectedUnit = item.unit;
    var selectedZone = item.storageZone;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Correct Receipt Item'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Receipt printed: "${item.rawText}"',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Ingredient Name',
                      prefixIcon: Icon(Icons.restaurant_rounded),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter ingredient name'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: quantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                          ),
                          validator: (value) {
                            final q = double.tryParse(value ?? '');
                            return q == null || q <= 0
                                ? 'Invalid quantity'
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedUnit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                          items: PantryProvider.units
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: (val) => setDialogState(
                            () => selectedUnit = val ?? selectedUnit,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: priceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Line Price',
                            prefixText: 'PKR ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedZone,
                          decoration: const InputDecoration(labelText: 'Zone'),
                          items: _zones
                              .map(
                                (z) =>
                                    DropdownMenuItem(value: z, child: Text(z)),
                              )
                              .toList(),
                          onChanged: (val) => setDialogState(
                            () => selectedZone = val ?? selectedZone,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save Correction'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && mounted) {
      final newName = nameController.text.trim();
      final newQty = double.parse(quantityController.text);
      final newPrice = double.tryParse(priceController.text);

      setState(() {
        item.name = newName;
        item.matchedIngredient = newName;
        item.totalQty = newQty;
        item.unit = selectedUnit;
        item.storageZone = selectedZone;
        item.linePrice = newPrice;
        item.needsReview = false;
        item.isSelected = true;
      });

      // Save user correction to household alias table
      if (originalRaw.isNotEmpty) {
        widget.onAliasCorrection(originalRaw, newName);
      }
    }
    nameController.dispose();
    quantityController.dispose();
    priceController.dispose();
    return saved == true;
  }

  void _addMissingItem() async {
    final newItem = ValidatedReceiptItem(
      rawText: 'Manual addition',
      name: 'New ingredient',
      matchedIngredient: 'New ingredient',
      totalQty: 1.0,
      unit: 'pcs',
      storageZone: 'Pantry Shelf',
      isSelected: true,
      needsReview: false,
    );
    setState(() => _items.add(newItem));
    final index = _items.length - 1;
    final saved = await _editItem(index);
    if (!saved && mounted) {
      setState(() => _items.remove(newItem));
    }
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resp = widget.response;

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
                // Drag handle
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

                // Sheet header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resp.storeName ?? 'Review your groceries',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${resp.date ?? "Date not detected"} • ${resp.currency ?? "PKR"} ${resp.receiptTotal?.toStringAsFixed(0) ?? _totalPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _addMissingItem,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add Item'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Warning Banners
                if (widget.isDuplicate)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warmAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.warmAmber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          color: AppTheme.warmAmber,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This receipt may already be in your pantry. Check the items before adding it again.',
                            style: TextStyle(
                              color: AppTheme.warmAmber,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (resp.totalMismatchWarning)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.price_change_rounded,
                          color: Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Total mismatch: Item sum (${resp.calculatedItemsTotal.toStringAsFixed(0)}) differs from printed total (${resp.receiptTotal?.toStringAsFixed(0)}) by ${resp.totalDifferencePercent.toStringAsFixed(1)}%. Review highlighted items below.',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Items List
                Expanded(
                  child: ListView.separated(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => _ReviewItemTile(
                      item: _items[i],
                      zones: _zones,
                      zoneIcons: _zoneIcons,
                      isDark: isDark,
                      onToggle: (val) =>
                          setState(() => _items[i].isSelected = val),
                      onZoneChange: (zone) =>
                          setState(() => _items[i].storageZone = zone),
                      onEdit: () => _editItem(i),
                      onDelete: () => _removeItem(i),
                    ),
                  ),
                ),

                // Confirm Bottom Bar
                Container(
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
                    minimum: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _saving ? null : widget.onRescan,
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retake'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed:
                                  _selectedCount == 0 || _saving || _saved
                                  ? null
                                  : _save,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryEmerald,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                              ),
                              label: Text(
                                _saving
                                    ? 'Saving…'
                                    : _saved
                                    ? 'Saved'
                                    : _selectedCount == 1
                                    ? 'Add 1 item'
                                    : 'Add $_selectedCount items',
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewItemTile extends StatelessWidget {
  final ValidatedReceiptItem item;
  final List<String> zones;
  final Map<String, IconData> zoneIcons;
  final bool isDark;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onZoneChange;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReviewItemTile({
    required this.item,
    required this.zones,
    required this.zoneIcons,
    required this.isDark,
    required this.onToggle,
    required this.onZoneChange,
    required this.onEdit,
    required this.onDelete,
  });

  bool get _hasWarning =>
      item.needsReview ||
      (!item.totalQty.isFinite || item.totalQty <= 0) ||
      item.confidence < 0.65;

  Color get _zoneColor {
    switch (item.storageZone) {
      case 'Fridge':
        return AppTheme.zoneFridge;
      case 'Freezer':
        return AppTheme.zoneFreezer;
      case 'Spice Rack':
        return AppTheme.zoneSpice;
      default:
        return AppTheme.zonePantry;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final warning = _hasWarning;
    return Material(
      color: warning
          ? AppTheme.warmAmber.withValues(alpha: .05)
          : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: warning
              ? AppTheme.warmAmber.withValues(alpha: .4)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.isSelected,
                  onChanged: (value) => onToggle(value ?? false),
                ),
                Expanded(
                  child: Text(
                    item.matchedIngredient.isNotEmpty
                        ? item.matchedIngredient
                        : item.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Review item options',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else {
                      onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Correct item')),
                    PopupMenuItem(value: 'remove', child: Text('Remove item')),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${NumberFormat('0.###').format(item.totalQty)} ${item.unit}${item.linePrice == null ? '' : ' · PKR ${item.linePrice!.toStringAsFixed(2)}'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (warning || !item.isFood) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (!item.totalQty.isFinite || item.totalQty <= 0)
                          _badge('Check the quantity', AppTheme.warmAmber),
                        if (item.confidence < .65)
                          _badge('Check the match', AppTheme.warmAmber),
                        if (item.needsReview)
                          _badge('Review this item', AppTheme.warmAmber),
                        if (!item.isFood)
                          _badge('Non-food item', colors.onSurfaceVariant),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            PopupMenuButton<String>(
              tooltip: 'Choose storage zone',
              onSelected: onZoneChange,
              itemBuilder: (_) => zones
                  .map(
                    (zone) => PopupMenuItem(
                      value: zone,
                      child: Row(
                        children: [
                          Icon(
                            zoneIcons[zone] ?? Icons.shelves,
                            size: 18,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 12),
                          Text(zone),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
                child: Row(
                  children: [
                    Icon(
                      zoneIcons[item.storageZone] ?? Icons.shelves,
                      size: 18,
                      color: _zoneColor,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Store in ${item.storageZone}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      color: colors.onSurfaceVariant,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? AppTheme.textDarkPrimary : color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
