import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/receipt_scanned_item.dart';
import '../../providers/pantry_provider.dart';
import '../../services/food_image_service.dart';

// Mock OCR response — simulates what the vision API returns
const _kMockReceiptItems = [
  {
    'name': 'Whole Milk',
    'quantity': 2.0,
    'unit': 'litres',
    'location': 'fridge',
    'price': 320.0,
  },
  {
    'name': 'Free Range Eggs',
    'quantity': 12.0,
    'unit': 'pcs',
    'location': 'fridge',
    'price': 280.0,
  },
  {
    'name': 'Basmati Rice',
    'quantity': 5.0,
    'unit': 'kg',
    'location': 'pantry_shelf',
    'price': 950.0,
  },
  {
    'name': 'Chicken Breast',
    'quantity': 1.0,
    'unit': 'kg',
    'location': 'fridge',
    'price': 680.0,
  },
  {
    'name': 'Olive Oil',
    'quantity': 500.0,
    'unit': 'ml',
    'location': 'pantry_shelf',
    'price': 450.0,
  },
  {
    'name': 'Cumin Seeds',
    'quantity': 100.0,
    'unit': 'g',
    'location': 'spice_rack',
    'price': 80.0,
  },
  {
    'name': 'Coriander Powder',
    'quantity': 100.0,
    'unit': 'g',
    'location': 'spice_rack',
    'price': 65.0,
  },
  {
    'name': 'Frozen Peas',
    'quantity': 500.0,
    'unit': 'g',
    'location': 'freezer',
    'price': 120.0,
  },
  {
    'name': 'Greek Yogurt',
    'quantity': 400.0,
    'unit': 'g',
    'location': 'fridge',
    'price': 195.0,
  },
  {
    'name': 'Garlic Paste',
    'quantity': 200.0,
    'unit': 'g',
    'location': 'fridge',
    'price': 75.0,
  },
];

class ReceiptScannerScreen extends StatefulWidget {
  const ReceiptScannerScreen({super.key});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen>
    with TickerProviderStateMixin {
  _ScanState _scanState = _ScanState.idle;
  List<ReceiptScannedItem> _scannedItems = [];
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _receiptImage;

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
    super.dispose();
  }

  Future<void> _startScan(ImageSource source) async {
    XFile? image;
    try {
      image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
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
    });

    // The captured image is ready for an OCR backend. Week 1 uses the
    // reviewable extraction fixture until that backend endpoint is connected.
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    setState(() => _scanState = _ScanState.processing);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // Build mock scanned items (simulate slight OCR variation)
    final rng = Random();
    final items = _kMockReceiptItems.map((data) {
      return ReceiptScannedItem(
        name: data['name'] as String,
        quantity:
            (data['quantity'] as double) + (rng.nextDouble() * 0.1 - 0.05),
        unit: data['unit'] as String,
        location: data['location'] as String,
        price: data['price'] as double?,
        isSelected: true,
      );
    }).toList();

    setState(() {
      _scannedItems = items;
      _scanState = _ScanState.review;
    });

    _showReviewSheet();
  }

  void _showReviewSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      builder: (_) => _ReviewSheet(
        items: _scannedItems,
        onConfirm: _confirmItems,
        onRescan: () {
          Navigator.pop(context);
          setState(() {
            _scanState = _ScanState.idle;
            _scannedItems = [];
            _receiptImage = null;
          });
        },
      ),
    );
  }

  void _confirmItems(List<ReceiptScannedItem> confirmed) {
    final pantry = Provider.of<PantryProvider>(context, listen: false);
    for (final item in confirmed.where((i) => i.isSelected)) {
      pantry.addItem(
        householdId: 'hh_demo',
        name: item.name,
        quantity: item.quantity,
        unit: item.unit,
        location: _zoneLabel(item.location),
        lowStockThreshold: _defaultThreshold(item.unit),
        addedVia: 'receipt_scan',
      );
    }

    Navigator.pop(context); // close sheet
    setState(() => _scanState = _ScanState.done);

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
              '${confirmed.where((i) => i.isSelected).length} items added to pantry!',
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

  // Converts internal zone key → display label used in PantryProvider
  String _zoneLabel(String loc) {
    switch (loc) {
      case 'fridge':
        return 'Fridge';
      case 'freezer':
        return 'Freezer';
      case 'spice_rack':
        return 'Spice Rack';
      default:
        return 'Pantry Shelf';
    }
  }

  double _defaultThreshold(String unit) {
    if (unit == 'kg' || unit == 'litres') return 0.5;
    if (unit == 'pcs') return 2;
    if (unit == 'g' || unit == 'ml') return 50;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.bgDark : const Color(0xFF14161B),
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
              onPressed: () => setState(() {
                _scanState = _ScanState.idle;
                _scannedItems = [];
                _receiptImage = null;
              }),
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
      _ScanState.review => const _ProcessingView(), // brief flash
      _ScanState.done => _DoneView(
        itemCount: _scannedItems.where((i) => i.isSelected).length,
        onNewScan: () => setState(() {
          _scanState = _ScanState.idle;
          _scannedItems = [];
          _receiptImage = null;
        }),
      ),
    };
  }
}

