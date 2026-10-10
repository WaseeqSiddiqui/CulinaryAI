import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/chef_name_formatter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pantry_provider.dart';
import '../../services/chef_chat_service.dart';

class ChatbotScreen extends StatefulWidget {
  final String? initialQuestion;

  const ChatbotScreen({super.key, this.initialQuestion});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isReplying = false;

  static const _suggestions = [
    'What can I cook?',
    'What is low stock?',
    'What do I have in my pantry?',
    'How do I cook tomato pasta?',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initial = widget.initialQuestion?.trim() ?? '';
      if (initial.isNotEmpty) _send(initial);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? value]) async {
    final question = (value ?? _controller.text).trim();
    if (question.isEmpty || _isReplying) return;
    final pantryItems = context.read<PantryProvider>().allItems;

    setState(() {
      _messages.add(_ChatMessage(text: question, isUser: true));
      _controller.clear();
      _isReplying = true;
    });
    _scrollToBottom();

    await Future<void>.delayed(const Duration(milliseconds: 350));
    final answer = ChefChatService.answer(question, pantryItems);
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: answer, isUser: false));
      _isReplying = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chefName = ChefNameFormatter.fromUser(
      context.watch<AuthProvider>().currentUser,
    );
    final muted = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chef Chat'),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: () => setState(_messages.clear),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _EmptyChat(
                      chefName: chefName,
                      suggestions: _suggestions,
                      onSuggestion: _send,
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      itemCount: _messages.length + (_isReplying ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          return const _TypingBubble();
                        }
                        return _MessageBubble(message: _messages[index]);
                      },
                    ),
            ),
            if (_messages.isNotEmpty)
              SizedBox(
                height: 42,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ActionChip(
                    label: Text(_suggestions[index]),
                    onPressed: _isReplying
                        ? null
                        : () => _send(_suggestions[index]),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chefChatInput'),
                      controller: _controller,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _isReplying ? null : _send,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Ask about recipes or your pantry…',
                        hintStyle: TextStyle(color: muted),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        prefixIcon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 19,
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filled(
                    key: const Key('chefChatSend'),
                    tooltip: 'Send',
                    onPressed: _isReplying ? null : _send,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_upward_rounded),
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

class _EmptyChat extends StatelessWidget {
  final String chefName;
  final List<String> suggestions;
  final ValueChanged<String> onSuggestion;

  const _EmptyChat({
    required this.chefName,
    required this.suggestions,
    required this.onSuggestion,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.textDarkSecondary
        : AppTheme.textLightSecondary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      children: [
        Align(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primaryFlame.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.soup_kitchen_outlined,
              size: 32,
              color: AppTheme.primaryFlame,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'What can I help you cook, Chef $chefName?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Ask about your pantry, meal ideas, missing ingredients, cooking time, or step-by-step instructions.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: secondary),
        ),
        const SizedBox(height: 28),
        for (final suggestion in suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              onPressed: () => onSuggestion(suggestion),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(suggestion),
              ),
            ),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: message.isUser
              ? AppTheme.primaryFlame
              : (isDark ? AppTheme.surfaceDark2 : AppTheme.creamSurface),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isUser ? 18 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 18),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            height: 1.45,
            color: message.isUser
                ? Colors.white
                : (isDark
                      ? AppTheme.textDarkPrimary
                      : AppTheme.textLightPrimary),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.fromLTRB(8, 4, 8, 16),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );
}

class _ChatMessage {
  final String text;
  final bool isUser;

  const _ChatMessage({required this.text, required this.isUser});
}
