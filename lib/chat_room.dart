part of 'main.dart';

class ChatRoomScreen extends StatefulWidget {
  final String nickname;
  final String roomName;

  const ChatRoomScreen({
    super.key,
    required this.nickname,
    required this.roomName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();

  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];
  Timer? _messageExpiryTimer;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.joinRoom(widget.roomName);
    _messageExpiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _removeExpiredMessages(),
    );
    _applyAutoFocusPreference();
  }

  Future<void> _applyAutoFocusPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final autoFocus = prefs.getBool('zerolog.chat.auto_focus') ?? true;

    if (!autoFocus || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageFocusNode.requestFocus();
    });
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
    if (!mounted) return;

    if (data['type'] == 'roomHistory' && data['room'] == widget.roomName) {
      final history = data['messages'];

      if (history is List) {
        for (final item in history) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                id:
                    (map['id'] ??
                            'legacy-${widget.roomName}-${map['ts'] ?? ''}-${map['from'] ?? map['sender'] ?? ''}-${map['text'] ?? ''}')
                        .toString(),
                sender: (map['sender'] ?? map['from'] ?? '').toString(),
                text: (map['text'] ?? '').toString(),
                timestamp: map['ts'] is num
                    ? (map['ts'] as num).toInt()
                    : int.tryParse((map['ts'] ?? '').toString()) ??
                        DateTime.now().millisecondsSinceEpoch,
                expiresAt: _roomMessageExpiresAt(map),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'roomMessage' && data['room'] == widget.roomName) {
      _addMessage(
        ChatMessage(
          id:
              (data['id'] ??
                      'live-${data['ts'] ?? ''}-${data['from'] ?? data['sender'] ?? ''}-${data['text'] ?? ''}')
                  .toString(),
          sender: (data['sender'] ?? data['from'] ?? '').toString(),
          text: (data['text'] ?? '').toString(),
          timestamp: data['ts'] is num
              ? (data['ts'] as num).toInt()
              : int.tryParse((data['ts'] ?? '').toString()) ?? DateTime.now().millisecondsSinceEpoch,
          expiresAt: _roomMessageExpiresAt(data),
        ),
      );
    }
  }

  int _roomMessageExpiresAt(Map<String, dynamic> map) {
    final explicit = map['expiresAt'];
    final value = explicit is num
        ? explicit.toInt()
        : int.tryParse(explicit?.toString() ?? '') ?? 0;
    if (value > 0) return value;

    final rawTs = map['ts'];
    final ts = rawTs is num
        ? rawTs.toInt()
        : int.tryParse(rawTs?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch;
    return ts + const Duration(hours: 24).inMilliseconds;
  }

  void _removeExpiredMessages() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = _messages.length;
    _messages.removeWhere((message) =>
        message.expiresAt > 0 && message.expiresAt <= now);
    if (_messages.length != before) setState(() {});
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;
    if (message.expiresAt > 0 &&
        message.expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      return;
    }

    final exists = _messages.any((m) => m.id == message.id);

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();

      // Android klavyeyi açtıktan sonra viewInsets/layout yeniden hesaplanır.
      // Bu ikinci scroll, son mesajın klavye altında kalmasını engeller.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        _scrollToBottom();
      });
    });
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    _scrollController.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    WsClient.instance.send({
      'type': 'roomMessage',
      'room': widget.roomName,
      'text': text,
    });

    _controller.clear();
  }

  @override
  void dispose() {
    WsClient.instance.leaveRoom(widget.roomName);
    _subscription.cancel();
    _messageExpiryTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        titleSpacing: 2,
        toolbarHeight: 68,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tag_rounded, color: theme.primary, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Topluluk odası',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.42),
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
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 46,
                            color: theme.text.withValues(alpha: 0.24),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Oda henüz boş',
                            style: TextStyle(
                              color: theme.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'İlk mesajı siz gönderin.',
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.45),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    itemCount: _messages.length,
                    itemBuilder: (_, index) {
                      final message = _messages[index];
                      final mine =
                          message.sender.toLowerCase() ==
                          widget.nickname.toLowerCase();

                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 330),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: mine ? theme.bubbleMine : theme.bubbleOther,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(mine ? 18 : 5),
                              bottomRight: Radius.circular(mine ? 5 : 18),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!mine) ...[
                                Text(
                                  message.sender,
                                  style: TextStyle(
                                    color: theme.primary,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                              ],
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          MessageInput(
            controller: _controller,
            onSend: _send,
            showCamera: false,
            focusNode: _messageFocusNode,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PRIVATE CHAT
// ============================================================
