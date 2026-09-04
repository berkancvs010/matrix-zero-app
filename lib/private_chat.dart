part of 'main.dart';

class PrivateChatScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final Map<String, dynamic>? pendingFileNotification;

  const PrivateChatScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
    this.pendingFileNotification,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

Future<void> _showPrivacyIntroDialog(BuildContext context) async {
  if (!context.mounted) return;

  final theme = ThemeController.instance.data;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: theme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ZeroLog Gizlilik',
                style: TextStyle(
                  color: theme.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _privacyInfoItem(
                theme,
                Icons.visibility_off_outlined,
                'Mesajlar kalıcı değildir',
                'Her mesaj, kendi gönderim zamanından itibaren 24 saat sonra otomatik olarak imha edilir.',
              ),
              const SizedBox(height: 16),
              _privacyInfoItem(
                theme,
                Icons.lock_outline_rounded,
                'Şifreli iletişim',
                'Mesajlaşma ve dosya aktarımı şifreli bağlantılar üzerinden gerçekleştirilir.',
              ),
              const SizedBox(height: 16),
              _privacyInfoItem(
                theme,
                Icons.devices_outlined,
                'Dosya transferi cihazlar arasında',
                'Dosya içeriği sunucuda depolanmaz. Transfer cihazlar arasında gerçekleştirilir.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.primary,
              foregroundColor: theme.background,
            ),
            onPressed: () async {
              await ZeroLogPrivacyIntro.markShown();

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Anladım'),
          ),
        ],
      );
    },
  );
}

