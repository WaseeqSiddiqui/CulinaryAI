import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/pantry_item_model.dart';
import '../../services/expiry_label_parser.dart';
import '../../services/receipt_ocr_service.dart';

class ConfirmedExpiry {
  final DateTime date;
  final ExpirySource source;
  final ExpiryConfidence confidence;

  const ConfirmedExpiry({
    required this.date,
    required this.source,
    required this.confidence,
  });
}

class ExpiryLabelScannerScreen extends StatefulWidget {
  const ExpiryLabelScannerScreen({super.key});

  @override
  State<ExpiryLabelScannerScreen> createState() =>
      _ExpiryLabelScannerScreenState();
}

class _ExpiryLabelScannerScreenState extends State<ExpiryLabelScannerScreen> {
  final _picker = ImagePicker();
  final _ocr = ReceiptOcrService();
  DateTime? _date;
  String? _matchedText;
  bool _busy = false;
  String? _message;

  Future<void> _scan(ImageSource source) async {
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 95,
      maxWidth: 2400,
    );
    if (image == null || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final ocr = await _ocr.recognize(image.path);
      final parsed = ExpiryLabelParser.parse(ocr.rawText);
      if (!mounted) return;
      setState(() {
        _date = parsed?.date;
        _matchedText = parsed?.matchedText;
        _message = parsed == null
            ? 'No clear expiry date was found. Choose the date manually.'
            : 'Date detected. Check it against the package before saving.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'The label could not be read. Choose the date manually.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 3650)),
      lastDate: now.add(const Duration(days: 3650)),
      helpText: 'Confirm expiry date',
    );
    if (value != null && mounted) {
      setState(() {
        _date = value;
        _message = 'Manually confirmed date.';
      });
    }
  }

  void _confirm() {
    final date = _date;
    if (date == null) return;
    Navigator.pop(
      context,
      ConfirmedExpiry(
        date: date,
        source: _matchedText == null
            ? ExpirySource.manual
            : ExpirySource.labelScan,
        confidence: ExpiryConfidence.high,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan expiry label')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.primaryFlame.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.document_scanner_outlined,
                    size: 52,
                    color: AppTheme.primaryFlame,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Keep EXP, Best Before or Use By text sharp and inside the frame.',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Always check the detected date against the package.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Take photo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_message != null) ...[
              const SizedBox(height: 18),
              Text(_message!, textAlign: TextAlign.center),
            ],
            const SizedBox(height: 18),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _date == null
                    ? 'No date selected'
                    : DateFormat('d MMMM yyyy').format(_date!),
              ),
              subtitle: _matchedText == null ? null : Text(_matchedText!),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: _pickDate,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _date == null ? null : _confirm,
              child: const Text('Confirm expiry date'),
            ),
          ],
        ),
      ),
    );
  }
}
