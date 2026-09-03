import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

class FileTransfer {
  static const MethodChannel _systemChannel =
      MethodChannel('zerolog/system');
  static const MethodChannel _backgroundSystemChannel =
      MethodChannel('zerolog/background_transfer');
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

  void Function({
    required String transferId,
    required String status,
    String? localUri,
  })?
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

  // Aynı signaling event'in pending queue + canlı socket üzerinden
  // iki kez uygulanmasını engeller.
  final Set<String> _processedSignalEvents = <String>{};

  // Signal sequence değeri transfer bazında takip edilir.
  // Farklı transferlerin seq değerleri birbirleriyle karşılaştırılmaz.
  final Map<String, int> _lastSignalSeqByTransfer = <String, int>{};

  String? _transferId;
  String? _fileName;
  int _fileSize = 0;
  int _receivedBytes = 0;
  int _sentBytes = 0;

  bool _nativeFileOpen = false;

  static bool backgroundTransferMode = false;

  File? _backgroundOutputFile;
  RandomAccessFile? _backgroundOutput;

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

  // Aktif transferin rolü açıkça tutulur.
  // _sending üzerinden rol tahmini yapılmaz.
  bool _incomingTransfer = false;

  // Eski async operasyonların yeni transfer state'ine dokunmasını engeller.
  int _transferGeneration = 0;

  // Sonlandırılmış transferlerin gecikmiş/duplicate signaling
  // event'leri ile yeniden başlamasını engeller.
  final Map<String, DateTime> _terminalTransferTombstones =
      <String, DateTime>{};

  static const Duration _terminalTransferTombstoneTtl = Duration(minutes: 10);

  Timer? _connectionTimeoutTimer;
  Timer? _transferTimeoutTimer;
  Timer? _finalizeTimeoutTimer;

  String? _sourceSha256;
  String? _remoteSha256;

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

  // Remote transfer state henüz oluşturulmadan gelen ICE'leri
  // transferId bazında kaybetmeden tut.
  final Map<String, List<RTCIceCandidate>> _earlyRemoteIce =
      <String, List<RTCIceCandidate>>{};

  // Aynı ICE candidate'in tekrar uygulanmasını engeller.
  final Set<String> _receivedIceFingerprints = <String>{};

  bool _remoteDescriptionSet = false;

  void _diag(String message) {
    // ignore: avoid_print
    print('[FILE_TRANSFER] $message');
  }

  void _cleanupTerminalTransferTombstones() {
    final now = DateTime.now();

    _terminalTransferTombstones.removeWhere(
      (_, timestamp) =>
          now.difference(timestamp) > _terminalTransferTombstoneTtl,
    );
  }