Widget _privacyInfoItem(
  ZeroLogThemeData theme,
  IconData icon,
  String title,
  String body,
) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: theme.primary, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: theme.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: TextStyle(
                color: theme.text.withValues(alpha: 0.58),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final FocusNode _messageFocusNode = FocusNode();

  final TextEditingController _controller = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  // Özel sohbet mesajları ve dosya transfer kayıtları 24 saat sonra
  // aktif sohbet ekranından ve local cache'den temizlenir.
  Timer? _messageExpiryTimer;
  File? _lastOutgoingFile;
  String _lastOutgoingFileName = '';
  bool _connected = true;
  bool _autoAcceptIncomingFiles = true;
  final Map<String, Future<Uint8List?>> _fileThumbnailCache = {};

  Future<void> _loadFileTransferPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoAcceptIncomingFiles =
          prefs.getBool('zerolog.notifications.auto_accept_files') ?? true;
    });
  }

  Future<void> _showIncomingFileOffer({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
  }) async {
    if (!mounted) return;

    final theme = ThemeController.instance.data;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final sizeMb = fileSize / (1024 * 1024);

        return AlertDialog(
          backgroundColor: theme.surface,
          title: const Text('Gelen dosya'),
          content: Text(
            '$sender size bir dosya gönderiyor.\n\n'
            'Dosya: $fileName\n'
            'Boyut: ${sizeMb.toStringAsFixed(2)} MB',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Reddet'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Kabul et'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (accepted != true) {
      await _fileTransfer.rejectIncoming(transferId);
      return;
    }

    await _fileTransfer.acceptIncoming(transferId);
  }

  late final FileTransfer _fileTransfer;

  Future<void> _openPendingFileNotification() async {
    final data = widget.pendingFileNotification;

    if (!mounted || data == null) return;

    final transferId = (data['fileId'] ?? '').toString().trim();
    final fileName = (data['fileName'] ?? 'Dosya').toString().trim();
    final sender = (data['from'] ?? '').toString().trim();

    final rawFileSize = data['fileSize'];
    final fileSize = rawFileSize is num
        ? rawFileSize.toInt()
        : int.tryParse(rawFileSize?.toString() ?? '') ?? 0;

    if (transferId.isEmpty ||
        fileName.isEmpty ||
        sender.isEmpty ||
        fileSize <= 0) {
      return;
    }

    // Normal socket event'i uygulama açıldıktan sonra zaten geldiyse
    // ikinci kez dialog açma.
    if (_fileTransfer.currentTransferId != transferId) {
      final prepared = await _fileTransfer.prepareIncomingFromNotification(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        sender: sender,
      );

      if (!prepared || !mounted) return;
    }

    _upsertFileMessage(
      transferId: transferId,
      sender: sender,
      fileName: fileName,
      fileSize: fileSize,
      transferBytes: 0,
      status: 'incoming',
    );

    // Auto-accept açıkken bu bildirim zaten native background service
    // tarafından yönetiliyor. UI isolate ikinci bir ACCEPT gönderirse
    // arka plandaki transfer ile yarışabilir ve sohbet kaydının UI'a
    // taşınmasını bozabilir. Sohbet geçmişi/normal signaling tek kaynak
    // olarak kullanılmalı.
    if (!_autoAcceptIncomingFiles) {
      await _showIncomingFileOffer(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        sender: sender,
      );
    }
  }

  String get _historyCacheKey {
    final me = widget.myNick.trim().toLowerCase();
    final peer = widget.targetNick.trim().toLowerCase();
    return 'zerolog.private_history.$me.$peer';
  }

  void _upsertFileMessage({
    required String transferId,
    required String sender,
    required String fileName,
    required int fileSize,
    required int transferBytes,
    required String status,
    String? localPath,
  }) {
    if (!mounted || transferId.isEmpty) return;

    final index = _messages.indexWhere(
      (message) => message.isFile && message.fileId == transferId,
    );

    final existing = index >= 0 ? _messages[index] : null;

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = existing != null && existing.expiresAt > 0
        ? existing.expiresAt
        : now + const Duration(hours: 24).inMilliseconds;

    final message = ChatMessage(
      id: transferId,
      sender: sender,
      text: fileName.isEmpty ? 'Dosya' : fileName,
      clientMessageId: transferId,
      status: status,
      timestamp: existing?.timestamp ?? now,
      isFile: true,
      fileId: transferId,
      fileName: fileName.isEmpty ? (existing?.fileName ?? 'Dosya') : fileName,
      fileSize: fileSize > 0 ? fileSize : (existing?.fileSize ?? 0),
      transferBytes: transferBytes,
      expiresAt: expiresAt,
      localPath: localPath != null && localPath.isNotEmpty
          ? localPath
          : (existing?.localPath ?? ''),
    );

    setState(() {
      if (index >= 0) {
        _messages[index] = message;
      } else {
        _messages.add(message);
      }
    });

    // Dosya aktarımı sırasında onProgress her 16 KB parçada gelebilir.
    // Her parçayı SharedPreferences'a yazmak gereksiz I/O oluşturur.
    // Cache'i yalnızca anlamlı durum geçişlerinde güncelle.
    const cacheStatuses = {
      'waiting',
      'connecting',
      'completed',
      'failed',
      'rejected',
      'incoming',
      'accepting',
    };

    if (cacheStatuses.contains(status)) {
      unawaited(_saveHistoryCache());
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _updateFileMessageStatus(String transferId, String status, {String? localPath}) {
    if (!mounted || transferId.isEmpty) return;

    final index = _messages.indexWhere(
      (message) => message.isFile && message.fileId == transferId,
    );

    if (index < 0) return;

    final current = _messages[index];

    setState(() {
      _messages[index] = current.copyWith(
        status: status,
        transferBytes: status == 'completed'
            ? current.fileSize
            : current.transferBytes,
        localPath: localPath != null && localPath.isNotEmpty
            ? localPath
            : current.localPath,
      );
    });

    unawaited(_saveHistoryCache());
  }

  int _expiresAtFromMap(Map<String, dynamic> map) {
    final rawExpiresAt = map['expiresAt'];
    final explicit = rawExpiresAt is num
        ? rawExpiresAt.toInt()
        : int.tryParse(rawExpiresAt?.toString() ?? '') ?? 0;

    if (explicit > 0) return explicit;

    final rawTs = map['ts'];
    final ts = rawTs is num
        ? rawTs.toInt()
        : int.tryParse(rawTs?.toString() ?? '') ?? 0;

    if (ts > 0) {
      return ts + const Duration(hours: 24).inMilliseconds;
    }

    return DateTime.now().millisecondsSinceEpoch +
        const Duration(hours: 24).inMilliseconds;
  }

  bool _purgeExpiredLocalMessages() {
    final before = _messages.length;
    final now = DateTime.now().millisecondsSinceEpoch;

    _messages.removeWhere(
      (message) => message.expiresAt > 0 && message.expiresAt <= now,
    );

    return _messages.length != before;
  }

  void _removeExpiredMessages() {
    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredFiles = _messages
        .where((message) =>
            message.isFile &&
            message.expiresAt > 0 &&
            message.expiresAt <= now &&
            message.sender.toLowerCase() != widget.myNick.toLowerCase())
        .map((message) => message.fileId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final removed = _purgeExpiredLocalMessages();

    if (expiredFiles.isNotEmpty) {
      for (final fileId in expiredFiles) {
        _fileThumbnailCache.remove(fileId);
        unawaited(const MethodChannel('zerolog/system').invokeMethod<bool>(
          'deleteReceivedFile',
          <String, dynamic>{'fileId': fileId},
        ));
      }
    }

    if (!removed) return;

    setState(() {});
    unawaited(_saveHistoryCache());
  }

  Map<String, dynamic> _messageToJson(ChatMessage message) {
    return {
      'id': message.id,
      'sender': message.sender,
      'text': message.text,
      'clientMessageId': message.clientMessageId,
      'status': message.status,
      'timestamp': message.timestamp,
      'isFile': message.isFile,
      'fileId': message.fileId,
      'fileName': message.fileName,
      'fileSize': message.fileSize,
      'transferBytes': message.transferBytes,
      'expiresAt': message.expiresAt,
      'localPath': message.localPath,
    };
  }

  ChatMessage? _messageFromJson(dynamic value) {
    if (value is! Map) return null;

    final map = Map<String, dynamic>.from(value);
    final id = (map['id'] ?? '').toString();
    final text = (map['text'] ?? '').toString();
    final rawExpiresAt = map['expiresAt'];
    final expiresAt = rawExpiresAt is num
        ? rawExpiresAt.toInt()
        : int.tryParse(rawExpiresAt?.toString() ?? '') ?? 0;

    if (id.isEmpty ||
        text.isEmpty ||
        expiresAt <= 0 ||
        expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      return null;
    }

    return ChatMessage(
      id: id,
      sender: (map['sender'] ?? '').toString(),
      text: text,
      clientMessageId: (map['clientMessageId'] ?? '').toString(),
      status: (map['status'] ?? 'stored').toString(),
      timestamp: map['timestamp'] is num
          ? (map['timestamp'] as num).toInt()
          : int.tryParse((map['timestamp'] ?? '').toString()) ??
                (map['ts'] is num
                    ? (map['ts'] as num).toInt()
                    : int.tryParse((map['ts'] ?? '').toString()) ?? 0),
      isFile: map['isFile'] == true,
      fileId: (map['fileId'] ?? '').toString(),
      fileName: (map['fileName'] ?? '').toString(),
      fileSize: map['fileSize'] is num
          ? (map['fileSize'] as num).toInt()
          : int.tryParse((map['fileSize'] ?? '').toString()) ?? 0,
      transferBytes: map['transferBytes'] is num
          ? (map['transferBytes'] as num).toInt()
          : int.tryParse((map['transferBytes'] ?? '').toString()) ?? 0,
      expiresAt: expiresAt,
      localPath: (map['localPath'] ?? '').toString(),
    );
  }

  // Cache yazılarını sıraya al.
  // ACK -> delivered -> read gibi hızlı ardışık event'lerde
  // eski bir snapshot'ın yeni status'ü ezmesini önler.
  Future<void> _cacheWriteQueue = Future<void>.value();

  Future<void> _saveHistoryCache() {
    _purgeExpiredLocalMessages();
    // Snapshot'ı kuyruğa girmeden önce al.
    // Böylece her yazma çağrısı o andaki mesaj durumunu korur.
    final encoded = jsonEncode(_messages.map(_messageToJson).toList());

    _cacheWriteQueue = _cacheWriteQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_historyCacheKey, encoded);
      } catch (_) {
        // Cache yazma hatası mesajlaşmayı etkilememeli.
      }
    });

    return _cacheWriteQueue;
  }

  Future<bool> _loadHistoryCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyCacheKey);

    if (raw == null || raw.isEmpty) return false;

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) return false;

      final cached = <ChatMessage>[];

      for (final item in decoded) {
        final message = _messageFromJson(item);

        if (message == null) continue;
        if (cached.any((m) => m.id == message.id)) continue;

        cached.add(message);
      }

      if (cached.isEmpty) {
        await prefs.remove(_historyCacheKey);
        return false;
      }
      if (!mounted) return false;

      setState(() {
        _messages
          ..clear()
          ..addAll(cached);
      });

      // Expired entries are removed from the persisted snapshot immediately.
      await _saveHistoryCache();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;

        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });

      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();

    _connected = WsClient.instance.connected;

    _messageExpiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _removeExpiredMessages(),
    );

    WsClient.instance.setActivePrivateChat(widget.targetNick);
    _loadFileTransferPreference();

    _fileTransfer = FileTransfer.shared(
      ws: WsClient.instance,
      me: widget.myNick,
      peer: widget.targetNick,
      turnUsername: WsClient.instance.turnUsername,
      turnPassword: WsClient.instance.turnPassword,
      turnUrls: WsClient.instance.turnUrls,
    );

    _fileTransfer.bindCallbacks(
      onProgress:
          ({
            required String transferId,
            required int sentBytes,
            required int totalBytes,
            required String status,
          }) {
            if (!mounted) return;

            final existingIndex = _messages.indexWhere(
              (message) => message.isFile && message.fileId == transferId,
            );

            final existing = existingIndex >= 0
                ? _messages[existingIndex]
                : null;

            final fileName = existing?.fileName.isNotEmpty == true
                ? existing!.fileName
                : (_fileTransfer.currentFileName ?? 'Dosya');

            final sender = existing?.sender.isNotEmpty == true
                ? existing!.sender
                : widget.myNick;

            _upsertFileMessage(
              transferId: transferId,
              sender: sender,
              fileName: fileName,
              fileSize: totalBytes,
              transferBytes: sentBytes,
              status: status,
              // Transfer callback sendFile() tamamlanmadan gelebilir.
              // Gönderici önizlemesini transferId döndükten sonraya
              // bırakma; seçilen yerel dosya hemen kullanılabilir.
              localPath: existing?.localPath.isNotEmpty == true
                  ? existing!.localPath
                  : (sender.toLowerCase() == widget.myNick.toLowerCase()
                      ? _lastOutgoingFile?.path
                      : null),
            );
          },
      onIncomingOffer:
          ({
            required String transferId,
            required String fileName,
            required int fileSize,
            required String sender,
          }) {
            if (!mounted) return;

            _upsertFileMessage(
              transferId: transferId,
              sender: sender,
              fileName: fileName,
              fileSize: fileSize,
              transferBytes: 0,
              status: 'incoming',
            );

            if (_autoAcceptIncomingFiles) {
              unawaited(_fileTransfer.acceptIncoming(transferId));
            } else {
              unawaited(
                _showIncomingFileOffer(
                  transferId: transferId,
                  fileName: fileName,
                  fileSize: fileSize,
                  sender: sender,
                ),
              );
            }
          },
      onIncomingStatus: ({
        required String transferId,
        required String status,
        String? localUri,
      }) {
        if (!mounted) return;

        _updateFileMessageStatus(transferId, status, localPath: localUri);

      },
    );

    // TURN bilgileri hazır olmadan PeerConnection oluşturma.
    unawaited(() async {
      final client = WsClient.instance;

      try {
        if (!client.turnCredentialsReady.isCompleted) {
          await client.turnCredentialsReady.future.timeout(
            const Duration(seconds: 10),
          );
        }
      } catch (_) {
        // TURN alınamazsa STUN fallback kullanılacak.
      }

      if (!mounted) return;

      _fileTransfer.turnUsername = client.turnUsername;
      _fileTransfer.turnPassword = client.turnPassword;
      _fileTransfer.turnUrls = List<String>.from(client.turnUrls);

      await _fileTransfer.initialize();
    }());

    _subscription = WsClient.instance.events.listen(_handleEvent);

    _loadHistoryCache().then((_) {
      if (!mounted) return;

      // Cache yalnızca sohbetin anında görünmesi içindir.
      // Sunucudan güncel geçmiş her zaman alınır.
      // Böylece offline/başka cihaz kaynaklı yeni mesajlar kaçırılmaz.
      WsClient.instance.send({
        'type': 'privateHistory',
        'peer': widget.targetNick,
      });
    });

    _applyAutoFocusPreference();

    // İlk özel sohbet açılışında ZeroLog'un gizlilik ve
    // 24 saatlik mesaj imha politikasını açıkça göster.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (await ZeroLogPrivacyIntro.shouldShow() && mounted) {
        await _showPrivacyIntroDialog(context);
      }
    });

    if (widget.pendingFileNotification != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        unawaited(_openPendingFileNotification());
      });
    }
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

    final eventType = data['type'];
    if (eventType == 'connectionLost' || eventType == 'reconnecting') {
      setState(() => _connected = false);
      return;
    }
    if (eventType == 'connectionRestored' || eventType == 'registered') {
      setState(() => _connected = true);
    }

    if (data['type'] == 'notificationSettings') {
      final value = data['autoAcceptFileTransfers'];
      if (value is bool) {
        if (mounted) {
          setState(() => _autoAcceptIncomingFiles = value);
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(
          'zerolog.notifications.auto_accept_files',
          value,
        );
      }
      return;
    }

    if (data['type'] == 'appStateChanged') {
      final state = (data['state'] ?? '').toString().trim().toLowerCase();

      if (state == 'foreground' &&
          WsClient.instance.activePrivateChatPeer?.trim().toLowerCase() ==
              widget.targetNick.trim().toLowerCase()) {
        await _markVisibleIncomingMessagesRead();
      }

      return;
    }

    if (data['type'] == 'profileCacheUpdated' ||
        data['type'] == 'profileUpdated') {
      final username = (data['username'] ?? '').toString().trim();

      if (username.isNotEmpty &&
          username.toLowerCase() == widget.targetNick.toLowerCase()) {
        setState(() {});
      }

      return;
    }

    // Sohbet socket kopukken açıldıysa privateHistory isteği queue'ya
    // alınmaz. Bağlantı yeniden kurulduğunda güncel geçmişi tekrar iste.
    if (data['type'] == 'connectionRestored' || data['type'] == 'registered') {
      WsClient.instance.send({
        'type': 'privateHistory',
        'peer': widget.targetNick,
      });
      return;
    }

    if (data['type'] == 'privateHistory') {
      final peer = (data['peer'] ?? data['with'] ?? data['target'] ?? '')
          .toString();

      if (peer.isNotEmpty &&
          peer.toLowerCase() != widget.targetNick.toLowerCase()) {
        return;
      }

      final list = data['messages'];

      if (list is List) {
        final historyMessages = <ChatMessage>[];
        final unreadHistoryMessages = <Map<String, dynamic>>[];

        for (final item in list) {
          if (item is! Map) continue;

          final map = Map<String, dynamic>.from(item);

          final messageId = (map['id'] ?? '').toString();
          final clientMessageId = (map['clientMessageId'] ?? '').toString();
          final sender = (map['sender'] ?? map['from'] ?? '').toString();

          final isFile =
              map['isFile'] == true ||
              map['type']?.toString() == 'privateFileMessage';

          final fileId = (map['fileId'] ?? '').toString();
          final fileName = (map['fileName'] ?? '').toString();

          final rawFileSize = map['fileSize'];
          final fileSize = rawFileSize is num
              ? rawFileSize.toInt()
              : int.tryParse(rawFileSize?.toString() ?? '') ?? 0;

          final text = isFile
              ? (fileName.isNotEmpty ? fileName : 'Dosya')
              : (map['text'] ?? '').toString();

          final expiresAt = _expiresAtFromMap(map);

          if (text.isEmpty ||
              expiresAt <= DateTime.now().millisecondsSinceEpoch) {
            continue;
          }

          if (sender.isNotEmpty &&
              sender.toLowerCase() != widget.myNick.toLowerCase() &&
              map['read'] != true) {
            unreadHistoryMessages.add(map);
          }

          final messageStatus =
              sender.toLowerCase() == widget.myNick.toLowerCase()
              ? ((map['read'] == true)
                    ? 'read'
                    : (map['delivered'] == true)
                    ? 'delivered'
                    : 'stored')
              : ((map['read'] == true) ? 'read' : 'delivered');

          final message = ChatMessage(
            id:
                (messageId.isNotEmpty
                        ? messageId
                        : (clientMessageId.isNotEmpty
                              ? clientMessageId
                              : 'private-legacy-${map['ts'] ?? ''}-$sender-${map['to'] ?? ''}-$text'))
                    .toString(),
            sender: sender,
            text: text,
            clientMessageId: clientMessageId,
            status: isFile
                ? ((map['transferStatus'] ?? 'stored').toString())
                : messageStatus,
            timestamp: map['ts'] is num
                ? (map['ts'] as num).toInt()
                : int.tryParse((map['ts'] ?? '').toString()) ?? 0,
            isFile: isFile,
            fileId: isFile ? (fileId.isNotEmpty ? fileId : messageId) : '',
            fileName: isFile ? (fileName.isNotEmpty ? fileName : 'Dosya') : '',
            fileSize: isFile ? fileSize : 0,
            transferBytes: isFile
                ? (() {
                    final rawTransferBytes = map['transferBytes'];
                    final parsedTransferBytes = rawTransferBytes is num
                        ? rawTransferBytes.toInt()
                        : int.tryParse(
                              rawTransferBytes?.toString() ?? '',
                            ) ??
                            0;
                    return parsedTransferBytes > 0
                        ? parsedTransferBytes
                        : ((map['transferStatus'] ?? '').toString() ==
                                  'completed'
                              ? fileSize
                              : 0);
                  })()
                : 0,
            expiresAt: expiresAt,
            localPath: '',
          );

          final existingIndex = _messages.indexWhere(
            (localMessage) =>
                (clientMessageId.isNotEmpty &&
                    localMessage.clientMessageId.isNotEmpty &&
                    localMessage.clientMessageId == clientMessageId) ||
                (messageId.isNotEmpty && localMessage.id == messageId),
          );

          if (existingIndex >= 0) {
            // Server geçmişi authoritative kaynaktır.
            // Özellikle sending -> stored -> delivered -> read geçişlerini
            // cache'deki eski durumun üzerine uygula.
            historyMessages.add(
              message.copyWith(
                id: message.id,
                clientMessageId: message.clientMessageId,
                status: message.status,
                timestamp: message.timestamp > 0
                    ? message.timestamp
                    : _messages[existingIndex].timestamp,
                localPath: message.localPath.isNotEmpty
                    ? message.localPath
                    : _messages[existingIndex].localPath,
              ),
            );
          } else {
            historyMessages.add(message);
          }
        }

        if (mounted) {
          final serverKeys = <String>{
            for (final message in historyMessages)
              if (message.clientMessageId.isNotEmpty)
                'c:${message.clientMessageId}'
              else if (message.id.isNotEmpty)
                'i:${message.id}',
          };

          final localSending = _messages.where((message) {
            if (message.status != 'sending') return false;
            if (message.expiresAt <= DateTime.now().millisecondsSinceEpoch) {
              return false;
            }

            if (message.clientMessageId.isNotEmpty &&
                serverKeys.contains('c:${message.clientMessageId}')) {
              return false;
            }

            if (message.id.isNotEmpty &&
                serverKeys.contains('i:${message.id}')) {
              return false;
            }

            return true;
          }).toList();

          setState(() {
            _messages
              ..clear()
              ..addAll(historyMessages)
              ..addAll(localSending);
          });
        }

        if (mounted) {
          await _saveHistoryCache();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) return;

            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          });
        }

        // Geçmiş yalnızca aktif sohbet gerçekten görünür durumdaysa
        // okundu kabul edilir. Arka planda/reconnect sırasında gelen
        // history mesajları yeşil tik'e yükseltilmez.
        final canMarkHistoryRead =
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
            WsClient.instance.appIsForeground &&
            WsClient.instance.activePrivateChatPeer?.trim().toLowerCase() ==
                widget.targetNick.trim().toLowerCase();

        if (canMarkHistoryRead) {
          for (final map in unreadHistoryMessages) {
          final sender = (map['sender'] ?? map['from'] ?? '').toString();

          final messageId = (map['id'] ?? '').toString();
          final clientMessageId = (map['clientMessageId'] ?? '').toString();

          if (sender.isEmpty ||
              (messageId.isEmpty && clientMessageId.isEmpty)) {
            continue;
          }

            WsClient.instance.send({
              'type': 'messageRead',
              'from': sender,
              'messageId': messageId,
              'clientMessageId': clientMessageId,
            });
          }
        }

        if (historyMessages.isNotEmpty && mounted) {
          await _saveHistoryCache();

          // Geçmiş mesajları animasyonla tek tek akıtma.
          // Liste doğrudan son mesaja konumlanır.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) return;

            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          });
        }
      }
    }

    if (data['type'] == 'privateMessageStatusSync') {
      final list = data['messages'];

      if (list is List) {
        var changed = false;

        for (final item in list) {
          if (item is! Map) continue;

          final map = Map<String, dynamic>.from(item);
          final messageId = (map['messageId'] ?? '').toString();
          final clientMessageId = (map['clientMessageId'] ?? '').toString();

          if (messageId.isEmpty && clientMessageId.isEmpty) continue;

          var targetIndex = -1;
          for (var i = 0; i < _messages.length; i++) {
            final message = _messages[i];
            if ((clientMessageId.isNotEmpty &&
                    message.clientMessageId == clientMessageId) ||
                (messageId.isNotEmpty && message.id == messageId)) {
              targetIndex = i;
              break;
            }
          }

          if (targetIndex < 0) continue;

          final current = _messages[targetIndex];
          final nextStatus = map['read'] == true
              ? 'read'
              : map['delivered'] == true
                  ? 'delivered'
                  : 'stored';

          const rank = <String, int>{
            'sending': 0,
            'stored': 1,
            'delivered': 2,
            'read': 3,
          };

          if ((rank[nextStatus] ?? 0) <= (rank[current.status] ?? 0)) {
            continue;
          }

          _messages[targetIndex] = current.copyWith(
            id: messageId.isNotEmpty ? messageId : current.id,
            clientMessageId: clientMessageId.isNotEmpty
                ? clientMessageId
                : current.clientMessageId,
            status: nextStatus,
          );
          changed = true;
        }

        if (changed && mounted) {
          setState(() {});
          await _saveHistoryCache();
        }
      }

      return;
    }

    if (data['type'] == 'messageAck') {
      final clientMessageId = (data['clientMessageId'] ?? '').toString();

      if (clientMessageId.isNotEmpty) {
        final messageId = (data['messageId'] ?? '').toString();

        setState(() {
          for (var i = 0; i < _messages.length; i++) {
            final message = _messages[i];

            if (message.clientMessageId == clientMessageId) {
              _messages[i] = message.copyWith(
                id: messageId.isNotEmpty ? messageId : message.id,
                status: 'stored',
              );
              break;
            }
          }
        });

        await _saveHistoryCache();
      }

      return;
    }

    if (data['type'] == 'messageDelivered') {
      final messageId = (data['messageId'] ?? '').toString();

      final clientMessageId = (data['clientMessageId'] ?? '').toString();

      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];

          final matches =
              (clientMessageId.isNotEmpty &&
                  message.clientMessageId == clientMessageId) ||
              (messageId.isNotEmpty && message.id == messageId);

          if (matches) {
            _messages[i] = message.copyWith(
              id: messageId.isNotEmpty ? messageId : message.id,
              clientMessageId: clientMessageId.isNotEmpty
                  ? clientMessageId
                  : message.clientMessageId,
              status: 'delivered',
            );
            break;
          }
        }
      });

      await _saveHistoryCache();

      return;
    }

    if (data['type'] == 'messageRead') {
      final messageId = (data['messageId'] ?? '').toString();
      final clientMessageId = (data['clientMessageId'] ?? '').toString();

      if (messageId.isEmpty && clientMessageId.isEmpty) {
        return;
      }

      if (!mounted) return;

      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final message = _messages[i];

          final matches =
              (clientMessageId.isNotEmpty &&
                  message.clientMessageId == clientMessageId) ||
              (messageId.isNotEmpty && message.id == messageId);

          if (matches) {
            _messages[i] = message.copyWith(
              id: messageId.isNotEmpty ? messageId : message.id,
              clientMessageId: clientMessageId.isNotEmpty
                  ? clientMessageId
                  : message.clientMessageId,
              status: 'read',
            );
            break;
          }
        }
      });

      await _saveHistoryCache();

      return;
    }

    if (data['type'] == 'pendingPrivateMessages') {
      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            final sender = (map['sender'] ?? map['from'] ?? '').toString();
            final target = (map['to'] ?? map['target'] ?? '').toString();

            if (sender.toLowerCase() != widget.targetNick.toLowerCase() ||
                target.toLowerCase() != widget.myNick.toLowerCase()) {
              continue;
            }

            final messageId = (map['id'] ?? '').toString();
            final clientMessageId = (map['clientMessageId'] ?? '').toString();

            _addMessage(
              ChatMessage(
                id:
                    (messageId.isNotEmpty
                            ? messageId
                            : (clientMessageId.isNotEmpty
                                  ? clientMessageId
                                  : 'pending-${map['ts'] ?? ''}-$sender-${map['text'] ?? ''}'))
                        .toString(),
                sender: sender,
                text: (map['text'] ?? '').toString(),
                clientMessageId: clientMessageId,
                status: map['read'] == true ? 'read' : 'delivered',
                timestamp: map['ts'] is num
                    ? (map['ts'] as num).toInt()
                    : int.tryParse((map['ts'] ?? '').toString()) ?? 0,
                expiresAt: _expiresAtFromMap(map),
              ),
            );

            // Mesaj sohbet ekranında gerçekten görünür durumdaysa okunur.
            WsClient.instance.send({
              'type': 'messageDelivered',
              'from': sender,
              'messageId': messageId,
              'clientMessageId': clientMessageId,
            });

            if (WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
              WsClient.instance.send({
                'type': 'messageRead',
                'from': sender,
                'messageId': messageId,
                'clientMessageId': clientMessageId,
              });
            }
          }
        }
      }

      return;
    }

    if (data['type'] == 'privateFileMessage') {
      final sender = (data['sender'] ?? data['from'] ?? '').toString();
      final target = (data['to'] ?? data['target'] ?? '').toString();

      final isFromPeer =
          sender.toLowerCase() == widget.targetNick.toLowerCase();
      final isFromMe = sender.toLowerCase() == widget.myNick.toLowerCase();

      final validPeerTarget =
          target.isEmpty || target.toLowerCase() == widget.myNick.toLowerCase();

      final validSelfTarget =
          target.isEmpty ||
          target.toLowerCase() == widget.targetNick.toLowerCase();

      final validTarget = isFromMe ? validSelfTarget : validPeerTarget;

      if ((!isFromPeer && !isFromMe) || !validTarget) {
        return;
      }

      final messageId = (data['id'] ?? '').toString();
      final clientMessageId = (data['clientMessageId'] ?? '').toString();
      final fileId = (data['fileId'] ?? '').toString();
      final fileName = (data['fileName'] ?? '').toString();
      final rawFileSize = data['fileSize'];
      final fileSize = rawFileSize is num
          ? rawFileSize.toInt()
          : int.tryParse(rawFileSize?.toString() ?? '') ?? 0;

      if (fileId.isEmpty || fileName.isEmpty || fileSize <= 0) {
        return;
      }

      final existingIndex = _messages.indexWhere(
        (message) => message.isFile && message.fileId == fileId,
      );

      final existing = existingIndex >= 0 ? _messages[existingIndex] : null;

      final incomingTransferStatus =
          (data['transferStatus'] ?? '').toString().trim();

      final transferStatus = existing?.status == 'completed' &&
              incomingTransferStatus == 'stored'
          ? 'completed'
          : incomingTransferStatus.isNotEmpty
              ? incomingTransferStatus
              : (existing == null ||
                      existing.status == 'stored' ||
                      existing.status == 'read' ||
                      existing.status == 'delivered')
                  ? 'stored'
                  : existing.status;

      final transferBytes = existing?.transferBytes ?? 0;

      _upsertFileMessage(
        transferId: fileId,
        sender: sender,
        fileName: fileName,
        fileSize: fileSize,
        transferBytes: transferBytes,
        status: transferStatus,
      );

      // Socket mesajı bu cihaza ulaştıysa teslim edilmiş sayılır.
      if (isFromPeer) {
        WsClient.instance.send({
          'type': 'messageDelivered',
          'from': sender,
          'messageId': messageId,
          'clientMessageId': clientMessageId,
        });

        if (WsClient.instance.appIsForeground) {
          WsClient.instance.send({
            'type': 'messageRead',
            'from': sender,
            'messageId': messageId,
            'clientMessageId': clientMessageId,
          });
        }
      }

      return;
    }

    if (data['type'] == 'privateMessage') {
      final sender = (data['sender'] ?? data['from'] ?? '').toString();

      final target = (data['to'] ?? data['target'] ?? '').toString();

      final isFromPeer =
          sender.toLowerCase() == widget.targetNick.toLowerCase();

      final isFromMe = sender.toLowerCase() == widget.myNick.toLowerCase();

      final validPeerTarget =
          target.isEmpty || target.toLowerCase() == widget.myNick.toLowerCase();

      final validSelfTarget =
          target.isEmpty ||
          target.toLowerCase() == widget.targetNick.toLowerCase();

      final validTarget = isFromMe ? validSelfTarget : validPeerTarget;

      if ((!isFromPeer && !isFromMe) || !validTarget) {
        return;
      }

      final clientMessageId = (data['clientMessageId'] ?? '').toString();
      final incomingMessageId = (data['id'] ?? '').toString();
      final incomingIsPeer =
          sender.toLowerCase() == widget.targetNick.toLowerCase();

      _addMessage(
        ChatMessage(
          id:
              (data['id'] ??
                      (clientMessageId.isNotEmpty
                          ? clientMessageId
                          : 'private-live-${data['ts'] ?? ''}-$sender-$target-${data['text'] ?? ''}'))
                  .toString(),
          sender: sender,
          text: (data['text'] ?? '').toString(),
          clientMessageId: clientMessageId,
          status: incomingIsPeer ? 'delivered' : 'stored',
          timestamp: data['ts'] is num
              ? (data['ts'] as num).toInt()
              : int.tryParse((data['ts'] ?? '').toString()) ??
                    DateTime.now().millisecondsSinceEpoch,
          expiresAt: _expiresAtFromMap(data),
        ),
      );

      if (incomingIsPeer) {
        WsClient.instance.send({
          'type': 'messageDelivered',
          'from': sender,
          'messageId': incomingMessageId,
          'clientMessageId': clientMessageId,
        });

        if (WsClient.instance.appIsForeground) {
          WsClient.instance.send({
            'type': 'messageRead',
            'from': sender,
            'messageId': incomingMessageId,
            'clientMessageId': clientMessageId,
          });
        }
      }
    }
  }

  Future<void> _markVisibleIncomingMessagesRead() async {
    if (!mounted || !WsClient.instance.appIsForeground) return;

    final peer = widget.targetNick.trim().toLowerCase();
    if (WsClient.instance.activePrivateChatPeer?.trim().toLowerCase() != peer) {
      return;
    }

    final unread = _messages.where((message) {
      return message.sender.trim().toLowerCase() == peer &&
          message.status != 'read' &&
          (message.id.isNotEmpty || message.clientMessageId.isNotEmpty);
    }).toList();

    for (final message in unread) {
      WsClient.instance.send({
        'type': 'messageRead',
        'from': widget.targetNick,
        'messageId': message.id,
        'clientMessageId': message.clientMessageId,
      });
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any(
      (m) =>
          m.id == message.id ||
          (message.clientMessageId.isNotEmpty &&
              m.clientMessageId.isNotEmpty &&
              m.clientMessageId == message.clientMessageId),
    );

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    unawaited(_saveHistoryCache());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );

      // Klavye açıkken Android\'in yeniden layout hesaplamasını bekle.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!_scrollController.hasClients) return;

        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      });
    });
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final clientMessageId =
        '${DateTime.now().microsecondsSinceEpoch}-${widget.myNick}-${widget.targetNick}';

    // Mesajı sunucudan geri gelmesini beklemeden gönderen ekranda göster.
    // clientMessageId sayesinde daha sonra gelen messageAck aynı mesajı günceller.
    _addMessage(
      ChatMessage(
        id: clientMessageId,
        sender: widget.myNick,
        text: text,
        clientMessageId: clientMessageId,
        status: 'sending',
        timestamp: timestamp,
        expiresAt: timestamp + const Duration(hours: 24).inMilliseconds,
      ),
    );

    WsClient.instance.send({
      'type': 'privateMessage',
      'to': widget.targetNick,
      'text': text,
      'clientMessageId': clientMessageId,
    });

    _controller.clear();
  }

  Future<void> _sendFile() async {
    try {
      final files = await FilePicker.pickFiles();
      if (files.isEmpty) return;
      final picked = files.single;
      final path = picked.path;
      if (path == null || path.isEmpty) return;

      _lastOutgoingFile = File(path);
      _lastOutgoingFileName = picked.name;

      final transferId = await _fileTransfer.sendFile(
        sourceFile: _lastOutgoingFile,
        sourceFileName: _lastOutgoingFileName,
      );

      if (transferId == null || transferId.isEmpty) return;
      _rememberLocalTransferPath(transferId, path);

      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya gönderilemedi: $e')),
      );
    }
  }

  Future<String> _persistOutgoingMedia(
    String sourcePath,
    String transferId,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final targetDirectory = Directory(
        '${directory.path}/ZeroLog/sent_media',
      );

      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;

      final extension = sourcePath.contains('.')
          ? '.${sourcePath.split('.').last.toLowerCase()}'
          : '.jpg';
      final target = File('${targetDirectory.path}/$transferId$extension');

      await source.copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('[FILE_TRANSFER] persistent media copy failed: $e');
      return sourcePath;
    }
  }

  Future<void> _sendPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();

      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 88,
      );

      if (picked == null) return;

      _lastOutgoingFile = File(picked.path);
      _lastOutgoingFileName = picked.name;

      final transferId = await _fileTransfer.sendFile(
        sourceFile: _lastOutgoingFile,
        sourceFileName: _lastOutgoingFileName,
      );

      if (transferId == null || transferId.isEmpty) return;

      final persistentPath = await _persistOutgoingMedia(
        picked.path,
        transferId,
      );
      _rememberLocalTransferPath(transferId, persistentPath);

      if (!mounted) return;

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotoğraf gönderilemedi: $e')),
      );
    }
  }

  void _rememberLocalTransferPath(String transferId, String path) {
    if (transferId.isEmpty || path.isEmpty || !mounted) return;
    final index = _messages.indexWhere(
      (message) => message.isFile && message.fileId == transferId,
    );
    if (index < 0) return;
    setState(() {
      _messages[index] = _messages[index].copyWith(localPath: path);
    });
    unawaited(_saveHistoryCache());
  }

  Future<void> _retryFailedTransfer(ChatMessage message) async {
    final file = _lastOutgoingFile;
    if (file == null || !file.existsSync()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaynak dosya artık cihazda bulunmuyor.')),
      );
      return;
    }

    try {
      final transferId = await _fileTransfer.sendFile(
        sourceFile: file,
        sourceFileName: _lastOutgoingFileName.isNotEmpty
            ? _lastOutgoingFileName
            : message.fileName,
      );
      if (transferId == null || transferId.isEmpty || !mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dosya yeniden gönderilemedi: $e')),
      );
    }
  }

  @override
  void dispose() {
    if (WsClient.instance.activePrivateChatPeer?.toLowerCase() ==
        widget.targetNick.toLowerCase()) {
      WsClient.instance.setActivePrivateChat(null);
    }

    _subscription.cancel();
    _messageExpiryTimer?.cancel();
    _messageExpiryTimer = null;
    _fileTransfer.unbindCallbacks();
    _controller.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    final online = WsClient.instance.onlineUsers.any(
      (u) => u.toLowerCase() == widget.targetNick.toLowerCase(),
    );

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        titleSpacing: 2,
        toolbarHeight: 68,
        title: Row(
          children: [
            GestureDetector(
              onTap: () => unawaited(_openChatProfile()),
              child: _chatAvatar(widget.targetNick, online: online),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.targetNick,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: online ? theme.primary : theme.text.withValues(alpha: 0.25), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(
                        online ? 'Çevrimiçi' : 'Çevrimdışı',
                        style: TextStyle(
                          color: online ? theme.primary : theme.text.withValues(alpha: 0.42),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sesli ara',
            onPressed: () {
              final callId =
                  '${DateTime.now().millisecondsSinceEpoch}-${widget.myNick}';

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    myNick: widget.myNick,
                    targetNick: widget.targetNick,
                    outgoing: true,
                    callId: callId,
                  ),
                ),
              );
            },
            icon: Icon(Icons.call_rounded, color: theme.primary),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: _connected ? 0 : 34,
            width: double.infinity,
            color: theme.text.withValues(alpha: 0.08),
            child: _connected
                ? const SizedBox.shrink()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 15, color: theme.text.withValues(alpha: 0.60)),
                      const SizedBox(width: 7),
                      Text(
                        'Çevrimdışı • Mesajlar yeniden bağlanınca senkronize edilecek',
                        style: TextStyle(color: theme.text.withValues(alpha: 0.62), fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? _emptyPrivateChat(theme)
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
                          widget.myNick.toLowerCase();

                      return _modernMessageBubble(
                        message,
                        mine: mine,
                        theme: theme,
                      );
                    },
                  ),
          ),
          MessageInput(
            controller: _controller,
            onSend: _send,
            onSendFile: _sendFile,
            onSendPhoto: (source) => _sendPhoto(source),
            focusNode: _messageFocusNode,
          ),
        ],
      ),
    );
  }

  Widget _chatAvatar(String name, {required bool online}) {
    final theme = ThemeController.instance.data;
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();

    final profile = WsClient.instance.profileFor(name);
    final type = (profile?['type'] ?? 'avatar').toString();

    final photoData = (profile?['photoData'] ?? '').toString().trim();

    if (WsClient.instance.connected &&
        (profile == null || (type == 'photo' && photoData.isEmpty))) {
      WsClient.instance.requestProfile(name);
    }

    Widget avatar;

    if (type == 'photo' && photoData.isNotEmpty) {
      try {
        avatar = ClipOval(
          child: SizedBox(
            width: 42,
            height: 42,
            child: Image.memory(
              base64Decode(photoData),
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
          ),
        );
      } catch (_) {
        avatar = _fallbackChatAvatar(theme, letter);
      }
    } else {
      avatar = _fallbackChatAvatar(theme, letter);
    }

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        avatar,
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: online ? theme.primary : theme.text.withValues(alpha: 0.22),
            shape: BoxShape.circle,
            border: Border.all(color: theme.background, width: 2),
          ),
        ),
      ],
    );
  }

  Widget _fallbackChatAvatar(ZeroLogThemeData theme, String letter) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: theme.primary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Future<void> _openChatProfile() async {
    final name = widget.targetNick.trim();

    if (name.isEmpty) return;

    var profile = WsClient.instance.profileFor(name);
    var needsPhoto = profile != null &&
        (profile['type'] ?? 'avatar').toString() == 'photo' &&
        (profile['photoData'] ?? '').toString().trim().isEmpty;

    if ((profile == null || needsPhoto) && WsClient.instance.connected) {
      WsClient.instance.requestProfile(name);

      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 150));

        if (!mounted) return;

        profile = WsClient.instance.profileFor(name);
        needsPhoto = profile != null &&
            (profile['type'] ?? 'avatar').toString() == 'photo' &&
            (profile['photoData'] ?? '').toString().trim().isEmpty;

        if (profile != null && !needsPhoto) break;
      }
    }

    if (!mounted) return;

    final theme = ThemeController.instance.data;
    final type = (profile?['type'] ?? 'avatar').toString();
    final about = (profile?['about'] ?? '').toString().trim();
    final photoData = (profile?['photoData'] ?? '').toString().trim();

    ImageProvider? image;

    if (type == 'photo' && photoData.isNotEmpty) {
      try {
        image = MemoryImage(base64Decode(photoData));
      } catch (_) {}
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        Widget avatar;

        if (image != null) {
          avatar = ClipOval(
            child: SizedBox(
              width: 110,
              height: 110,
              child: Image(image: image, fit: BoxFit.cover),
            ),
          );
        } else {
          avatar = CircleAvatar(
            radius: 55,
            backgroundColor: theme.primary.withValues(alpha: 0.14),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: theme.primary,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        }

        final online = WsClient.instance.onlineUsers.any(
          (u) => u.toLowerCase() == name.toLowerCase(),
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(height: 14),
                Text(
                  name,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  online ? 'Çevrimiçi' : 'Çevrimdışı',
                  style: TextStyle(
                    color: online
                        ? theme.primary
                        : theme.text.withValues(alpha: 0.45),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (about.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                    decoration: BoxDecoration(
                      color: theme.background.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      about,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.78),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Kapat'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _emptyPrivateChat(ZeroLogThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 34,
                color: theme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Özel sohbet',
              style: TextStyle(
                color: theme.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${widget.targetNick} ile güvenli şekilde mesajlaşmaya başlayın.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text.withValues(alpha: 0.48),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _messageStatusLabel(String status) {
    switch (status) {
      case 'sending':
        return 'Gönderiliyor';
      case 'stored':
        return 'Gönderildi';
      case 'delivered':
        return 'Teslim edildi';
      case 'read':
        return 'Okundu';
      default:
        return '';
    }
  }

  String _formatMessageTime(int timestamp) {
    if (timestamp <= 0) return '';

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '$hh:$mm';
    }

    final dd = date.day.toString().padLeft(2, '0');
    final mo = date.month.toString().padLeft(2, '0');
    return '$dd.$mo $hh:$mm';
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return 'Boyut bilinmiyor';

    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }

  String _fileStatusText(ChatMessage message) {
    switch (message.status) {
      case 'waiting':
        return 'Gönderim bekliyor';
      case 'connecting':
        return 'Bağlanıyor…';
      case 'transferring':
        final incoming =
            message.sender.toLowerCase() != widget.myNick.toLowerCase();
        if (message.fileSize > 0) {
          final percent = ((message.transferBytes / message.fileSize) * 100)
              .clamp(0, 100)
              .round();
          return incoming ? 'Alınıyor • %$percent' : 'Gönderiliyor • %$percent';
        }
        return incoming ? 'Alınıyor…' : 'Gönderiliyor…';
      case 'incoming':
        return 'Gelen dosya';
      case 'accepting':
        return 'Kabul ediliyor…';
      case 'completed':
        return 'Gönderildi';
      case 'failed':
        return 'Transfer başarısız';
      case 'rejected':
        return 'Reddedildi';
      default:
        return message.status;
    }
  }

  bool _isImageFile(ChatMessage message) {
    final lower = message.fileName.toLowerCase();
    return RegExp(r'\.(jpg|jpeg|png|webp|gif|heic)$').hasMatch(lower);
  }

  Future<void> _openImageMessage(ChatMessage message) async {
    if (!message.isFile || message.fileId.isEmpty) return;

    try {
      Uint8List? bytes;

      // Received files are indexed natively by fileId. This survives
      // history reloads even when the Flutter cache has no localPath.
      bytes = await const MethodChannel('zerolog/system')
          .invokeMethod<Uint8List>(
        'readReceivedImageBytes',
        <String, dynamic>{'fileId': message.fileId},
      );

      if ((bytes == null || bytes.isEmpty) && message.localPath.isNotEmpty &&
          !message.localPath.startsWith('content://')) {
        final file = File(message.localPath);
        if (file.existsSync()) bytes = await file.readAsBytes();
      }

      if (!mounted) return;

      if (bytes == null || bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf açılamadı. Dosya cihazda bulunamıyor.')),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.94),
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(bytes!, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fotoğraf açılamadı: $e')),
      );
    }
  }

  Future<void> _openReceivedFile(ChatMessage message) async {
    if (!message.isFile || message.fileId.isEmpty) return;

    try {
      final result = await const MethodChannel('zerolog/system')
          .invokeMethod<bool>('openReceivedFile', <String, dynamic>{
            'fileId': message.fileId,
            'fileName': message.fileName,
          });

      if (result != true && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Dosya açılamadı.')));
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya açılamadı: $e')));
    }
  }

  Future<Uint8List?> _loadReceivedThumbnail(String fileId) {
    return _fileThumbnailCache.putIfAbsent(fileId, () async {
      try {
        // Full image read is already verified by the working viewer.
        // Reuse that path for the inline preview.
        return await const MethodChannel('zerolog/system')
            .invokeMethod<Uint8List>(
          'readReceivedImageBytes',
          <String, dynamic>{'fileId': fileId},
        );
      } catch (_) {
        return null;
      }
    });
  }

  Widget _receivedImagePreview(
    ChatMessage message,
    ZeroLogThemeData theme,
  ) {
    return FutureBuilder<Uint8List?>(
      future: _loadReceivedThumbnail(message.fileId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.image_outlined, color: theme.primary, size: 34),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: 190),
        );
      },
    );
  }

  Widget _fileMessageContent(
    ChatMessage message, {
    required bool mine,
    required ZeroLogThemeData theme,
  }) {
    final status = _fileStatusText(message);
    final lower = message.fileName.toLowerCase();
    final isImage = RegExp(r'\.(jpg|jpeg|png|webp|gif|heic)$').hasMatch(lower);
    final isReceivedUri = message.localPath.startsWith('content://');
    final canUseNativeImagePreview =
        !mine &&
        isImage &&
        message.fileId.isNotEmpty &&
        (message.status == 'completed' ||
            message.status == 'stored' ||
            isReceivedUri);
    final hasLocalImage = isImage &&
        (isReceivedUri ||
            canUseNativeImagePreview ||
            (message.localPath.isNotEmpty &&
                !message.localPath.startsWith('content://') &&
                File(message.localPath).existsSync()));
    final displayedTransferBytes =
        (message.status == 'completed' || message.status == 'stored') &&
                message.fileSize > 0
            ? message.fileSize
            : message.transferBytes;

    final progress = message.fileSize > 0
        ? (displayedTransferBytes / message.fileSize).clamp(0.0, 1.0)
        : 0.0;

    final canOpenLocalImage =
        isImage &&
        message.localPath.isNotEmpty &&
        !isReceivedUri &&
        File(message.localPath).existsSync();

    final canOpenReceived =
        message.isFile &&
        message.fileId.isNotEmpty &&
        (message.status == 'completed' ||
            message.status == 'stored' ||
            isReceivedUri ||
            canOpenLocalImage);

    final canOpen = canOpenReceived;

    return InkWell(
      onTap: canOpen
          ? () => unawaited(
                _isImageFile(message)
                    ? _openImageMessage(message)
                    : _openReceivedFile(message),
              )
          : null,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: theme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: theme.primary.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasLocalImage) ...[
              if (isReceivedUri || canUseNativeImagePreview)
                _receivedImagePreview(message, theme)
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: AspectRatio(
                    aspectRatio: 1.25,
                    child: Image.file(File(message.localPath), fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(height: 9),
            ],
            Row(
              children: [
                if (!hasLocalImage)
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      isImage ? Icons.image_rounded : Icons.insert_drive_file_rounded,
                      color: theme.primary,
                      size: 23,
                    ),
                  ),
                if (!hasLocalImage) const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName.isEmpty ? message.text : message.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_formatFileSize(message.transferBytes)} / ${_formatFileSize(message.fileSize)}',
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.50),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (message.status == 'failed' && mine)
                  IconButton(
                    tooltip: 'Tekrar dene',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_retryFailedTransfer(message)),
                    icon: Icon(Icons.refresh_rounded, color: theme.primary),
                  ),
              ],
            ),
            if (message.status == 'transferring' || message.status == 'connecting') ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: message.status == 'connecting' ? null : progress,
                  minHeight: 5,
                  backgroundColor: theme.text.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 5),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: message.status == 'failed'
                          ? theme.text.withValues(alpha: 0.55)
                          : theme.primary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (message.fileSize > 0 &&
                    (message.status == 'transferring' || message.status == 'completed'))
                  Text(
                    '%${(progress * 100).round()}',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.50),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMessageOptions(ChatMessage message) async {
    if (!mounted) return;
    final theme = ThemeController.instance.data;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.copy_rounded, color: theme.primary),
                  title: Text('Kopyala', style: TextStyle(color: theme.text)),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.text));
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mesaj panoya kopyalandı.')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: theme.text.withValues(alpha: 0.65)),
                  title: Text('Bu cihazdan kaldır', style: TextStyle(color: theme.text)),
                  subtitle: Text('Karşı taraftaki kayıt silinmez.', style: TextStyle(color: theme.text.withValues(alpha: 0.42), fontSize: 11)),
                  onTap: () {
                    setState(() => _messages.removeWhere((item) => item.id == message.id));
                    unawaited(_saveHistoryCache());
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modernMessageBubble(
    ChatMessage message, {
    required bool mine,
    required ZeroLogThemeData theme,
  }) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => unawaited(_showMessageOptions(message)),
        child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
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
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
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
            if (message.isFile)
              _fileMessageContent(message, mine: mine, theme: theme)
            else
              Text(
                message.text,
                style: TextStyle(color: theme.text, fontSize: 14, height: 1.35),
              ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final messageTime = _formatMessageTime(message.timestamp);

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (messageTime.isNotEmpty)
                      Text(
                        messageTime,
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.42),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (mine &&
                        message.status.isNotEmpty &&
                        !message.isFile) ...[
                      const SizedBox(width: 5),
                      Text(
                        _messageStatusLabel(message.status),
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.42),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: _messageStatusLabel(message.status),
                        child: Icon(
                          message.status == 'sending'
                              ? Icons.schedule_rounded
                              : (message.status == 'read' ||
                                      message.status == 'delivered')
                                  ? Icons.done_all_rounded
                                  : Icons.done_rounded,
                          size: 14,
                          color: message.status == 'sending'
                              ? Colors.grey
                              : message.status == 'stored'
                              ? Colors.grey
                              : message.status == 'delivered'
                              ? Colors.amber
                              : message.status == 'read'
                              ? Colors.greenAccent
                              : theme.text.withValues(alpha: 0.48),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ============================================================
// WEBRTC CALL
// ============================================================
