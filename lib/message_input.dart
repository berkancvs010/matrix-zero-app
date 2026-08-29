part of 'main.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Future<void> Function()? onSendFile;
  final Future<void> Function(ImageSource source)? onSendPhoto;
  final bool showCamera;

  final FocusNode? focusNode;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.onSendFile,
    this.onSendPhoto,
    this.showCamera = true,
    this.focusNode,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  bool _enterToSend = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _enterToSend = prefs.getBool('zerolog.chat.enter_to_send') ?? true;
    });
  }

  void _handleSubmitted(String value) {
    if (!_enterToSend) return;
    if (value.trim().isEmpty) return;

    widget.onSend();
  }

  Future<void> _openAttachmentMenu() async {
    final theme = ThemeController.instance.data;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onSendFile != null)
                  ListTile(
                    leading: Icon(
                      Icons.attach_file_rounded,
                      color: theme.primary,
                    ),
                    title: const Text('Dosya'),
                    subtitle: const Text('Dosya seç ve gönder'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.onSendFile!();
                    },
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ek seçenekler',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.onSendPhoto != null)
                  ListTile(
                    leading: Icon(
                      Icons.photo_library_outlined,
                      color: theme.primary,
                    ),
                    title: const Text('Galeri'),
                    subtitle: const Text('Galeriden fotoğraf seç ve gönder'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.onSendPhoto?.call(ImageSource.gallery);
                    },
                  ),
                if (widget.onSendPhoto != null)
                  ListTile(
                    leading: Icon(
                      Icons.camera_alt_outlined,
                      color: theme.primary,
                    ),
                    title: const Text('Kamera'),
                    subtitle: const Text('Kamera ile fotoğraf çek ve gönder'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await widget.onSendPhoto?.call(ImageSource.camera);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    Icons.emoji_emotions_outlined,
                    color: theme.primary,
                  ),
                  title: const Text('Emoji'),
                  subtitle: const Text('Mesaja emoji ekle'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openEmojiPicker();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openEmojiPicker() async {
    final theme = ThemeController.instance.data;

    const emojis = [
      '😀',
      '😂',
      '😍',
      '🥰',
      '😎',
      '🤔',
      '😢',
      '😡',
      '👍',
      '👎',
      '❤️',
      '🔥',
      '🎉',
      '👏',
      '🙏',
      '💯',
      '🚀',
      '🔒',
      '😊',
      '😉',
      '😄',
      '😁',
      '🤣',
      '😇',
    ];

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: emojis.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemBuilder: (_, index) {
                final emoji = emojis[index];

                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final value = widget.controller.text;
                    final selection = widget.controller.selection;

                    final start = selection.start >= 0
                        ? selection.start
                        : value.length;
                    final end = selection.end >= 0
                        ? selection.end
                        : value.length;

                    final newText = value.replaceRange(start, end, emoji);

                    widget.controller.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(
                        offset: start + emoji.length,
                      ),
                    );

                    Navigator.pop(sheetContext);

                    widget.focusNode?.requestFocus();
                  },
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 27)),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: theme.text.withValues(alpha: 0.055),
                  ),
                ),
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  minLines: 1,
                  maxLines: 5,
                  onSubmitted: _handleSubmitted,
                  textInputAction: _enterToSend
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Mesaj yaz…',
                    hintStyle: TextStyle(
                      color: theme.text.withValues(alpha: 0.38),
                      fontSize: 13.5,
                    ),
                    prefixIcon: IconButton(
                      tooltip: 'Ek seçenekler',
                      onPressed: _openAttachmentMenu,
                      icon: Icon(
                        Icons.add_rounded,
                        color: theme.text.withValues(alpha: 0.42),
                      ),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(0, 12, 14, 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                tooltip: 'Gönder',
                onPressed: widget.onSend,
                icon: Icon(
                  Icons.arrow_upward_rounded,
                  color: theme.background,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODEL
// ============================================================
