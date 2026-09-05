part of 'main.dart';

class MainScreen extends StatefulWidget {
  final String nickname;

  const MainScreen({super.key, required this.nickname});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  late final ProfileController _profileController;

  String? get _profilePhotoPath => _profileController.photoPath;
  String get _profilePhotoData => _profileController.photoData;
  String get _profileAbout => _profileController.about;

  String? _pendingProfilePhotoData;
  String _previousProfilePhotoData = '';
  bool _profilePhotoSaving = false;
  int _profileRevision = 0;

  Future<void> _applyRemoteOwnProfile(Map<String, dynamic> profile) async {
    await _profileController.applyRemote(profile);

    if (!mounted) return;

    setState(() {});
  }

  void _requestRemoteProfilePhoto(String username) {
    final name = username.trim();
    if (name.isEmpty || !WsClient.instance.connected) return;

    final normalized = name.toLowerCase();
    if (_profileFetchRequested.contains(normalized)) return;

    _profileFetchRequested.add(normalized);

    unawaited(() async {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!mounted || !WsClient.instance.connected) break;

        WsClient.instance.requestProfile(name);

        await Future<void>.delayed(
          Duration(milliseconds: 250 + attempt * 350),
        );

        final profile = WsClient.instance.profileFor(name);
        final type = (profile?['type'] ?? 'avatar').toString();
        final photo = (profile?['photoData'] ?? '').toString().trim();

        if (type != 'photo' || photo.isNotEmpty) {
          break;
        }
      }

      _profileFetchRequested.remove(normalized);
    }());
  }

  Future<void> _loadProfileData() async {
    await _profileController.load();

    if (!mounted) return;

    setState(() {});

    // Local cache provides an immediate preview, but the server is the
    // authoritative source. Fetch the full profile after every app start
    // so a photo cannot disappear after process/app restart.
    if (WsClient.instance.connected) {
      WsClient.instance.requestProfile(widget.nickname);
    }
  }

  Future<String?> _encodeProfilePhoto(String path) async {
    try {
      final source = File(path);
      final bytes = await source.readAsBytes();
      if (bytes.isEmpty) return null;

      const maxBase64Chars = 680000;
      final isGif = bytes.length >= 6 &&
          bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38 &&
          (bytes[4] == 0x37 || bytes[4] == 0x39) &&
          bytes[5] == 0x61;

      // Kullanıcının seçtiği GIF profil fotoğrafı olarak korunur.
      // Animated GIF'i img paketinde JPEG'e çevirmek animasyonu tek kareye
      // düşüreceğinden GIF byte'larını doğrudan base64 olarak saklıyoruz.
      // Sunucunun profil veri sınırıyla uyumlu kalmak için büyük GIF'ler
      // normal fotoğraflarla aynı üst sınırda reddedilir.
      if (isGif) {
        final encodedGif = base64Encode(bytes);
        if (encodedGif.length <= maxBase64Chars) {
          return encodedGif;
        }

        debugPrint('[PROFILE] GIF profile image is too large');
        return null;
      }

      img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      decoded = img.bakeOrientation(decoded);

      var working = decoded;
      var quality = 82;

      for (var attempt = 0; attempt < 8; attempt++) {
        if (working.width > 720 || working.height > 720) {
          working = img.copyResize(
            working,
            width: working.width >= working.height ? 720 : null,
            height: working.height > working.width ? 720 : null,
            interpolation: img.Interpolation.average,
          );
        }

        final jpg = img.encodeJpg(working, quality: quality);
        final encoded = base64Encode(jpg);
        if (encoded.length <= maxBase64Chars) return encoded;

        if (quality > 56) {
          quality -= 6;
        } else {
          final nextWidth = (working.width * 0.82).round();
          final nextHeight = (working.height * 0.82).round();
          if (nextWidth < 320 || nextHeight < 320) break;
          working = img.copyResize(
            working,
            width: nextWidth,
            height: nextHeight,
            interpolation: img.Interpolation.average,
          );
          quality = 72;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[PROFILE] photo encode failed: $e');
      return null;
    }
  }

  Future<void> _pickProfilePhoto() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (image == null) return;

    final photoData = await _encodeProfilePhoto(image.path);

    if (photoData == null || photoData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil görseli hazırlanamadı veya dosya çok büyük.')),
        );
      }
      return;
    }

    _previousProfilePhotoData = _profilePhotoData;
    _pendingProfilePhotoData = photoData;
    _profilePhotoSaving = true;
    _profileRevision++;
    await _profileController.setPhotoData(photoData);

    if (!mounted) return;

    setState(() {
      _profileController.photoPath = null;
      _profileController.photoData = photoData;
    });

    final sent = WsClient.instance.send({
      'type': 'setProfile',
      'profileType': 'photo',
      'avatarId': null,
      'photoData': photoData,
      'about': _profileAbout,
      'profileRevision': _profileRevision,
    });

    if (!sent && mounted) {
      _pendingProfilePhotoData = null;
      _profilePhotoSaving = false;
      if (_previousProfilePhotoData.isNotEmpty) {
        await _profileController.setPhotoData(_previousProfilePhotoData);
      } else {
        await _profileController.clearPhoto();
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil fotoğrafı gönderilemedi: bağlantı hazır değil.')),
      );
    }
  }

  Future<void> _takeProfilePhoto() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
    );

    if (image == null) return;

    final photoData = await _encodeProfilePhoto(image.path);

    if (photoData == null || photoData.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil görseli hazırlanamadı veya dosya çok büyük.')),
        );
      }
      return;
    }

    _previousProfilePhotoData = _profilePhotoData;
    _pendingProfilePhotoData = photoData;
    _profilePhotoSaving = true;
    _profileRevision++;
    await _profileController.setPhotoData(photoData);

    if (!mounted) return;

    setState(() {
      _profileController.photoPath = null;
      _profileController.photoData = photoData;
    });

    final sent = WsClient.instance.send({
      'type': 'setProfile',
      'profileType': 'photo',
      'avatarId': null,
      'photoData': photoData,
      'about': _profileAbout,
      'profileRevision': _profileRevision,
    });

    if (!sent && mounted) {
      _pendingProfilePhotoData = null;
      _profilePhotoSaving = false;
      if (_previousProfilePhotoData.isNotEmpty) {
        await _profileController.setPhotoData(_previousProfilePhotoData);
      } else {
        await _profileController.clearPhoto();
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil fotoğrafı gönderilemedi: bağlantı hazır değil.')),
      );
    }
  }


  Future<void> _editProfileAbout() async {
    final controller = TextEditingController(text: _profileAbout);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final theme = ThemeController.instance.data;

        return AlertDialog(
          backgroundColor: theme.surface,
          title: const Text('Hakkında'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 160,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Kendiniz hakkında kısa bir bilgi',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (result == null) return;

    await _profileController.setAbout(result);

    if (!mounted) return;

    setState(() {
      _profileController.about = result;
    });

    WsClient.instance.send({
      'type': 'setProfile',
      'profileType': _profilePhotoData.isNotEmpty ? 'photo' : 'avatar',
      'avatarId': null,
      'photoData': _profilePhotoData,
      'about': result,
    });
  }

  MemoryImage? _cachedProfileImage(
    String username,
    String photoData, {
    int revision = 0,
  }) {
    final key = username.trim().toLowerCase();
    final source = photoData.trim();

    if (key.isEmpty || source.isEmpty) return null;

    // Revision is the authoritative identity of a profile snapshot. If an
    // old server does not provide one, use a compact fingerprint instead of
    // retaining a second copy of the potentially 680 KB base64 string.
    final version = revision > 0
        ? 'r:$revision:${source.length}:${source.hashCode}'
        : 'h:${source.length}:${source.hashCode}';

    if (_profileImageVersionByUser[key] == version) {
      return _profileImageByUser[key];
    }

    try {
      final image = MemoryImage(base64Decode(source));
      _profileImageVersionByUser[key] = version;
      _profileImageByUser[key] = image;

      // Bound decoded-image memory when many users have profile photos.
      if (_profileImageByUser.length > 64) {
        final oldestKey = _profileImageByUser.keys.first;
        _profileImageByUser.remove(oldestKey);
        _profileImageVersionByUser.remove(oldestKey);
      }

      return image;
    } catch (e) {
      _profileImageVersionByUser.remove(key);
      _profileImageByUser.remove(key);
      debugPrint('[PROFILE] cached photo decode failed: $e');
      return null;
    }
  }

  MemoryImage? _cachedOwnProfileImage(String photoData) {
    final source = photoData.trim();

    if (source.isEmpty) {
      _ownProfileImage = null;
      _ownProfileImageSource = '';
      return null;
    }

    if (_ownProfileImageSource == source && _ownProfileImage != null) {
      return _ownProfileImage;
    }

    try {
      final image = MemoryImage(base64Decode(source));
      _ownProfileImageSource = source;
      _ownProfileImage = image;
      return image;
    } catch (e) {
      _ownProfileImageSource = '';
      _ownProfileImage = null;
      debugPrint('[PROFILE] own photo decode failed: $e');
      return null;
    }
  }

  Widget _profileAvatar({double radius = 25}) {
    final theme = ThemeController.instance.data;


    final ownPhotoImage = _cachedOwnProfileImage(_profilePhotoData);

    if (ownPhotoImage != null) {
      return ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Image(
            image: ownPhotoImage,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }


    final path = _profilePhotoPath;

    if (path != null && path.isNotEmpty) {
      final file = File(path);

      if (file.existsSync()) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: theme.primary.withValues(alpha: 0.14),
          backgroundImage: FileImage(file),
        );
      }
    }

    final letter = widget.nickname.trim().isEmpty
        ? '?'
        : widget.nickname.trim().substring(0, 1).toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.primary.withValues(alpha: 0.14),
      child: Text(
        letter,
        style: TextStyle(
          color: theme.primary,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.68,
        ),
      ),
    );
  }

  Future<void> _openProfilePhotoActions() async {
    if (!mounted) return;

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
                ListTile(
                  leading: Icon(Icons.photo_camera_rounded, color: theme.primary),
                  title: const Text('Kamerayla çek'),
                  subtitle: const Text('Yeni profil fotoğrafı oluştur'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _takeProfilePhoto();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.photo_library_rounded, color: theme.primary),
                  title: const Text('Galeriden seç'),
                  subtitle: const Text('Galeriden fotoğraf seç'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _pickProfilePhoto();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openProfileEditor() async {
    final theme = ThemeController.instance.data;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: theme.background,
          appBar: AppBar(
            backgroundColor: theme.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            title: const Text('Profil'),
          ),
          body: StatefulBuilder(
            builder: (pageContext, setPageState) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
              children: [
              Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          _profileAvatar(radius: 58),
                          Material(
                            color: theme.primary,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () async {
                                await _openProfilePhotoActions();
                                if (pageContext.mounted) {
                                  setPageState(() {});
                                }
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.edit_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.nickname,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _profilePhotoSaving
                           ? 'Profil fotoğrafı sunucuya kaydediliyor…'
                           : 'Profilin diğer ZeroLog kullanıcılarına böyle görünür.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.48),
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'PROFİL GÖRÜNÜMÜ',
                style: TextStyle(
                  color: theme.text.withValues(alpha: 0.42),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.photo_camera_rounded, color: theme.primary),
                      title: const Text('Kamerayla çek'),
                      subtitle: const Text('Yeni profil fotoğrafı oluştur'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await _takeProfilePhoto();
                        if (pageContext.mounted) {
                          setPageState(() {});
                        }
                      },
                    ),
                    Divider(height: 1, color: theme.text.withValues(alpha: 0.06)),
                    ListTile(
                      leading: Icon(Icons.photo_library_rounded, color: theme.primary),
                      title: const Text('Galeriden seç'),
                      subtitle: const Text('Cihazındaki bir fotoğrafı kullan'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await _pickProfilePhoto();
                        if (pageContext.mounted) {
                          setPageState(() {});
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'HAKKINDA',
                style: TextStyle(
                  color: theme.text.withValues(alpha: 0.42),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
                  leading: Icon(Icons.notes_rounded, color: theme.primary),
                  title: Text(
                    _profileAbout.trim().isEmpty
                        ? 'Hakkında bilgisi ekle'
                        : _profileAbout.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text('Karşı tarafta profilinde gösterilir'),
                  trailing: IconButton(
                    tooltip: 'Düzenle',
                    onPressed: () async {
                      await _editProfileAbout();
                      if (pageContext.mounted) {
                        setPageState(() {});
                      }
                    },
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  onTap: () async {
                    await _editProfileAbout();
                    if (pageContext.mounted) {
                      setPageState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(height: 14),
              if (_profileController.photoData.isNotEmpty ||
                  _profileController.photoPath != null)
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.text.withValues(alpha: 0.62),
                    ),
                    title: const Text('Profil görselini kaldır'),
                    subtitle: const Text('Varsayılan profil görünümüne dön'),
                    onTap: () async {
                      await _profileController.clearPhoto();
                      if (!mounted) return;

                      setState(() {
                        _profileController.photoPath = null;
                        _profileController.photoData = '';
                      });

                      WsClient.instance.send({
                        'type': 'setProfile',
                        'profileType': 'avatar',
                        'avatarId': null,
                        'photoData': '',
                        'about': _profileAbout,
                      });
                    },
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Profil fotoğrafı ve hakkında bilgisi tek bir profil kaynağından yönetilir. '
                'Değişiklikler sunucuya kaydedildikten sonra diğer cihazlara aktarılır.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.text.withValues(alpha: 0.36),
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  final Set<String> _handledCallIds = <String>{};

  // Bildirimden açılan dosya transferinin sohbet ekranına taşınan bilgileri.
  Map<String, dynamic>? _pendingFileNotification;

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<String> _onlineUsers = [];
  final List<String> _knownUsers = [];

  final Set<String> _profileFetchRequested = <String>{};

  // Keep decoded profile images stable between rebuilds. Creating a new
  // MemoryImage/Uint8List on every build can make Flutter briefly replace
  // the image, producing the visible "blink" seen during profile updates.
  final Map<String, String> _profileImageVersionByUser = <String, String>{};
  final Map<String, MemoryImage> _profileImageByUser = <String, MemoryImage>{};
  MemoryImage? _ownProfileImage;
  String _ownProfileImageSource = '';

  // WhatsApp benzeri kişi bazlı okunmamış özel mesaj sayaçları.
  // Okunmamış özel mesajları mesaj ID'si bazında tut.
  // Böylece uygulama yeniden açıldığında aynı pending mesaj ikinci kez
  // sayaçta sayılmaz.
  final Map<String, Map<String, int>> _unreadPrivateMessageIds =
      <String, Map<String, int>>{};

  static const String _unreadPrivateMessagesKey =
      'zerolog.unread_private_message_ids';

  Future<void>? _unreadLoadFuture;

  // Okunmamış sayaç kayıtlarının hızlı ardışık event'lerde
  // eski snapshot ile yeni snapshot'ı ezmesini engeller.
  Future<void> _unreadWriteQueue = Future<void>.value();

  bool _connected = false;
  bool _reconnecting = false;

  bool _presenceVisible = true;
  bool _privateMessagesEnabled = true;
  bool _messageNotificationsEnabled = true;
  bool _callNotificationsEnabled = true;
  bool _autoAcceptFileTransfers = true;

  int _selectedIndex = 0;

  final TextEditingController _contactSearchController =
      TextEditingController();

  String _contactSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _profileController = ProfileController(nickname: widget.nickname);
    _loadProfileData();
    _unreadLoadFuture = _loadUnreadPrivateMessages();

    WidgetsBinding.instance.addObserver(this);

    _connected = WsClient.instance.connected;

    _onlineUsers
      ..clear()
      ..addAll(WsClient.instance.onlineUsers);

    _knownUsers
      ..clear()
      ..addAll(WsClient.instance.knownUsers);

    _subscription = WsClient.instance.events.listen(_handleEvent);

    ZeroLogPushService.setIncomingCallHandler(
      (data) => _openIncomingCallFromNative(data),
    );
    WsClient.instance.requestPrivacySettings();
    WsClient.instance.requestNotificationSettings();

    WsClient.instance.requestPresence();
    WsClient.instance.requestUserDirectory();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ZeroLogPushService.pullPendingNativeMessage();
      await _openPendingIncomingCall();
      await _openPendingPrivateMessage();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;

    if (state == AppLifecycleState.resumed) {
      // Android may suspend the WebSocket while the app is in background.
      // Foreground state must be known by the server so calls can choose
      // WebSocket vs FCM correctly.
      WsClient.instance.updateAppState('foreground');
      WsClient.instance.onAppResumed();

      Future<void>.delayed(const Duration(milliseconds: 250), () async {
        if (!mounted) return;

        await ZeroLogPushService.pullPendingNativeMessage();
        await _openPendingIncomingCall();
        await _openPendingPrivateMessage();
      });

      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Keep the WebSocket alive if Android allows it, but mark this user
      // as background so incoming calls use native FCM/full-screen handling.
      WsClient.instance.updateAppState('background');
    }
  }

  Future<void> _autoAcceptBackgroundFileOffer(
    Map<String, dynamic> data,
  ) async {
    if (!_autoAcceptFileTransfers || !WsClient.instance.connected) return;

    final transferId = (data['transferId'] ?? '').toString().trim();
    final sender = (data['from'] ?? '').toString().trim();
    final rawSize = data['fileSize'];
    final fileSize = rawSize is num
        ? rawSize.toInt()
        : int.tryParse(rawSize?.toString() ?? '') ?? 0;

    if (transferId.isEmpty || sender.isEmpty || fileSize <= 0) return;

    // Özel sohbet ekranı transferi zaten yönetiyorsa ikinci ACCEPT gönderme.
    if (FileTransfer.active(widget.nickname, sender) != null) return;

    if (WsClient.instance.activePrivateChatPeer?.trim().toLowerCase() ==
        sender.toLowerCase()) {
      return;
    }

    final transfer = FileTransfer.shared(
      ws: WsClient.instance,
      me: widget.nickname,
      peer: sender,
      turnUsername: WsClient.instance.turnUsername,
      turnPassword: WsClient.instance.turnPassword,
      turnUrls: WsClient.instance.turnUrls,
    );

    try {
      await transfer.initialize();

      // MainScreen bu olayı yalnızca uygulama foreground'dayken görür.
      // Bu durumda native background service başlatmak yerine mevcut
      // foreground WebSocket üzerinden normal incoming state oluştur.
      await transfer.handleExternalEvent(
        Map<String, dynamic>.from(data),
      );

      if (transfer.currentTransferId != transferId) return;

      await transfer.acceptIncoming(transferId);
    } catch (e) {
      debugPrint('[FILE_TRANSFER] background auto-accept failed: $e');
    }
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
    if (!mounted) return;

    final type = data['type'];

    if (type == 'fileTransferOffer' && data['sdp'] == null) {
      unawaited(_autoAcceptBackgroundFileOffer(data));
    }

    if (type == 'privateMessage') {
      final from = (data['from'] ?? data['sender'] ?? '').toString().trim();

      if (from.isNotEmpty) {
        final messageId =
            (data['id'] ??
                    data['clientMessageId'] ??
                    'private-live-${data['ts'] ?? ''}-$from-${data['text'] ?? ''}')
                .toString();

        final rawExpiresAt = data['expiresAt'];
        final expiresAt = rawExpiresAt is num
            ? rawExpiresAt.toInt()
            : int.tryParse(rawExpiresAt?.toString() ?? '') ?? 0;

        unawaited(
          _incrementUnreadFor(from, messageId: messageId, expiresAt: expiresAt),
        );

        // Mesaj uygulamaya ulaştı ancak sohbet açık değilse teslim
        // edilmiştir. Read sinyali PrivateChatScreen'den gelecektir.
        if (from.toLowerCase() != widget.nickname.toLowerCase()) {
          WsClient.instance.send({
            'type': 'messageDelivered',
            'from': from,
            'messageId': messageId,
            'clientMessageId':
                (data['clientMessageId'] ?? '').toString(),
          });
        }
      }
    }

    if (type == 'pendingPrivateMessages') {
      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is! Map) continue;

          final map = Map<String, dynamic>.from(item);
          final sender = (map['sender'] ?? map['from'] ?? '').toString().trim();
          final messageId =
              (map['id'] ??
                      map['clientMessageId'] ??
                      'pending-${map['ts'] ?? ''}-$sender-${map['text'] ?? ''}')
                  .toString();

          final rawExpiresAt = map['expiresAt'];
          final expiresAt = rawExpiresAt is num
              ? rawExpiresAt.toInt()
              : int.tryParse(rawExpiresAt?.toString() ?? '') ?? 0;

          if (sender.isNotEmpty && messageId.isNotEmpty) {
            unawaited(
              _incrementUnreadFor(
                sender,
                messageId: messageId,
                expiresAt: expiresAt,
              ),
            );

            // Mesaj bu cihaza ulaştı fakat kullanıcı henüz sohbeti
            // açmadı. Gönderen tarafta teslim edildi çift tiki görünür;
            // okundu bilgisi sohbet gerçekten açıldığında gönderilir.
            if (sender.toLowerCase() != widget.nickname.toLowerCase()) {
              WsClient.instance.send({
                'type': 'messageDelivered',
                'from': sender,
                'messageId': map['id']?.toString() ?? '',
                'clientMessageId':
                    map['clientMessageId']?.toString() ?? '',
              });
            }
          }
        }
      }

      return;
    }

    if (type == 'privacySettings') {
      final presenceVisible = data['presenceVisible'];
      final privateMessagesEnabled = data['privateMessagesEnabled'];

      if (presenceVisible is bool || privateMessagesEnabled is bool) {
        setState(() {
          if (presenceVisible is bool) {
            _presenceVisible = presenceVisible;
          }

          if (privateMessagesEnabled is bool) {
            _privateMessagesEnabled = privateMessagesEnabled;
          }
        });
      }
    }

    if (type == 'notificationSettings') {
      final messageNotificationsEnabled = data['messageNotificationsEnabled'];
      final callNotificationsEnabled = data['callNotificationsEnabled'];
      final autoAcceptFileTransfers = data['autoAcceptFileTransfers'];

      if (messageNotificationsEnabled is bool ||
          callNotificationsEnabled is bool ||
          autoAcceptFileTransfers is bool) {
        setState(() {
          if (messageNotificationsEnabled is bool) {
            _messageNotificationsEnabled = messageNotificationsEnabled;
          }

          if (callNotificationsEnabled is bool) {
            _callNotificationsEnabled = callNotificationsEnabled;
          }

          if (autoAcceptFileTransfers is bool) {
            _autoAcceptFileTransfers = autoAcceptFileTransfers;
          }
        });

        if (autoAcceptFileTransfers is bool) {
          unawaited(
            SharedPreferences.getInstance().then(
              (prefs) => prefs.setBool(
                'zerolog.notifications.auto_accept_files',
                autoAcceptFileTransfers,
              ),
            ),
          );
        }
      }
    }

    if (type == 'accountDeleted') {
      await _profileController.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_unreadPrivateMessagesKey);

      if (!mounted) return;

      setState(() {
        _profileController.photoPath = null;
        _profileController.photoData = '';
        _profileController.about = '';
      });

      await SecureSession.clear();
      await WsClient.instance.disconnect();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const NicknameScreen()),
        (route) => false,
      );
      return;
    }

    if (type == 'registered') {
      setState(() {
        _connected = data['success'] != false;
      });
    }

    if (type == 'userDirectory') {
      final raw = data['users'];
      final profiles = data['profiles'];

      final parsedProfiles = <String, Map<String, dynamic>>{};

      if (profiles is Map) {
        for (final entry in profiles.entries) {
          if (entry.value is Map) {
            parsedProfiles[entry.key.toString()] = Map<String, dynamic>.from(
              entry.value as Map,
            );
          }
        }
      }

      if (raw is List) {
        final users =
            raw
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .where((e) => e.toLowerCase() != widget.nickname.toLowerCase())
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        setState(() {
          _knownUsers
            ..clear()
            ..addAll(users);

          for (final entry in parsedProfiles.entries) {
            WsClient.instance.cacheProfile(entry.key, entry.value);
          }

          final ownProfile = parsedProfiles.entries
              .where(
                (entry) =>
                    entry.key.toLowerCase() == widget.nickname.toLowerCase(),
              )
              .map((entry) => entry.value)
              .firstOrNull;

          if (ownProfile != null) {
            _applyRemoteOwnProfile(ownProfile);
          }
        });
      }
    }

    if (type == 'userList') {
      final raw = data['users'];
      final profiles = data['profiles'];

      final users = raw is List
          ? raw
                .map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .where((e) => e.toLowerCase() != widget.nickname.toLowerCase())
                .toSet()
                .toList()
          : <String>[];

      final parsedProfiles = <String, Map<String, dynamic>>{};

      if (profiles is Map) {
        for (final entry in profiles.entries) {
          if (entry.value is Map) {
            parsedProfiles[entry.key.toString()] = Map<String, dynamic>.from(
              entry.value as Map,
            );
          }
        }
      }

      setState(() {
        _onlineUsers
          ..clear()
          ..addAll(users);

        for (final entry in parsedProfiles.entries) {
          WsClient.instance.cacheProfile(entry.key, entry.value);
        }
        _profileFetchRequested.clear();
      });
    }

    if (type == 'profileRejected') {
      final rejectedUsername = (data['username'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (rejectedUsername.isNotEmpty) {
        _profileFetchRequested.remove(rejectedUsername);
      }

      if (rejectedUsername == widget.nickname.trim().toLowerCase() ||
          (rejectedUsername.isEmpty && _pendingProfilePhotoData != null)) {
        _pendingProfilePhotoData = null;
        _profilePhotoSaving = false;
        if (_previousProfilePhotoData.isNotEmpty) {
          await _profileController.setPhotoData(_previousProfilePhotoData);
        } else {
          await _profileController.clearPhoto();
        }
        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil fotoğrafı sunucuya kaydedilemedi.')),
          );
        }
      }
    }

    if (type == 'profile') {
      final username = (data['username'] ?? '').toString().trim();

      if (username.isNotEmpty && mounted) {
        final profile = <String, dynamic>{
          'type': (data['profileType'] ?? data['type'] ?? 'avatar').toString(),
          'avatarId': data['avatarId'],
          'about': (data['about'] ?? '').toString(),
          'photoAvailable': data['photoAvailable'] == true,
          'photoData': (data['photoData'] ?? '').toString(),
          'profileRevision': data['profileRevision'] is num
              ? (data['profileRevision'] as num).toInt()
              : int.tryParse((data['profileRevision'] ?? '').toString()) ?? 0,
        };

        if (!mounted) return;

        final incomingRevision =
            data['profileRevision'] is num
                ? (data['profileRevision'] as num).toInt()
                : int.tryParse((data['profileRevision'] ?? '').toString()) ?? 0;

        final isOwnProfile =
            username.toLowerCase() == widget.nickname.toLowerCase();

        if (isOwnProfile &&
            incomingRevision > 0 &&
            incomingRevision < _profileRevision) {
          return;
        }

        if (isOwnProfile &&
            _pendingProfilePhotoData != null &&
            (profile['photoData'] ?? '').toString().isNotEmpty &&
            profile['photoData'] != _pendingProfilePhotoData) {
          // Yalnızca gerçekten fotoğraf taşıyan ve revizyon kontrolünden
          // geçmiş bir cevap seçilen yeni fotoğrafla çelişiyorsa reddedilir.
          return;
        }

        WsClient.instance.cacheProfile(username, profile);

        setState(() {
          _profileFetchRequested.remove(username.toLowerCase());
          if (username.toLowerCase() == widget.nickname.toLowerCase() &&
              incomingRevision > 0) {
            _profileRevision = incomingRevision;
          }
        });

        final photoNeedsFetch =
            profile['photoAvailable'] == true &&
            (profile['photoData'] ?? '').toString().isEmpty;

        if (username.toLowerCase() == widget.nickname.toLowerCase() &&
            !photoNeedsFetch) {
          final pendingPhoto = _pendingProfilePhotoData;
          final remotePhoto = (profile['photoData'] ?? '').toString();

          if (pendingPhoto != null &&
              remotePhoto.isNotEmpty &&
              (profile['type'] ?? 'avatar').toString() == 'photo') {
            _pendingProfilePhotoData = null;
            _profilePhotoSaving = false;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profil fotoğrafı güncellendi.')),
              );
            }
          }

          await _applyRemoteOwnProfile(profile);
        }
      }

      return;
    }

    if (type == 'profileCacheUpdated') {
      final username = (data['username'] ?? '').toString().trim();

      if (username.isEmpty || !mounted) return;

      final profile = <String, dynamic>{
        'type': (data['profileType'] ?? data['type'] ?? 'avatar').toString(),
        'avatarId': data['avatarId'],
        'about': (data['about'] ?? '').toString(),
        'photoAvailable': data['photoAvailable'] == true,
        'photoData': (data['photoData'] ?? '').toString(),
        'profileRevision': data['profileRevision'] is num
            ? (data['profileRevision'] as num).toInt()
            : int.tryParse((data['profileRevision'] ?? '').toString()) ?? 0,
      };

      final isOwnProfile =
          username.toLowerCase() == widget.nickname.toLowerCase();

      if (profile['photoAvailable'] == true &&
          (profile['photoData'] ?? '').toString().isEmpty) {
        if (isOwnProfile) {
          WsClient.instance.requestProfile(username);
        } else if (WsClient.instance.connected) {
          _requestRemoteProfilePhoto(username);
        }
      }

      // userDirectory intentionally carries only profile metadata. Never
      // let an empty photoData field from that metadata erase a valid local
      // photo. A full profile response is required before applying a photo.
      if (isOwnProfile &&
          ((profile['type'] ?? 'avatar').toString() != 'photo' ||
              (profile['photoData'] ?? '').toString().isNotEmpty)) {
        await _applyRemoteOwnProfile(profile);
      }

      if (!mounted) return;
      setState(() {
        if (!isOwnProfile) {
          _profileFetchRequested.remove(username.toLowerCase());
        }
      });

      return;
    }

    if (type == 'profileUpdated') {
      final username = (data['username'] ?? '').toString().trim();

      if (username.isNotEmpty && mounted) {
        final profile = <String, dynamic>{
          'type': (data['profileType'] ?? 'avatar').toString(),
          'avatarId': data['avatarId'],
          'about': (data['about'] ?? '').toString(),
          'photoAvailable': data['photoAvailable'] == true,
          'photoData': (data['photoData'] ?? '').toString(),
          'profileRevision': data['profileRevision'] is num
              ? (data['profileRevision'] as num).toInt()
              : int.tryParse((data['profileRevision'] ?? '').toString()) ?? 0,
        };

        if (!mounted) return;

        final incomingRevision =
            data['profileRevision'] is num
                ? (data['profileRevision'] as num).toInt()
                : int.tryParse((data['profileRevision'] ?? '').toString()) ?? 0;

        final isOwnProfile =
            username.toLowerCase() == widget.nickname.toLowerCase();

        if (isOwnProfile &&
            incomingRevision > 0 &&
            incomingRevision < _profileRevision) {
          return;
        }

        // profileUpdated yayınında fotoğrafın kendisi bilinçli olarak
        // gönderilmez. Pending fotoğrafı bu metadata paketi yüzünden
        // reddetme; aşağıdaki getProfile isteği gerçek photoData'yı getirir.

        WsClient.instance.cacheProfile(username, profile);

        if (isOwnProfile &&
            incomingRevision > 0) {
          _profileRevision = incomingRevision;
        }

        final photoData = (profile['photoData'] ?? '').toString();

        // profileUpdated artık fotoğrafı da taşıyabilir. Fotoğraf mevcutsa
        // ayrı getProfile round-trip'i gerekmez; yalnızca metadata geldiyse
        // eski sunucularla uyumluluk için full profile isteği yap.
        if (profile['photoAvailable'] == true && photoData.isEmpty) {
          _requestRemoteProfilePhoto(username);
        }

        setState(() {
          _profileFetchRequested.remove(username.toLowerCase());
        });

        if (username.toLowerCase() == widget.nickname.toLowerCase()) {
          final pendingPhoto = _pendingProfilePhotoData;
          final remotePhoto = (profile['photoData'] ?? '').toString();

          if (pendingPhoto != null &&
              remotePhoto.isNotEmpty &&
              (profile['type'] ?? 'avatar').toString() == 'photo') {
            _pendingProfilePhotoData = null;
            _profilePhotoSaving = false;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profil fotoğrafı güncellendi.')),
            );
          }

          await _applyRemoteOwnProfile(profile);
        }
      }
    }

    if (type == 'userOnline') {
      final username = (data['username'] ?? data['nick'] ?? '')
          .toString()
          .trim();

      if (username.isNotEmpty &&
          username.toLowerCase() != widget.nickname.toLowerCase()) {
        setState(() {
          if (!_onlineUsers.any(
            (user) => user.toLowerCase() == username.toLowerCase(),
          )) {
            _onlineUsers.add(username);
          }
        });
      }
    }

    if (type == 'userOffline') {
      final username = (data['username'] ?? data['nick'] ?? '')
          .toString()
          .trim();

      if (username.isNotEmpty) {
        setState(() {
          _onlineUsers.removeWhere(
            (user) => user.toLowerCase() == username.toLowerCase(),
          );
        });
      }
    }

    if (type == 'reconnecting') {
      setState(() {
        _connected = false;
        _reconnecting = true;
      });
    }

    if (type == 'connectionLost' ||
        type == 'connectionError' ||
        type == 'connectionClosed') {
      setState(() {
        _connected = false;
        _reconnecting = true;
        _onlineUsers.clear();
      });
    }

    if (type == 'connectionRestored' || type == 'registered') {
      _profileFetchRequested.clear();
      WsClient.instance.requestUserDirectory();
      WsClient.instance.requestProfile(widget.nickname);

      setState(() {
        _connected = true;
        _reconnecting = false;
      });
    }

    if (type == 'callInvite') {
      final from = (data['from'] ?? data['caller'] ?? '').toString().trim();
      final to = (data['to'] ?? data['callee'] ?? '').toString().trim();
      final callId = (data['callId'] ?? '').toString().trim();

      if (from.isEmpty || to.isEmpty || callId.isEmpty) {
        return;
      }

      if (to.toLowerCase() != widget.nickname.toLowerCase()) {
        return;
      }

      if (_handledCallIds.contains(callId)) {
        return;
      }

      // Uygulama arka plandayken WebSocket doğrudan Navigator'a
      // dokunmamalı. FCM/full-screen intent ile yarışmasını önlemek
      // için çağrıyı ortak pending kuyruğuna bırak.
      if (_appLifecycleState != AppLifecycleState.resumed) {
        await ZeroLogPushService.storeNotificationPayload(
          jsonEncode({
            'type': 'callInvite',
            'from': from,
            'to': to,
            'callId': callId,
          }),
        );
        return;
      }

      _handledCallIds.add(callId);

      await ZeroLogPushService.startIncomingCallTone();

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            myNick: widget.nickname,
            targetNick: from,
            outgoing: false,
            callId: callId,
          ),
        ),
      );
      return;
    }

    // Eski/uyumluluk akışı: doğrudan offer gelirse de kabul et.
    if (type == 'callOffer') {
      final from = (data['from'] ?? '').toString();
      final to = (data['to'] ?? '').toString();

      if (from.isEmpty || to.isEmpty) return;

      if (to.toLowerCase() != widget.nickname.toLowerCase()) {
        return;
      }

      final callId = (data['callId'] ?? '').toString().trim();

      if (callId.isNotEmpty && _handledCallIds.contains(callId)) {
        return;
      }

      if (callId.isNotEmpty) {
        _handledCallIds.add(callId);
      }

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            myNick: widget.nickname,
            targetNick: from,
            outgoing: false,
            callId: callId.isEmpty ? null : callId,
            incomingOffer: data['sdp']?.toString(),
          ),
        ),
      );
    }
  }

  void _openRoom(String room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatRoomScreen(nickname: widget.nickname, roomName: room),
      ),
    );
  }

  Widget _unreadBadge(String username) {
    final unread = _unreadCountFor(username);

    if (unread <= 0) {
      return const SizedBox.shrink();
    }

    final theme = ThemeController.instance.data;

    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
      child: Text(
        unread > 99 ? '99+' : '$unread',
        style: TextStyle(
          color: theme.background,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  int _unreadCountFor(String username) {
    final key = username.trim().toLowerCase();
    final ids = _unreadPrivateMessageIds[key];

    if (ids == null || ids.isEmpty) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    ids.removeWhere((_, expiresAt) => expiresAt <= now);

    if (ids.isEmpty) {
      _unreadPrivateMessageIds.remove(key);
      unawaited(_saveUnreadPrivateMessages());
      return 0;
    }

    return ids.length;
  }

  Future<void> _loadUnreadPrivateMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_unreadPrivateMessagesKey);

    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;

      final restored = <String, Map<String, int>>{};

      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim().toLowerCase();
        final value = entry.value;

        if (key.isEmpty || value is! List) continue;

        final ids = <String, int>{};

        for (final item in value) {
          if (item is! Map) continue;

          final id = (item['id'] ?? '').toString().trim();
          final rawExpiresAt = item['expiresAt'];
          final expiresAt = rawExpiresAt is num
              ? rawExpiresAt.toInt()
              : int.tryParse(rawExpiresAt?.toString() ?? '') ?? 0;

          if (id.isEmpty ||
              expiresAt <= DateTime.now().millisecondsSinceEpoch) {
            continue;
          }

          ids[id] = expiresAt;
        }

        if (ids.isNotEmpty) restored[key] = ids;
      }

      if (!mounted) return;

      setState(() {
        _unreadPrivateMessageIds
          ..clear()
          ..addAll(restored);
      });
    } catch (_) {}
  }

  Future<void> _saveUnreadPrivateMessages() {
    // Snapshot'ı kuyruğa girmeden önce al.
    // Böylece hızlı ardışık event'lerde her yazma kendi
    // çağrıldığı andaki durumu korur.
    final encoded = jsonEncode(
      _unreadPrivateMessageIds.map(
        (key, ids) => MapEntry(
          key,
          ids.entries
              .map(
                (entry) => <String, dynamic>{
                  'id': entry.key,
                  'expiresAt': entry.value,
                },
              )
              .toList(),
        ),
      ),
    );

    _unreadWriteQueue = _unreadWriteQueue.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_unreadPrivateMessagesKey, encoded);
      } catch (_) {}
    });

    return _unreadWriteQueue;
  }

  Future<void> _clearUnreadFor(String username) async {
    await _unreadLoadFuture;
    final key = username.trim().toLowerCase();

    if (key.isEmpty || !_unreadPrivateMessageIds.containsKey(key)) return;

    if (mounted) {
      setState(() {
        _unreadPrivateMessageIds.remove(key);
      });
    } else {
      _unreadPrivateMessageIds.remove(key);
    }

    await _saveUnreadPrivateMessages();
  }

  Future<void> _incrementUnreadFor(
    String username, {
    String? messageId,
    int? expiresAt,
  }) async {
    await _unreadLoadFuture;
    final key = username.trim().toLowerCase();
    final id = messageId?.trim() ?? '';

    final effectiveExpiresAt = expiresAt != null && expiresAt > 0
        ? expiresAt
        : DateTime.now().millisecondsSinceEpoch +
              const Duration(hours: 24).inMilliseconds;

    if (key.isEmpty ||
        key == widget.nickname.trim().toLowerCase() ||
        WsClient.instance.activePrivateChatPeer?.trim().toLowerCase() == key ||
        id.isEmpty) {
      return;
    }

    final ids = _unreadPrivateMessageIds.putIfAbsent(
      key,
      () => <String, int>{},
    );

    final existingExpiresAt = ids[id];
    if (existingExpiresAt != null &&
        existingExpiresAt > DateTime.now().millisecondsSinceEpoch) {
      return;
    }

    if (effectiveExpiresAt <= DateTime.now().millisecondsSinceEpoch) {
      return;
    }

    ids[id] = effectiveExpiresAt;

    if (mounted) setState(() {});

    await _saveUnreadPrivateMessages();
  }

  void _openPrivate(String target) {
    _clearUnreadFor(target);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PrivateChatScreen(myNick: widget.nickname, targetNick: target),
      ),
    );
  }

  void _call(String target) {
    final callId =
        '${DateTime.now().millisecondsSinceEpoch}-${widget.nickname}';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: target,
          outgoing: true,
          callId: callId,
        ),
      ),
    );
  }

  Future<void> _openPendingPrivateMessage() async {
    final data = await ZeroLogPushService.takePendingNotification();

    if (!mounted || data == null) return;

    final type = (data['type'] ?? '').toString();

    if (type != 'privateMessage' && type != 'privateFileMessage') {
      return;
    }

    final from = (data['from'] ?? data['sender'] ?? '').toString().trim();
    final to = (data['to'] ?? data['target'] ?? '').toString().trim();

    if (from.isEmpty) return;

    if (to.isNotEmpty && to.toLowerCase() != widget.nickname.toLowerCase()) {
      return;
    }

    if (from.toLowerCase() == widget.nickname.toLowerCase()) {
      return;
    }

    final activePeer = WsClient.instance.activePrivateChatPeer;

    if (activePeer != null &&
        activePeer.trim().isNotEmpty &&
        activePeer.trim().toLowerCase() == from.toLowerCase()) {
      debugPrint(
        '[FCM] pending notification open suppressed: '
        'active chat with $from',
      );
      return;
    }

    if (type == 'privateFileMessage') {
      final fileId = (data['fileId'] ?? '').toString().trim();
        final fileName = (data['fileName'] ?? 'Dosya').toString().trim();
      final rawFileSize = data['fileSize'];

      final fileSize = rawFileSize is num
          ? rawFileSize.toInt()
          : int.tryParse(rawFileSize?.toString() ?? '') ?? 0;

      if (fileId.isEmpty || fileName.isEmpty || fileSize <= 0) {
        debugPrint(
          '[FCM] invalid pending file notification '
          'fileId=$fileId fileName=$fileName fileSize=$fileSize',
        );
        return;
      }

      _pendingFileNotification = <String, dynamic>{
        'type': 'privateFileMessage',
        'from': from,
        'to': to,
        'id': (data['id'] ?? '').toString(),
        'clientMessageId': (data['clientMessageId'] ?? '').toString(),
        'fileId': fileId,
        'fileName': fileName,
        'fileSize': fileSize,
      };
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          myNick: widget.nickname,
          targetNick: from,
          pendingFileNotification: type == 'privateFileMessage'
              ? _pendingFileNotification
              : null,
        ),
      ),
    );

    // Route'a aktarıldıktan sonra parent state'teki referansı temizle.
    _pendingFileNotification = null;
  }

  Future<void> _openIncomingCallFromNative(Map<String, dynamic> data) async {
    if (!mounted) return;

    await _openIncomingCallData(data);
  }

  Future<void> _openIncomingCallData(Map<String, dynamic> data) async {
    if (!mounted) return;

    final from = (data['from'] ?? data['caller'] ?? '').toString().trim();
    final to = (data['to'] ?? data['callee'] ?? '').toString().trim();
    final callId = (data['callId'] ?? '').toString().trim();

    if (from.isEmpty ||
        to.isEmpty ||
        callId.isEmpty ||
        to.toLowerCase() != widget.nickname.toLowerCase()) {
      return;
    }

    // WebSocket, FCM pending veya native full-screen intent
    // aynı çağrıyı farklı kanallardan bildirirse tek CallScreen aç.
    if (!_handledCallIds.add(callId)) {
      return;
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: from,
          outgoing: false,
          callId: callId,
        ),
      ),
    );
  }

  Future<void> _openPendingIncomingCall() async {
    final data = await ZeroLogPushService.takePendingCall();

    if (!mounted || data == null) return;

    await _openIncomingCallData(data);
  }

  Future<void> _deleteAccount({required bool allData}) async {
    final title = allData ? 'Tüm kayıtları sil' : 'Hesabı sil';

    final message = allData
        ? 'Hesabınız, özel mesajlarınız ve odalarda gönderdiğiniz mesajlar kalıcı olarak silinecek. Bu işlem geri alınamaz.'
        : 'Hesabınız ve özel mesaj geçmişiniz kalıcı olarak silinecek. Bu işlem geri alınamaz.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    WsClient.instance.send({
      'type': allData ? 'deleteAllData' : 'deleteAccount',
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription.cancel();
    _contactSearchController.dispose();
    super.dispose();
  }

  Widget _avatar(String name, {bool online = false}) {
    final theme = ThemeController.instance.data;
    final letter = name.trim().isEmpty
        ? '?'
        : name.trim().substring(0, 1).toUpperCase();

    final isMyProfile =
        name.trim().toLowerCase() == widget.nickname.trim().toLowerCase();

    final profilePath = isMyProfile ? _profilePhotoPath : null;

    String? remotePhotoData;

    final remoteProfile = !isMyProfile
        ? WsClient.instance.profileFor(name)
        : null;

    remotePhotoData = (remoteProfile?['photoData'] ?? '').toString().trim();

    final profileFile = profilePath == null || profilePath.isEmpty
        ? null
        : File(profilePath);

    MemoryImage? remotePhotoImage;

    if (!isMyProfile && remotePhotoData.isNotEmpty) {
      remotePhotoImage = _cachedProfileImage(
      name,
      remotePhotoData,
      revision: int.tryParse(
            (remoteProfile?['profileRevision'] ?? '').toString(),
          ) ??
          0,
    );
    }

    final remoteType = (remoteProfile?['type'] ?? 'avatar').toString();

    final hasRemotePhoto =
        !isMyProfile && remoteType == 'photo' && remotePhotoImage != null;

    return Stack(
      children: [
        if (hasRemotePhoto)
          ClipOval(
            child: SizedBox(
              width: 50,
              height: 50,
              child: Image(
                image: remotePhotoImage,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          )
        else
          CircleAvatar(
            radius: 25,
            backgroundColor: theme.primary.withValues(alpha: 0.14),
            backgroundImage:
                remotePhotoImage ??
                (profileFile != null && profileFile.existsSync()
                    ? FileImage(profileFile)
                    : null),
            child:
                remotePhotoImage != null ||
                    (profileFile != null && profileFile.existsSync())
                ? null
                : Text(
                    letter,
                    style: TextStyle(
                      color: theme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
          ),
        if (online)
          Positioned(
            right: 0,
            bottom: 1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
                border: Border.all(color: theme.background, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _connectionBanner() {
    final theme = ThemeController.instance.data;

    if (_connected && !_reconnecting) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _reconnecting ? 'Bağlantı yeniden kuruluyor…' : 'Bağlanıyor…',
            style: TextStyle(color: theme.text, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsPage() {
    final theme = ThemeController.instance.data;
    final onlineCount = _onlineUsers.length;
    final visibleUsers = _knownUsers.take(12).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      children: [
        _connectionBanner(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.primary.withValues(alpha: 0.18),
                theme.secondary.withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: theme.primary.withValues(alpha: 0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.shield_rounded, color: theme.primary, size: 23),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('$onlineCount çevrimiçi', style: TextStyle(color: theme.text.withValues(alpha: 0.72), fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Özel iletişim, sade deneyim.', style: TextStyle(color: theme.text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(height: 5),
              Text('ZeroLog ile konuşmalarınızı tek bir akışta yönetin.', style: TextStyle(color: theme.text.withValues(alpha: 0.56), fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 15),
              Material(
                color: theme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(17),
                child: InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => setState(() => _selectedIndex = 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded, color: theme.primary, size: 21),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Yeni sohbet veya kişi ara', style: TextStyle(color: theme.text.withValues(alpha: 0.55), fontSize: 13, fontWeight: FontWeight.w600))),
                        Icon(Icons.arrow_forward_rounded, color: theme.text.withValues(alpha: 0.35), size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: Text('Sohbetler', style: TextStyle(color: theme.text, fontSize: 18, fontWeight: FontWeight.w800))),
            if (visibleUsers.isNotEmpty) Text('${visibleUsers.length}', style: TextStyle(color: theme.text.withValues(alpha: 0.36), fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        if (visibleUsers.isEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: theme.text.withValues(alpha: 0.05))),
            child: Column(
              children: [
                Container(width: 64, height: 64, decoration: BoxDecoration(color: theme.primary.withValues(alpha: 0.10), shape: BoxShape.circle), child: Icon(Icons.forum_rounded, color: theme.primary, size: 29)),
                const SizedBox(height: 14),
                Text('Henüz sohbet yok', style: TextStyle(color: theme.text, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('Kişiler sekmesinden bir kullanıcı bulup ilk sohbetinizi başlatın.', textAlign: TextAlign.center, style: TextStyle(color: theme.text.withValues(alpha: 0.48), fontSize: 12.5, height: 1.4)),
              ],
            ),
          )
        else
          ...visibleUsers.map((user) {
            final online = _onlineUsers.any((u) => u.toLowerCase() == user.toLowerCase());
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => _openPrivate(user),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                    child: Row(
                      children: [
                        _avatar(user, online: online),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(user, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: theme.text, fontSize: 14.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 5),
                            Row(children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: online ? theme.primary : theme.text.withValues(alpha: 0.24), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(online ? 'Çevrimiçi' : 'Çevrimdışı', style: TextStyle(color: theme.text.withValues(alpha: 0.42), fontSize: 11.5, fontWeight: FontWeight.w600)),
                            ]),
                          ]),
                        ),
                        _unreadBadge(user),
                        const SizedBox(width: 4),
                        IconButton(tooltip: 'Ara', onPressed: () => _call(user), icon: Icon(Icons.call_rounded, color: theme.primary, size: 20)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: Text('Topluluk odaları', style: TextStyle(color: theme.text, fontSize: 18, fontWeight: FontWeight.w800))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: theme.primary.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(15)), child: Text('${rooms.length}', style: TextStyle(color: theme.primary, fontSize: 11, fontWeight: FontWeight.w800))),
          ],
        ),
        const SizedBox(height: 10),
        ...rooms.map((room) => Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Material(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _openRoom(room),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: theme.secondary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.tag_rounded, color: theme.secondary, size: 21)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(room, style: TextStyle(color: theme.text, fontSize: 14, fontWeight: FontWeight.w700))),
                  Icon(Icons.chevron_right_rounded, color: theme.text.withValues(alpha: 0.28)),
                ]),
              ),
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildContactsPage() {
    final theme = ThemeController.instance.data;
    final query = _contactSearchQuery.trim().toLowerCase();

    final filteredUsers = query.isEmpty
        ? _knownUsers
        : _knownUsers
              .where((user) => user.toLowerCase().contains(query))
              .toList();

    final exactUser = query.isEmpty
        ? null
        : _knownUsers.cast<String?>().firstWhere(
            (user) => user!.toLowerCase() == query,
            orElse: () => null,
          );

    Widget quickAction({
      required IconData icon,
      required String title,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: theme.primary, size: 21),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        Text(
          'Kişiler',
          style: TextStyle(
            color: theme.text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Güvenli bir şekilde yeni bir sohbet başlatın.',
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.48),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 18),

        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(20),
          child: TextField(
            controller: _contactSearchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rumuz ara',
              hintStyle: TextStyle(color: theme.text.withValues(alpha: 0.40)),
              prefixIcon: Icon(Icons.search_rounded, color: theme.primary),
              suffixIcon: query.isNotEmpty
                  ? IconButton(
                      tooltip: 'Temizle',
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.text.withValues(alpha: 0.45),
                      ),
                      onPressed: () {
                        _contactSearchController.clear();
                        setState(() => _contactSearchQuery = '');
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 17,
              ),
            ),
            onChanged: (value) {
              setState(() => _contactSearchQuery = value);
            },
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            quickAction(
              icon: Icons.person_search_rounded,
              title: 'Rumuz bul',
              onTap: () {
                FocusScope.of(context).requestFocus(FocusNode());
              },
            ),
            const SizedBox(width: 9),
            quickAction(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Yeni sohbet',
              onTap: () {
                setState(() => _selectedIndex = 1);
              },
            ),
            const SizedBox(width: 9),
            quickAction(
              icon: Icons.call_outlined,
              title: 'Arama başlat',
              onTap: () {
                setState(() => _selectedIndex = 2);
              },
            ),
          ],
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(4, 25, 4, 10),
          child: Row(
            children: [
              Text(
                query.isEmpty ? 'Kişileriniz' : 'Arama sonuçları',
                style: TextStyle(
                  color: theme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (filteredUsers.isNotEmpty)
                Text(
                  '${filteredUsers.length}',
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.40),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),

        if (filteredUsers.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 30),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.person_search_rounded,
                  size: 34,
                  color: theme.text.withValues(alpha: 0.28),
                ),
                const SizedBox(height: 12),
                Text(
                  query.isEmpty
                      ? 'Henüz kişi bulunmuyor'
                      : 'Kullanıcı bulunamadı',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  query.isEmpty
                      ? 'Bir rumuz arayarak yeni bir sohbet başlatabilirsiniz.'
                      : 'Farklı bir rumuz deneyin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.45),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else
          ...(exactUser != null ? [exactUser] : filteredUsers).map(
            _contactResultCard,
          ),
      ],
    );
  }

  Future<void> _showContactAvatarActions(String user) async {
    final theme = ThemeController.instance.data;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(
                  children: [
                    _avatar(
                      user,
                      online: _onlineUsers.any(
                        (u) => u.toLowerCase() == user.toLowerCase(),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: Icon(Icons.call_outlined, color: theme.primary),
                title: const Text('Ara'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _call(user);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: theme.primary,
                ),
                title: const Text('Mesaj at'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openPrivate(user);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.person_outline_rounded,
                  color: theme.primary,
                ),
                title: const Text('Profil'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openUserProfile(user);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openUserProfile(String user) async {
    final theme = ThemeController.instance.data;
    final normalizedUser = user.trim().toLowerCase();

    Map<String, dynamic>? profile = WsClient.instance.profileFor(user);

    final knownType = (profile?['type'] ?? 'avatar').toString();
    final knownPhoto = (profile?['photoData'] ?? '').toString().trim();

    if (WsClient.instance.connected &&
        (profile == null || (knownType == 'photo' && knownPhoto.isEmpty))) {
      _profileFetchRequested.add(normalizedUser);
      WsClient.instance.requestProfile(user);

      for (var attempt = 0; attempt < 12; attempt++) {
        await Future.delayed(const Duration(milliseconds: 150));

        if (!mounted) return;

        profile = WsClient.instance.profileFor(user);

        if (profile != null) {
          final type = (profile['type'] ?? 'avatar').toString();
          final photo = (profile['photoData'] ?? '').toString().trim();

          if (type != 'photo' || photo.isNotEmpty) {
            break;
          }
        }
      }
    }

    final about = (profile?['about'] ?? '').toString().trim();
    final profileType = (profile?['type'] ?? 'avatar').toString();

    final photoData = (profile?['photoData'] ?? '').toString().trim();
    final photoRevision = int.tryParse(
          (profile?['profileRevision'] ?? '').toString(),
        ) ??
        0;

    ImageProvider? photoImage;

    if (profileType == 'photo' && photoData.isNotEmpty) {
      photoImage = _cachedProfileImage(
        user,
        photoData,
        revision: photoRevision,
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final online = _onlineUsers.any(
          (u) => u.toLowerCase() == user.toLowerCase(),
        );

        Widget avatar;

        if (photoImage != null) {
          avatar = ClipOval(
            child: SizedBox(
              width: 92,
              height: 92,
              child: Image(
                image: photoImage,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
          );
        } else {
          final letter = user.trim().isEmpty
              ? '?'
              : user.trim().substring(0, 1).toUpperCase();

          avatar = CircleAvatar(
            radius: 46,
            backgroundColor: theme.primary.withValues(alpha: 0.14),
            child: Text(
              letter,
              style: TextStyle(
                color: theme.primary,
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: online
                            ? theme.primary
                            : theme.text.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _openPrivate(user);
                        },
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Mesaj'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _call(user);
                        },
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Ara'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _contactResultCard(String user) {
    final theme = ThemeController.instance.data;
    final online = _onlineUsers.any(
      (u) => u.toLowerCase() == user.toLowerCase(),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openPrivate(user),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showContactAvatarActions(user),
                  child: _avatar(user, online: online),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: online
                                  ? theme.primary
                                  : theme.text.withValues(alpha: 0.25),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            online ? 'Çevrimiçi' : 'Çevrimdışı',
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.48),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _unreadBadge(user),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Mesaj',
                  onPressed: () => _openPrivate(user),
                  icon: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: theme.primary,
                    size: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Ara',
                  onPressed: () => _call(user),
                  icon: Icon(
                    Icons.call_rounded,
                    color: theme.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCallsPage() {
    final theme = ThemeController.instance.data;

    final onlineUsers = _knownUsers
        .where(
          (user) => _onlineUsers.any(
            (online) => online.toLowerCase() == user.toLowerCase(),
          ),
        )
        .take(8)
        .toList();

    final recentUsers = _knownUsers.take(5).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        Text(
          'Çağrılar',
          style: TextStyle(
            color: theme.text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Güvenli sesli görüşmelerinizi yönetin.',
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.48),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 18),

        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.call_rounded,
                    color: theme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Güvenli arama',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'ZeroLog üzerinden sesli görüşme başlatın.',
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.48),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.lock_rounded, size: 17, color: theme.primary),
              ],
            ),
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'Hızlı arama',
          style: TextStyle(
            color: theme.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),

        if (onlineUsers.isEmpty)
          Material(
            color: theme.surface,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.person_off_outlined,
                    color: theme.text.withValues(alpha: 0.32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Şu anda çevrimiçi kişi bulunmuyor.',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.52),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...onlineUsers.map(
            (user) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _call(user),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        _avatar(user, online: true),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: theme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Çevrimiçi',
                                    style: TextStyle(
                                      color: theme.text.withValues(alpha: 0.46),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: theme.primary.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.call_rounded,
                            color: theme.primary,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (recentUsers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Kişiler',
            style: TextStyle(
              color: theme.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...recentUsers.map((user) {
            final online = _onlineUsers.any(
              (onlineUser) => onlineUser.toLowerCase() == user.toLowerCase(),
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: theme.surface,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 2,
                  ),
                  leading: _avatar(user, online: online),
                  title: Text(
                    user,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    online ? 'Çevrimiçi' : 'Çevrimdışı',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.43),
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Ara',
                    onPressed: () => _call(user),
                    icon: Icon(Icons.call_outlined, color: theme.primary),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSettingsPage() {
    final theme = ThemeController.instance.data;

    Widget sectionTitle(String text) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 9),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.42),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    Widget tile({
      required IconData icon,
      required String title,
      String? subtitle,
      VoidCallback? onTap,
      Widget? trailing,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(19),
          child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: theme.primary, size: 21),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.text.withValues(alpha: 0.45),
                              fontSize: 11.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        color: theme.text.withValues(alpha: 0.28),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        Material(
          color: theme.surface,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: _openProfileEditor,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                children: [
                  Stack(
                    children: [
                      _profileAvatar(radius: 25),
                      Positioned(
                        right: 0,
                        bottom: 1,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _profileAbout.trim().isEmpty
                              ? 'Profilini düzenle'
                              : _profileAbout.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.48),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.edit_outlined,
                    color: theme.text.withValues(alpha: 0.32),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        const SizedBox(height: 4),

        if (ThemeController.instance.current == ZeroLogTheme.mivi) ...[
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF0F2), Color(0xFFFFFFFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Color(0xFFD90429), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD90429),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mivi',
                        style: TextStyle(
                          color: Color(0xFF12365A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Kırmızı, beyaz ve lacivert ile yeniden tasarlandı.',
                        style: TextStyle(
                          color: theme.text.withValues(alpha: 0.58),
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        sectionTitle('Görünüm'),

        tile(
          icon: Icons.palette_outlined,
          title: 'Tema',
          subtitle: zeroLogThemes[ThemeController.instance.current]!.name,
          onTap: () async {
            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: theme.surface,
              showDragHandle: true,
              builder: (sheetContext) {
                return SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      Text(
                        'Tema seç',
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...ZeroLogTheme.values.map((value) {
                        final selected =
                            ThemeController.instance.current == value;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: value == ZeroLogTheme.mivi
                              ? Container(
                                  width: 48,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: CustomPaint(
                                    painter: _MiviFlagPainter(),
                                  ),
                                )
                              : Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: zeroLogThemes[value]!.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                          title: Text(
                            zeroLogThemes[value]!.name,
                            style: TextStyle(
                              color: theme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle_rounded,
                                  color: theme.primary,
                                )
                              : null,
                          onTap: () async {
                            await ThemeController.instance.setTheme(value);
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (mounted) {
                              setState(() {});
                            }
                          },
                        );
                      }),
                    ],
                  ),
                );
              },
            );
          },
        ),

        tile(
          icon: Icons.notifications_none_rounded,
          title: 'Bildirimler',
          subtitle: 'Mesaj ve çağrı bildirimlerini yönet',
          onTap: _openNotificationSettings,
        ),

        tile(
          icon: Icons.shield_outlined,
          title: 'Gizlilik',
          subtitle: 'Çevrimiçi görünürlüğü ve özel mesajları yönet',
          onTap: _openPrivacySettings,
        ),

        sectionTitle('Uygulama'),

        tile(
          icon: Icons.tune_rounded,
          title: 'Sohbet tercihleri',
          subtitle: 'Mesajlaşma ve sohbet davranışlarını düzenle',
          onTap: _openChatPreferences,
        ),

        tile(
          icon: Icons.folder_outlined,
          title: 'Dosya kayıt konumu',
          subtitle: 'Alınan dosyaların otomatik kaydedileceği klasörü seç',
          onTap: _openFileStorageSettings,
        ),

        tile(
          icon: Icons.storage_outlined,
          title: 'Depolama ve veriler',
          subtitle: 'Profil ve yerel uygulama verilerini yönet',
          onTap: () async {
            final prefs = await SharedPreferences.getInstance();

            if (!mounted) return;

            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: theme.surface,
              showDragHandle: true,
              builder: (sheetContext) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Depolama ve veriler',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ZeroLog bu cihazda tuttuğu yerel tercihleri burada yönetir.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.48),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          leading: Icon(
                            Icons.account_circle_outlined,
                            color: theme.primary,
                          ),
                          title: const Text('Profil verileri'),
                          subtitle: Text(
                            (_profilePhotoPath != null &&
                                        _profilePhotoPath!.isNotEmpty) ||
                                    _profileAbout.trim().isNotEmpty
                                ? 'Profil bilgileri kayıtlı'
                                : 'Ek profil verisi bulunmuyor',
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.cleaning_services_outlined),
                          title: const Text('Profil verilerini temizle'),
                          subtitle: const Text(
                            'Profil fotoğrafı ve hakkında bilgisini kaldır',
                          ),
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: sheetContext,
                              builder: (dialogContext) {
                                return AlertDialog(
                                  title: const Text(
                                    'Profil verileri silinsin mi?',
                                  ),
                                  content: const Text(
                                    'Profil fotoğrafı ve hakkında bilgisi '
                                    'bu cihazdan kaldırılacak.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('İptal'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('Temizle'),
                                    ),
                                  ],
                                );
                              },
                            );

                            if (confirmed != true) return;

                            await _profileController.clear();

                            if (!mounted) return;

                            setState(() {
                              _profileController.photoPath = null;
                              _profileController.photoData = '';
                              _profileController.about = '';
                            });

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profil verileri temizlendi.'),
                                ),
                              );
                            }
                          },
                        ),
                        ListTile(
                          leading: const Icon(
                            Icons.settings_backup_restore_rounded,
                          ),
                          title: const Text('Sohbet tercihlerini sıfırla'),
                          subtitle: const Text(
                            'Mesajlaşma ayarlarını varsayılana döndür',
                          ),
                          onTap: () async {
                            await prefs.remove('zerolog.chat.enter_to_send');
                            await prefs.remove('zerolog.chat.message_preview');
                            await prefs.remove('zerolog.chat.auto_focus');

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sohbet tercihleri sıfırlandı.',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),

        tile(
          icon: Icons.info_outline_rounded,
          title: 'ZeroLog hakkında',
          subtitle: 'Sürüm, geliştirici ve uygulama bilgileri',
          onTap: _openAboutPage,
        ),

        tile(
          icon: Icons.menu_book_outlined,
          title: 'Açık kaynak lisansları',
          subtitle: 'ZeroLog içinde kullanılan açık kaynak bileşenler',
          onTap: () {
            showLicensePage(
              context: context,
              applicationName: 'ZeroLog',
              applicationVersion: '1.0.8',
              applicationLegalese:
                  'Bu program BerkanCVS tarafından hazırlanmıştır.',
            );
          },
        ),

        const SizedBox(height: 18),

        Center(
          child: Text(
            'ZeroLog • Güvenli iletişim',
            style: TextStyle(
              color: theme.text.withValues(alpha: 0.28),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  void _openAboutPage() {
    final theme = ThemeController.instance.data;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          return Scaffold(
            backgroundColor: theme.background,
            appBar: AppBar(
              backgroundColor: theme.background,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: const Text('ZeroLog hakkında'),
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: theme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: theme.primary,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'ZeroLog',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Güvenli iletişim',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.48),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Uygulama hakkında',
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Bu program BerkanCVS tarafından hazırlanmıştır. '
                          'Yazılımda emeği geçen İlay Kayra’ya sonsuz '
                          'teşekkürlerimi sunarım.',
                          style: TextStyle(
                            color: theme.text.withValues(alpha: 0.62),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    leading: Icon(
                      Icons.system_update_outlined,
                      color: theme.primary,
                    ),
                    title: Text(
                      'Sürüm',
                      style: TextStyle(
                        color: theme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'ZeroLog 1.0.8',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.48),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: theme.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: ListTile(
                    leading: Icon(
                      Icons.menu_book_outlined,
                      color: theme.primary,
                    ),
                    title: Text(
                      'Açık kaynak lisansları',
                      style: TextStyle(
                        color: theme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      'ZeroLog içinde kullanılan bileşenler',
                      style: TextStyle(
                        color: theme.text.withValues(alpha: 0.48),
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: theme.text.withValues(alpha: 0.28),
                    ),
                    onTap: () {
                      showLicensePage(
                        context: context,
                        applicationName: 'ZeroLog',
                        applicationVersion: '1.0.8',
                        applicationLegalese:
                            'Bu program BerkanCVS tarafından hazırlanmıştır.',
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _settingsSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = ThemeController.instance.data;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 14, 10, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: theme.primary, size: 21),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: theme.primary.withValues(alpha: 0.48),
              thumbColor: WidgetStatePropertyAll(theme.primary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsInfoCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    final theme = ThemeController.instance.data;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.primary, size: 19),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: TextStyle(
                    color: theme.text.withValues(alpha: 0.48),
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChatPreferences() async {
    final theme = ThemeController.instance.data;
    final prefs = await SharedPreferences.getInstance();

    bool enterToSend = prefs.getBool('zerolog.chat.enter_to_send') ?? true;
    bool messagePreview = prefs.getBool('zerolog.chat.message_preview') ?? true;
    bool autoFocus = prefs.getBool('zerolog.chat.auto_focus') ?? true;

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            Future<void> save(String key, bool value) async {
              await prefs.setBool(key, value);
            }

            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Sohbet tercihleri'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Mesajlaşma deneyimi',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Sohbet ekranının davranışını kullanımınıza göre ayarlayın.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _settingsSectionCard(
                    icon: Icons.keyboard_return_rounded,
                    title: 'Enter ile gönder',
                    subtitle: 'Klavyedeki Enter tuşu mesajı doğrudan göndersin',
                    value: enterToSend,
                    onChanged: (value) {
                      setPageState(() => enterToSend = value);
                      save('zerolog.chat.enter_to_send', value);
                    },
                  ),
                  _settingsSectionCard(
                    icon: Icons.visibility_outlined,
                    title: 'Bildirim önizlemesi',
                    subtitle: 'Mesaj bildirimlerinde mesaj içeriğini göster',
                    value: messagePreview,
                    onChanged: (value) {
                      setPageState(() => messagePreview = value);
                      save('zerolog.chat.message_preview', value);
                    },
                  ),
                  _settingsSectionCard(
                    icon: Icons.keyboard_alt_outlined,
                    title: 'Sohbet açıldığında klavye',
                    subtitle:
                        'Yeni sohbet açıldığında mesaj alanına otomatik odaklan',
                    value: autoFocus,
                    onChanged: (value) {
                      setPageState(() => autoFocus = value);
                      save('zerolog.chat.auto_focus', value);
                    },
                  ),
                  _settingsInfoCard(
                    icon: Icons.tune_rounded,
                    title: 'Tercihler cihazınızda saklanır',
                    text:
                        'Bu seçenekler uygulamayı yeniden açtığınızda korunur.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openFileStorageSettings() async {
    final theme = ThemeController.instance.data;
    const channel = MethodChannel('zerolog/system');

    String directory = 'İndirilenler';

    try {
      final current = await channel.invokeMethod<String>(
        'getFileSaveDirectory',
      );

      if (current != null && current.trim().isNotEmpty) {
        directory = current.trim();
      }
    } catch (e) {
      debugPrint('[FILE_STORAGE] read directory failed: $e');
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            Future<void> chooseDirectory() async {
              try {
                final selected = await channel.invokeMethod<String>(
                  'chooseFileSaveDirectory',
                );

                if (selected != null && selected.trim().isNotEmpty) {
                  setPageState(() => directory = selected.trim());

                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Dosyalar artık "$directory" '
                          'klasörüne kaydedilecek.',
                        ),
                      ),
                    );
                  }
                }
              } on PlatformException catch (e) {
                if (!mounted) return;

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      e.message ?? 'Kayıt klasörü değiştirilemedi.',
                    ),
                  ),
                );
              } catch (_) {
                if (!mounted) return;

                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('Kayıt klasörü değiştirilemedi.'),
                  ),
                );
              }
            }

            Future<void> resetDirectory() async {
              try {
                final selected = await channel.invokeMethod<String>(
                  'resetFileSaveDirectory',
                );

                setPageState(
                  () =>
                      directory = (selected == null || selected.trim().isEmpty)
                      ? 'İndirilenler'
                      : selected.trim(),
                );
              } catch (e) {
                debugPrint('[FILE_STORAGE] reset directory failed: $e');
              }
            }

            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Dosya kayıt konumu'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Dosya aktarımı',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Kabul ettiğiniz dosyalar onaydan sonra '
                    'otomatik olarak seçtiğiniz klasöre '
                    'kaydedilir.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(Icons.folder_rounded, color: theme.primary),
                    ),
                    title: const Text(
                      'Kayıt klasörü',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(directory),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: chooseDirectory,
                  ),
                  const SizedBox(height: 10),
                  _settingsInfoCard(
                    icon: Icons.download_rounded,
                    title: 'Varsayılan: İndirilenler',
                    text:
                        'Özel bir klasör seçmediğiniz sürece '
                        'alınan dosyalar Android\'in '
                        'İndirilenler klasörüne otomatik '
                        'kaydedilir. Dosya kabul edildiğinde '
                        'ayrıca kayıt yeri seçmeniz istenmez.',
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.restore_rounded),
                    title: const Text('Varsayılana dön'),
                    subtitle: const Text(
                      'Kayıt konumunu İndirilenler '
                      'klasörüne geri al',
                    ),
                    onTap: resetDirectory,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openNotificationSettings() {
    final theme = ThemeController.instance.data;

    var messageEnabled = _messageNotificationsEnabled;
    var callEnabled = _callNotificationsEnabled;
    var autoAcceptFiles = _autoAcceptFileTransfers;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Bildirimler'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  Text(
                    'Bildirim tercihleri',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'ZeroLog size nasıl ulaşacağını kontrol edin.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _settingsSectionCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Mesaj bildirimleri',
                    subtitle: 'Özel mesaj geldiğinde bildirim göster',
                    value: messageEnabled,
                    onChanged: (value) {
                      setPageState(() => messageEnabled = value);
                      _messageNotificationsEnabled = value;

                      WsClient.instance.setNotificationSettings(
                        messageNotificationsEnabled: value,
                      );
                    },
                  ),

                  _settingsSectionCard(
                    icon: Icons.call_outlined,
                    title: 'Çağrı bildirimleri',
                    subtitle: 'Gelen sesli çağrıları bildirim olarak göster',
                    value: callEnabled,
                    onChanged: (value) {
                      setPageState(() => callEnabled = value);
                      _callNotificationsEnabled = value;

                      WsClient.instance.setNotificationSettings(
                        callNotificationsEnabled: value,
                      );
                    },
                  ),

                  _settingsSectionCard(
                    icon: Icons.download_done_rounded,
                    title: 'Gelen dosya ve medyayı otomatik kabul et',
                    subtitle:
                        autoAcceptFiles
                            ? 'Gelen dosyalar onay beklemeden otomatik alınır.'
                            : 'Gelen dosyada kabul et veya reddet bildirimi gösterilir.',
                    value: autoAcceptFiles,
                    onChanged: (value) {
                      setPageState(() => autoAcceptFiles = value);
                      _autoAcceptFileTransfers = value;

                      final prefs = SharedPreferences.getInstance();
                      unawaited(prefs.then((valuePrefs) => valuePrefs.setBool(
                            'zerolog.notifications.auto_accept_files',
                            value,
                          )));

                      WsClient.instance.setNotificationSettings(
                        autoAcceptFileTransfers: value,
                      );
                    },
                  ),

                  _settingsInfoCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Bildirimler güvenli şekilde yönetilir',
                    text:
                        'Tercihleriniz ZeroLog hesabınızla senkronize edilir. '
                        'Çağrı bildirimleri kilit ekranında da gösterilebilir.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    WsClient.instance.requestNotificationSettings();
  }

  void _openPrivacySettings() {
    final theme = ThemeController.instance.data;

    var presenceVisible = _presenceVisible;
    var privateMessagesEnabled = _privateMessagesEnabled;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (context, setPageState) {
            return Scaffold(
              backgroundColor: theme.background,
              appBar: AppBar(
                backgroundColor: theme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                title: const Text('Gizlilik'),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  Text(
                    'Gizlilik ve güvenlik',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Kimlerin sizi görebileceğini ve size ulaşabileceğini seçin.',
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.46),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  _settingsSectionCard(
                    icon: Icons.visibility_outlined,
                    title: 'Çevrimiçi durum',
                    subtitle: 'Çevrimiçi olduğunuzu diğer kullanıcılar görsün',
                    value: presenceVisible,
                    onChanged: (value) {
                      setPageState(() => presenceVisible = value);
                      _presenceVisible = value;

                      WsClient.instance.setPrivacySettings(
                        presenceVisible: value,
                      );
                    },
                  ),

                  _settingsSectionCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Özel mesajlar',
                    subtitle:
                        'Diğer kullanıcıların size mesaj göndermesine izin ver',
                    value: privateMessagesEnabled,
                    onChanged: (value) {
                      setPageState(() => privateMessagesEnabled = value);
                      _privateMessagesEnabled = value;

                      WsClient.instance.setPrivacySettings(
                        privateMessagesEnabled: value,
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  Material(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _deleteAccount(allData: true),
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.text.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: theme.text.withValues(alpha: 0.62),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Verilerimi sil',
                                    style: TextStyle(
                                      color: theme.text,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Hesap ve kayıtları kalıcı olarak yönet',
                                    style: TextStyle(
                                      color: theme.text.withValues(alpha: 0.45),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: theme.text.withValues(alpha: 0.30),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  _settingsInfoCard(
                    icon: Icons.shield_outlined,
                    title: 'Kontrol sizde',
                    text:
                        'Gizlilik tercihleri hesabınıza kaydedilir. '
                        'Çevrimiçi durumunu kapattığınızda diğer kullanıcılar '
                        'sizi çevrimiçi listesinde göremez.',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    WsClient.instance.requestPrivacySettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    final titles = ['Sohbetler', 'Kişiler', 'Çağrılar', 'Ayarlar'];
    final subtitles = ['Özel ve güvenli iletişim', 'ZeroLog kullanıcılarını keşfet', 'Sesli görüşmelerin', 'Hesap ve uygulama tercihleri'];
    final selectedIcons = [Icons.chat_bubble_rounded, Icons.people_alt_rounded, Icons.call_rounded, Icons.settings_rounded];
    final unselectedIcons = [Icons.chat_bubble_outline_rounded, Icons.people_outline_rounded, Icons.call_outlined, Icons.settings_outlined];
    final pages = [_buildChatsPage(), _buildContactsPage(), _buildCallsPage(), _buildSettingsPage()];

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 13, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('Zero', style: TextStyle(color: theme.text, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                        Text('Log', style: TextStyle(color: theme.primary, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                      ]),
                      const SizedBox(height: 2),
                      Text(subtitles[_selectedIndex], style: TextStyle(color: theme.text.withValues(alpha: 0.42), fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                  Material(
                    color: theme.surface,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _openProfileEditor,
                      child: Padding(padding: const EdgeInsets.all(2), child: _profileAvatar(radius: 20)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: IndexedStack(index: _selectedIndex, children: pages)),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        height: 72,
        onDestinationSelected: (index) {
          if (_selectedIndex == index) return;
          setState(() => _selectedIndex = index);
        },
        destinations: List.generate(4, (index) {
          return NavigationDestination(
            icon: Icon(unselectedIcons[index]),
            selectedIcon: Icon(selectedIcons[index]),
            label: titles[index],
          );
        }),
      ),
    );
  }
}

// ============================================================
// ROOM CHAT
// ============================================================
