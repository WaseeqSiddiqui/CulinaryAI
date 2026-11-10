import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/cooking_session.dart';
import '../models/recipe_recommendation_model.dart';
import '../services/cooking_assistant_service.dart';

class CookingSessionProvider extends ChangeNotifier {
  static final SpeechToText _sharedSpeech = SpeechToText();
  static CookingSessionProvider? _activeVoiceSession;
  static bool _sharedSpeechConfigured = false;
  static bool _sharedSpeechAvailable = false;

  CookingSessionProvider({
    required this.recipe,
    required this.dietaryRestrictions,
    CookingAssistantService? service,
    SpeechToText? speech,
    FlutterTts? tts,
  }) : _service = service ?? CookingAssistantService(),
       _ownsService = service == null,
       _speech = speech ?? _sharedSpeech,
       _usesSharedSpeech = speech == null,
       _tts = tts ?? FlutterTts();

  final RecipeRecommendationModel recipe;
  final List<String> dietaryRestrictions;
  final CookingAssistantService _service;
  final bool _ownsService;
  final SpeechToText _speech;
  final bool _usesSharedSpeech;
  final FlutterTts _tts;

  final List<CookingChatMessage> _messages = [];
  final Set<int> _completedSteps = {};
  final List<String> _adjustments = [];
  final Map<int, DetailedCookingStep> _details = {};
  Timer? _timer;
  DateTime? _timerDeadline;
  int _remainingSeconds = 0;
  int _stepIndex = 0;
  bool _initialized = false;
  bool _loadingDetail = false;
  bool _sending = false;
  bool _analyzingImage = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isPaused = false;
  bool _speechAvailable = false;
  bool _voiceInitializing = false;
  bool _ttsAvailable = false;
  bool _timerFinished = false;
  String _heardWords = '';
  String? _error;
  String? _voiceError;
  String _voiceLocale = 'auto';
  List<LocaleName> _speechLocales = const [];

  List<CookingChatMessage> get messages => List.unmodifiable(_messages);
  Set<int> get completedSteps => Set.unmodifiable(_completedSteps);
  List<String> get adjustments => List.unmodifiable(_adjustments);
  int get stepIndex => _stepIndex;
  int get stepNumber => _stepIndex + 1;
  int get remainingSeconds => _remainingSeconds;
  bool get initialized => _initialized;
  bool get loadingDetail => _loadingDetail;
  bool get sending => _sending;
  bool get analyzingImage => _analyzingImage;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get isPaused => _isPaused;
  bool get speechAvailable => _speechAvailable;
  bool get voiceInitializing => _voiceInitializing;
  bool get ttsAvailable => _ttsAvailable;
  bool get timerFinished => _timerFinished;
  String get heardWords => _heardWords;
  String? get error => _error;
  String? get voiceError => _voiceError;
  String get voiceLocale => _voiceLocale;
  bool get isLastStep => _stepIndex == recipe.instructions.length - 1;
  String get currentInstruction => recipe.instructionWithQuantities(_stepIndex);
  DetailedCookingStep get currentDetail =>
      _details[_stepIndex] ?? DetailedCookingStep.fallback(currentInstruction);

