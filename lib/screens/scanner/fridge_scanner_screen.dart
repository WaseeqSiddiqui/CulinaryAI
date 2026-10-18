import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/fridge_vision_models.dart';
import '../../providers/pantry_provider.dart';
import '../../services/food_image_service.dart';
import '../../services/vision_api_service.dart';
import '../../widgets/server_settings_modal.dart';

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
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Camera access failed. Check app permissions.'),
        ),
      );
      return;
    }
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    setState(() {
      _scanState = _ScanState.scanning;
      _fridgeImage = bytes;
      _scanError = null;
    });

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
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
        _scanError = 'Failed to analyze fridge shelf. Check your backend server and connection.';
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _FridgeReconciliationSheet(
        response: resp,
        onConfirm: _applyReconciliation,
        onRescan: () {
          Navigator.pop(context);
          _resetScan();
        },
      ),
    );
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.bgDark : const Color(0xFF2A2420),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Scan fridge',
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
          IconButton(
            tooltip: 'Server IP Settings',
            icon: const Icon(Icons.dns_rounded, color: Colors.white70),
            onPressed: () => ServerSettingsModal.show(context),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

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
        onConfigureServer: () => ServerSettingsModal.show(context),
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
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 290,
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.zoneFridge, width: 2),
                    color: Colors.white.withValues(alpha: 0.03),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.kitchen_rounded,
                          size: 52,
                          color: AppTheme.zoneFridge.withValues(alpha: 0.8),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Photograph your open fridge',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Full fridge or one shelf—no arranging needed',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'The scanner checks the full image, including cluttered shelves and door compartments. You review every item before pantry stock changes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 20),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
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
                    'Scan fridge',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.zoneFridge,
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
      ],
    );
  }
}

// ── Scanning & Processing Views ──────────────────────────────────────────────

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
              width: 300,
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
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.zoneFridge.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppTheme.zoneFridge,
                strokeWidth: 3,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Auditing Fridge Stock...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reconciling detected items with your pantry inventory',
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

class _FridgeErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onConfigureServer;
  final VoidCallback onUseDemo;

  const _FridgeErrorView({
    required this.message,
    required this.onRetry,
    required this.onConfigureServer,
    required this.onUseDemo,
  });

  @override
  Widget build(BuildContext context) {
    final isConnectionError = message.contains('SocketException') ||
        message.contains('Connection refused') ||
        message.contains('connect') ||
        message.contains('127.0.0.1');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Audit Incomplete',
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
            if (isConnectionError) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.warmSaffron.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.warmSaffron.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline_rounded,
                      color: AppTheme.warmSaffron,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'On physical Android devices, use your PC Wi-Fi IP (192.168.100.147:8000) instead of 127.0.0.1.',
                        style: TextStyle(
                          color: AppTheme.warmSaffron,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.zoneFridge,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onConfigureServer,
                  icon: const Icon(Icons.dns_rounded, size: 18),
                  label: const Text('Server IP'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onUseDemo,
              icon: const Icon(
                Icons.kitchen_rounded,
                size: 18,
                color: AppTheme.zoneFridge,
              ),
              label: const Text(
                'Test with Sample Fridge Scan',
                style: TextStyle(
                  color: AppTheme.zoneFridge,
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

class _DoneFridgeView extends StatelessWidget {
  final VoidCallback onNewScan;
  const _DoneFridgeView({required this.onNewScan});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_rounded,
              color: AppTheme.zoneFridge,
              size: 56,
            ),
            const SizedBox(height: 20),
            const Text(
              'Fridge Reconciled',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stock counts verified and adjusted based on your confirmation.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                  ),
                  child: const Text('Return Home'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: onNewScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.zoneFridge,
                  ),
                  child: const Text(
                    'Scan Another Shelf',
                    style: TextStyle(color: Colors.white),
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

// ── Fridge Reconciliation Bottom Sheet ───────────────────────────────────────

class _FridgeReconciliationSheet extends StatefulWidget {
  final FridgeScanResponse response;
  final void Function(List<ReconciledFridgeItem>) onConfirm;
  final VoidCallback onRescan;

  const _FridgeReconciliationSheet({
    required this.response,
    required this.onConfirm,
    required this.onRescan,
  });

  @override
  State<_FridgeReconciliationSheet> createState() =>
      _FridgeReconciliationSheetState();
}

class _FridgeReconciliationSheetState
    extends State<_FridgeReconciliationSheet> {
  late List<ReconciledFridgeItem> _items;

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

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Fridge Reconciliation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _statusChip(
                        '${verified.length} Verified',
                        AppTheme.primaryEmerald,
                      ),
                      const SizedBox(width: 8),
                      if (mismatches.isNotEmpty) ...[
                        _statusChip(
                          '${mismatches.length} Questions',
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
                    _sectionHeader(
                      'Stock Questions (User Clarification Required)',
                    ),
                    ...mismatches.map(
                      (item) => _buildMismatchTile(item, isDark),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (newItems.isNotEmpty) ...[
                    _sectionHeader('Spotted New Items (Not in Ledger)'),
                    ...newItems.map((item) => _buildNewItemTile(item, isDark)),
                    const SizedBox(height: 16),
                  ],
                  if (verified.isNotEmpty) ...[
                    _sectionHeader('Verified Matching Stock'),
                    ...verified.map((item) => _buildVerifiedTile(item, isDark)),
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
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onRescan,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Re-snap'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => widget.onConfirm(_items),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.zoneFridge,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'Apply Confirmed Updates',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
        ),
      ),
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
                      'Pantry: ${item.currentQuantity} ${item.unit}  •  Scan: ${item.suggestedQuantity} ${item.unit}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
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
            child: const Text(
              'estimated = true',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
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
          const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.primaryEmerald,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item.matchedName ?? item.detectedName} (${item.currentQuantity} ${item.unit})',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const Text(
            'Verified',
            style: TextStyle(
              color: AppTheme.primaryEmerald,
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
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
