# Interactive Multimodal AI Chef

## Existing architecture

Before this enhancement, the cooking experience had three separate concerns:

- `ChatbotScreen` handled pantry questions through `ChefChatService` and sent meal-planning requests to `MealPlanningApiService`.
- The FastAPI backend kept Gemini credentials server-side and exposed `/chef-chat`, meal planning, and existing vision endpoints.
- `GuidedCookingScreen` displayed one recipe instruction at a time with a local countdown timer. Its current step, timer, and conversation were not persisted, and it had no cooking-context chat, photo verification, speech input, or spoken output.
- Recipes were stored as `RecipeRecommendationModel` objects with string instructions. Favorites, preferences, and completed-meal history were persisted by `RecipeExperienceProvider` with `SharedPreferences`.

This separation was retained: recipe discovery still uses the existing Chef Chat and verified meal-plan path, and selecting **Cook this recipe** still opens the guided-cooking route.

## Implemented multimodal architecture

The guided-cooking route now creates one recipe-scoped `CookingSessionProvider`. It is the single state owner for:

- current, completed, and remaining steps;
- detailed structured guidance for the current instruction;
- text, voice-transcribed, and image-related conversation messages;
- prior adjustments and configured dietary restrictions;
- timer deadline, pause/resume state, and elapsed state;
- speech listening, speech playback, and interruption state; and
- retryable network and vision errors.

The provider persists the active session under the recipe ID. Reopening the same recipe restores progress, messages, adjustments, selected-image paths, timer state, and voice language. Only explicit controls or recognized commands advance a step.

`CookingAssistantService` is the sole Flutter networking adapter for the three cooking endpoints:

| Endpoint | Purpose |
| --- | --- |
| `POST /step-explanation` | Expands an existing recipe instruction into structured action, heat, pace, estimated duration, technique, sensory cues, precautions, and completion criteria. |
| `POST /cooking-step-chat` | Answers a text or transcribed voice question with the current recipe, step, recent bounded history, adjustments, and dietary context. |
| `POST /validate-cooking-step` | Sends an optimized camera/gallery image with the current step and question for visible-progress analysis. |

Gemini remains behind FastAPI, so no API credential is exposed to Flutter. Conversation history is bounded to the ten most recent turns before upload. Captured images are resized to at most 1600 × 1600 and compressed to 78% quality before submission.

## Safety behavior

- Durations are always presented as estimates; visible, texture, aroma, and thermometer checks take priority.
- Visual analysis has an explicit `image_sufficient` result. Blurry, dark, obscured, or unavailable analysis can return `unable_to_assess`.
- If Gemini is unavailable, the backend returns zero confidence and states that it did not assess the photo. It never fabricates visible observations.
- Every visual result states that a photo cannot verify internal temperature, complete doneness, or food safety.
- Step chat is instructed not to advance without an explicit user request and to recommend a thermometer when safety depends on internal temperature.

## User experience

The existing guided-cooking screen now includes:

- a visible current-step progress bar and revisitable completed-step markers;
- an essential action card plus expandable professional technique and doneness cues;
- heat, pace, estimated-duration, timer, precaution, and completion information;
- camera and gallery actions with preview and editable question before upload;
- inline image and visual-feedback messages;
- typed step-aware chat;
- English and Urdu speech-recognition selection, with mixed-language handling where the device recognizer supports it;
- spoken AI responses with microphone barge-in;
- voice commands for next step, repeat/explain again, pause, resume, and time remaining;
- previous, repeat, pause/resume, explicit next-step confirmation, and finish controls; and
- text fallback plus retry/error banners when speech or backend services are unavailable.

## Modified and added files

### Flutter

- `lib/screens/cooking/guided_cooking_screen.dart` — integrated multimodal cooking UI.
- `lib/providers/cooking_session_provider.dart` — unified session state, persistence, commands, timers, STT, TTS, and interruption handling.
- `lib/services/cooking_assistant_service.dart` — detailed-step, step-chat, and multipart vision API client.
- `lib/models/cooking_session.dart` — structured step, message, and vision-result models.
- `pubspec.yaml` / `pubspec.lock` — `speech_to_text` and `flutter_tts` dependencies.
- Android, iOS, and macOS permission files — microphone, speech-recognition, and Android TTS service discovery.

### Backend

- `backend/app/models/vision_schemas.py` — structured step, bounded context, uncertainty, and safety fields.
- `backend/app/services/gemini_service.py` — detailed step generation, context-aware cooking chat, and safe visual verification.
- `backend/app/main.py` — three cooking endpoints and unified context forwarding.

### Tests

- `test/cooking_assistant_service_test.dart`
- `test/cooking_session_provider_test.dart`
- `backend/tests/test_cooking_step_endpoints.py`

## Dependencies, APIs, and permissions

- Existing `image_picker` handles camera and gallery images.
- `speech_to_text` provides device speech recognition. Availability and supported Urdu/mixed-language behavior depend on the OS speech service.
- `flutter_tts` provides spoken responses through installed system voices. If an Urdu voice is unavailable, the written response remains available.
- Android requires `RECORD_AUDIO` and a TTS service query. iOS requires microphone and speech-recognition usage descriptions. macOS requires the same descriptions plus the audio-input sandbox entitlement.
- FastAPI requires `python-multipart` for image upload and continues to read Gemini credentials from backend environment configuration.

## Logical rollout phases

1. **Structured guidance and state** — deploy the schema/endpoints and session provider; validate session restoration and explicit advancement.
2. **Vision verification** — enable photo controls and monitor insufficient-image rate, latency, upload size, and model errors.
3. **Conversational voice** — enable STT/TTS, permission education, device-language coverage, interruption, and audio cleanup.
4. **Production hardening** — add authenticated server-side session sync if cross-device resume is required, push/local timer notifications for background operation, observability, retention rules for cooking images, and streaming/realtime audio only if tap-to-converse latency proves insufficient.

The current implementation deliberately uses conversational device STT + backend LLM + device TTS because it fits the existing HTTP architecture and keeps credentials secure. A realtime streaming transport can replace the voice adapter later without changing the cooking-session model or UI contract.
