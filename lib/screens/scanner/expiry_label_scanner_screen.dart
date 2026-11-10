import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../widgets/app_ui.dart';
import '../../widgets/scan_ui.dart';
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
  const ExpiryLabelScannerScreen({
    super.key,
    this.imagePicker,
    this.ocrService,
  });

  final ImagePicker? imagePicker;
  final ReceiptOcrService? ocrService;

  @override
  State<ExpiryLabelScannerScreen> createState() =>
      _ExpiryLabelScannerScreenState();
}

class _ExpiryLabelScannerScreenState extends State<ExpiryLabelScannerScreen> {
  late final _picker = widget.imagePicker ?? ImagePicker();
  late final _ocr = widget.ocrService ?? ReceiptOcrService();
  DateTime? _date;
  String? _matchedText;
  bool _busy = false;
  String? _message;

  Future<void> _scan(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 2400,
      );
      if (image == null || !mounted) return;
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
        _matchedText = null;
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan an expiry label')),
    body: SafeArea(
      child: AppPageBody(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          children: [
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              ScanLanding(
                embedded: true,
                busy: _busy,
                title: 'Make the fresh things last.',
                description: 'Read the date on your package, then confirm it before saving.',
                icon: Icons.event_available_outlined,
                onCamera: () => _scan(ImageSource.camera),
                onGallery: () => _scan(ImageSource.gallery),
                tip: 'Keep EXP, Best Before or Use By text sharp and in focus. Compare the detected date with the package.',
              ),
            if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) ...[
              const PageIntro(
                title: 'Give freshness a date.',
                subtitle: 'Choose the expiry date printed on your package. Check whether the label says Use By or Best Before.',
              ),
              const SizedBox(height: 20),
              const StatusNotice(
                message: 'Photo date scanning is available on Android. You can confirm the printed date manually below.',
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 20),
              StatusNotice(message: _message!),
            ],
            const SizedBox(height: 24),
            FormSection(
              title: 'Confirm the date',
              description: 'You can edit the date if it needs correcting.',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.event_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    _date == null
                        ? 'Choose an expiry date'
                        : DateFormat('d MMMM yyyy').format(_date!),
                  ),
                  subtitle: _matchedText == null
                      ? const Text('Choose manually or scan a label above')
                      : Text(_matchedText!),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _busy ? null : _pickDate,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _date == null || _busy ? null : _confirm,
                  child: const Text('Confirm expiry date'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