enum _ScanState { idle, scanning, processing, review, done }

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
                // Camera viewfinder mock
                Container(
                  width: 280,
                  height: 200,
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
                      // Corner brackets
                      ..._buildCorners(),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              size: 48,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Point camera at receipt',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Info chips
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: const [
                    _InfoChip(
                      icon: Icons.flash_on_rounded,
                      label: 'Auto-detects items',
                    ),
                    _InfoChip(
                      icon: Icons.edit_rounded,
                      label: 'Review before adding',
                    ),
                    _InfoChip(
                      icon: Icons.bolt_rounded,
                      label: 'Batch pantry update',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Bottom action area
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: onCamera,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryEmerald,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 22),
                  label: const Text(
                    'Scan Receipt',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: onGallery,
                icon: const Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: Colors.white54,
                ),
                label: const Text(
                  'Upload from Gallery',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static List<Widget> _buildCorners() {
    const color = AppTheme.primaryEmerald;
    const size = 20.0;
    const thickness = 3.0;
    return [
      // TL
      Positioned(
        top: 12,
        left: 12,
        child: _Corner(
          top: true,
          left: true,
          color: color,
          size: size,
          thickness: thickness,
        ),
      ),
      // TR
      Positioned(
        top: 12,
        right: 12,
        child: _Corner(
          top: true,
          left: false,
          color: color,
          size: size,
          thickness: thickness,
        ),
      ),
      // BL
      Positioned(
        bottom: 12,
        left: 12,
        child: _Corner(
          top: false,
          left: true,
          color: color,
          size: size,
          thickness: thickness,
        ),
      ),
      // BR
      Positioned(
        bottom: 12,
        right: 12,
        child: _Corner(
          top: false,
          left: false,
          color: color,
          size: size,
          thickness: thickness,
        ),
      ),
    ];
  }
}

class _Corner extends StatelessWidget {
  final bool top, left;
  final Color color;
  final double size, thickness;
  const _Corner({
    required this.top,
    required this.left,
    required this.color,
    required this.size,
    required this.thickness,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          top: top,
          left: left,
          color: color,
          thickness: thickness,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final bool top, left;
  final Color color;
  final double thickness;
  _CornerPainter({
    required this.top,
    required this.left,
    required this.color,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;
    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
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

// ── Scanning View ─────────────────────────────────────────────────────────────

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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 280,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryEmerald, width: 2),
              color: Colors.white.withValues(alpha: 0.03),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AnimatedBuilder(
                animation: scanLineAnim,
                builder: (_, _) => Stack(
                  children: [
                    if (imageBytes != null)
                      Positioned.fill(
                        child: Image.memory(imageBytes!, fit: BoxFit.cover),
                      ),
                    // scan overlay gradient
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppTheme.primaryEmerald.withValues(alpha: 0.0),
                              AppTheme.primaryEmerald.withValues(alpha: 0.04),
                              AppTheme.primaryEmerald.withValues(alpha: 0.0),
                            ],
                            stops: [
                              (scanLineAnim.value - 0.1).clamp(0.0, 1.0),
                              scanLineAnim.value,
                              (scanLineAnim.value + 0.1).clamp(0.0, 1.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // scan line
                    Positioned(
                      top: scanLineAnim.value * 190,
                      left: 12,
                      right: 12,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              AppTheme.primaryEmerald,
                              Colors.transparent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryEmerald.withValues(
                                alpha: 0.6,
                              ),
                              blurRadius: 8,
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
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: pulseAnim,
            builder: (_, _) => Transform.scale(
              scale: pulseAnim.value,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryEmerald,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Scanning receipt...',
                      style: TextStyle(
                        color: AppTheme.primaryEmerald,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
            'Extracting items...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'OCR Vision AI is reading your receipt',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
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
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: AppTheme.heroGradient,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.4),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 52,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Pantry Updated!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$itemCount items added from your receipt',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: onNewScan,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryEmerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                label: const Text(
                  'Scan Another Receipt',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Back to Dashboard',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Review Bottom Sheet ───────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final List<ReceiptScannedItem> items;
  final void Function(List<ReceiptScannedItem>) onConfirm;
  final VoidCallback onRescan;

  const _ReviewSheet({
    required this.items,
    required this.onConfirm,
    required this.onRescan,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late List<ReceiptScannedItem> _items;
  final _zones = ['fridge', 'freezer', 'pantry_shelf', 'spice_rack'];
  final _zoneLabels = {
    'fridge': 'Fridge',
    'freezer': 'Freezer',
    'pantry_shelf': 'Pantry Shelf',
    'spice_rack': 'Spice Rack',
  };
  final _zoneIcons = {
    'fridge': Icons.kitchen_rounded,
    'freezer': Icons.ac_unit_rounded,
    'pantry_shelf': Icons.shelves,
    'spice_rack': Icons.spa_rounded,
  };

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  int get _selectedCount => _items.where((i) => i.isSelected).length;
  double get _totalPrice => _items
      .where((i) => i.isSelected && i.price != null)
      .fold(0.0, (sum, i) => sum + i.price!);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryEmerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: AppTheme.primaryEmerald,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Review Scanned Items',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${_items.length} items detected • $_selectedCount selected',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      final allSelected = _selectedCount == _items.length;
                      for (final item in _items) {
                        item.isSelected = !allSelected;
                      }
                    }),
                    child: Text(
                      _selectedCount == _items.length ? 'None' : 'All',
                      style: const TextStyle(
                        color: AppTheme.primaryEmerald,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Total price bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryEmerald.withValues(
                    alpha: isDark ? 0.08 : 0.06,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primaryEmerald.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.receipt_rounded,
                      color: AppTheme.primaryEmerald,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Receipt Total:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryEmerald,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'PKR ${_totalPrice.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryEmerald,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Items list
            Expanded(
              child: ListView.separated(
                controller: controller,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _ReviewItemTile(
                  item: _items[i],
                  zones: _zones,
                  zoneLabels: _zoneLabels,
                  zoneIcons: _zoneIcons,
                  isDark: isDark,
                  onToggle: (val) => setState(() => _items[i].isSelected = val),
                  onZoneChange: (zone) =>
                      setState(() => _items[i].location = zone),
                  onQtyChange: (qty) =>
                      setState(() => _items[i].quantity = qty),
                ),
              ),
            ),
            // Bottom confirm bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
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
                      onPressed: _selectedCount == 0
                          ? null
                          : () => widget.onConfirm(_items),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryEmerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.kitchen_rounded, size: 18),
                      label: Text(
                        'Add $_selectedCount to Pantry',
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
}

class _ReviewItemTile extends StatelessWidget {
  final ReceiptScannedItem item;
  final List<String> zones;
  final Map<String, String> zoneLabels;
  final Map<String, IconData> zoneIcons;
  final bool isDark;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onZoneChange;
  final ValueChanged<double> onQtyChange;

  const _ReviewItemTile({
    required this.item,
    required this.zones,
    required this.zoneLabels,
    required this.zoneIcons,
    required this.isDark,
    required this.onToggle,
    required this.onZoneChange,
    required this.onQtyChange,
  });

  Color get _zoneColor {
    switch (item.location) {
      case 'fridge':
        return AppTheme.zoneFridge;
      case 'freezer':
        return AppTheme.zoneFreezer;
      case 'spice_rack':
        return AppTheme.zoneSpice;
      default:
        return AppTheme.zonePantry;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _zoneColor;
    final isSelected = item.isSelected;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isSelected ? 1.0 : 0.45,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? (isSelected
                    ? color.withValues(alpha: 0.07)
                    : AppTheme.surfaceDark)
              : (isSelected
                    ? color.withValues(alpha: 0.04)
                    : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.25)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Checkbox
            Transform.scale(
              scale: 1.1,
              child: Checkbox(
                value: isSelected,
                onChanged: (v) => onToggle(v ?? false),
                activeColor: AppTheme.primaryEmerald,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Food Photo Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                _getScannedItemImage(item.name),
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    zoneIcons[item.location] ?? Icons.shelves,
                    color: color,
                    size: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Name & details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.textDarkPrimary
                          : AppTheme.textLightPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        '${item.quantity.toStringAsFixed(item.quantity.truncateToDouble() == item.quantity ? 0 : 1)} ${item.unit}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (item.price != null) ...[
                        const Text(
                          ' • ',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'PKR ${item.price!.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Zone dropdown
            PopupMenuButton<String>(
              onSelected: onZoneChange,
              itemBuilder: (_) => zones
                  .map(
                    (z) => PopupMenuItem(
                      value: z,
                      child: Row(
                        children: [
                          Icon(
                            zoneIcons[z],
                            size: 16,
                            color: z == item.location
                                ? AppTheme.primaryEmerald
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            zoneLabels[z] ?? z,
                            style: TextStyle(
                              fontWeight: z == item.location
                                  ? FontWeight.w700
                                  : FontWeight.normal,
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
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(zoneIcons[item.location], color: color, size: 14),
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
}

String _getScannedItemImage(String name) =>
    FoodImageService.resolveImageUrl(name);
