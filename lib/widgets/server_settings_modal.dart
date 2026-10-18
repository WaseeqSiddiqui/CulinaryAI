import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../services/server_config_service.dart';

class ServerSettingsModal extends StatefulWidget {
  final VoidCallback? onSaved;

  const ServerSettingsModal({super.key, this.onSaved});

  static Future<void> show(BuildContext context, {VoidCallback? onSaved}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServerSettingsModal(onSaved: onSaved),
    );
  }

  @override
  State<ServerSettingsModal> createState() => _ServerSettingsModalState();
}

class _ServerSettingsModalState extends State<ServerSettingsModal> {
  late final TextEditingController _urlController;
  bool _testing = false;
  bool? _testSuccess;
  String? _testMessage;
  int? _latency;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ServerConfigService.currentBaseUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _testMessage = null;
    });

    final res = await ServerConfigService.testConnection(_urlController.text);

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSuccess = res.success;
      _testMessage = res.message;
      _latency = res.latencyMs;
    });
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await ServerConfigService.setBaseUrl(url);
    if (!mounted) return;
    widget.onSaved?.call();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Server URL set to: $url'),
        backgroundColor: AppTheme.freshHerb,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryFlame.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  color: AppTheme.primaryFlame,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Server Configuration',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppTheme.textLightPrimary,
                      ),
                    ),
                    Text(
                      'Host computer running FastAPI backend',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : AppTheme.textLightSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Quick Presets:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.wifi, size: 14),
                label: const Text('Wi-Fi PC (192.168.100.147)'),
                onPressed: () {
                  _urlController.text = 'http://192.168.100.147:8000';
                  setState(() {
                    _testMessage = null;
                  });
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.usb, size: 14),
                label: const Text('USB adb reverse (127.0.0.1)'),
                onPressed: () {
                  _urlController.text = 'http://127.0.0.1:8000';
                  setState(() {
                    _testMessage = null;
                  });
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.phone_android, size: 14),
                label: const Text('Android Emulator (10.0.2.2)'),
                onPressed: () {
                  _urlController.text = 'http://10.0.2.2:8000';
                  setState(() {
                    _testMessage = null;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Backend URL',
              hintText: 'e.g. http://192.168.100.147:8000',
              prefixIcon: const Icon(Icons.link_rounded),
              suffixIcon: IconButton(
                tooltip: 'Test Connection',
                onPressed: _testing ? null : _runTest,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_rounded),
              ),
            ),
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (_testSuccess == true ? AppTheme.freshHerb : AppTheme.errorRed)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (_testSuccess == true ? AppTheme.freshHerb : AppTheme.errorRed)
                      .withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _testSuccess == true
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: _testSuccess == true
                        ? AppTheme.freshHerb
                        : AppTheme.errorRed,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _latency != null
                          ? '$_testMessage (${_latency}ms)'
                          : _testMessage!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _testSuccess == true
                            ? AppTheme.freshHerb
                            : AppTheme.errorRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _runTest,
                  child: const Text('Test Ping'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save & Connect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