  String get timerLabel {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get statusLabel {
    if (_voiceInitializing) return 'Preparing microphone…';
    if (_isListening) {
      return _heardWords.isEmpty ? 'Listening… speak now' : _heardWords;
    }
    if (_isSpeaking) return 'Chef is speaking — tap the mic to interrupt';
    if (_analyzingImage) return 'Chef is checking your photo…';
    if (_sending) return 'Chef is thinking…';
    if (_isPaused) return 'Session paused';
    if (!_speechAvailable) {
      return _voiceError ?? 'Voice is unavailable — tap to retry';
    }
    return 'Tap to talk to Chef';
  }

  Future<void> initialize() async {
    if (_initialized) return;
    await _restore();
    await _configureVoice();
    _initialized = true;
    notifyListeners();
    await loadCurrentDetail();
  }

  Future<void> _configureVoice() async {
    if (_voiceInitializing) return;
    _voiceInitializing = true;
    _voiceError = null;
    if (_usesSharedSpeech) _activeVoiceSession = this;
    notifyListeners();

    try {
      _tts.setStartHandler(() {
        _isSpeaking = true;
        notifyListeners();
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      _tts.setCancelHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.46);
      _ttsAvailable = true;
    } on Object {
      _ttsAvailable = false;
    }

    try {
      if (_usesSharedSpeech) {
        if (!_sharedSpeechConfigured || !_sharedSpeechAvailable) {
          _sharedSpeechAvailable = await _speech.initialize(
            onStatus: (status) =>
                _activeVoiceSession?._handleSpeechStatus(status),
            onError: (value) =>
                _activeVoiceSession?._handleSpeechError(value.errorMsg),
          );
          _sharedSpeechConfigured = true;
        }
        _speechAvailable = _sharedSpeechAvailable;
      } else {
        _speechAvailable = await _speech.initialize(
          onStatus: _handleSpeechStatus,
          onError: (value) => _handleSpeechError(value.errorMsg),
        );
      }
      if (_speechAvailable) {
        _speechLocales = await _speech.locales();
      } else {
        _voiceError = 'Speech recognition is disabled on this device';
      }
    } on Object catch (value) {
      _speechAvailable = false;
      _voiceError = 'Microphone setup failed: $value';
    } finally {
      _voiceInitializing = false;
      notifyListeners();
    }
  }

  void _handleSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      notifyListeners();
    }
  }

  void _handleSpeechError(String error) {
    _isListening = false;
    _voiceError = _friendlySpeechError(error);
    notifyListeners();
  }

  String _friendlySpeechError(String error) {
    final value = error.toLowerCase();
    if (value.contains('permission') || value.contains('notallowed')) {
      return 'Microphone permission is required — tap to retry';
    }
    if (value.contains('recognizer') || value.contains('unavailable')) {
      return 'Enable Google speech recognition, then tap to retry';
    }
    if (value.contains('network')) {
      return 'Speech service needs a connection — tap to retry';
    }
    if (value.contains('no_match')) {
      return 'I did not catch that — tap and try again';
    }
    return 'Voice stopped ($error) — tap to retry';
  }

  Future<void> loadCurrentDetail({bool force = false}) async {
    if (_loadingDetail || (!force && _details.containsKey(_stepIndex))) return;
    _loadingDetail = true;
    _error = null;
    notifyListeners();
    try {
      _details[_stepIndex] = await _service.explainStep(
        recipeTitle: recipe.title,
        stepNumber: stepNumber,
        instruction: currentInstruction,
      );
    } on CookingAssistantException catch (value) {
      _error = value.message;
    } finally {
      _loadingDetail = false;
      notifyListeners();
    }
  }

  Future<void> nextStep() async {
    if (isLastStep) return;
    _completedSteps.add(_stepIndex);
    _stepIndex++;
    _isPaused = false;
    stopTimer();
    await _addAssistantMessage(
      'Step $stepNumber is ready. $currentInstruction',
    );
    await _persist();
    await loadCurrentDetail();
  }

  Future<void> previousStep() async {
    if (_stepIndex == 0) return;
    _stepIndex--;
    _isPaused = false;
    stopTimer();
    await _persist();
    await loadCurrentDetail();
  }

  Future<void> revisitStep(int index) async {
    if (index < 0 || index >= recipe.instructions.length) return;
    _stepIndex = index;
    _isPaused = false;
    stopTimer();
    await _persist();
    await loadCurrentDetail();
  }

  Future<void> repeatStep() async {
    final detail = currentDetail;
    final text =
        '${detail.action} Heat: ${detail.heatLevel}. '
        'You are ready to continue when ${detail.completionCriteria.toLowerCase()}';
    await _addAssistantMessage(text, speak: true);
  }