  void _markTransferTerminal(String transferId) {
    final id = transferId.trim();

    if (id.isEmpty) return;

    _cleanupTerminalTransferTombstones();
    _terminalTransferTombstones[id] = DateTime.now();

    if (_terminalTransferTombstones.length > 256) {
      final oldest = _terminalTransferTombstones.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );

      _terminalTransferTombstones.remove(oldest.key);
    }
  }

  bool _isTerminalTransfer(String transferId) {
    final id = transferId.trim();

    if (id.isEmpty) return false;

    _cleanupTerminalTransferTombstones();

    return _terminalTransferTombstones.containsKey(id);
  }

  void _cancelTransferTimers() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;

    _transferTimeoutTimer?.cancel();
    _transferTimeoutTimer = null;

    _finalizeTimeoutTimer?.cancel();
    _finalizeTimeoutTimer = null;
  }

  void _startFinalizeTimeout(String transferId) {
    _finalizeTimeoutTimer?.cancel();

    _finalizeTimeoutTimer = Timer(const Duration(minutes: 5), () {
      if (_disposed || _transferId != transferId || _terminalEventHandled) {
        return;
      }

      _diag('FINALIZE_TIMEOUT transfer=$transferId');

      unawaited(
        _failTransfer(
          transferId,
          'Dosya doğrulama veya kayıt işlemi 5 dakika içinde tamamlanmadı.',
          reset: true,
          incoming: true,
        ),
      );
    });
  }

  void _startConnectionTimeout(String transferId, {bool incoming = false}) {
    _connectionTimeoutTimer?.cancel();

    _connectionTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_disposed || _transferId != transferId || _terminalEventHandled) {
        return;
      }

      _diag('CONNECTION_TIMEOUT transfer=$transferId');

      unawaited(
        _failTransfer(
          transferId,
          'Dosya bağlantısı zaman aşımına uğradı.',
          reset: true,
          incoming: incoming,
        ),
      );
    });
  }

  void _startTransferTimeout(String transferId, {bool incoming = false}) {
    _transferTimeoutTimer?.cancel();

    // Bu artık toplam transfer süresi değildir.
    // Sadece veri akışı tamamen durursa transferi sonlandırır.
    //
    // Büyük dosyalar, yavaş bağlantılar ve TURN üzerinden aktarımlar
    // 5 dakikayı aşabilir. Veri gelmeye/gönderilmeye devam ettiği sürece
    // timeout sürekli yenilenir.
    _transferTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_disposed || _transferId != transferId || _terminalEventHandled) {
        return;
      }

      _diag(
        'TRANSFER_INACTIVITY_TIMEOUT '
        'transfer=$transferId '
        'incoming=$incoming',
      );

      unawaited(
        _failTransfer(
          transferId,
          'Dosya aktarımı 60 saniye boyunca ilerlemedi.',
          reset: true,
          incoming: incoming,
        ),
      );
    });
  }

  void _touchTransferTimeout(String transferId, {required bool incoming}) {
    if (_disposed || _transferId != transferId || _terminalEventHandled) {
      return;
    }

    _startTransferTimeout(transferId, incoming: incoming);
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
    void Function({
      required String transferId,
      required String status,
      String? localUri,
    })?
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

  Future<void> _startBackgroundTransferService() async {
    if (_disposed || backgroundTransferMode) return;

    try {
      await _systemChannel.invokeMethod<bool>(
        'startFileTransferForegroundService',
      );
    } catch (_) {}
  }

  Future<void> _stopBackgroundTransferService() async {
    try {
      await _systemChannel.invokeMethod<bool>(
        'stopFileTransferForegroundService',
      );
    } catch (_) {}
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
    unawaited(_startBackgroundTransferService());
    _fileName = fileName;
    _fileSize = size;

    _sentBytes = 0;
    _sendingFile = file;
    _sending = false;

    // Transfer başlamadan önce kaynak dosyanın SHA-256 değerini hesapla.
    _sourceSha256 = await _calculateFileSha256(file);
    _remoteSha256 = null;

    onProgress?.call(
      transferId: transferId,
      sentBytes: 0,
      totalBytes: size,
      status: 'waiting',
    );

    /*
     * KRİTİK SIGNALING SIRASI:
     *
     * _createPeer() sırasında ICE candidate oluşmuş olabilir.
     * Ancak alıcı taraf henüz fileTransferOffer metadata'sını
     * almadan transfer state'ini oluşturmaz.
     *
     * Bu nedenle pending ICE candidate'ları metadata offer'dan
     * ÖNCE göndermek hatalıdır:
     *
     *   ICE(seq=1)
     *   OFFER(seq=2)
     *
     * Alıcı ICE event'ini transfer state oluşmadan aldığı için
     * düşürebilir.
     *
     * Doğru sıra:
     *
     *   OFFER(metadata)
     *   ICE...
     *
     * SDP offer daha sonra _startOutgoingTransfer() içinde
     * oluşturulur ve gönderilir.
     */
    ws.send({
      'type': 'fileTransferOffer',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'fileName': _fileName,
      'fileSize': size,
    });

    // Metadata offer artık server/client signaling zincirine
    // girdi. Bundan sonra oluşturulmuş ICE candidate'ları gönder.
    await _flushLocalIce();

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
      // Headless background isolate yeni FileTransfer örneğiyle gelir.
      // Burada reset çağrısı foreground service'i durdurmamalıdır.
      if (!backgroundTransferMode) {
        await _resetTransferState();
      }

      _incomingTransfer = true;

      // Bildirimden/arka plandan gelen transferde WebRTC peer'i
      // oluşturmadan önce foreground service'i başlat.
      await _startBackgroundTransferService();

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

      _startConnectionTimeout(normalizedId, incoming: true);

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

      _diag('ACCEPT_FAILED transfer=$transferId error=$e');

      ws.send({
        'type': 'fileTransferFailed',
        'from': me,
        'to': peer,
        'transferId': transferId,
        'reason': 'Dosya kayıt konumu açılamadı.',
      });

      onIncomingStatus?.call(transferId: transferId, status: 'failed');

      await _resetTransferState();
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

    final generation = _transferGeneration;

    if (_transferId != transferId ||
        generation != _transferGeneration ||
        _disposed ||
        _terminalEventHandled) {
      return;
    }

    _sending = true;
    _sendLoopStarted = false;
    _terminalEventHandled = false;
    _awaitingCompletionAck = false;

    _startConnectionTimeout(transferId);

    _diag('CREATE_DATA_CHANNEL transfer=$transferId');

    final channel = await _pc!.createDataChannel(
      'file-$transferId',
      RTCDataChannelInit()..ordered = true,
    );

    if (_disposed ||
        _transferId != transferId ||
        generation != _transferGeneration ||
        _terminalEventHandled) {
      try {
        await channel.close();
      } catch (_) {}
      return;
    }

    _channel = channel;

    _diag('DATA_CHANNEL_CREATED label=${channel.label}');

    channel.onDataChannelState = (state) {
      _diag('OUTGOING_DATA_CHANNEL: $state');

      if (_disposed || _transferId != transferId) {
        return;
      }

      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;

        _startTransferTimeout(transferId);

        _diag('DATA_CHANNEL_OPEN -> SEND_START');

        // OPEN event'i birden fazla kez gelebilir.
        // Aynı dosyanın ikinci kez gönderilmesini engelle.
        if (!_sendLoopStarted) {
          _sendLoopStarted = true;
          unawaited(_sendFileBytes(file, generation: generation));
        }
      } else if (state == RTCDataChannelState.RTCDataChannelClosing ||
          state == RTCDataChannelState.RTCDataChannelClosed) {
        // file-end gönderildiyse kanal kapanışı beklenen sonlandırma
        // olabilir. Completion ACK gelene kadar FAILED üretme.
        if (_awaitingCompletionAck) {
          _diag(
            'OUTGOING_DATA_CHANNEL_CLOSED_WAITING_COMPLETION '
            'transfer=$transferId',
          );
          return;
        }

        if (!_terminalEventHandled) {
          _diag('OUTGOING_DATA_CHANNEL_CLOSED transfer=$transferId');

          unawaited(
            _failTransfer(
              transferId,
              'Dosya veri kanalı kapandı.',
              reset: true,
            ),
          );
        }
      }
    };

    if (_disposed ||
        _transferId != transferId ||
        generation != _transferGeneration ||
        _terminalEventHandled) {
      return;
    }

    _diag('CREATE_OFFER');

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 0,
      'offerToReceiveVideo': 0,
    });

    _diag(
      'OFFER_CREATED '
      'type=${offer.type} sdpLength=${offer.sdp?.length ?? 0}',
    );

    if (_disposed ||
        _transferId != transferId ||
        generation != _transferGeneration ||
        _terminalEventHandled) {
      return;
    }

    await _pc!.setLocalDescription(offer);

    if (_disposed ||
        _transferId != transferId ||
        generation != _transferGeneration ||
        _terminalEventHandled) {
      return;
    }

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

  Future<void> _sendFileBytes(File file, {required int generation}) async {
    final channel = _channel;
    final transferId = _transferId;

    if (channel == null || transferId == null) return;

    if (generation != _transferGeneration ||
        _transferId != transferId ||
        _disposed ||
        _terminalEventHandled) {
      return;
    }

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
        if (_disposed ||
            _transferId != transferId ||
            generation != _transferGeneration) {
          return;
        }

        final bytes = await raf.read(chunkSize);

        if (bytes.isEmpty) break;

        final backpressureDeadline = DateTime.now().add(
          const Duration(seconds: 30),
        );

        while (await channel.getBufferedAmount() > 4 * 1024 * 1024) {
          if (_disposed ||
              _transferId != transferId ||
              generation != _transferGeneration) {
            return;
          }

          if (DateTime.now().isAfter(backpressureDeadline)) {
            throw StateError('DataChannel gönderim tamponu boşalmadı.');
          }

          await Future<void>.delayed(const Duration(milliseconds: 20));

          _touchTransferTimeout(transferId, incoming: false);
        }

        await channel.send(
          RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)),
        );

        if (_disposed ||
            _transferId != transferId ||
            generation != _transferGeneration) {
          return;
        }

        _sentBytes += bytes.length;

        _touchTransferTimeout(transferId, incoming: false);

        onProgress?.call(
          transferId: transferId,
          sentBytes: _sentBytes,
          totalBytes: _fileSize,
          status: 'transferring',
        );
      }

      if (_disposed ||
          _transferId != transferId ||
          generation != _transferGeneration) {
        return;
      }

      // file-end yalnızca gönderimin bittiğini bildirir.
      // Receiver gerçek dosya boyutunu doğrulayıp native stream'i
      // kapattıktan sonra fileTransferComplete gönderir.
      // ACK bekleme durumu file-end GÖNDERİLMEDEN önce aktif edilmeli.
      // Receiver çok hızlı şekilde completion gönderebilir.
      if (_disposed ||
          _transferId != transferId ||
          generation != _transferGeneration ||
          _terminalEventHandled) {
        return;
      }

      // ACK bekleme durumu file-end gönderilmeden hemen önce aktif edilir.
      // Böylece hızlı receiver completion gönderse bile event kaybolmaz.
      _awaitingCompletionAck = true;

      try {
        await channel.send(
          RTCDataChannelMessage(
            jsonEncode({
              'type': 'file-end',
              'transferId': transferId,
              'size': _fileSize,
              'sha256': _sourceSha256,
            }),
          ),
        );
      } catch (e) {
        _awaitingCompletionAck = false;
        rethrow;
      }

      if (_disposed ||
          _transferId != transferId ||
          generation != _transferGeneration) {
        return;
      }

      if (!_awaitingCompletionAck) {
        return;
      }

      onProgress?.call(
        transferId: transferId,
        sentBytes: _fileSize,
        totalBytes: _fileSize,
        status: 'transferring',
      );
    } catch (e) {
      _diag('SEND_BINARY_FAILED: $e');

      await _failTransfer(
        transferId,
        'Dosya verisi gönderilirken hata oluştu.',
        reset: true,
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
    _earlyRemoteIce.clear();
    _receivedIceFingerprints.clear();
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

      if (_disposed || _transferId == null) return;

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        final transferId = _transferId!;

        // file-end gönderildikten sonra WebRTC bağlantısının kapanması
        // tek başına başarısızlık değildir. Alıcı gerçek sonucu
        // fileTransferComplete ile bildirir.
        if (_awaitingCompletionAck) {
          _diag(
            'PEER_CONNECTION_CLOSED_WAITING_COMPLETION '
            'transfer=$transferId',
          );
          return;
        }

        if (!_terminalEventHandled) {
          unawaited(
            _failTransfer(
              transferId,
              'Dosya bağlantısı koptu.',
              reset: true,
              incoming: _incomingTransfer,
            ),
          );
        }
      }
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

        if (_disposed || _transferId == null) {
          return;
        }

        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _connectionTimeoutTimer?.cancel();
          _connectionTimeoutTimer = null;

          _startTransferTimeout(_transferId!, incoming: true);
        } else if (state == RTCDataChannelState.RTCDataChannelClosing ||
            state == RTCDataChannelState.RTCDataChannelClosed) {
          final transferId = _transferId!;

          if (!_terminalEventHandled) {
            _diag('INCOMING_DATA_CHANNEL_CLOSED transfer=$transferId');

            unawaited(
              _failTransfer(
                transferId,
                'Dosya veri kanalı kapandı.',
                reset: true,
                incoming: true,
              ),
            );
          }
        }
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

              final transferId = _transferId;
              if (_disposed || transferId == null || _terminalEventHandled) {
                return;
              }

              unawaited(
                _failTransfer(
                  transferId,
                  'Dosya alımı sırasında beklenmeyen bir hata oluştu.',
                  reset: true,
                  incoming: true,
                ),
              );
            });
      };
    };

    _eventsSub = ws.events.listen(_handleEvent);
  }

  /// Headless/background transfer dispatcher.
  ///
  /// WsClient uses a broadcast stream, so the background isolate may
  /// temporarily capture events before FileTransfer has attached its
  /// normal listener. This public bridge lets the headless entry point
  /// replay those events safely after the transfer state is prepared.
  Future<void> handleExternalEvent(Map<String, dynamic> event) async {
    await _handleEvent(event);
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

    final isFileSignal =
        type == 'fileTransferOffer' ||
        type == 'fileTransferAnswer' ||
        type == 'fileTransferIce' ||
        type == 'fileTransferAccept' ||
        type == 'fileTransferReject' ||
        type == 'fileTransferComplete' ||
        type == 'fileTransferFailed';

    if (isFileSignal) {
      final signalTransferId = (event['transferId'] ?? '').toString().trim();

      // Tamamlanmış/reddedilmiş/başarısız eski transferin
      // gecikmiş signaling'i yeni transfer başlatmasın.
      if (_transferId != signalTransferId &&
          _isTerminalTransfer(signalTransferId)) {
        _diag(
          'TERMINAL_TRANSFER_SIGNAL_IGNORED '
          'transfer=$signalTransferId type=$type',
        );
        return;
      }

      if (signalTransferId.isEmpty) return;

      final rawSeq = event['seq'];
      final seq = rawSeq is num
          ? rawSeq.toInt()
          : int.tryParse(rawSeq?.toString() ?? '') ?? 0;

      final signalKey = [
        signalTransferId,
        type ?? '',
        seq.toString(),
        from.toLowerCase(),
        jsonEncode(event),
      ].join('|');

      if (_processedSignalEvents.contains(signalKey)) {
        _diag(
          'SIGNAL_DUPLICATE_IGNORED '
          'transfer=$signalTransferId type=$type seq=$seq',
        );
        return;
      }

      _processedSignalEvents.add(signalKey);

      // Server pending queue's seq değerleri aynı transfer içinde
      // monotonik olduğundan, geriye dönük event tekrarlarını kabul etmiyoruz.
      // Sequence değerleri transferler arasında karşılaştırılmaz.
      final lastSeq = _lastSignalSeqByTransfer[signalTransferId] ?? 0;

      if (seq > 0 && seq < lastSeq) {
        _diag(
          'SIGNAL_OUT_OF_ORDER_IGNORED '
          'transfer=$signalTransferId type=$type seq=$seq '
          'last=$lastSeq',
        );
        return;
      }

      if (seq > 0) {
        _lastSignalSeqByTransfer[signalTransferId] = seq;
      }

      if (_processedSignalEvents.length > 512) {
        _processedSignalEvents.remove(_processedSignalEvents.first);
      }
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
        _markTransferTerminal(_transferId!);

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

    final incomingFileName =
        event['fileName']?.toString().trim().isNotEmpty == true
        ? event['fileName']!.toString().trim()
        : 'received_file';

    final rawSize = event['fileSize'];
    final incomingFileSize = rawSize is num
        ? rawSize.toInt()
        : int.tryParse(rawSize?.toString() ?? '') ?? 0;

    if (incomingFileSize <= 0) {
      _diag(
        'INCOMING_OFFER_INVALID_SIZE '
        'transfer=$incomingId size=$incomingFileSize',
      );
      return;
    }

    /*
     * Bildirimden gelen metadata ile transfer state'i daha önce
     * hazırlanmış olabilir. Aynı transferId tekrar geldiğinde state'i
     * sıfırlamak kesinlikle yapılmamalı.
     *
     * Özellikle:
     * FCM -> prepareIncomingFromNotification()
     * ardından
     * WebSocket -> fileTransferOffer
     *
     * sıralamasında reset yapılırsa kullanıcı ACCEPT verdikten sonra
     * native output ve WebRTC state'i kaybolabilir.
     */
    if (_transferId == incomingId) {
      _incomingTransfer = true;

      // Metadata'yı doğrula/güncelle; mevcut transfer state'ine dokunma.
      if (_fileName == null || _fileName!.isEmpty) {
        _fileName = incomingFileName;
      }

      if (_fileSize <= 0) {
        _fileSize = incomingFileSize;
      }

      if (_fileSize != incomingFileSize) {
        _diag(
          'INCOMING_OFFER_SIZE_MISMATCH '
          'transfer=$incomingId '
          'current=$_fileSize '
          'incoming=$incomingFileSize',
        );
        return;
      }

      _diag(
        'INCOMING_OFFER_DUPLICATE_METADATA_IGNORED '
        'transfer=$incomingId '
        'accepted=$_accepted',
      );

      // Transfer zaten hazırlanmışsa kullanıcıya ikinci kez teklif
      // gösterme. Böylece FCM + WebSocket çift bildirim yarışını
      // engelle.
      return;
    }

    // Başka bir aktif transfer varsa onu ezme.
    if (_transferId != null &&
        _transferId!.isNotEmpty &&
        _transferId != incomingId) {
      _diag(
        'INCOMING_OFFER_ACTIVE_TRANSFER_IGNORED '
        'current=$_transferId incoming=$incomingId',
      );
      return;
    }

    await _resetTransferState();

    _incomingTransfer = true;

    // Incoming WebRTC transferi peer kurulmadan önce servis tarafından
    // korunmalı; özellikle uygulama arka plandayken bu kritik.
    await _startBackgroundTransferService();

    await _createPeer();

    _transferId = incomingId;
    _fileName = incomingFileName;
    _fileSize = incomingFileSize;

    _receivedBytes = 0;
    _accepted = false;

    await _flushLocalIce();

    _startConnectionTimeout(incomingId, incoming: true);

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
    await _flushEarlyRemoteIce(_transferId!);

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
    final transferId = _transferId;
    if (transferId != null && transferId.isNotEmpty) {
      await _flushEarlyRemoteIce(transferId);
    }
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
    final transferId = event['transferId']?.toString().trim();

    if (transferId == null || transferId.isEmpty) {
      return;
    }

    final candidateData = event['candidate'];

    if (candidateData is! Map) {
      return;
    }

    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );

    final fingerprint = [
      transferId,
      candidate.candidate ?? '',
      candidate.sdpMid ?? '',
      candidate.sdpMLineIndex?.toString() ?? '',
    ].join('|');

    if (!_receivedIceFingerprints.add(fingerprint)) {
      _diag(
        'ICE_DUPLICATE_IGNORED '
        'transfer=$transferId',
      );
      return;
    }

    // ICE metadata offer'dan önce gelirse kaybetme.
    if (_transferId != transferId) {
      final buffered = _earlyRemoteIce.putIfAbsent(
        transferId,
        () => <RTCIceCandidate>[],
      );

      buffered.add(candidate);

      _diag(
        'ICE_EARLY_BUFFERED '
        'transfer=$transferId '
        'count=${buffered.length}',
      );
      return;
    }

    if (!_remoteDescriptionSet) {
      _pendingIce.add(candidate);
      return;
    }

    try {
      await _pc?.addCandidate(candidate);
    } catch (e) {
      _diag(
        'ICE_ADD_FAILED '
        'transfer=$transferId '
        'error=$e',
      );

      if (_transferId == transferId &&
          !_disposed &&
          !_pendingIce.contains(candidate)) {
        _pendingIce.add(candidate);
      }
    }
  }

  Future<void> _flushEarlyRemoteIce(String transferId) async {
    if (_disposed ||
        _pc == null ||
        !_remoteDescriptionSet ||
        transferId.isEmpty ||
        _transferId != transferId) {
      return;
    }

    final early = _earlyRemoteIce.remove(transferId);

    if (early == null || early.isEmpty) {
      return;
    }

    _diag(
      'ICE_EARLY_FLUSH '
      'transfer=$transferId '
      'count=${early.length}',
    );

    for (final candidate in early) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (e) {
        _diag(
          'ICE_EARLY_FLUSH_FAILED '
          'transfer=$transferId '
          'error=$e',
        );

        _pendingIce.add(candidate);
      }
    }
  }

  Future<void> _flushPendingIce() async {
    if (!_remoteDescriptionSet || _pc == null) return;

    final pending = List<RTCIceCandidate>.from(_pendingIce);
    _pendingIce.clear();

    for (final candidate in pending) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (e) {
        _diag('ICE_PENDING_FLUSH_FAILED: $e');
        _pendingIce.add(candidate);
      }
    }
  }

  Future<void> _receiveChunk(RTCDataChannelMessage message) async {
    final transferId = _transferId;
    final generation = _transferGeneration;

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

        if (_disposed ||
            _transferId != transferId ||
            generation != _transferGeneration ||
            !_accepted) {
          return;
        }

        if (_receivedBytes + bytes.length > _fileSize) {
          throw StateError('Alınan veri beklenen dosya boyutunu aşıyor.');
        }

        if (backgroundTransferMode) {
          final output = _backgroundOutput;

          if (output == null) {
            throw StateError(
              'Arka plan dosya akışı hazır değil.',
            );
          }

          await output.writeFrom(bytes);
        } else {
          final written = await _systemChannel.invokeMethod<bool>(
            'writeIncomingFile',
            bytes,
          );

          if (written != true) {
            throw StateError('Dosya verisi diske yazılamadı.');
          }
        }

        if (_disposed ||
            _transferId != transferId ||
            generation != _transferGeneration) {
          return;
        }

        _receivedBytes += bytes.length;

        // Dosya boyutunu aşan veri kesinlikle kabul edilmez.
        if (_receivedBytes > _fileSize) {
          throw StateError('Alınan veri beklenen dosya boyutunu aştı.');
        }

        _touchTransferTimeout(transferId, incoming: true);

        onProgress?.call(
          transferId: transferId,
          sentBytes: _receivedBytes,
          totalBytes: _fileSize,
          status: 'transferring',
        );
      } catch (e) {
        if (_disposed ||
            _transferId != transferId ||
            generation != _transferGeneration) {
          _diag(
            'RECEIVE_BINARY_STALE_ABORT '
            'transfer=$transferId '
            'generation=$generation '
            'currentGeneration=$_transferGeneration',
          );
          return;
        }

        _diag('RECEIVE_BINARY_FAILED: $e');

        await _failTransfer(
          transferId,
          'Dosya verisi alınırken hata oluştu.',
          reset: true,
          incoming: true,
        );
      }

      return;
    }

    final data = message.text;
    final messageGeneration = generation;

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

    if (messageGeneration != _transferGeneration ||
        _transferId != transferId ||
        !_accepted ||
        _disposed) {
      return;
    }

    if (_terminalEventHandled) {
      return;
    }

    // DataChannel üzerinden veri aktarımı sona erdi.
    // Bundan sonra checksum + finalize işlemi yapılıyor.
    // Bu aşamada transfer inactivity timer'ı artık gereksiz.
    _transferTimeoutTimer?.cancel();
    _transferTimeoutTimer = null;

    _startFinalizeTimeout(transferId);

    final declaredSize =
        int.tryParse(control['size']?.toString() ?? '') ?? _fileSize;

    final declaredSha256 =
        control['sha256']?.toString().trim().toLowerCase() ?? '';

    try {
      if (declaredSize != _fileSize) {
        throw StateError('Gönderici dosya boyutu uyuşmuyor.');
      }

      if (_receivedBytes != _fileSize) {
        throw StateError(
          'Eksik dosya alındı: $_receivedBytes / $_fileSize byte.',
        );
      }

      String receivedSha256;

      if (backgroundTransferMode) {
        final output = _backgroundOutput;
        final file = _backgroundOutputFile;

        if (output == null || file == null) {
          throw StateError(
            'Arka plan dosya akışı bulunamadı.',
          );
        }

        await output.flush();
        await output.close();

        _backgroundOutput = null;
        _nativeFileOpen = false;

        receivedSha256 = await _calculateFileSha256(file);
      } else {
        final closed = await _systemChannel.invokeMethod<bool>(
          'closeIncomingFile',
        );

        if (messageGeneration != _transferGeneration ||
            _transferId != transferId ||
            _disposed) {
          return;
        }

        _nativeFileOpen = false;

        if (closed != true) {
          throw StateError('Dosya kayıt akışı kapatılamadı.');
        }

        if (declaredSha256.isEmpty) {
          throw StateError('Gönderici SHA-256 göndermedi.');
        }

        final nativeSha256 =
            await _systemChannel.invokeMethod<String>(
          'getIncomingFileSha256',
        );

        if (nativeSha256 == null || nativeSha256.isEmpty) {
          throw StateError(
            'Alınan dosyanın SHA-256 değeri hesaplanamadı.',
          );
        }

        receivedSha256 = nativeSha256;
      }

      if (declaredSha256.isEmpty) {
        throw StateError('Gönderici SHA-256 göndermedi.');
      }

      final normalizedReceivedSha256 =
          receivedSha256.trim().toLowerCase();

      if (messageGeneration != _transferGeneration ||
          _transferId != transferId ||
          _disposed) {
        return;
      }

      if (normalizedReceivedSha256 != declaredSha256) {
        _diag(
          'CHECKSUM_MISMATCH '
          'transfer=$transferId '
          'expected=$declaredSha256 '
          'actual=$normalizedReceivedSha256',
        );

        throw StateError('SHA-256 doğrulaması başarısız.');
      }

      _remoteSha256 = normalizedReceivedSha256;

      // SHA-256 doğrulaması temp dosya üzerinde tamamlandı.
      // Şimdi ve yalnızca şimdi temp dosyayı kullanıcının seçtiği
      // gerçek hedef URI'ye atomik olmayan ama kontrollü şekilde
      // kopyalıyoruz.
      String? finalizedUri;

      if (backgroundTransferMode) {
        final source = _backgroundOutputFile;

        if (source == null || !await source.exists()) {
          throw StateError(
            'Doğrulanan arka plan dosyası bulunamadı.',
          );
        }

        final finalPath =
            await _backgroundSystemChannel.invokeMethod<String>(
          'registerBackgroundReceivedFile',
          <String, dynamic>{
            'fileId': transferId,
            'sourcePath': source.path,
            'fileName': _fileName ?? 'received_file',
          },
        );

        if (finalPath == null || finalPath.trim().isEmpty) {
          throw StateError(
            'Arka plan alınan dosya native depolamaya kaydedilemedi.',
          );
        }

        // Android 10+ background kayıt MediaStore content URI döndürür.
        // Android 9 ve altında FileProvider/local path dönebilir.
        // Native tarafı boyutu ve kalıcı hedefi zaten doğruladığı için
        // burada content:// URI'yi File() ile kontrol etmiyoruz.
        _backgroundOutputFile = null;
        _nativeFileOpen = false;
        finalizedUri = finalPath.trim();
      } else {
        finalizedUri =
            await _systemChannel.invokeMethod<String>(
          'finalizeIncomingFile',
          <String, dynamic>{'fileId': transferId},
        );

        if (finalizedUri == null ||
            finalizedUri.trim().isEmpty) {
          throw StateError(
            'Doğrulanan dosya hedef konuma aktarılamadı.',
          );
        }
      }

      if (messageGeneration != _transferGeneration ||
          _transferId != transferId ||
          _disposed) {
        return;
      }

      _terminalEventHandled = true;
      _markTransferTerminal(transferId);

      // Dosya artık:
      // 1. Tam boyutta alındı
      // 2. Temp dosyaya yazıldı
      // 3. SHA-256 ile doğrulandı
      // 4. Kullanıcının seçtiği gerçek hedefe kopyalandı
      //
      // Bundan sonra sender'a completion ACK gönderiyoruz.
      ws.send({
        'type': 'fileTransferComplete',
        'from': me,
        'to': peer,
        'transferId': transferId,
        'fileSize': _receivedBytes,
        'sha256': _remoteSha256,
      });

      // Dosya ancak alıcı tarafından tamamen yazılıp SHA-256 ile
      // doğrulandıktan sonra sohbet geçmişine gerçek dosya mesajı
      // olarak kaydedilir.
      //
      // Böylece ACCEPT/REJECT öncesinde privateFileMessage oluşmaz.
      ws.send({
        'type': 'privateFileMessage',
        'to': peer,
        'fileId': transferId,
        'fileName': _fileName ?? 'Dosya',
        'fileSize': _fileSize,
        'clientMessageId': transferId,
      });

      onProgress?.call(
        transferId: transferId,
        sentBytes: _receivedBytes,
        totalBytes: _fileSize,
        status: 'completed',
      );

      onIncomingStatus?.call(
        transferId: transferId,
        status: 'completed',
        localUri: finalizedUri,
      );

      _finalizeTimeoutTimer?.cancel();
      _finalizeTimeoutTimer = null;

      await _resetTransferState();
    } catch (e) {
      _diag('RECEIVE_FINALIZE_FAILED: $e');

      await _failTransfer(
        transferId,
        'Dosya doğrulanamadı veya tamamlanamadı.',
        reset: true,
        incoming: true,
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

    _awaitingCompletionAck = false;

    final remoteSize = int.tryParse(event['fileSize']?.toString() ?? '') ?? 0;
    final remoteSha256 = event['sha256']?.toString().trim().toLowerCase() ?? '';

    if (remoteSize != _fileSize ||
        remoteSha256.isEmpty ||
        remoteSha256 != (_sourceSha256 ?? '').toLowerCase()) {
      _diag(
        'REMOTE_CHECKSUM_MISMATCH '
        'transfer=$transferId '
        'local=${_sourceSha256 ?? ''} '
        'remote=$remoteSha256',
      );
      const reason = 'Alıcı tarafından bildirilen dosya doğrulaması başarısız.';

      // Receiver completion gönderdiğini düşünse bile sender'ın
      // doğrulaması başarısızsa karşı taraf da terminal FAILED state'e
      // geçirilmelidir. Böylece iki cihazın transfer state'i ayrışmaz.
      ws.send({
        'type': 'fileTransferFailed',
        'from': me,
        'to': peer,
        'transferId': transferId,
        'reason': reason,
      });

      onProgress?.call(
        transferId: transferId,
        sentBytes: _sentBytes,
        totalBytes: _fileSize,
        status: 'failed',
      );

      _terminalEventHandled = true;
      _markTransferTerminal(transferId);

      await _resetTransferState();
      return;
    }

    _terminalEventHandled = true;
    _markTransferTerminal(transferId);

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
    _markTransferTerminal(transferId);

    onProgress?.call(
      transferId: transferId,
      sentBytes: _sentBytes,
      totalBytes: _fileSize,
      status: 'failed',
    );

    await _resetTransferState();
  }

  Future<void> _failTransfer(
    String transferId,
    String reason, {
    bool reset = false,
    bool incoming = false,
  }) async {
    if (_terminalEventHandled && !reset) return;

    _terminalEventHandled = true;
    _markTransferTerminal(transferId);

    _diag('${incoming ? 'INCOMING' : 'OUTGOING'}_TRANSFER_FAILED: $reason');

    if (incoming) {
      final cleanupChannel = backgroundTransferMode
          ? _backgroundSystemChannel
          : _systemChannel;

      try {
        await cleanupChannel.invokeMethod<bool>(
          'closeIncomingFile',
        );
      } catch (_) {}

      try {
        await cleanupChannel.invokeMethod<bool>(
          'discardIncomingFile',
        );
      } catch (_) {}

      _nativeFileOpen = false;
    }

    ws.send({
      'type': 'fileTransferFailed',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'reason': reason,
    });

    onProgress?.call(
      transferId: transferId,
      sentBytes: incoming ? _receivedBytes : _sentBytes,
      totalBytes: _fileSize,
      status: 'failed',
    );

    if (incoming) {
      onIncomingStatus?.call(transferId: transferId, status: 'failed');
    }

    if (reset) {
      await _resetTransferState();
    }
  }

  Future<void> _openOutput() async {
    if (backgroundTransferMode) {
      final directory =
          await getApplicationDocumentsDirectory();

      final receivedDirectory = Directory(
        '${directory.path}/received_files',
      );

      await receivedDirectory.create(recursive: true);

      final safeId = (_transferId ?? 'unknown').replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );

      final partFile = File(
        '${receivedDirectory.path}/$safeId.part',
      );

      if (await partFile.exists()) {
        await partFile.delete();
      }

      _backgroundOutputFile = partFile;
      _backgroundOutput = await partFile.open(
        mode: FileMode.write,
      );

      _nativeFileOpen = true;
      _receivedBytes = 0;
      return;
    }

    final safeName = (_fileName ?? 'received_file').replaceAll(
      RegExp(r'[/\\]'),
      '_',
    );

    final result = await _systemChannel.invokeMethod<dynamic>(
      'requestIncomingFileSave',
      <String, dynamic>{'fileName': safeName},
    );

    if (result == null) {
      throw StateError('Dosya kayıt hedefi açılamadı.');
    }

    _nativeFileOpen = true;
  }

  Future<String> _calculateFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _resetTransferState() async {
    // Background isolate kendi foreground service'i tarafından çalıştırılır.
    // İlk prepare aşamasında service'i kapatmamak gerekir.
    // Terminal reset sonrasında ise service kapatılabilir.
    if (!backgroundTransferMode) {
      await _stopBackgroundTransferService();
    }

    if (_disposed) return;

    _cancelTransferTimers();

    // Eski async sender/receiver işlemlerini geçersiz kıl.
    _transferGeneration++;
    _processedSignalEvents.clear();
    _lastSignalSeqByTransfer.clear();

    if (_nativeFileOpen) {
      if (backgroundTransferMode) {
        try {
          await _backgroundOutput?.close();
        } catch (_) {}

        _backgroundOutput = null;

        try {
          final file = _backgroundOutputFile;
          if (file != null && await file.exists()) {
            await file.delete();
          }
        } catch (_) {}

        _backgroundOutputFile = null;
      } else {
        try {
          await _systemChannel.invokeMethod<bool>(
            'closeIncomingFile',
          );
        } catch (_) {}

        try {
          await _systemChannel.invokeMethod<bool>(
            'discardIncomingFile',
          );
        } catch (_) {}
      }

      _nativeFileOpen = false;
    }

    _channel = null;
    _pendingIce.clear();
    _pendingLocalIce.clear();
    _earlyRemoteIce.clear();
    _receivedIceFingerprints.clear();
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
    _incomingTransfer = false;

    _receiveQueue = Future<void>.value();
    _awaitingCompletionAck = false;
    _terminalEventHandled = false;
    _sourceSha256 = null;
    _remoteSha256 = null;

    await _pc?.close();
    _pc = null;

    if (backgroundTransferMode) {
      try {
        const backgroundChannel = MethodChannel(
          'zerolog/background_transfer',
        );
        await backgroundChannel.invokeMethod<dynamic>(
          'stopService',
        );
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _stopBackgroundTransferService();

    if (_disposed) return;

    _disposed = true;

    _cancelTransferTimers();

    await _eventsSub?.cancel();

    if (_nativeFileOpen) {
      if (backgroundTransferMode) {
        try {
          await _backgroundOutput?.close();
        } catch (_) {}

        _backgroundOutput = null;

        try {
          final file = _backgroundOutputFile;
          if (file != null && await file.exists()) {
            await file.delete();
          }
        } catch (_) {}

        _backgroundOutputFile = null;
      } else {
        try {
          await _systemChannel.invokeMethod<bool>(
            'closeIncomingFile',
          );
        } catch (_) {}

        try {
          await _systemChannel.invokeMethod<bool>(
            'discardIncomingFile',
          );
        } catch (_) {}
      }

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
