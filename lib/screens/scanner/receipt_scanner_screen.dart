import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/receipt_vision_models.dart';
import '../../providers/pantry_provider.dart';
import '../../services/food_image_service.dart';
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
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

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
    XFile? image;
    try {
      image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera access failed. Check the app permissions.'),
        ),
      );
      return;
    }
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _scanState = _ScanState.scanning;
      _receiptImage = bytes;
      _scanError = null;
    });

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
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
      final receiptKey = validatedResponse.imageHash ??
          '${validatedResponse.storeName ?? "store"}_${validatedResponse.date ?? "nodate"}_${validatedResponse.receiptTotal ?? 0}';
      final isDuplicate = await VisionApiService.isDuplicate(householdId, receiptKey);

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
        _scanError = 'Failed to analyze receipt. Check your backend server and connection.';
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _ReviewSheet(
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
    );
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Receipt scanner is intentionally a dark camera-first experience;
      // dark mode uses the warm truffle obsidian, light mode uses a warm camera-dark.
      backgroundColor: isDark ? AppTheme.bgDark : const Color(0xFF2A2420),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Receipt Scanner',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white70,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_scanState == _ScanState.done)
            TextButton.icon(
              onPressed: _resetScan,
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppTheme.primaryEmerald,
                size: 18,
              ),
              label: const Text(
                'New Scan',
                style: TextStyle(
                  color: AppTheme.primaryEmerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

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
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Viewfinder container
                Container(
                  width: 290,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryEmerald,
                      width: 2,
                    ),
                    color: Colors.white.withValues(alpha: 0.03),
                  ),
                  child: Stack(
                    children: [
                      ..._buildCorners(),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.document_scanner_rounded,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Point camera at grocery receipt',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'AI-powered receipt scanning',
                              style: TextStyle(
                                color: AppTheme.primaryEmerald.withValues(alpha: 0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: const [
                    _InfoChip(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'Auto Crop & Deskew',
                    ),
                    _InfoChip(
                      icon: Icons.reviews_outlined,
                      label: 'Mandatory Review',
                    ),
                    _InfoChip(
                      icon: Icons.history_edu_rounded,
                      label: 'Ledger Audit',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Bottom action buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 24),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 20),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 22),
                  label: const Text(
                    'Snap Receipt',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCorners() {
    const size = 18.0;
    const thickness = 3.0;
    const color = AppTheme.primaryEmerald;

    return [
      Positioned(
        top: 10,
        left: 10,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: thickness),
              left: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
      Positioned(
        top: 10,
        right: 10,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: thickness),
              right: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 10,
        left: 10,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: thickness),
              left: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
      Positioned(
        bottom: 10,
        right: 10,
        child: Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: thickness),
              right: BorderSide(color: color, width: thickness),
            ),
          ),
        ),
      ),
    ];
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryEmerald),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scanning View ────────────────────────────────────────────────────────────

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
          Positioned.fill(
            child: Image.memory(
              imageBytes!,
              fit: BoxFit.cover,
            ),
          ),
        Container(color: Colors.black.withValues(alpha: 0.45)),
        Center(
          child: ScaleTransition(
            scale: pulseAnim,
            child: Container(
              width: 290,
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
                              color: AppTheme.primaryEmerald.withValues(alpha: 0.8),
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
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppTheme.primaryEmerald,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Analyzing receipt...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reading line items & prices',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error View ───────────────────────────────────────────────────────────────

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
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Scan Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryEmerald,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onUseDemo,
              icon: const Icon(
                Icons.receipt_long_rounded,
                size: 18,
                color: AppTheme.warmSaffron,
              ),
              label: const Text(
                'Test with Sample Demo Receipt',
                style: TextStyle(
                  color: AppTheme.warmSaffron,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Done View ────────────────────────────────────────────────────────────────

class _DoneView extends StatelessWidget {
  final int itemCount;
  final VoidCallback onNewScan;

  const _DoneView({required this.itemCount, required this.onNewScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.primaryEmerald,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Stock Ingested Successfully',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$itemCount items added to pantry inventory & purchase ledger',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back to Home'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onNewScan,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Scan Another'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Review Sheet (Mandatory Review) ──────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final ValidatedReceiptResponse response;
  final List<ValidatedReceiptItem> items;
  final bool isDuplicate;
  final Uint8List? receiptImage;
  final void Function(String rawText, String newName) onAliasCorrection;
  final void Function(List<ValidatedReceiptItem>) onConfirm;
  final VoidCallback onRescan;

  const _ReviewSheet({
    required this.response,
    required this.items,
    required this.isDuplicate,
    required this.receiptImage,
    required this.onAliasCorrection,
    required this.onConfirm,
    required this.onRescan,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late List<ValidatedReceiptItem> _items;
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

  Future<bool> _editItem(int index) async {
    final item = _items[index];
    final originalRaw = item.rawText;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: item.matchedIngredient.isNotEmpty ? item.matchedIngredient : item.name);
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
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Enter ingredient name' : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: quantityController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Quantity'),
                          validator: (value) {
                            final q = double.tryParse(value ?? '');
                            return q == null || q <= 0 ? 'Invalid quantity' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedUnit,
                          decoration: const InputDecoration(labelText: 'Unit'),
                          items: PantryProvider.units
                              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                          onChanged: (val) => setDialogState(() => selectedUnit = val ?? selectedUnit),
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                              .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                              .toList(),
                          onChanged: (val) => setDialogState(() => selectedZone = val ?? selectedZone),
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

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 30,
              offset: const Offset(0, -6),
            ),
          ],
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resp.storeName ?? 'Receipt Review',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${resp.date ?? "Detected Date: Today"} • ${resp.currency ?? "PKR"} ${resp.receiptTotal?.toStringAsFixed(0) ?? _totalPrice.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),

            // Warning Banners
            if (widget.isDuplicate)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.warmAmber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warmAmber.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.copy_rounded, color: AppTheme.warmAmber, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Duplicate Receipt Warning: This receipt appears to have been scanned previously. Please verify items before confirming.',
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.price_change_rounded, color: Colors.orange, size: 20),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _ReviewItemTile(
                  item: _items[i],
                  zones: _zones,
                  zoneIcons: _zoneIcons,
                  isDark: isDark,
                  onToggle: (val) => setState(() => _items[i].isSelected = val),
                  onZoneChange: (zone) => setState(() => _items[i].storageZone = zone),
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
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
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
                      onPressed: widget.onRescan,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Re-scan'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                      onPressed: _selectedCount == 0 ? null : () => widget.onConfirm(_items),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: Text(
                        'Confirm $_selectedCount Items',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
      (item.count == null && item.packSize == null) ||
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
    final color = _zoneColor;
    final isSelected = item.isSelected;
    final warning = _hasWarning;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSelected ? 1.0 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark
              ? (warning
                  ? AppTheme.warmAmber.withValues(alpha: 0.12)
                  : isSelected
                      ? color.withValues(alpha: 0.07)
                      : AppTheme.surfaceDark)
              : (warning
                  ? AppTheme.warmAmber.withValues(alpha: 0.08)
                  : isSelected
                      ? color.withValues(alpha: 0.04)
                      : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: warning
                ? AppTheme.warmAmber
                : isSelected
                    ? color.withValues(alpha: 0.3)
                    : Colors.transparent,
            width: warning ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (v) => onToggle(v ?? false),
              activeColor: AppTheme.primaryEmerald,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                FoodImageService.resolveImageUrl(
                  item.matchedIngredient.isNotEmpty ? item.matchedIngredient : item.name,
                ),
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(zoneIcons[item.storageZone] ?? Icons.shelves, color: color, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.matchedIngredient.isNotEmpty ? item.matchedIngredient : item.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppTheme.textDarkPrimary : AppTheme.textLightPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Correct item',
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 30, height: 28),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(width: 30, height: 28),
                        icon: const Icon(Icons.close_rounded, size: 17),
                      ),
                    ],
                  ),
                  if (warning) ...[
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      children: [
                        if (item.count == null && item.packSize == null)
                          _badge('Null Qty (Tap to fix)', AppTheme.warmAmber),
                        if (item.confidence < 0.65)
                          _badge('Low Conf ${(item.confidence * 100).toInt()}%', Colors.orange),
                        if (item.needsReview && (item.count != null || item.packSize != null))
                          _badge('Needs Review', AppTheme.warmAmber),
                      ],
                    ),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${item.totalQty.toStringAsFixed(item.totalQty.truncateToDouble() == item.totalQty ? 0 : 1)} ${item.unit}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.linePrice != null) ...[
                        const Text(' • ', style: TextStyle(color: AppTheme.textSecondary)),
                        Text(
                          'PKR ${item.linePrice!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (!item.isFood) ...[
                        const SizedBox(width: 6),
                        _badge('Non-food', Colors.grey),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Storage Zone Dropdown
            PopupMenuButton<String>(
              onSelected: onZoneChange,
              itemBuilder: (_) => zones
                  .map(
                    (z) => PopupMenuItem(
                      value: z,
                      child: Row(
                        children: [
                          Icon(
                            zoneIcons[z] ?? Icons.shelves,
                            size: 16,
                            color: z == item.storageZone ? AppTheme.primaryEmerald : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            z,
                            style: TextStyle(
                              fontWeight: z == item.storageZone ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(zoneIcons[item.storageZone] ?? Icons.shelves, color: color, size: 14),
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, color: color, size: 14),
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
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
