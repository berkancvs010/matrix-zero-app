import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Reliable private file/media transport.
///
/// The previous implementation used WebRTC DataChannels. That made delivery
/// dependent on ICE/SDP/TURN state even though the app already has a reliable
/// authenticated WebSocket. This implementation uses the authenticated
/// WebSocket as a framed, ordered relay:
///
///   start -> accept -> binary chunks -> end -> SHA-256 verify -> complete
///
/// The server never stores file contents; it only relays the binary frames.
/// Chunk acknowledgements provide bounded application-level backpressure.
class _ZeroLogDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest event) {
    value = event;
  }

  @override
  void close() {}
}

class FileTransfer {
  final dynamic ws;
  final String me;
  final String peer;

  // Kept for source compatibility with the old WebRTC implementation.
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
    final value = _sharedTransfers[_sharedKey(me, peer)];
    if (value == null ||
        value._disposed ||
        value._transferId == null ||
        value._transferId!.isEmpty) {
      return null;
    }
    return value;
  }

  static String _sharedKey(String a, String b) =>
      '${a.trim().toLowerCase()}|${b.trim().toLowerCase()}';

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

  bool _initialized = false;
  bool _disposed = false;
  StreamSubscription? _eventsSub;

  String? _transferId;
  String? _fileName;
  int _fileSize = 0;
  int _sentBytes = 0;
  int _receivedBytes = 0;

  File? _sendingFile;
  RandomAccessFile? _incomingFile;
  File? _incomingTempFile;

  String? _sourceSha256;

  bool _incomingTransfer = false;
  bool _accepted = false;
  bool _sending = false;
  bool _terminalEventHandled = false;
  bool _completionAcknowledged = false;

  int _nextSendSeq = 0;
  int _lastAckSeq = -1;
  int _confirmedBytes = 0;
  int _lastReceivedSeq = -1;

  final Set<String> _terminalTransferTombstones = <String>{};

  Timer? _connectionTimeoutTimer;
  Timer? _transferTimeoutTimer;

  // Keep a bounded 32-chunk send window. Encoded frames are retained so a
  // short WebSocket transition can be recovered without restarting the file.
  static const int _sendWindowSize = 32;
  // Larger frames reduce WebSocket/Dart framing overhead while keeping the
  // bounded 32-frame window at a reasonable memory footprint (~4 MiB).
  static const int _chunkSize = 128 * 1024;
  static const int _maxFileSize = 1024 * 1024 * 1024;
  final Map<int, Uint8List> _outstandingFrames = <int, Uint8List>{};
  Completer<void>? _windowWaiter;
  RandomAccessFile? _sendingRaf;
  int? _pendingResumeSeq;

  Future<void> _eventQueue = Future<void>.value();

  static bool backgroundTransferMode = false;

  String? get currentTransferId => _transferId;
  String? get currentFileName => _fileName;
  int get currentFileSize => _fileSize;

  void _diag(String value) {
    // ignore: avoid_print
    print('[FILE_TRANSFER] $value');
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

    _eventsSub = ws.events.listen((event) {
      if (event is Map<String, dynamic> &&
          event['type'] == 'connectionRestored') {
        unawaited(_sendResumeHandshake());
      }
      unawaited(handleExternalEvent(event));
    });
  }

  Future<String?> sendFile({File? sourceFile, String? sourceFileName}) async {
    if (_disposed) {
      throw StateError('Dosya aktarımı kullanılamıyor.');
    }

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
      file = File(files.first.path!);
      fileName = files.first.name;
    }

    if (!await file.exists()) {
      throw StateError('Seçilen dosya bulunamadı.');
    }

    final size = await file.length();
    if (size <= 0) {
      throw StateError('Seçilen dosya boş.');
    }
    if (size > _maxFileSize) {
      throw StateError('Dosya boyutu 1 GB sınırını aşıyor.');
    }

    if (_transferId != null || _sending || _accepted) {
      throw StateError('Bu sohbet için devam eden bir dosya transferi var.');
    }

    if (!ws.connected) {
      throw StateError('Dosya gönderilemedi: bağlantı hazır değil.');
    }

    await _resetTransferState();

    final transferId =
        '${DateTime.now().microsecondsSinceEpoch}-$me-${_safeRandomPart()}';

    _transferId = transferId;
    _fileName = fileName;
    _fileSize = size;
    _sendingFile = file;
    _incomingTransfer = false;
    _sourceSha256 = (await _calculateFileSha256(file)).trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(_sourceSha256!)) {
      await _failTransfer(
        transferId,
        'Dosya SHA-256 bilgisi geçersiz.',
        reset: true,
      );
      throw StateError('Dosya SHA-256 bilgisi geçersiz.');
    }
    _sentBytes = 0;
    _nextSendSeq = 0;
    _lastAckSeq = -1;
    _terminalEventHandled = false;

    onProgress?.call(
      transferId: transferId,
      sentBytes: 0,
      totalBytes: size,
      status: 'waiting',
    );

    final sent = ws.send({
      'type': 'fileTransferStart',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'fileName': fileName,
      'fileSize': size,
      'sha256': _sourceSha256,
    });

    if (!sent) {
      await _failTransfer(
        transferId,
        'Dosya transferi sunucuya gönderilemedi.',
        reset: true,
      );
      throw StateError('Dosya transferi sunucuya gönderilemedi.');
    }

    _startConnectionTimeout(transferId);

    return transferId;
  }

  /// Compatibility entry point used by notification/background code.
  Future<bool> prepareIncomingFromNotification({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
    String? sha256,
  }) async {
    if (_disposed ||
        transferId.trim().isEmpty ||
        fileSize <= 0 ||
        fileSize > _maxFileSize) {
      return false;
    }

    final id = transferId.trim();

    if (_transferId == id) return true;

    if (_transferId != null && _transferId!.isNotEmpty) {
      return false;
    }

    try {
      await _resetTransferState();

      _incomingTransfer = true;
      _transferId = id;
      _fileName = fileName.trim().isEmpty ? 'received_file' : fileName.trim();
      _fileSize = fileSize;
      _sourceSha256 = (sha256 ?? '').trim().toLowerCase();
      if (_sourceSha256!.isNotEmpty &&
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(_sourceSha256!)) {
        _diag('INCOMING_INVALID_SHA transfer=$id');
        await _resetTransferState();
        return false;
      }
      _accepted = false;
      _receivedBytes = 0;
      _lastReceivedSeq = -1;

      await _prepareIncomingFile(id);

      _startConnectionTimeout(id);

      onIncomingOffer?.call(
        transferId: id,
        fileName: _fileName!,
        fileSize: _fileSize,
        sender: sender,
      );

      return true;
    } catch (e) {
      _diag('INCOMING_PREPARE_FAILED transfer=$id error=$e');
      await _resetTransferState();
      return false;
    }
  }

  Future<void> acceptIncoming(String transferId) async {
    if (_disposed || _transferId != transferId) return;

    // ACCEPT itself is not durable on the WebSocket. If it was previously
    // accepted but the socket changed, resend the idempotent ACCEPT so the
    // server can bind the new receiver socket to this transfer.
    if (_accepted) {
      if (!ws.connected) {
        _startConnectionTimeout(transferId);
        return;
      }

      final sent = ws.send({
        'type': 'fileTransferAccept',
        'from': me,
        'to': peer,
        'transferId': transferId,
      });

      if (sent) {
        _connectionTimeoutTimer?.cancel();
        _connectionTimeoutTimer = null;
        await _sendResumeHandshake();
      } else {
        _startConnectionTimeout(transferId);
      }
      return;
    }

    try {
      if (_incomingTempFile == null || _incomingFile == null) {
        await _prepareIncomingFile(transferId);
      }

      _accepted = true;

      // ACCEPT completed the connection phase. Do not let the original
      // 90-second connection timer abort a long but active transfer.
      _connectionTimeoutTimer?.cancel();
      _connectionTimeoutTimer = null;

      onIncomingStatus?.call(transferId: transferId, status: 'accepting');

      final sent = ws.send({
        'type': 'fileTransferAccept',
        'from': me,
        'to': peer,
        'transferId': transferId,
      });

      if (sent) {
        await _sendResumeHandshake();
      } else {
        // Keep the prepared incoming transfer alive. WsClient will reconnect
        // and the ACCEPT is retried by the caller/normal transfer signaling
        // path instead of destroying a valid pending receive.
        _startConnectionTimeout(transferId);
      }
    } catch (e) {
      _accepted = false;
      await _failTransfer(
        transferId,
        'Dosya kayıt akışı hazırlanamadı: $e',
        reset: true,
        incoming: true,
      );
    }
  }

  /// User-initiated cancellation. It is deliberately separate from
  /// transport failure so an active transfer cannot leave the shared
  /// FileTransfer instance occupied after its chat bubble is removed.
  Future<void> cancelTransfer(String transferId) async {
    if (_disposed || _transferId != transferId || transferId.trim().isEmpty) {
      return;
    }

    if (_terminalEventHandled) {
      await _resetTransferState();
      return;
    }

    _terminalEventHandled = true;
    _markTerminal(transferId);

    _diag('TRANSFER_CANCELLED transfer=$transferId');

    ws.send({
      'type': 'fileTransferFailed',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'reason': 'Dosya transferi kullanıcı tarafından iptal edildi.',
    });

    final incoming = _incomingTransfer;
    onProgress?.call(
      transferId: transferId,
      sentBytes: incoming ? _receivedBytes : _sentBytes,
      totalBytes: _fileSize,
      status: 'failed',
    );

    if (incoming) {
      onIncomingStatus?.call(
        transferId: transferId,
        status: 'failed',
      );
    }

    await _deleteReceiveManifest(transferId);
    await _resetTransferState();
  }

  Future<void> rejectIncoming(String transferId) async {
    if (_disposed || _transferId != transferId) return;

    ws.send({
      'type': 'fileTransferReject',
      'from': me,
      'to': peer,
      'transferId': transferId,
    });

    onIncomingStatus?.call(transferId: transferId, status: 'rejected');

    await _deleteReceiveManifest(transferId);
    await _resetTransferState();
  }

  Future<void> handleExternalEvent(Map<String, dynamic> event) async {
    final next = _eventQueue.then((_) async {
      try {
        await _handleEvent(event);
      } catch (error, stack) {
        final eventId = (event['transferId'] ?? '').toString().trim();
        final activeId = eventId.isNotEmpty ? eventId : _transferId;
        _diag('FILE_EVENT_QUEUE_FAILED transfer=$activeId error=$error stack=$stack');
        if (activeId != null &&
            activeId.isNotEmpty &&
            _transferId == activeId &&
            !_terminalEventHandled) {
          try {
            await _failTransfer(
              activeId,
              'Dosya transferi beklenmeyen bir hatayla durdu: $error',
              reset: true,
              incoming: _incomingTransfer,
            );
          } catch (cleanupError, cleanupStack) {
            _diag(
              'FILE_EVENT_QUEUE_CLEANUP_FAILED transfer=$activeId '
              'error=$cleanupError stack=$cleanupStack',
            );
            try {
              await _incomingFile?.close();
            } catch (closeError) {
              _diag('FILE_EVENT_QUEUE_FORCE_CLOSE_FAILED error=$closeError');
            }
            _incomingFile = null;
            _cancelTimers();
            if (_transferId == activeId) {
              _transferId = null;
              _sendingFile = null;
              _incomingTempFile = null;
              _incomingTransfer = false;
              _sending = false;
              _accepted = false;
              _terminalEventHandled = false;
            }
          }
        }
      }
    });
    _eventQueue = next.catchError((error, stack) {
      _diag('FILE_EVENT_QUEUE_RECOVERY_FAILED error=$error stack=$stack');
    });
    await _eventQueue;
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    if (_disposed) return;

    final type = (event['type'] ?? '').toString();

    if (type == 'fileTransferResumeState') {
      final resumeId = (event['transferId'] ?? '').toString().trim();
      if (resumeId != _transferId || _terminalEventHandled) return;
      final rawSeq = event['lastReceivedSeq'];
      final seq = rawSeq is num
          ? rawSeq.toInt()
          : int.tryParse(rawSeq?.toString() ?? '') ?? -1;
      final expectedMaxSeq = _fileSize > 0
          ? ((_fileSize + _chunkSize - 1) ~/ _chunkSize) - 1
          : -1;
      if (seq < -1 || seq > expectedMaxSeq) {
        await _failTransfer(
          resumeId,
          'Geçersiz resume sequence bilgisi.',
          reset: true,
          incoming: _incomingTransfer,
        );
        return;
      }
      final stateFrom = (event['from'] ?? '').toString().trim();
      final stateTo = (event['to'] ?? '').toString().trim();
      final stateName = (event['fileName'] ?? '').toString().trim();
      final stateSize = int.tryParse((event['fileSize'] ?? '').toString()) ?? 0;
      final stateSha = (event['sha256'] ?? '').toString().trim().toLowerCase();
      final expectedSha = (_sourceSha256 ?? '').trim().toLowerCase();
      final resumeMetadataValid =
          stateFrom.toLowerCase() == peer.toLowerCase() &&
          stateTo.toLowerCase() == me.toLowerCase() &&
          stateName == (_fileName ?? '') &&
          stateSize == _fileSize &&
          stateSha == expectedSha &&
          event['protocolVersion']?.toString() == '1';
      if (!resumeMetadataValid) {
        await _failTransfer(
          resumeId,
          'Resume metadata bilgisi eşleşmedi.',
          reset: true,
          incoming: _incomingTransfer,
        );
        return;
      }
      if (!_incomingTransfer && event['state']?.toString() == 'completed') {
        await _handleRemoteCompletion(event);
        return;
      }
      if (_incomingTransfer) {
        // The receiver's durable manifest/.part is authoritative. A server
        // resume state can be stale relative to the last locally flushed
        // chunk, so never advance local receive state from this event.
        return;
      }
      _lastAckSeq = seq;
      _confirmedBytes = _seqCommittedBytes(seq);
      _outstandingFrames.removeWhere((key, _) => key <= seq);
      _nextSendSeq = seq + 1;
      _sentBytes = _seqCommittedBytes(seq);
      _pendingResumeSeq = seq;
      final waiter = _windowWaiter;
      _windowWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }

    if (type == 'fileTransferStartAck') {
      final id = (event['transferId'] ?? '').toString().trim();
      if (id == _transferId && !_incomingTransfer) {
        onProgress?.call(
          transferId: id,
          sentBytes: _sentBytes,
          totalBytes: _fileSize,
          status: 'stored',
        );
      }
      return;
    }

    if (type == 'fileTransferOffer') {
      final id = (event['transferId'] ?? '').toString().trim();
      final from = (event['from'] ?? '').toString().trim();
      final to = (event['to'] ?? '').toString().trim();

      if (id.isEmpty ||
          from.toLowerCase() != peer.toLowerCase() ||
          (to.isNotEmpty && to.toLowerCase() != me.toLowerCase())) {
        return;
      }

      final rawSize = event['fileSize'];
      final size = rawSize is num
          ? rawSize.toInt()
          : int.tryParse(rawSize?.toString() ?? '') ?? 0;

      final name = (event['fileName'] ?? 'Dosya').toString().trim();
      if (size <= 0 || size > _maxFileSize || name.isEmpty) return;

      if (_transferId != null && _transferId != id) return;

      if (_transferId == id) {
        // A reconnect can replay the same OFFER after the receiver prepared
        // the file. The metadata must remain identical to the original
        // transfer before the existing partial file is reused.
        final replaySha = (event['sha256'] ?? '').toString().trim().toLowerCase();
        if (_incomingTransfer &&
            (_fileSize != size ||
             (_sourceSha256 != null &&
              _sourceSha256!.isNotEmpty &&
              replaySha.isNotEmpty &&
              _sourceSha256 != replaySha))) {
          await _failTransfer(
            id,
            'Dosya transferi metadata bilgisi değişti.',
            reset: true,
            incoming: true,
          );
          return;
        }
        if (_incomingTransfer && replaySha.isNotEmpty) {
          _sourceSha256 = replaySha;
          await _persistReceiveManifest(id);
          await acceptIncoming(id);
        }
        return;
      }

      try {
        await _resetTransferState();
        _incomingTransfer = true;
        _transferId = id;
        _fileName = name;
        _fileSize = size;
        _sourceSha256 = (event['sha256'] ?? '').toString().trim().toLowerCase();
        _receivedBytes = 0;
        _lastReceivedSeq = -1;

        await _prepareIncomingFile(id);
        _startConnectionTimeout(id);

        onIncomingOffer?.call(
          transferId: id,
          fileName: name,
          fileSize: size,
          sender: from,
        );
      } catch (e) {
        await _failTransfer(
          id,
          'Gelen dosya hazırlanamadı: $e',
          reset: true,
          incoming: true,
        );
      }

      return;
    }

    final id = (event['transferId'] ?? '').toString().trim();
    if (id.isEmpty || id != _transferId) return;

    switch (type) {
      case 'fileTransferAccept':
        if (!_incomingTransfer && !_sending && _sendingFile != null) {
          await _startOutgoingTransfer();
        }
        break;

      case 'fileTransferChunkAck':
        if (_incomingTransfer) return;

        final raw = event['receivedSeq'];
        final receivedSeq = raw is num
            ? raw.toInt()
            : int.tryParse(raw?.toString() ?? '') ?? -1;

        final maxAckSeq = _fileSize > 0
            ? ((_fileSize + _chunkSize - 1) ~/ _chunkSize) - 1
            : -1;
        if (receivedSeq < -1 || receivedSeq > maxAckSeq) {
          await _failTransfer(
            id,
            'Geçersiz dosya ACK sequence bilgisi.',
            reset: true,
            incoming: false,
          );
          return;
        }

        if (receivedSeq > _lastAckSeq) {
          _lastAckSeq = receivedSeq;
          _confirmedBytes = _seqCommittedBytes(receivedSeq);
          _outstandingFrames.removeWhere(
            (seq, _) => seq <= _lastAckSeq,
          );
          final waiter = _windowWaiter;
          _windowWaiter = null;
          if (waiter != null && !waiter.isCompleted) {
            waiter.complete();
          }
        }
        break;

      case 'fileTransferComplete':
        if (!_incomingTransfer) {
          await _handleRemoteCompletion(event);
        }
        break;

      case 'fileTransferCompleteAck':
        if (_incomingTransfer && event['transferId']?.toString() == _transferId) {
          _completionAcknowledged = true;
        }
        break;

      case 'fileTransferReject':
        if (!_incomingTransfer) {
          await _failTransfer(id, 'Karşı taraf dosyayı reddetti.', reset: true);
        }
        break;

      case 'fileTransferFailed':
        if (event['transferId']?.toString() == _transferId) {
          ws.send({
            'type': 'fileTransferFailedAck',
            'from': me,
            'to': peer,
            'transferId': id,
          });
        }
        await _failTransfer(
          id,
          (event['reason']?.toString().trim().isNotEmpty ?? false)
              ? event['reason'].toString().trim()
              : 'Dosya transferi karşı tarafta başarısız oldu.',
          reset: true,
          incoming: _incomingTransfer,
        );
        break;

      case 'fileTransferChunk':
        final bytes = event['bytes'];
        try {
          if (bytes is Uint8List) {
            await _receiveChunk(bytes, event['seq']);
          } else if (bytes is List<int>) {
            await _receiveChunk(
              Uint8List.fromList(bytes),
              event['seq'],
            );
          }
        } catch (error, stack) {
          await _handleReceiveQueueFailure(id, error, stack);
        }
        break;

      case 'fileTransferEnd':
        // All file events are serialized by _eventQueue, so END can never
        // overtake an in-flight chunk or its failure handler.
        await _finalizeIncoming(event);
        break;
    }
  }

  Future<void> _startOutgoingTransfer() async {
    final id = _transferId;
    final file = _sendingFile;

    if (_disposed ||
        id == null ||
        id.isEmpty ||
        file == null ||
        _sending ||
        _terminalEventHandled) {
      return;
    }

    _sending = true;
    // The 90-second connection timer only covers the pre-ACCEPT phase.
    // Once the receiver has accepted and byte transfer has started, the
    // inactivity timer below is the authoritative timeout.
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _startTransferTimeout(id);

    try {
      final raf = await file.open();
      _sendingRaf = raf;
      try {

        while (true) {
          if (_disposed ||
              _terminalEventHandled ||
              _transferId != id) {
            throw StateError('Dosya transferi sonlandı.');
          }

          if (!ws.connected) {
            final restored = await _waitForConnection(
              const Duration(seconds: 90),
            );
            if (!restored) {
              throw StateError('Dosya bağlantısı yeniden kurulamadı.');
            }
            await _resendOutstandingFrames(id);
          }

          final pendingResume = _pendingResumeSeq;
          if (pendingResume != null) {
            _pendingResumeSeq = null;
            final offset = _seqCommittedBytes(pendingResume);
            await raf.setPosition(offset);
            _sentBytes = offset;
          }

          final bytes = await raf.read(_chunkSize);
          if (bytes.isEmpty) break;

          if (_pendingResumeSeq != null) {
            // A resume handshake arrived while the read was awaiting I/O.
            // Discard this stale chunk and restart from the receiver's
            // authoritative committed sequence.
            continue;
          }

          final seq = _nextSendSeq++;

          final frame = _encodeChunkFrame(
            transferId: id,
            seq: seq,
            payload: Uint8List.fromList(bytes),
          );

          if (!ws.sendBinary(frame)) {
            // A false return can mean normal socket backpressure, not a lost
            // connection. Do not enter the 90-second reconnect path here.
            // Retry the same frame promptly while preserving its sequence.
            if (!await _resendFrameUntilAccepted(id, seq, frame)) {
              throw StateError('Dosya parçası karşı tarafa gönderilemedi.');
            }
          }

          _outstandingFrames[seq] = frame;
          _sentBytes += bytes.length;

          onProgress?.call(
            transferId: id,
            // UI progress is receiver-confirmed, not merely bytes queued
            // into the local socket. This keeps sender and receiver progress
            // on the same authoritative ACK boundary.
            sentBytes: _confirmedBytes.clamp(0, _fileSize),
            totalBytes: _fileSize,
            status: 'transferring',
          );

          _touchTransferTimeout(id);

          // Give the Flutter event loop a brief chance to paint progress and
          // service incoming ACKs without throttling the actual socket send.
          if (seq % 8 == 7) {
            await Future<void>.delayed(Duration.zero);
          }

          if (seq - _lastAckSeq >= _sendWindowSize) {
            await _waitForAck(id, seq);
          }
        }
      } finally {
        if (identical(_sendingRaf, raf)) _sendingRaf = null;
        await raf.close();
      }

      await _sendEndAndWaitForCompletion(id);

      onProgress?.call(
        transferId: id,
        sentBytes: _fileSize,
        totalBytes: _fileSize,
        status: 'transferring',
      );
    } catch (e) {
      await _failTransfer(
        id,
        'Dosya gönderilirken hata oluştu: $e',
        reset: true,
      );
    }
  }

  Future<void> _sendEndAndWaitForCompletion(String transferId) async {
    final deadline = DateTime.now().add(const Duration(minutes: 30));

    // Do not let the byte-transfer inactivity timer abort a healthy receiver
    // while it hashes/finalizes the completed file.
    _transferTimeoutTimer?.cancel();
    _transferTimeoutTimer = null;

    while (!_disposed &&
        _transferId == transferId &&
        !_terminalEventHandled &&
        DateTime.now().isBefore(deadline)) {
      if (!ws.connected) {
        if (!await _waitForConnection(const Duration(seconds: 30))) {
          continue;
        }
      }

      final sent = ws.send({
        'type': 'fileTransferEnd',
        'from': me,
        'to': peer,
        'transferId': transferId,
        'fileSize': _sentBytes,
        'sha256': _sourceSha256,
      });

      if (sent) {
        final waitUntil = DateTime.now().add(const Duration(seconds: 8));
        while (!_disposed &&
            _transferId == transferId &&
            !_terminalEventHandled &&
            DateTime.now().isBefore(waitUntil)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }

        if (_terminalEventHandled) return;
      } else {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    throw TimeoutException('Alıcı dosyayı doğrulayıp tamamlayamadı.');
  }

  Future<void> _waitForAck(String transferId, int targetSeq) async {
    final deadline = DateTime.now().add(const Duration(minutes: 10));

    while (_lastAckSeq < targetSeq) {
      if (_disposed || _transferId != transferId) {
        throw StateError('Dosya transferi sonlandı.');
      }

      final waiter = Completer<void>();
      _windowWaiter = waiter;

      final timeout = Timer(const Duration(seconds: 30), () {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      });

      try {
        await waiter.future;
      } finally {
        timeout.cancel();
        if (identical(_windowWaiter, waiter)) {
          _windowWaiter = null;
        }
      }

      if (_lastAckSeq >= targetSeq) break;

      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'Dosya alıcısından parça onayı alınamadı.',
        );
      }

      // A lost ACK must not permanently kill an otherwise valid transfer.
      // Re-send the bounded outstanding window; the receiver treats
      // duplicates idempotently and re-ACKs its latest committed sequence.
      if (!ws.connected) {
        final restored = await _waitForConnection(
          const Duration(seconds: 90),
        );
        if (!restored) {
          throw TimeoutException('Dosya bağlantısı yeniden kurulamadı.');
        }
      }

      await _resendOutstandingFrames(transferId);
    }
  }

  int _seqCommittedBytes(int seq) {
    if (seq < 0) return 0;
    final value = (seq + 1) * _chunkSize;
    return value > _fileSize ? _fileSize : value;
  }

  Future<void> _sendResumeHandshake() async {
    final id = _transferId;
    if (_disposed || id == null || id.isEmpty || _terminalEventHandled) return;
    if (!ws.connected) return;
    final receivedSeq = _incomingTransfer ? _lastReceivedSeq : -1;
    ws.send({
      'type': 'fileTransferResume',
      'from': me,
      'to': peer,
      'transferId': id,
      'role': _incomingTransfer ? 'receiver' : 'sender',
      'lastReceivedSeq': receivedSeq,
      'fileName': _fileName ?? '',
      'fileSize': _fileSize,
      'sha256': _sourceSha256 ?? '',
      'protocolVersion': 1,
    });
  }

  Future<File> _receiveManifestFile(String transferId) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/received_files');
    await dir.create(recursive: true);
    return File('${dir.path}/${_sanitizeId(transferId)}.manifest.json');
  }

  Future<Map<String, dynamic>?> _readReceiveManifest(String transferId) async {
    try {
      final file = await _receiveManifestFile(transferId);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? decoded
          : (decoded is Map ? Map<String, dynamic>.from(decoded) : null);
    } catch (e) {
      _diag('RECEIVE_MANIFEST_READ_FAILED transfer=$transferId error=$e');
      return null;
    }
  }

  Future<void> _persistReceiveManifest(String transferId) async {
    if (!_incomingTransfer || transferId.isEmpty || _fileSize <= 0) return;
    try {
      final file = await _receiveManifestFile(transferId);
      final temp = File('${file.path}.tmp');
      final payload = jsonEncode({
        'transferId': transferId,
        'fileName': _fileName ?? 'received_file',
        'fileSize': _fileSize,
        'sha256': _sourceSha256 ?? '',
        'protocolVersion': 1,
        'lastReceivedSeq': _lastReceivedSeq,
        'receivedBytes': _receivedBytes,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      await temp.writeAsString(payload, flush: true);
      await temp.rename(file.path);
    } catch (e) {
      _diag('RECEIVE_MANIFEST_SAVE_FAILED transfer=$transferId error=$e');
    }
  }

  Future<void> _deleteReceiveManifest(String transferId) async {
    try {
      final file = await _receiveManifestFile(transferId);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _handleReceiveQueueFailure(
    String? transferId,
    Object error,
    StackTrace stack,
  ) async {
    final id = transferId;
    if (id == null || id.isEmpty || _transferId != id || _terminalEventHandled) {
      return;
    }
    _diag('RECEIVE_QUEUE_FAILED transfer=$id error=$error');
    await _failTransfer(
      id,
      'Dosya parçası işlenemedi: $error',
      reset: true,
      incoming: true,
    );
  }

  Future<bool> _waitForConnection(Duration timeout) async {
    final end = DateTime.now().add(timeout);

    while (!_disposed && DateTime.now().isBefore(end)) {
      if (ws.connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    return !_disposed && ws.connected;
  }

  Future<bool> _resendFrameUntilAccepted(
    String transferId,
    int seq,
    Uint8List frame,
  ) async {
    final end = DateTime.now().add(const Duration(minutes: 5));

    while (!_disposed &&
        _transferId == transferId &&
        DateTime.now().isBefore(end)) {
      if (!ws.connected) {
        if (!await _waitForConnection(const Duration(seconds: 10))) {
          continue;
        }
      }

      if (ws.sendBinary(frame)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return false;
  }

  Future<void> _resendOutstandingFrames(String transferId) async {
    if (_disposed || _transferId != transferId || _outstandingFrames.isEmpty) {
      return;
    }

    final frames = _outstandingFrames.entries
        .where((entry) => entry.key > _lastAckSeq)
        .toList(growable: false);

    for (final entry in frames) {
      if (_disposed || _transferId != transferId) return;

      if (!ws.connected) {
        if (!await _waitForConnection(const Duration(seconds: 90))) {
          throw StateError('Dosya bağlantısı yeniden kurulamadı.');
        }
      }

      if (!ws.sendBinary(entry.value)) {
        if (!await _resendFrameUntilAccepted(
          transferId,
          entry.key,
          entry.value,
        )) {
          throw StateError('Bekleyen dosya parçası yeniden gönderilemedi.');
        }
      }
    }
  }

  Future<void> _receiveChunk(Uint8List bytes, dynamic rawSeq) async {
    final id = _transferId;
    if (_disposed ||
        !_incomingTransfer ||
        !_accepted ||
        id == null ||
        _terminalEventHandled) {
      return;
    }

    final seq = rawSeq is num
        ? rawSeq.toInt()
        : int.tryParse(rawSeq?.toString() ?? '') ?? -1;

    final maxSeq = _fileSize > 0
        ? ((_fileSize + _chunkSize - 1) ~/ _chunkSize) - 1
        : -1;
    if (seq < 0 || seq > maxSeq) {
      throw StateError('Geçersiz dosya parça numarası.');
    }

    final expectedChunkBytes = seq == maxSeq
        ? _fileSize - (seq * _chunkSize)
        : _chunkSize;
    if (expectedChunkBytes <= 0 || bytes.length != expectedChunkBytes) {
      throw StateError('Dosya parçasının boyutu geçersiz.');
    }

    if (seq <= _lastReceivedSeq) {
      // Duplicate delivery is harmless because the payload was already
      // committed. Re-ACK the latest received sequence so the sender can
      // recover if the original ACK was lost during a socket transition.
      if (seq == _lastReceivedSeq && id.isNotEmpty) {
        ws.send({
          'type': 'fileTransferChunkAck',
          'from': me,
          'to': peer,
          'transferId': id,
          'receivedSeq': _lastReceivedSeq,
        });
      }
      return;
    }

    if (seq != _lastReceivedSeq + 1) {
      throw StateError(
        'Dosya parça sırası bozuldu: beklenen '
        '${_lastReceivedSeq + 1}, gelen $seq.',
      );
    }

    if (_receivedBytes + bytes.length > _fileSize) {
      throw StateError('Alınan veri beklenen dosya boyutunu aşıyor.');
    }

    final file = _incomingFile;
    if (file == null) {
      throw StateError('Alıcı dosya akışı hazır değil.');
    }

    await file.writeFrom(bytes);

    _lastReceivedSeq = seq;
    _receivedBytes += bytes.length;
    _touchTransferTimeout(id);

    onProgress?.call(
      transferId: id,
      sentBytes: _receivedBytes,
      totalBytes: _fileSize,
      status: 'transferring',
    );

    // ACK every 4 chunks (~512 KiB) so the sender's UI follows the receiver
    // closely without creating excessive ACK traffic. Persist the durable
    // checkpoint less often; the .part file itself remains the authoritative
    // local resume source.
    if (seq % 4 == 3 || _receivedBytes == _fileSize) {
      if (seq % 32 == 31 || _receivedBytes == _fileSize) {
        await _persistReceiveManifest(id);
      }
      ws.send({
        'type': 'fileTransferChunkAck',
        'from': me,
        'to': peer,
        'transferId': id,
        'receivedSeq': seq,
      });
    }
  }

  Future<void> _finalizeIncoming(Map<String, dynamic> event) async {
    final id = _transferId;
    if (_disposed ||
        !_incomingTransfer ||
        !_accepted ||
        id == null ||
        _terminalEventHandled) {
      return;
    }

    _cancelTimers();

    try {
      final declaredSize =
          int.tryParse(event['fileSize']?.toString() ?? '') ?? 0;
      final declaredSha = (event['sha256'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (declaredSize != _fileSize ||
          _receivedBytes != _fileSize ||
          declaredSha.isEmpty) {
        throw StateError('Alınan dosya boyutu veya doğrulama bilgisi hatalı.');
      }

      final raf = _incomingFile;
      final temp = _incomingTempFile;
      if (raf == null || temp == null) {
        throw StateError('Alınan dosya akışı bulunamadı.');
      }

      await raf.flush();
      await raf.close();
      _incomingFile = null;

      final actualSha = (await _calculateFileSha256(temp)).toLowerCase();

      if (actualSha != declaredSha) {
        throw StateError('Dosya SHA-256 doğrulaması başarısız.');
      }

      final sourceSha = _sourceSha256?.trim().toLowerCase();
      if (sourceSha != null &&
          sourceSha.isNotEmpty &&
          sourceSha != declaredSha) {
        throw StateError('Gönderici dosya doğrulaması eşleşmedi.');
      }

      final support = await getApplicationSupportDirectory();
      final receivedDir = Directory('${support.path}/received_files');
      await receivedDir.create(recursive: true);

      final extension = _fileExtension(_fileName ?? 'Dosya');
      final finalFile = File(
        '${receivedDir.path}/${_sanitizeId(id)}$extension',
      );

      if (await finalFile.exists()) {
        await finalFile.delete();
      }

      await temp.rename(finalFile.path);
      _incomingTempFile = null;

      _terminalEventHandled = true;

      // The file is already verified and persisted locally. Tell the server
      // authoritatively, retrying across a short socket transition.
      await _sendCompletionWithRetry(
        transferId: id,
        fileSize: _receivedBytes,
        sha256: actualSha,
      );

      onIncomingStatus?.call(
        transferId: id,
        status: 'completed',
        localUri: finalFile.path,
      );

      await _deleteReceiveManifest(id);
      await _resetTransferState(keepFinalFile: true);
    } catch (e) {
      await _failTransfer(
        id,
        'Dosya doğrulanamadı veya kaydedilemedi: $e',
        reset: true,
        incoming: true,
      );
    }
  }

  Future<void> _sendCompletionWithRetry({
    required String transferId,
    required int fileSize,
    required String sha256,
  }) async {
    final deadline = DateTime.now().add(
      backgroundTransferMode
          ? const Duration(minutes: 15)
          : const Duration(minutes: 5),
    );
    _completionAcknowledged = false;

    while (!_disposed &&
        _transferId == transferId &&
        DateTime.now().isBefore(deadline)) {
      if (_completionAcknowledged) return;

      if (!ws.connected) {
        if (!await _waitForConnection(const Duration(seconds: 30))) {
          continue;
        }
      }

      final sent = ws.send({
        'type': 'fileTransferComplete',
        'from': me,
        'to': peer,
        'transferId': transferId,
        'fileSize': fileSize,
        'sha256': sha256,
      });

      if (sent) {
        final waitUntil = DateTime.now().add(const Duration(seconds: 3));
        while (!_disposed &&
            _transferId == transferId &&
            !_completionAcknowledged &&
            DateTime.now().isBefore(waitUntil)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        if (_completionAcknowledged) return;
      } else {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    throw TimeoutException('Dosya tamamlandı ancak sunucu onayı alınamadı.');
  }

  Future<void> _handleRemoteCompletion(Map<String, dynamic> event) async {
    final id = _transferId;
    if (_disposed ||
        _incomingTransfer ||
        id == null ||
        id.isEmpty ||
        _terminalEventHandled) {
      return;
    }

    final remoteSize = int.tryParse(event['fileSize']?.toString() ?? '') ?? 0;
    final remoteSha = (event['sha256'] ?? '').toString().trim().toLowerCase();

    if (remoteSize != _fileSize ||
        remoteSha.isEmpty ||
        remoteSha != (_sourceSha256 ?? '').trim().toLowerCase()) {
      await _failTransfer(id, 'Alıcı dosyayı doğrulayamadı.', reset: true);
      return;
    }

    _terminalEventHandled = true;

    onProgress?.call(
      transferId: id,
      sentBytes: _fileSize,
      totalBytes: _fileSize,
      status: 'completed',
    );

    await _resetTransferState();
  }

  Future<void> _prepareIncomingFile(String transferId) async {
    if (_incomingFile != null && _incomingTempFile != null) return;

    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/received_files');
    await dir.create(recursive: true);

    final temp = File('${dir.path}/${_sanitizeId(transferId)}.part');
    final manifest = await _readReceiveManifest(transferId);

    // A .part file is resumable only when its durable manifest proves that it
    // belongs to the same transfer. Never trust an orphaned/foreign partial
    // file after an app/process restart.
    var manifestValid = false;
    if (manifest != null) {
      final manifestId = (manifest['transferId'] ?? '').toString().trim();
      final manifestName = (manifest['fileName'] ?? '').toString().trim();
      final manifestSize = int.tryParse(
        (manifest['fileSize'] ?? '').toString(),
      ) ?? 0;
      final manifestSha = (manifest['sha256'] ?? '').toString().trim().toLowerCase();
      final manifestProtocol = int.tryParse(
        (manifest['protocolVersion'] ?? '').toString(),
      ) ?? 0;
      final manifestSeq = int.tryParse(
        (manifest['lastReceivedSeq'] ?? '').toString(),
      ) ?? -2;
      final manifestBytes = int.tryParse(
        (manifest['receivedBytes'] ?? '').toString(),
      ) ?? -1;
      final expectedSha = (_sourceSha256 ?? '').trim().toLowerCase();
      final maxSeq = _fileSize > 0
          ? ((_fileSize + _chunkSize - 1) ~/ _chunkSize) - 1
          : -1;

      manifestValid = manifestId == transferId &&
          manifestName == (_fileName ?? 'received_file') &&
          manifestSize == _fileSize &&
          manifestProtocol == 1 &&
          manifestSeq >= -1 &&
          manifestSeq <= maxSeq &&
          manifestBytes >= 0 &&
          manifestBytes <= _fileSize &&
          (expectedSha.isEmpty || manifestSha == expectedSha);

      if (!manifestValid) {
        await temp.delete().catchError((_) => temp);
        await _deleteReceiveManifest(transferId);
      }
    } else if (await temp.exists()) {
      // No metadata means we cannot prove which transfer produced the bytes.
      await temp.delete();
    }

    var existingLength = 0;
    if (manifestValid && await temp.exists()) {
      existingLength = await temp.length();

      if (existingLength > _fileSize && _fileSize > 0) {
        await temp.delete();
        await _deleteReceiveManifest(transferId);
        existingLength = 0;
        manifestValid = false;
      } else if (existingLength % _chunkSize != 0) {
        final completeLength =
            (existingLength ~/ _chunkSize) * _chunkSize;
        final truncateFile = await temp.open(mode: FileMode.append);
        await truncateFile.truncate(completeLength);
        await truncateFile.close();
        existingLength = completeLength;
      }

      // The physical .part length is the byte-level source of truth. The
      // manifest is metadata only and must describe exactly that prefix.
      final manifestBytes = int.tryParse(
        (manifest?['receivedBytes'] ?? '').toString(),
      ) ?? -1;
      final manifestSeq = int.tryParse(
        (manifest?['lastReceivedSeq'] ?? '').toString(),
      ) ?? -2;
      final expectedSeq = existingLength > 0
          ? (existingLength ~/ _chunkSize) - 1
          : -1;
      final expectedBytes = existingLength;
      if (manifestBytes != expectedBytes || manifestSeq != expectedSeq) {
        _diag(
          'RECEIVE_MANIFEST_NORMALIZED transfer=$transferId '
          'manifestBytes=$manifestBytes physicalBytes=$expectedBytes '
          'manifestSeq=$manifestSeq physicalSeq=$expectedSeq',
        );
      }
    }

    final raf = await temp.open(
      mode: existingLength > 0 ? FileMode.append : FileMode.write,
    );

    _incomingTempFile = temp;
    _incomingFile = raf;

    _receivedBytes = existingLength;
    _lastReceivedSeq =
        existingLength > 0 ? (existingLength ~/ _chunkSize) - 1 : -1;
    await _persistReceiveManifest(transferId);
  }

  Future<void> _failTransfer(
    String transferId,
    String reason, {
    bool reset = false,
    bool incoming = false,
  }) async {
    if (_disposed) return;

    if (!_terminalEventHandled) {
      _terminalEventHandled = true;
      _markTerminal(transferId);

      _diag(
        '${incoming ? 'INCOMING' : 'OUTGOING'}_TRANSFER_FAILED '
        'transfer=$transferId reason=$reason',
      );

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
    }

    if (reset && incoming) {
      await _deleteReceiveManifest(transferId);
    }

    if (reset && _transferId == transferId) {
      // A stale async send/receive task can finish after the user has already
      // started a new transfer. Never let that old task reset the new transfer.
      await _resetTransferState();
    }
  }

  void _markTerminal(String id) {
    if (id.trim().isNotEmpty) {
      _terminalTransferTombstones.add(id.trim());
      if (_terminalTransferTombstones.length > 256) {
        _terminalTransferTombstones.remove(_terminalTransferTombstones.first);
      }
    }
  }

  void _startConnectionTimeout(String id) {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 180), () {
      if (_disposed || _transferId != id || _terminalEventHandled) {
        return;
      }

      unawaited(
        _failTransfer(
          id,
          'Dosya bağlantısı 180 saniye içinde kurulamadı.',
          reset: true,
          incoming: _incomingTransfer,
        ),
      );
    });
  }

  void _startTransferTimeout(String id) {
    _transferTimeoutTimer?.cancel();

    // Background transfers can legitimately be paused by Android while the
    // foreground service is being resumed. Give those transfers a longer
    // inactivity window without weakening the normal foreground timeout.
    final timeout = backgroundTransferMode
        ? const Duration(minutes: 20)
        : const Duration(minutes: 10);

    _transferTimeoutTimer = Timer(timeout, () {
      if (_disposed || _transferId != id || _terminalEventHandled) {
        return;
      }

      unawaited(
        _failTransfer(
          id,
          backgroundTransferMode
              ? 'Dosya aktarımı 20 dakika boyunca ilerlemedi.'
              : 'Dosya aktarımı 10 dakika boyunca ilerlemedi.',
          reset: true,
          incoming: _incomingTransfer,
        ),
      );
    });
  }

  void _touchTransferTimeout(String id) {
    if (_disposed || _transferId != id || _terminalEventHandled) {
      return;
    }
    _startTransferTimeout(id);
  }

  void _cancelTimers() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = null;
    _transferTimeoutTimer?.cancel();
    _transferTimeoutTimer = null;
  }

  Future<void> _resetTransferState({bool keepFinalFile = false}) async {
    _cancelTimers();

    final waiter = _windowWaiter;
    _windowWaiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Dosya transferi sonlandırıldı.'));
    }

    try {
      await _incomingFile?.close();
    } catch (_) {}
    try {
      await _sendingRaf?.close();
    } catch (_) {}
    _sendingRaf = null;

    _incomingFile = null;

    if (_incomingTempFile != null && !keepFinalFile) {
      try {
        if (await _incomingTempFile!.exists()) {
          await _incomingTempFile!.delete();
        }
      } catch (_) {}
    }

    _incomingTempFile = null;

    _transferId = null;
    _fileName = null;
    _fileSize = 0;
    _sentBytes = 0;
    _receivedBytes = 0;
    _sendingFile = null;
    _sourceSha256 = null;
    _incomingTransfer = false;
    _accepted = false;
    _sending = false;
    _terminalEventHandled = false;
    _completionAcknowledged = false;
    _nextSendSeq = 0;
    _lastAckSeq = -1;
    _confirmedBytes = 0;
    _outstandingFrames.clear();
    _lastReceivedSeq = -1;
    }

  String _safeRandomPart() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  String _sanitizeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  String _fileExtension(String name) {
    final index = name.lastIndexOf('.');
    if (index <= 0 || index == name.length - 1) return '.bin';

    final ext = name.substring(index).toLowerCase();
    if (ext.length > 12 || !RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
      return '.bin';
    }

    return ext;
  }

  Uint8List _encodeChunkFrame({
    required String transferId,
    required int seq,
    required Uint8List payload,
  }) {
    final idBytes = utf8.encode(transferId);

    if (idBytes.isEmpty || idBytes.length > 65535) {
      throw StateError('Geçersiz transfer ID.');
    }

    final frame = Uint8List(4 + 1 + 2 + idBytes.length + 4 + payload.length);

    final data = ByteData.sublistView(frame);
    frame.setRange(0, 4, const <int>[0x5a, 0x4c, 0x46, 0x32]); // ZLF2
    frame[4] = 1;
    data.setUint16(5, idBytes.length);
    frame.setRange(7, 7 + idBytes.length, idBytes);
    data.setUint32(7 + idBytes.length, seq);
    frame.setRange(11 + idBytes.length, frame.length, payload);

    return frame;
  }

  Future<String> _calculateFileSha256(File file) async {
    final output = _ZeroLogDigestSink();
    final input = sha256.startChunkedConversion(output);

    final raf = await file.open();
    try {
      while (true) {
        final bytes = await raf.read(_chunkSize);
        if (bytes.isEmpty) break;
        input.add(bytes);
      }
    } finally {
      await raf.close();
    }

    input.close();
    final result = output.value;
    if (result == null) {
      throw StateError('SHA-256 hesaplanamadı.');
    }
    return result.toString();
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _resetTransferState();
    _sharedTransfers.remove(_sharedKey(me, peer));
  }
}