  void togglePause() {
    _isPaused = !_isPaused;
    if (_isPaused) {
      _timer?.cancel();
      unawaited(_stopSpeakingSafely());
    } else if (_remainingSeconds > 0) {
      _startTicker();
    }
    notifyListeners();
    unawaited(_persist());
  }

  void startTimer(int minutes) {
    _timer?.cancel();
    _remainingSeconds = minutes * 60;
    _timerDeadline = DateTime.now().add(Duration(seconds: _remainingSeconds));
    _timerFinished = false;
    _isPaused = false;
    _startTicker();
    notifyListeners();
    unawaited(_persist());
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPaused) return;
      if (_timerDeadline != null) {
        _remainingSeconds = _timerDeadline!
            .difference(DateTime.now())
            .inSeconds
            .clamp(0, 86400);
      } else {
        _remainingSeconds = (_remainingSeconds - 1).clamp(0, 86400);
      }
      if (_remainingSeconds == 0) {
        _timer?.cancel();
        _timerFinished = true;
        _timerDeadline = null;
        unawaited(
          _addAssistantMessage(
            'The timer has finished. Check the visible and texture cues before moving on.',
            speak: true,
          ),
        );
      }
      notifyListeners();
    });
  }

  void acknowledgeTimer() {
    _timerFinished = false;
    notifyListeners();
  }

  void stopTimer() {
    _timer?.cancel();
    _timerDeadline = null;
    _remainingSeconds = 0;
    _timerFinished = false;
    notifyListeners();
  }

  Future<void> submitQuestion(
    String rawMessage, {
    bool speakReply = false,
  }) async {
    final message = rawMessage.trim();
    if (message.isEmpty || _sending || _analyzingImage) return;
    _error = null;
    _messages.add(_message(text: message, isUser: true));
    _sending = true;
    notifyListeners();
    await _persist();

    if (await _handleCommand(message, speakReply: speakReply)) {
      _sending = false;
      notifyListeners();
      return;
    }

    try {
      final reply = await _service.askStep(
        recipeTitle: recipe.title,
        stepNumber: stepNumber,
        instruction: currentInstruction,
        message: message,
        history: _messages.length <= 1
            ? const []
            : _messages.sublist(0, _messages.length - 1),
        adjustments: _adjustments,
        dietaryRestrictions: dietaryRestrictions,
      );
      if (_looksLikeAdjustment(message)) _adjustments.add(message);
      await _addAssistantMessage(reply, speak: speakReply);
    } on CookingAssistantException catch (value) {
      _error = value.message;
      await _addAssistantMessage(
        '${value.message} Stay on Step $stepNumber and use the displayed doneness cues.',
      );
    } finally {
      _sending = false;
      notifyListeners();
      await _persist();
    }
  }

  Future<bool> _handleCommand(
    String message, {
    required bool speakReply,
  }) async {
    final value = message.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '');
    if (value == 'next' ||
        value.contains('next step') ||
        value == 'whats next') {
      if (isLastStep) {
        await _addAssistantMessage(
          'This is the final step. Use the completion and food-safety checks, then tap Finish cooking when ready.',
          speak: speakReply,
        );
      } else {
        await nextStep();
        if (speakReply) await speak('Step $stepNumber. $currentInstruction');
      }
      return true;
    }
    if (value.contains('repeat') || value.contains('explain again')) {
      await repeatStep();
      return true;
    }
    if (value == 'pause' || value.contains('pause cooking')) {
      if (!_isPaused) togglePause();
      await _addAssistantMessage(
        'Cooking session paused. Say resume when you are ready.',
        speak: speakReply,
      );
      return true;
    }
    if (value == 'resume' || value.contains('resume cooking')) {
      if (_isPaused) togglePause();
      await _addAssistantMessage(
        'Session resumed at Step $stepNumber.',
        speak: speakReply,
      );
      return true;
    }
    if (value.contains('time left') || value.contains('how much time')) {
      final reply = _remainingSeconds > 0
          ? '$timerLabel remains on the current timer. Use the doneness cues as the final check.'
          : 'No timer is running. Tap the timer button to start one.';
      await _addAssistantMessage(reply, speak: speakReply);
      return true;
    }
    return false;
  }

  Future<void> submitImage({
    required Uint8List imageBytes,
    String imageName = 'cooking.jpg',
    String? imagePath,
    required String question,
    required String userId,
  }) async {
    if (_analyzingImage || _sending) return;
    final prompt = question.trim().isEmpty
        ? 'Does this look ready for the current step?'
        : question.trim();
    _messages.add(
      _message(
        text: prompt,
        isUser: true,
        kind: CookingMessageKind.image,
        imagePath: imagePath,
      ),
    );
    _analyzingImage = true;
    _error = null;
    notifyListeners();
    await _persist();
    try {
      final result = await _service.validateImage(
        imageBytes: imageBytes,
        imageName: imageName,
        recipeTitle: recipe.title,
        stepNumber: stepNumber,
        instruction: currentInstruction,
        question: prompt,
        userId: userId,
      );
      final text =
          '${result.feedback}\n\nNext: ${result.actionSuggestion}\n${result.safetyNote}';
      _messages.add(
        CookingChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: text,
          isUser: false,
          kind: CookingMessageKind.image,
          createdAt: DateTime.now(),
          visionResult: result,
        ),
      );
      await speak(text);
    } on CookingAssistantException catch (value) {
      _error = value.message;
      await _addAssistantMessage(value.message);
    } finally {
      _analyzingImage = false;
      notifyListeners();
      await _persist();
    }
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      try {
        await _speech.stop();
      } on Object catch (value) {
        _handleSpeechError('$value');
      }
      _isListening = false;
      notifyListeners();
      return;
    }
    if (!_speechAvailable) {
      await _configureVoice();
      if (!_speechAvailable) return;
    }
    if (_usesSharedSpeech) _activeVoiceSession = this;
    if (_isSpeaking) await _stopSpeakingSafely();
    _heardWords = '';
    _isListening = true;
    _voiceError = null;
    notifyListeners();
    try {
      await _speech.listen(
        onResult: (result) {
          _heardWords = result.recognizedWords;
          notifyListeners();
          if (result.finalResult && _heardWords.trim().isNotEmpty) {
            final words = _heardWords;
            _isListening = false;
            notifyListeners();
            unawaited(submitQuestion(words, speakReply: true));
          }
        },
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 3),
          localeId: _resolvedSpeechLocale(),
          cancelOnError: true,
          partialResults: true,
          listenMode: ListenMode.dictation,
          contextualPhrases: const [
            'next step',
            'repeat that',
            'pause',
            'resume',
            'heat',
            'temperature',
            'onions',
          ],
        ),
      );
    } on Object catch (value) {
      _handleSpeechError('$value');
    }
  }

  String? _resolvedSpeechLocale() {
    if (_voiceLocale == 'auto') return null;
    final prefix = _voiceLocale == 'ur' ? 'ur' : 'en';
    for (final locale in _speechLocales) {
      final normalized = locale.localeId.toLowerCase().replaceAll('_', '-');
      if (normalized == '$prefix-pk' || normalized == '$prefix-us') {
        return locale.localeId;
      }
    }
    for (final locale in _speechLocales) {
      if (locale.localeId.toLowerCase().startsWith(prefix)) {
        return locale.localeId;
      }
    }
    return null;
  }

  Future<void> setVoiceLocale(String locale) async {
    _voiceLocale = locale;
    notifyListeners();
    await _persist();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty || !_ttsAvailable) return;
    try {
      await _tts.stop();
      final hasUrdu = RegExp(r'[\u0600-\u06ff]').hasMatch(text);
      await _tts.setLanguage(hasUrdu ? 'ur-PK' : 'en-US');
      await _tts.speak(text);
    } on Object {
      _isSpeaking = false;
      _voiceError =
          'Spoken playback is unavailable; the response is shown as text';
      notifyListeners();
    }
  }

  Future<void> _stopSpeakingSafely() async {
    try {
      await _tts.stop();
    } on Object {
      // Native speech plugins are unavailable in unit tests and some desktops.
    }
  }

  Future<void> _cancelListeningSafely() async {
    try {
      await _speech.cancel();
    } on Object {
      // Native speech plugins are unavailable in unit tests and some desktops.
    }
  }

  Future<void> _addAssistantMessage(String text, {bool speak = false}) async {
    _messages.add(_message(text: text, isUser: false));
    notifyListeners();
    await _persist();
    if (speak) await this.speak(text);
  }

  CookingChatMessage _message({
    required String text,
    required bool isUser,
    CookingMessageKind kind = CookingMessageKind.text,
    String? imagePath,
  }) => CookingChatMessage(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    text: text,
    isUser: isUser,
    kind: kind,
    createdAt: DateTime.now(),
    imagePath: imagePath,
  );

  bool _looksLikeAdjustment(String message) {
    final value = message.toLowerCase();
    return value.contains('substitute') ||
        value.contains("don't have") ||
        value.contains('instead') ||
        value.contains('changed') ||
        value.contains('allergy');
  }

  String get _storageKey => 'culinary_cooking_session_v2_${recipe.id}';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      _stepIndex =
          (json['stepIndex'] is num ? (json['stepIndex'] as num).toInt() : 0)
              .clamp(0, recipe.instructions.length - 1);
      _completedSteps.addAll(
        (json['completedSteps'] as List? ?? const []).whereType<num>().map(
          (value) => value.toInt(),
        ),
      );
      _adjustments.addAll(
        (json['adjustments'] as List? ?? const []).map((value) => '$value'),
      );
      _messages.addAll(
        (json['messages'] as List? ?? const []).whereType<Map>().map(
          (value) =>
              CookingChatMessage.fromJson(Map<String, dynamic>.from(value)),
        ),
      );
      _isPaused = json['isPaused'] == true;
      final savedLocale = json['voiceLocale']?.toString() ?? 'auto';
      _voiceLocale = savedLocale.startsWith('ur')
          ? 'ur'
          : savedLocale.startsWith('en')
          ? 'en'
          : 'auto';
      final deadline = DateTime.tryParse(
        json['timerDeadline']?.toString() ?? '',
      );
      if (deadline != null && deadline.isAfter(DateTime.now())) {
        _timerDeadline = deadline;
        _remainingSeconds = deadline.difference(DateTime.now()).inSeconds;
        if (!_isPaused) _startTicker();
      } else if (_isPaused && json['remainingSeconds'] is num) {
        _remainingSeconds = (json['remainingSeconds'] as num).toInt();
      }
    } on Object {
      // Ignore malformed or obsolete local sessions.
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'stepIndex': _stepIndex,
        'completedSteps': _completedSteps.toList(),
        'adjustments': _adjustments,
        'messages': _messages
            .takeLast(60)
            .map((value) => value.toJson())
            .toList(),
        'isPaused': _isPaused,
        'voiceLocale': _voiceLocale,
        'remainingSeconds': _remainingSeconds,
        'timerDeadline': _timerDeadline?.toIso8601String(),
      }),
    );
  }

  Future<void> clearSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_activeVoiceSession == this) _activeVoiceSession = null;
    unawaited(_cancelListeningSafely());
    unawaited(_stopSpeakingSafely());
    if (_ownsService) _service.close();
    super.dispose();
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int count) =>
      length <= count ? this : skip(length - count);
}
