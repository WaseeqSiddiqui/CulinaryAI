enum CookingMessageKind { text, image, system }

class DetailedCookingStep {
  final String action;
  final String heatLevel;
  final String pace;
  final String estimatedDuration;
  final String technique;
  final List<String> visualCues;
  final String textureAndAroma;
  final List<String> precautions;
  final String completionCriteria;
  final String proTip;

  const DetailedCookingStep({
    required this.action,
    required this.heatLevel,
    required this.pace,
    required this.estimatedDuration,
    required this.technique,
    required this.visualCues,
    required this.textureAndAroma,
    required this.precautions,
    required this.completionCriteria,
    required this.proTip,
  });

  factory DetailedCookingStep.fromJson(
    Map<String, dynamic> json, {
    required String fallbackAction,
  }) => DetailedCookingStep(
    action: _text(json['action'], fallbackAction),
    heatLevel: _text(json['heat_level'], 'Adjust heat as needed'),
    pace: _text(json['pace'], 'Cook steadily and monitor closely'),
    estimatedDuration: _text(
      json['estimated_duration'],
      'Use observable doneness cues rather than the clock alone',
    ),
    technique: _text(json['technique'], 'Check frequently and cook evenly'),
    visualCues: _strings(json['visual_cues']),
    textureAndAroma: _text(
      json['texture_and_aroma'],
      _text(json['aroma_and_sound'], 'Watch, smell, and listen for changes'),
    ),
    precautions: _strings(json['precautions'] ?? json['mistakes_to_avoid']),
    completionCriteria: _text(
      json['completion_criteria'],
      'Continue only when the instruction and observable cues are satisfied',
    ),
    proTip: _text(json['pro_tip'], ''),
  );

  factory DetailedCookingStep.fallback(String instruction) =>
      DetailedCookingStep(
        action: instruction,
        heatLevel: 'Adjust heat as needed',
        pace: 'Cook steadily and monitor closely',
        estimatedDuration:
            'Timing is an estimate; prioritize observable doneness cues',
        technique: 'Stir, flip, or check often enough to cook evenly',
        visualCues: const ['Look for the visible change named in the step'],
        textureAndAroma:
            'Use texture, aroma, and sound together with the visual cues',
        precautions: const [
          'Avoid rushing with excessive heat',
          'Use a food thermometer where safe internal temperature matters',
        ],
        completionCriteria: 'Proceed only when the step goal is visibly met and any required food-safety check passes',
        proTip: '',
      );
}

class CookingVisionResult {
  final String status;
  final String headline;
  final String feedback;
  final String actionSuggestion;
  final List<String> observations;
  final double confidence;
  final bool imageSufficient;
  final String safetyNote;

  const CookingVisionResult({
    required this.status,
    required this.headline,
    required this.feedback,
    required this.actionSuggestion,
    required this.observations,
    required this.confidence,
    required this.imageSufficient,
    required this.safetyNote,
  });

  factory CookingVisionResult.fromJson(Map<String, dynamic> json) =>
      CookingVisionResult(
        status: _text(json['status'], 'attention_needed'),
        headline: _text(json['headline'], 'Check the cooking progress'),
        feedback: _text(json['feedback'], 'The image could not be assessed.'),
        actionSuggestion: _text(
          json['action_suggestion'],
          'Use the step cues and upload a clearer photo if needed.',
        ),
        observations: _strings(json['visual_observations']),
        confidence: json['confidence'] is num
            ? (json['confidence'] as num).toDouble()
            : 0,
        imageSufficient: json['image_sufficient'] == true,
        safetyNote: _text(
          json['safety_note'],
          'A photo cannot verify internal temperature or food safety.',
        ),
      );
}

class CookingChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final CookingMessageKind kind;
  final DateTime createdAt;
  final String? imagePath;
  final CookingVisionResult? visionResult;

  const CookingChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.kind,
    required this.createdAt,
    this.imagePath,
    this.visionResult,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'isUser': isUser,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'imagePath': imagePath,
  };

  factory CookingChatMessage.fromJson(Map<String, dynamic> json) =>
      CookingChatMessage(
        id: _text(json['id'], DateTime.now().microsecondsSinceEpoch.toString()),
        text: _text(json['text'], ''),
        isUser: json['isUser'] == true,
        kind: CookingMessageKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => CookingMessageKind.text,
        ),
        createdAt:
            DateTime.tryParse(_text(json['createdAt'], '')) ?? DateTime.now(),
        imagePath: json['imagePath']?.toString(),
      );
}

String _text(Object? value, String fallback) {
  final result = value?.toString().trim() ?? '';
  return result.isEmpty ? fallback : result;
}

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];
