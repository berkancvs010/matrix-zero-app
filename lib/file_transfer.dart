import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileTransfer {
  static const MethodChannel _systemChannel = MethodChannel('zerolog/system');
  final dynamic ws;
  final String me;
  final String peer;

  String? turnUsername;
  String? turnPassword;
  List<String> turnUrls;

  void Function({
    required String transferId,
    required int sentBytes,
    required int totalBytes,
    required String status,
  })?
  onProgress;

  void Function({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
  })?
  onIncomingOffer;

  void Function({required String transferId, required String status})?
  onIncomingStatus;

  static final Map<String, FileTransfer> _sharedTransfers =
      <String, FileTransfer>{};

  static FileTransfer? active(String me, String peer) {
    final transfer = _sharedTransfers[_sharedKey(me, peer)];
    if (transfer == null || transfer._disposed) return null;
    return transfer;
  }

  bool _initialized = false;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  StreamSubscription? _eventsSub;

  String? _transferId;
  String? _fileName;
  int _fileSize = 0;
  int _receivedBytes = 0;
  int _sentBytes = 0;

  bool _nativeFileOpen = false;

  File? _sendingFile;
  bool _sending = false;
  bool _sendLoopStarted = false;
  bool _accepted = false;
  bool _disposed = false;

  // DataChannel mesajları kesinlikle paralel işlenmez.
  // Her chunk bir öncekinin tamamen diske yazılmasını bekler.
  Future<void> _receiveQueue = Future<void>.value();

  // Sender tarafında file-end gönderildikten sonra receiver'ın
  // gerçek tamamlanma ACK'i beklenir.
  bool _awaitingCompletionAck = false;

  // Aynı terminal event'in iki kez işlenmesini engeller.
  bool _terminalEventHandled = false;

  /// Aktif transferin ID'si.
  String? get currentTransferId => _transferId;

  /// Aktif transferin dosya adı.
  /// PrivateChatScreen, onProgress callback'i sırasında bu bilgiyi
  /// UI mesajına aktarabilmek için kullanır.
  String? get currentFileName => _fileName;

  /// Aktif transferin toplam dosya boyutu.
  int get currentFileSize => _fileSize;

  final List<RTCIceCandidate> _pendingIce = [];
  final List<RTCIceCandidate> _pendingLocalIce = [];
  bool _remoteDescriptionSet = false;

  void _diag(String message) {
    // ignore: avoid_print
    print('[FILE_TRANSFER] $message');
  }

  FileTransfer({
    required this.ws,
    required this.me,
    required this.peer,
    this.turnUsername,
    this.turnPassword,
    this.turnUrls = const [],
    this.onProgress,
    this.onIncomingOffer,
    this.onIncomingStatus,
  });

  static String _sharedKey(String me, String peer) =>
      '${me.trim().toLowerCase()}|${peer.trim().toLowerCase()}';

  static FileTransfer shared({
    required dynamic ws,
    required String me,
    required String peer,
    String? turnUsername,
    String? turnPassword,
    List<String> turnUrls = const [],
  }) {
    final key = _sharedKey(me, peer);

    final existing = _sharedTransfers[key];

    if (existing != null && !existing._disposed) {
      existing.turnUsername = turnUsername;
      existing.turnPassword = turnPassword;
      existing.turnUrls = List<String>.from(turnUrls);
      return existing;
    }

    final transfer = FileTransfer(
      ws: ws,
      me: me,
      peer: peer,
      turnUsername: turnUsername,
      turnPassword: turnPassword,
      turnUrls: List<String>.from(turnUrls),
    );

    _sharedTransfers[key] = transfer;
    return transfer;
  }

  void bindCallbacks({
    void Function({
      required String transferId,
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
    void Function({
      required String transferId,
      required String fileName,
      required int fileSize,
      required String sender,
    })?
    onIncomingOffer,
    void Function({required String transferId, required String status})?
    onIncomingStatus,
  }) {
    this.onProgress = onProgress;
    this.onIncomingOffer = onIncomingOffer;
    this.onIncomingStatus = onIncomingStatus;
  }

  void unbindCallbacks() {
    onProgress = null;
    onIncomingOffer = null;
    onIncomingStatus = null;
  }

  Future<void> initialize() async {
    if (_initialized || _disposed) return;

    _initialized = true;

    try {
      await _createPeer();
    } catch (_) {
      _initialized = false;
      rethrow;
    }
  }

  Future<String?> sendFile({File? sourceFile, String? sourceFileName}) async {
    File file;
    String fileName;

    if (sourceFile != null) {
      file = sourceFile;
      fileName = sourceFileName?.trim().isNotEmpty == true
          ? sourceFileName!.trim()
          : 'file';
    } else {
      final files = await FilePicker.pickFiles();

      if (files.isEmpty || files.first.path == null) return null;

      final selected = files.first;
      file = File(selected.path!);
      fileName = selected.name;
    }

    final size = await file.length();

    if (size <= 0) {
      throw StateError('Seçilen dosya boş.');
    }

    // Aynı peer ile devam eden transferi yeni gönderim ezmemeli.
    if (_transferId != null ||
        _sending ||
        _accepted ||
        _awaitingCompletionAck) {
      throw StateError('Bu sohbet için devam eden bir dosya transferi var.');
    }

    await _resetTransferState();

    await _createPeer();

    final transferId = '${DateTime.now().microsecondsSinceEpoch}-$me';

    _transferId = transferId;
    _fileName = fileName;
    _fileSize = size;

    await _flushLocalIce();
    _sentBytes = 0;
    _sendingFile = file;
    _sending = false;

    onProgress?.call(
      transferId: transferId,
      sentBytes: 0,
      totalBytes: size,
      status: 'waiting',
    );

    ws.send({
      'type': 'fileTransferOffer',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'fileName': _fileName,
      'fileSize': size,
    });

    return transferId;
  }

  /// Bildirimden açılan dosya transferi için alıcı state'ini
  /// yeniden oluşturur.
  ///
  /// Uygulama kapalıyken ilk metadata fileTransferOffer event'i
  /// kaçırılmış olabilir. Bildirim zaten transferId/fileName/fileSize
  /// taşıdığı için WebRTC transfer state'i burada yeniden hazırlanır.
  Future<bool> prepareIncomingFromNotification({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
  }) async {
    if (_disposed || transferId.trim().isEmpty) return false;

    final normalizedId = transferId.trim();

    // Socket event'i zaten gelip transfer hazırlanmışsa tekrar oluşturma.
    if (_transferId == normalizedId) {
      return true;
    }

    // Farklı bir aktif transfer varsa mevcut transferi ezme.
    if (_transferId != null &&
        _transferId!.isNotEmpty &&
        _transferId != normalizedId) {
      return false;
    }

    try {
      await _resetTransferState();
      await _createPeer();

      _transferId = normalizedId;
      _fileName = fileName.trim().isEmpty ? 'received_file' : fileName.trim();
      _fileSize = fileSize > 0 ? fileSize : 0;

      if (_fileSize <= 0) {
        await _resetTransferState();
        return false;
      }

      _receivedBytes = 0;
      _accepted = false;

      await _flushLocalIce();

      _diag(
        'INCOMING_NOTIFICATION_PREPARED '
        'transfer=$normalizedId '
        'file=$_fileName '
        'size=$_fileSize '
        'sender=$sender',
      );

      return true;
    } catch (e) {
      _diag(
        'INCOMING_NOTIFICATION_PREPARE_FAILED '
        'transfer=$normalizedId error=$e',
      );

      await _resetTransferState();
      return false;
    }
  }

  Future<void> acceptIncoming(String transferId) async {
    if (_disposed) return;
    if (_transferId != transferId) return;

    try {
      // Kayıt konumunu sender'a ACCEPT göndermeden önce seç.
      // Böylece sender veri göndermeye başladığında receiver hazır olur.
      if (!_nativeFileOpen) {
        await _openOutput();
      }

      _accepted = true;

      onIncomingStatus?.call(transferId: transferId, status: 'accepting');

      ws.send({
        'type': 'fileTransferAccept',
        'from': me,
        'to': peer,
        'transferId': transferId,
      });
    } catch (e) {
      _accepted = false;

      onIncomingStatus?.call(transferId: transferId, status: 'failed');
    }
  }

  Future<void> rejectIncoming(String transferId) async {
    if (_disposed) return;
    if (_transferId != transferId) return;

    onIncomingStatus?.call(transferId: transferId, status: 'rejected');

    ws.send({
      'type': 'fileTransferReject',
      'from': me,
      'to': peer,
      'transferId': transferId,
    });

    await _resetTransferState();
  }

  Future<void> _startOutgoingTransfer() async {
    if (_sending || _disposed) return;

    final file = _sendingFile;
    final transferId = _transferId;

    if (file == null || transferId == null) return;

    _sending = true;
    _sendLoopStarted = false;
    _terminalEventHandled = false;
    _awaitingCompletionAck = false;

    _diag('CREATE_DATA_CHANNEL transfer=$transferId');

    final channel = await _pc!.createDataChannel(
      'file-$transferId',
      RTCDataChannelInit()..ordered = true,
    );

    _channel = channel;

    _diag('DATA_CHANNEL_CREATED label=${channel.label}');

    channel.onDataChannelState = (state) {
      _diag('OUTGOING_DATA_CHANNEL: $state');

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _diag('DATA_CHANNEL_OPEN -> SEND_START');

        // OPEN event'i birden fazla kez gelebilir.
        // Aynı dosyanın ikinci kez gönderilmesini engelle.
        if (!_sendLoopStarted) {
          _sendLoopStarted = true;
          unawaited(_sendFileBytes(file));
        }
      }
    };

    _diag('CREATE_OFFER');

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 0,
      'offerToReceiveVideo': 0,
    });

    _diag(
      'OFFER_CREATED '
      'type=${offer.type} sdpLength=${offer.sdp?.length ?? 0}',
    );

    await _pc!.setLocalDescription(offer);

    _diag('LOCAL_DESCRIPTION_SET');

    ws.send({
      'type': 'fileTransferOffer',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'fileName': _fileName,
      'fileSize': _fileSize,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });

    onProgress?.call(
      transferId: transferId,
      sentBytes: 0,
      totalBytes: _fileSize,
      status: 'connecting',
    );
  }

  Future<void> _sendFileBytes(File file) async {
    final channel = _channel;
    final transferId = _transferId;

    if (channel == null || transferId == null) return;

    // Transfer state artık geçerli değilse eski async gönderim
    // kesinlikle yeni transferin kanalını kullanmamalı.
    if (_terminalEventHandled || _disposed) return;

    final raf = await file.open();

    try {
      // WebRTC DataChannel mesaj boyutunu küçük tut.
      // 16 KB, farklı Android/WebRTC SCTP sınırlarında güvenli
      // bir dosya transfer parçasıdır.
      const chunkSize = 16 * 1024;

      while (true) {
        if (_disposed || _transferId != transferId) return;

        final bytes = await raf.read(chunkSize);

        if (bytes.isEmpty) break;

        while (await channel.getBufferedAmount() > 4 * 1024 * 1024) {
          await Future<void>.delayed(const Duration(milliseconds: 20));

          if (_disposed || _transferId != transferId) return;
        }

        await channel.send(
          RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)),
        );

        _sentBytes += bytes.length;

        onProgress?.call(
          transferId: transferId,
          sentBytes: _sentBytes,
          totalBytes: _fileSize,
          status: 'transferring',
        );
      }

      // file-end yalnızca gönderimin bittiğini bildirir.
      // Receiver gerçek dosya boyutunu doğrulayıp native stream'i
      // kapattıktan sonra fileTransferComplete gönderir.
      // ACK bekleme durumu file-end GÖNDERİLMEDEN önce aktif edilmeli.
      // Receiver çok hızlı şekilde completion gönderebilir.
      _awaitingCompletionAck = true;

      await channel.send(
        RTCDataChannelMessage(
          '{"type":"file-end","transferId":"$transferId","size":$_fileSize}',
        ),
      );

      onProgress?.call(
        transferId: transferId,
        sentBytes: _fileSize,
        totalBytes: _fileSize,
        status: 'transferring',
      );
    } catch (e) {
      onProgress?.call(
        transferId: transferId,
        sentBytes: _sentBytes,
        totalBytes: _fileSize,
        status: 'failed',
      );
    } finally {
      await raf.close();
    }
  }

  Future<void> _createPeer() async {
    await _eventsSub?.cancel();
    await _pc?.close();

    _pendingIce.clear();
    _pendingLocalIce.clear();
    _remoteDescriptionSet = false;

    final iceServers = <Map<String, dynamic>>[
      {
        'urls': ['stun:stun.l.google.com:19302', 'stun:92.5.38.220:3478'],
      },
    ];

    if (turnUsername != null &&
        turnUsername!.isNotEmpty &&
        turnPassword != null &&
        turnPassword!.isNotEmpty &&
        turnUrls.isNotEmpty) {
      iceServers.add({
        'urls': turnUrls,
        'username': turnUsername,
        'credential': turnPassword,
      });
    }

    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'iceTransportPolicy': 'all',
    });

    // WebRTC bağlantı teşhisi.
    // ignore: avoid_print
    print('[FILE_TRANSFER] PEER_CREATED');

    _pc!.onIceGatheringState = (state) {
      // ignore: avoid_print
      print('[FILE_TRANSFER] ICE_GATHERING: $state');
    };

    _pc!.onIceConnectionState = (state) {
      // ignore: avoid_print
      print('[FILE_TRANSFER] ICE_CONNECTION: $state');
    };

    _pc!.onConnectionState = (state) {
      // ignore: avoid_print
      print('[FILE_TRANSFER] PEER_CONNECTION: $state');
    };

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null) {
        return;
      }

      final transferId = _transferId;

      if (transferId == null) {
        _pendingLocalIce.add(candidate);
        return;
      }

      _sendLocalIceCandidate(candidate, transferId);
    };

    _pc!.onDataChannel = (channel) {
      _diag(
        'INCOMING_DATA_CHANNEL '
        'label=${channel.label}',
      );

      _channel = channel;

      channel.onDataChannelState = (state) {
        _diag('INCOMING_DATA_CHANNEL_STATE: $state');
      };

      channel.onMessage = (message) {
        _diag(
          'INCOMING_DATA '
          'binary=${message.isBinary} '
          'size=${message.isBinary ? message.binary.length : message.text.length}',
        );

        // KRİTİK:
        // DataChannel callback'i her chunk için paralel çalışabilir.
        // Native OutputStream'e aynı anda write yapılması dosyayı
        // bozabileceği için tüm chunk'ları tek bir FIFO kuyruğunda
        // sırayla işliyoruz.
        _receiveQueue = _receiveQueue
            .then((_) => _receiveChunk(message))
            .catchError((error, stack) {
              _diag('RECEIVE_QUEUE_ERROR: $error');
              if (!_disposed && _transferId != null) {
                onIncomingStatus?.call(
                  transferId: _transferId!,
                  status: 'failed',
                );
              }
            });
      };
    };

    _eventsSub = ws.events.listen(_handleEvent);
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    if (_disposed) return;

    final type = event['type']?.toString();

    final from = (event['from'] ?? '').toString().trim();
    final to = (event['to'] ?? '').toString().trim();

    if (type == 'turnCredentials') {
      final username = (event['username'] ?? '').toString().trim();
      final credential = (event['credential'] ?? '').toString();
      final rawUrls = event['urls'];

      if (username.isNotEmpty && credential.isNotEmpty && rawUrls is List) {
        final urls = rawUrls
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false);

        if (urls.isNotEmpty) {
          turnUsername = username;
          turnPassword = credential;
          turnUrls = urls;
        }
      }

      return;
    }

    if (from.isNotEmpty && from.toLowerCase() != peer.toLowerCase()) {
      return;
    }

    if (to.isNotEmpty && to.toLowerCase() != me.toLowerCase()) {
      return;
    }

    if (type == 'fileTransferOffer') {
      final incomingId = event['transferId']?.toString();

      if (incomingId == null || incomingId.isEmpty) return;

      final hasSdp = event['sdp'] != null;

      // İlk offer yalnızca metadata taşır. Bu event geldiğinde
      // alıcı taraf transfer kaydını oluşturur ve kullanıcıdan
      // kabul/red kararı bekler.
      if (!hasSdp) {
        if (_transferId != null &&
            _transferId!.isNotEmpty &&
            _transferId != incomingId) {
          return;
        }

        await _prepareIncomingOffer(event);
        return;
      }

      // Kabul sonrasında gelen SDP offer aynı transfer ID'sine
      // ait olmalıdır.
      if (incomingId != _transferId) return;

      await _handleOfferSdp(event);
      return;
    }

    if (event['transferId']?.toString() != _transferId) {
      return;
    }

    switch (type) {
      case 'fileTransferAccept':
        if (from.toLowerCase() == peer.toLowerCase()) {
          if (_sendingFile == null || _transferId == null) return;
          if (_sending) return;

          await _startOutgoingTransfer();
        }
        break;

      case 'fileTransferReject':
        if (_transferId == null || _transferId!.isEmpty) return;

        if (_terminalEventHandled) return;
        _terminalEventHandled = true;

        onProgress?.call(
          transferId: _transferId!,
          sentBytes: _sentBytes,
          totalBytes: _fileSize,
          status: 'rejected',
        );

        await _resetTransferState();
        break;

      case 'fileTransferAnswer':
        await _handleAnswer(event);
        break;

      case 'fileTransferIce':
        await _handleIce(event);
        break;

      case 'fileTransferComplete':
        await _handleRemoteCompletion(event);
        break;

      case 'fileTransferFailed':
        await _handleRemoteFailure(event);
        break;
    }
  }

  Future<void> _prepareIncomingOffer(Map<String, dynamic> event) async {
    final incomingId = event['transferId']?.toString();

    if (incomingId == null || incomingId.isEmpty) return;

    await _resetTransferState();
    await _createPeer();

    _transferId = incomingId;
    await _flushLocalIce();

    _fileName = event['fileName']?.toString() ?? 'received_file';

    final rawSize = event['fileSize'];
    _fileSize = rawSize is num
        ? rawSize.toInt()
        : int.tryParse(rawSize?.toString() ?? '') ?? 0;

    _receivedBytes = 0;
    _accepted = false;

    onIncomingOffer?.call(
      transferId: incomingId,
      fileName: _fileName!,
      fileSize: _fileSize,
      sender: peer,
    );
  }

  Future<void> _handleOfferSdp(Map<String, dynamic> event) async {
    if (!_accepted) return;

    final sdpData = event['sdp'];

    if (sdpData is! Map) return;

    final sdp = Map<String, dynamic>.from(sdpData);

    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'], sdp['type']),
    );

    _remoteDescriptionSet = true;

    await _flushPendingIce();

    final answer = await _pc!.createAnswer({
      'offerToReceiveAudio': 0,
      'offerToReceiveVideo': 0,
    });

    await _pc!.setLocalDescription(answer);

    ws.send({
      'type': 'fileTransferAnswer',
      'from': me,
      'to': peer,
      'transferId': _transferId,
      'sdp': {'type': answer.type, 'sdp': answer.sdp},
    });

    onIncomingStatus?.call(transferId: _transferId!, status: 'transferring');
  }

  Future<void> _handleAnswer(Map<String, dynamic> event) async {
    final sdpData = event['sdp'];

    if (sdpData is! Map) return;

    final sdp = Map<String, dynamic>.from(sdpData);

    await _pc?.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'], sdp['type']),
    );

    _remoteDescriptionSet = true;

    await _flushPendingIce();
  }

  void _sendLocalIceCandidate(RTCIceCandidate candidate, String transferId) {
    ws.send({
      'type': 'fileTransferIce',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  Future<void> _flushLocalIce() async {
    final transferId = _transferId;

    if (transferId == null || transferId.isEmpty) {
      return;
    }

    final pending = List<RTCIceCandidate>.from(_pendingLocalIce);
    _pendingLocalIce.clear();

    for (final candidate in pending) {
      _sendLocalIceCandidate(candidate, transferId);
    }
  }

  Future<void> _handleIce(Map<String, dynamic> event) async {
    final candidateData = event['candidate'];

    if (candidateData is! Map) return;

    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );

    if (!_remoteDescriptionSet) {
      _pendingIce.add(candidate);
      return;
    }

    try {
      await _pc?.addCandidate(candidate);
    } catch (_) {}
  }

  Future<void> _flushPendingIce() async {
    if (!_remoteDescriptionSet || _pc == null) return;

    final pending = List<RTCIceCandidate>.from(_pendingIce);

    _pendingIce.clear();

    for (final candidate in pending) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (_) {}
    }
  }

  Future<void> _receiveChunk(RTCDataChannelMessage message) async {
    final transferId = _transferId;

    if (transferId == null || !_accepted || _disposed) {
      return;
    }

    if (message.isBinary) {
      try {
        final bytes = message.binary;

        if (bytes.isEmpty) {
          return;
        }

        if (!_nativeFileOpen) {
          await _openOutput();
        }

        final written = await _systemChannel.invokeMethod<bool>(
          'writeIncomingFile',
          bytes,
        );

        if (written != true) {
          throw StateError('Dosya verisi diske yazılamadı.');
        }

        _receivedBytes += bytes.length;

        // Dosya boyutunu aşan veri kesinlikle kabul edilmez.
        if (_receivedBytes > _fileSize) {
          throw StateError('Alınan veri beklenen dosya boyutunu aştı.');
        }

        onProgress?.call(
          transferId: transferId,
          sentBytes: _receivedBytes,
          totalBytes: _fileSize,
          status: 'transferring',
        );
      } catch (e) {
        _diag('RECEIVE_BINARY_FAILED: $e');

        await _failIncomingTransfer(
          transferId,
          'Dosya verisi alınırken hata oluştu.',
        );
      }

      return;
    }

    final data = message.text;

    Map<String, dynamic>? control;

    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) {
        control = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Geçersiz kontrol mesajı.
      return;
    }

    if (control == null) return;

    if (control['type']?.toString() != 'file-end') {
      return;
    }

    if (control['transferId']?.toString() != transferId) {
      return;
    }

    if (_terminalEventHandled) {
      return;
    }

    _terminalEventHandled = true;

    final declaredSize =
        int.tryParse(control['size']?.toString() ?? '') ?? _fileSize;

    try {
      if (declaredSize != _fileSize) {
        throw StateError('Gönderici dosya boyutu uyuşmuyor.');
      }

      if (_receivedBytes != _fileSize) {
        throw StateError(
          'Eksik dosya alındı: $_receivedBytes / $_fileSize byte.',
        );
      }

      final closed = await _systemChannel.invokeMethod<bool>(
        'closeIncomingFile',
      );

      _nativeFileOpen = false;

      if (closed != true) {
        throw StateError('Dosya kayıt akışı kapatılamadı.');
      }

      // Artık dosya gerçekten diske yazıldı ve kapatıldı.
      // Ancak bundan SONRA sender'a completion ACK gönderiyoruz.
      ws.send({
        'type': 'fileTransferComplete',
        'from': me,
        'to': peer,
        'transferId': transferId,
        'fileSize': _receivedBytes,
      });

      onProgress?.call(
        transferId: transferId,
        sentBytes: _receivedBytes,
        totalBytes: _fileSize,
        status: 'completed',
      );

      onIncomingStatus?.call(transferId: transferId, status: 'completed');

      await _resetTransferState();
    } catch (e) {
      _diag('RECEIVE_FINALIZE_FAILED: $e');

      await _failIncomingTransfer(
        transferId,
        'Dosya doğrulanamadı veya tamamlanamadı.',
        reset: true,
      );
    }
  }

  Future<void> _handleRemoteCompletion(Map<String, dynamic> event) async {
    final transferId = event['transferId']?.toString();

    if (transferId == null ||
        transferId.isEmpty ||
        transferId != _transferId ||
        !_awaitingCompletionAck ||
        _terminalEventHandled) {
      return;
    }

    _terminalEventHandled = true;
    _awaitingCompletionAck = false;

    final remoteSize = int.tryParse(event['fileSize']?.toString() ?? '') ?? 0;

    if (remoteSize != _fileSize) {
      onProgress?.call(
        transferId: transferId,
        sentBytes: _sentBytes,
        totalBytes: _fileSize,
        status: 'failed',
      );

      onIncomingStatus?.call(transferId: transferId, status: 'failed');

      await _resetTransferState();
      return;
    }

    onProgress?.call(
      transferId: transferId,
      sentBytes: _fileSize,
      totalBytes: _fileSize,
      status: 'completed',
    );

    await _resetTransferState();
  }

  Future<void> _handleRemoteFailure(Map<String, dynamic> event) async {
    final transferId = event['transferId']?.toString();

    if (transferId == null || transferId.isEmpty || transferId != _transferId) {
      return;
    }

    if (_terminalEventHandled) return;

    _terminalEventHandled = true;

    onProgress?.call(
      transferId: transferId,
      sentBytes: _sentBytes,
      totalBytes: _fileSize,
      status: 'failed',
    );

    await _resetTransferState();
  }

  Future<void> _failIncomingTransfer(
    String transferId,
    String reason, {
    bool reset = false,
  }) async {
    if (_terminalEventHandled && !reset) return;

    _terminalEventHandled = true;

    _diag('INCOMING_TRANSFER_FAILED: $reason');

    try {
      await _systemChannel.invokeMethod<bool>('closeIncomingFile');
    } catch (_) {}

    _nativeFileOpen = false;

    ws.send({
      'type': 'fileTransferFailed',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'reason': reason,
    });

    onProgress?.call(
      transferId: transferId,
      sentBytes: _receivedBytes,
      totalBytes: _fileSize,
      status: 'failed',
    );

    onIncomingStatus?.call(transferId: transferId, status: 'failed');

    if (reset) {
      await _resetTransferState();
    }
  }

  Future<void> _openOutput() async {
    final safeName = (_fileName ?? 'received_file').replaceAll(
      RegExp(r'[/\\]'),
      '_',
    );

    final result = await _systemChannel.invokeMethod<dynamic>(
      'requestIncomingFileSave',
      <String, dynamic>{'fileName': safeName},
    );

    if (result == null) {
      throw StateError('Dosya kayıt konumu seçilmedi.');
    }

    _nativeFileOpen = true;
  }

  Future<void> _resetTransferState() async {
    if (_disposed) return;

    if (_nativeFileOpen) {
      try {
        await _systemChannel.invokeMethod<bool>('closeIncomingFile');
      } catch (_) {}

      _nativeFileOpen = false;
    }

    _channel = null;
    _pendingIce.clear();
    _pendingLocalIce.clear();
    _remoteDescriptionSet = false;

    _transferId = null;
    _fileName = null;
    _fileSize = 0;
    _receivedBytes = 0;
    _sentBytes = 0;

    _sendingFile = null;
    _sending = false;
    _sendLoopStarted = false;
    _accepted = false;

    _receiveQueue = Future<void>.value();
    _awaitingCompletionAck = false;
    _terminalEventHandled = false;

    await _pc?.close();
    _pc = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    await _eventsSub?.cancel();

    if (_nativeFileOpen) {
      try {
        await _systemChannel.invokeMethod<bool>('closeIncomingFile');
      } catch (_) {}

      _nativeFileOpen = false;
    }

    await _pc?.close();

    _eventsSub = null;
    _channel = null;
    _pc = null;

    _pendingIce.clear();
    _pendingLocalIce.clear();
    _remoteDescriptionSet = false;

    _transferId = null;
    _fileName = null;
    _fileSize = 0;
    _receivedBytes = 0;
    _sentBytes = 0;

    _sendingFile = null;
    _sending = false;
    _sendLoopStarted = false;
    _accepted = false;

    _initialized = false;

    _sharedTransfers.remove(_sharedKey(me, peer));
  }
}
