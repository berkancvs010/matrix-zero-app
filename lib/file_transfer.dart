import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// ZeroLog reliable file transport.
///
/// The transport deliberately uses one small state machine over the already
/// authenticated WsClient connection.  There is no parallel send window:
/// sender -> one binary chunk -> receiver writes -> ACK -> next chunk.
///
/// This is intentionally conservative.  Correctness, resumability and clear
/// failure boundaries are more important than maximum throughput.  The
/// server remains a relay only; file bytes are never persisted by the server.
class FileTransferCallbackHandle {
  FileTransferCallbackHandle._(this._owner);
  final FileTransfer _owner;
  bool _active = true;

  void dispose() {
    if (!_active) return;
    _active = false;
    _owner._removeCallbackBinding(this);
  }
}

class _FileTransferCallbackBinding {
  _FileTransferCallbackBinding({
    required this.handle,
    this.onProgress,
    this.onIncomingOffer,
    this.onIncomingStatus,
  });

  final FileTransferCallbackHandle handle;
  final void Function({
    required String transferId,
    required int sentBytes,
    required int totalBytes,
    required String status,
  })? onProgress;
  final void Function({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
  })? onIncomingOffer;
  final void Function({
    required String transferId,
    required String status,
    String? localUri,
  })? onIncomingStatus;
}

class FileTransfer {
  final dynamic ws;
  final String me;
  final String peer;

  String? turnUsername;
  String? turnPassword;
  List<String> turnUrls;

  static final Map<String, FileTransfer> _sharedTransfers =
      <String, FileTransfer>{};

  static bool backgroundTransferMode = false;

  static String _sharedKey(String a, String b) =>
      '${a.trim().toLowerCase()}|${b.trim().toLowerCase()}';

  static FileTransfer? active(String me, String peer) {
    final value = _sharedTransfers[_sharedKey(me, peer)];
    if (value == null || value._disposed || value._transferId == null) {
      return null;
    }
    return value;
  }

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

    final value = FileTransfer(
      ws: ws,
      me: me,
      peer: peer,
      turnUsername: turnUsername,
      turnPassword: turnPassword,
      turnUrls: List<String>.from(turnUrls),
    );
    _sharedTransfers[key] = value;
    return value;
  }

  FileTransfer({
    required this.ws,
    required this.me,
    required this.peer,
    this.turnUsername,
    this.turnPassword,
    this.turnUrls = const [],
  });

  static const int _chunkSize = 128 * 1024;
  static const int _maxFileSize = 1024 * 1024 * 1024;
  static const int _protocolVersion = 1;

  final List<_FileTransferCallbackBinding> _callbackBindings =
      <_FileTransferCallbackBinding>[];

  bool _initialized = false;
  bool _disposed = false;
  StreamSubscription? _eventsSub;

  String? _transferId;
  String? _fileName;
  int _fileSize = 0;
  int _sentBytes = 0;
  int _receivedBytes = 0;
  String? _sourceSha256;

  File? _sendingFile;
  RandomAccessFile? _sendingRaf;
  File? _incomingTempFile;
  RandomAccessFile? _incomingFile;

  bool _incomingTransfer = false;
  bool _accepted = false;
  bool _sending = false;
  bool _terminalEventHandled = false;
  bool _completionAcknowledged = false;
  bool _completionSending = false;

  int _nextSendSeq = 0;
  int _lastAckSeq = -1;
  int _lastReceivedSeq = -1;

  Completer<void>? _ackWaiter;
  Timer? _connectionTimer;
  Timer? _transferTimer;

  String? get currentTransferId => _transferId;
  String? get currentFileName => _fileName;
  int get currentFileSize => _fileSize;

  void _diag(String value) {
    // ignore: avoid_print
    print('[FILE_TRANSFER] $value');
  }

  FileTransferCallbackHandle bindCallbacks({
    void Function({
      required String transferId,
      required int sentBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
    void Function({
      required String transferId,
      required String fileName,
      required int fileSize,
      required String sender,
    })? onIncomingOffer,
    void Function({
      required String transferId,
      required String status,
      String? localUri,
    })? onIncomingStatus,
  }) {
    final handle = FileTransferCallbackHandle._(this);
    _callbackBindings.add(_FileTransferCallbackBinding(
      handle: handle,
      onProgress: onProgress,
      onIncomingOffer: onIncomingOffer,
      onIncomingStatus: onIncomingStatus,
    ));
    return handle;
  }

  void _removeCallbackBinding(FileTransferCallbackHandle handle) {
    _callbackBindings.removeWhere((item) => item.handle == handle);
  }

  void _emitProgress({
    required String transferId,
    required int sentBytes,
    required int totalBytes,
    required String status,
  }) {
    for (final binding in List<_FileTransferCallbackBinding>.from(
      _callbackBindings,
    )) {
      if (!binding.handle._active) continue;
      binding.onProgress?.call(
        transferId: transferId,
        sentBytes: sentBytes,
        totalBytes: totalBytes,
        status: status,
      );
    }
  }

  void _emitIncomingOffer({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
  }) {
    for (final binding in List<_FileTransferCallbackBinding>.from(
      _callbackBindings,
    )) {
      if (!binding.handle._active) continue;
      binding.onIncomingOffer?.call(
        transferId: transferId,
        fileName: fileName,
        fileSize: fileSize,
        sender: sender,
      );
    }
  }

  void _emitIncomingStatus({
    required String transferId,
    required String status,
    String? localUri,
  }) {
    for (final binding in List<_FileTransferCallbackBinding>.from(
      _callbackBindings,
    )) {
      if (!binding.handle._active) continue;
      binding.onIncomingStatus?.call(
        transferId: transferId,
        status: status,
        localUri: localUri,
      );
    }
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
    if (_disposed) throw StateError('Dosya aktarımı kullanılamıyor.');

    final File file;
    final String fileName;
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

    if (!await file.exists()) throw StateError('Seçilen dosya bulunamadı.');
    final size = await file.length();
    if (size <= 0) throw StateError('Seçilen dosya boş.');
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

    final id =
        '${DateTime.now().microsecondsSinceEpoch}-$me-${_safeRandomPart()}';
    _transferId = id;
    _fileName = fileName;
    _fileSize = size;
    _sendingFile = file;
    _sourceSha256 = (await _calculateFileSha256(file)).toLowerCase();
    _incomingTransfer = false;
    _accepted = false;
    _sending = false;
    _terminalEventHandled = false;
    _nextSendSeq = 0;
    _lastAckSeq = -1;
    _sentBytes = 0;

    _emitProgress(
      transferId: id,
      sentBytes: 0,
      totalBytes: size,
      status: 'waiting',
    );

    if (!ws.send({
      'type': 'fileTransferStart',
      'from': me,
      'to': peer,
      'transferId': id,
      'fileName': fileName,
      'fileSize': size,
      'sha256': _sourceSha256,
    })) {
      await _failTransfer(id, 'Dosya transferi sunucuya gönderilemedi.', reset: true);
      throw StateError('Dosya transferi sunucuya gönderilemedi.');
    }

    _startConnectionTimeout(id);
    return id;
  }

  Future<bool> prepareIncomingFromNotification({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
    String? sha256,
  }) async {
    if (_disposed || transferId.trim().isEmpty || fileSize <= 0 || fileSize > _maxFileSize) {
      return false;
    }
    final id = transferId.trim();
    if (_transferId == id) return true;
    if (_transferId != null && _transferId!.isNotEmpty) return false;

    try {
      await _resetTransferState();
      _incomingTransfer = true;
      _transferId = id;
      _fileName = fileName.trim().isEmpty ? 'received_file' : fileName.trim();
      _fileSize = fileSize;
      _sourceSha256 = (sha256 ?? '').trim().toLowerCase();
      if (_sourceSha256!.isNotEmpty && !_validSha(_sourceSha256!)) {
        await _resetTransferState();
        return false;
      }
      _receivedBytes = 0;
      _lastReceivedSeq = -1;
      await _prepareIncomingFile(id);
      _startConnectionTimeout(id);
      _emitIncomingOffer(
        transferId: id,
        fileName: _fileName!,
        fileSize: _fileSize,
        sender: sender,
      );
      return true;
    } catch (e) {
      _diag('INCOMING_PREPARE_FAILED transfer=$id error=$e');
      await _failTransfer(id, 'Gelen dosya hazırlanamadı: $e', reset: true, incoming: true);
      return false;
    }
  }

  Future<void> acceptIncoming(String transferId) async {
    final id = transferId.trim();
    if (_disposed || id.isEmpty || id != _transferId || !_incomingTransfer) return;
    if (_accepted) return;
    if (!ws.connected) throw StateError('Dosya kabul edilemedi: bağlantı hazır değil.');

    _accepted = true;
    _terminalEventHandled = false;
    _touchTransferTimeout(id);

    final sent = ws.send({
      'type': 'fileTransferAccept',
      'from': me,
      'to': peer,
      'transferId': id,
    });
    if (!sent) {
      _accepted = false;
      throw StateError('Dosya kabulü sunucuya gönderilemedi.');
    }
    _emitIncomingStatus(transferId: id, status: 'accepted');
    await _persistReceiveManifest(id);
  }

  Future<void> cancelTransfer(String transferId) async {
    final id = transferId.trim();
    if (id.isEmpty) return;

    // The UI can outlive the FileTransfer isolate that owned a background
    // transfer. In that case there is no local _transferId, but the server
    // still owns the durable transfer session. Send the terminal cancel
    // directly so the Cancel button remains effective after background work.
    if (id != _transferId) {
      if (ws.connected) {
        final sent = ws.send({
          'type': 'fileTransferFailed',
          'from': me,
          'to': peer,
          'transferId': id,
          'reason': 'Dosya transferi kullanıcı tarafından iptal edildi.',
        });
        if (sent) {
          _emitIncomingStatus(transferId: id, status: 'failed');
        }
      }
      return;
    }

    if (ws.connected) {
      ws.send({
        'type': 'fileTransferFailed',
        'from': me,
        'to': peer,
        'transferId': id,
        'reason': 'Dosya transferi kullanıcı tarafından iptal edildi.',
      });
    }
    await _failTransfer(id, 'Dosya transferi iptal edildi.', reset: true);
  }

  Future<void> rejectIncoming(String transferId) async {
    final id = transferId.trim();
    if (id.isEmpty || id != _transferId || !_incomingTransfer) return;
    if (ws.connected) {
      ws.send({
        'type': 'fileTransferReject',
        'from': me,
        'to': peer,
        'transferId': id,
      });
    }
    await _failTransfer(id, 'Dosya karşı tarafça reddedildi.', reset: true, incoming: true);
  }

  // The FileTransfer instance's own internal WsClient subscription (see
  // initialize()) and an external caller (e.g. MainScreen's background-accept
  // path, which also calls handleExternalEvent directly after initialize())
  // can both receive the SAME event. Several handlers below (notably
  // _handleOffer) are not atomic across their `await` points, so two
  // concurrent entries for the same event could both pass an early guard
  // before either one updates state. Serializing every entry through this
  // queue removes that window. Long-running work (the outgoing chunk send
  // loop) stays outside the queue via `unawaited` in _handleAccept, so a
  // slow transfer can never block subsequent ACK/resume events from being
  // processed - only the (cheap, synchronous-ish) event handlers themselves
  // are serialized.
  Future<void> _eventQueue = Future<void>.value();

  Future<void> handleExternalEvent(Map<String, dynamic> event) async {
    final next = _eventQueue.then((_) => _dispatchEvent(event));
    _eventQueue = next.catchError((Object error, StackTrace stack) {
      _diag('EVENT_QUEUE_ERROR error=$error');
    });
    await _eventQueue;
  }

  Future<void> _dispatchEvent(Map<String, dynamic> event) async {
    if (_disposed) return;
    final type = (event['type'] ?? '').toString();
    if (!type.startsWith('fileTransfer')) return;

    // A stale terminal event must never destroy a newer transfer.
    final eventId = (event['transferId'] ?? '').toString().trim();
    if (eventId.isNotEmpty &&
        _transferId != null &&
        eventId != _transferId &&
        type != 'fileTransferOffer' &&
        type != 'fileTransferStart') {
      if (type == 'fileTransferFailed') {
        _diag('FAILED_IGNORED transfer=$eventId current=$_transferId');
      }
      return;
    }

    switch (type) {
      case 'fileTransferStartAck':
        if (!_incomingTransfer && eventId == _transferId) {
          _emitProgress(
            transferId: eventId,
            sentBytes: _sentBytes,
            totalBytes: _fileSize,
            status: 'stored',
          );
        }
        return;

      case 'fileTransferOffer':
        await _handleOffer(event);
        return;

      case 'fileTransferAccept':
        await _handleAccept(event);
        return;

      case 'fileTransferChunkAck':
        _handleChunkAck(event);
        return;

      case 'fileTransferChunk':
        // _handleChunk throws on any protocol violation (bad sequence,
        // wrong size, missing file handle). It must never escape as an
        // unhandled async error - that would leave the transfer stuck
        // (no _failTransfer sent, no local state reset) instead of
        // failing cleanly and letting the user retry.
        try {
          await _handleChunk(event);
        } catch (e) {
          final id = _transferId;
          if (id != null) {
            await _failTransfer(id, 'Dosya parçası işlenemedi: $e', reset: true, incoming: true);
          }
        }
        return;

      case 'fileTransferEnd':
        await _handleEnd(event);
        return;

      case 'fileTransferComplete':
        await _handleComplete(event);
        return;

      case 'fileTransferCompleteAck':
        if (_incomingTransfer && eventId == _transferId) {
          _completionAcknowledged = true;
        }
        return;

      case 'fileTransferReject':
        if (!_incomingTransfer && eventId == _transferId) {
          await _failTransfer(eventId, 'Karşı taraf dosyayı reddetti.', reset: true);
        }
        return;

      case 'fileTransferFailed':
        if (eventId != _transferId) return;
        ws.send({
          'type': 'fileTransferFailedAck',
          'from': me,
          'to': peer,
          'transferId': eventId,
        });
        await _failTransfer(
          eventId,
          (event['reason']?.toString().trim().isNotEmpty ?? false)
              ? event['reason'].toString().trim()
              : 'Dosya transferi karşı tarafta başarısız oldu.',
          reset: true,
          incoming: _incomingTransfer,
        );
        return;

      case 'fileTransferResumeState':
        await _handleResumeState(event);
        return;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> event) async {
    final id = (event['transferId'] ?? '').toString().trim();
    final from = (event['from'] ?? '').toString().trim();
    final to = (event['to'] ?? '').toString().trim();
    final size = _asInt(event['fileSize']);
    final name = (event['fileName'] ?? 'Dosya').toString().trim();
    final sha = (event['sha256'] ?? '').toString().trim().toLowerCase();

    if (id.isEmpty || from.toLowerCase() != peer.toLowerCase() ||
        (to.isNotEmpty && to.toLowerCase() != me.toLowerCase()) ||
        size <= 0 || size > _maxFileSize || name.isEmpty) {
      return;
    }

    if (_transferId != null && _transferId != id) return;
    if (_transferId == id) {
      if (_incomingTransfer && sha.isNotEmpty && _sourceSha256 != sha) {
        await _failTransfer(id, 'Dosya transferi metadata bilgisi değişti.', reset: true, incoming: true);
        return;
      }
      if (_incomingTransfer && !_accepted) await acceptIncoming(id);
      return;
    }

    await _resetTransferState();
    _incomingTransfer = true;
    _transferId = id;
    _fileName = name;
    _fileSize = size;
    _sourceSha256 = sha;
    _receivedBytes = 0;
    _lastReceivedSeq = -1;

    try {
      await _prepareIncomingFile(id);
      _startConnectionTimeout(id);
      _emitIncomingOffer(
        transferId: id,
        fileName: name,
        fileSize: size,
        sender: from,
      );
    } catch (e) {
      await _failTransfer(id, 'Gelen dosya hazırlanamadı: $e', reset: true, incoming: true);
    }
  }

  Future<void> _handleAccept(Map<String, dynamic> event) async {
    final id = (event['transferId'] ?? '').toString().trim();
    if (id.isEmpty || id != _transferId) {
      _diag('ACCEPT_REJECTED reason=transfer_id_mismatch expected=$_transferId received=$id');
      return;
    }

    _diag(
      'ACCEPT_RECEIVED transfer=$id incoming=$_incomingTransfer '
      'sending=$_sending sendingFile=${_sendingFile != null}',
    );

    if (_incomingTransfer || _sending || _sendingFile == null) return;
    _accepted = true;
    _diag('SEND_START_REQUEST transfer=$id');
    // Do not block the serialized event queue while the outgoing transfer waits for ACK.
    unawaited(_startOutgoingTransfer());
  }

  void _handleChunkAck(Map<String, dynamic> event) {
    if (_incomingTransfer || !_sending || event['transferId']?.toString() != _transferId) return;
    final seq = _asInt(event['receivedSeq']);
    if (seq < _lastAckSeq || seq >= _nextSendSeq) return;
    _lastAckSeq = seq;
    final waiter = _ackWaiter;
    _ackWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    _touchTransferTimeout(_transferId!);
    _emitProgress(
      transferId: _transferId!,
      sentBytes: _lastAckedBytes(seq),
      totalBytes: _fileSize,
      status: 'transferring',
    );
  }

  Future<void> _handleChunk(Map<String, dynamic> event) async {
    final id = _transferId;
    if (_disposed || !_incomingTransfer || !_accepted || id == null || event['transferId']?.toString() != id) return;

    final seq = _asInt(event['seq']);
    final bytes = event['bytes'];
    final payload = bytes is Uint8List
        ? bytes
        : bytes is List<int>
            ? Uint8List.fromList(bytes)
            : null;
    if (payload == null) throw StateError('Dosya parçası verisi geçersiz.');

    final maxSeq = (_fileSize + _chunkSize - 1) ~/ _chunkSize - 1;
    if (seq < 0 || seq > maxSeq) throw StateError('Geçersiz dosya parça numarası.');
    final expected = seq == maxSeq ? _fileSize - seq * _chunkSize : _chunkSize;
    if (payload.length != expected) throw StateError('Dosya parçasının boyutu geçersiz.');

    if (seq <= _lastReceivedSeq) {
      ws.send({
        'type': 'fileTransferChunkAck',
        'from': me,
        'to': peer,
        'transferId': id,
        'receivedSeq': _lastReceivedSeq,
      });
      return;
    }
    if (seq != _lastReceivedSeq + 1) {
      throw StateError('Dosya parça sırası bozuldu.');
    }

    final file = _incomingFile;
    if (file == null) throw StateError('Alıcı dosya akışı hazır değil.');
    await file.writeFrom(payload);
    _lastReceivedSeq = seq;
    _receivedBytes += payload.length;
    _touchTransferTimeout(id);

    _emitProgress(
      transferId: id,
      sentBytes: _receivedBytes,
      totalBytes: _fileSize,
      status: 'transferring',
    );

    if (!ws.send({
      'type': 'fileTransferChunkAck',
      'from': me,
      'to': peer,
      'transferId': id,
      'receivedSeq': seq,
    })) {
      throw StateError('Dosya ACK gönderilemedi.');
    }
    await _persistReceiveManifest(id);
  }

  Future<void> _handleEnd(Map<String, dynamic> event) async {
    final id = _transferId;
    if (_disposed || !_incomingTransfer || !_accepted || id == null || event['transferId']?.toString() != id) return;
    // Once the verified file has been committed locally, completion is sent
    // by a separate task so the event queue stays free to receive the ACK.
    // Duplicate END events during that period are harmless and must not try
    // to reopen/rename a temp file that has already been committed.
    if (_completionSending) return;
    final declaredSize = _asInt(event['fileSize']);
    final declaredSha = (event['sha256'] ?? '').toString().trim().toLowerCase();
    if (declaredSize != _fileSize || _receivedBytes != _fileSize || !_validSha(declaredSha)) {
      await _failTransfer(id, 'Alınan dosya boyutu veya doğrulama bilgisi hatalı.', reset: true, incoming: true);
      return;
    }

    try {
      final raf = _incomingFile;
      final temp = _incomingTempFile;
      if (raf == null || temp == null) throw StateError('Alınan dosya akışı bulunamadı.');
      await raf.flush();
      await raf.close();
      _incomingFile = null;

      final actualSha = (await _calculateFileSha256(temp)).toLowerCase();
      if (actualSha != declaredSha ||
          (_sourceSha256?.isNotEmpty == true && _sourceSha256 != declaredSha)) {
        throw StateError('Dosya SHA-256 doğrulaması başarısız.');
      }

      final support = await getApplicationSupportDirectory();
      final dir = Directory('${support.path}/received_files');
      await dir.create(recursive: true);
      final finalFile = File('${dir.path}/${_sanitizeId(id)}${_fileExtension(_fileName ?? 'Dosya')}');
      if (await finalFile.exists()) await finalFile.delete();
      await temp.rename(finalFile.path);
      _incomingTempFile = null;

      // Completion ACK is itself a WebSocket event. Do not await the retry
      // loop from the serialized event queue, otherwise the queue would be
      // blocked waiting for the very ACK it must process.
      if (_completionSending) return;
      _completionSending = true;
      unawaited(_finishIncomingTransferAfterCommit(id, actualSha, finalFile));
    } catch (e) {
      await _failTransfer(id, 'Dosya doğrulanamadı veya kaydedilemedi: $e', reset: true, incoming: true);
    }
  }

  Future<void> _finishIncomingTransferAfterCommit(
    String id,
    String actualSha,
    File finalFile,
  ) async {
    try {
      await _sendCompletionWithRetry(id, _fileSize, actualSha);
      if (_transferId != id) {
        // Something else (e.g. a fileTransferFailed for this same id, or a
        // manual cancel) already reset this transfer's state while we were
        // waiting for the completion ACK. The file was already committed to
        // its final location above, so it must still be cleaned up here -
        // otherwise it is silently orphaned on disk with no manifest entry
        // and no UI status.
        try {
          if (await finalFile.exists()) await finalFile.delete();
        } catch (_) {}
        await _deleteReceiveManifest(id);
        return;
      }
      _terminalEventHandled = true;
      _completionSending = false;
      _emitIncomingStatus(
        transferId: id,
        status: 'completed',
        localUri: finalFile.path,
      );
      await _deleteReceiveManifest(id);
      await _resetTransferState(keepFinalFile: true);
    } catch (e) {
      if (_transferId == id) {
        _completionSending = false;
        _terminalEventHandled = false;
        try {
          if (await finalFile.exists()) await finalFile.delete();
        } catch (_) {}
        await _failTransfer(
          id,
          'Dosya tamamlanma onayı alınamadı: $e',
          reset: true,
          incoming: true,
        );
      }
    }
  }

  Future<void> _handleComplete(Map<String, dynamic> event) async {
    final id = _transferId;
    if (_disposed || _incomingTransfer || id == null || event['transferId']?.toString() != id) return;
    final size = _asInt(event['fileSize']);
    final sha = (event['sha256'] ?? '').toString().trim().toLowerCase();
    if (size != _fileSize || sha != (_sourceSha256 ?? '').toLowerCase()) {
      await _failTransfer(id, 'Alıcı dosyayı doğrulayamadı.', reset: true);
      return;
    }
    _terminalEventHandled = true;
    _emitProgress(transferId: id, sentBytes: _fileSize, totalBytes: _fileSize, status: 'completed');
    await _resetTransferState();
  }

  Future<void> _handleResumeState(Map<String, dynamic> event) async {
    final id = (event['transferId'] ?? '').toString().trim();
    if (id != _transferId || _terminalEventHandled) return;
    final stateFrom = (event['from'] ?? '').toString().trim().toLowerCase();
    final stateTo = (event['to'] ?? '').toString().trim().toLowerCase();
    final expectedSha = (_sourceSha256 ?? '').toLowerCase();
    if (stateFrom != peer.toLowerCase() || stateTo != me.toLowerCase() ||
        event['fileName']?.toString() != _fileName ||
        _asInt(event['fileSize']) != _fileSize ||
        event['sha256']?.toString().toLowerCase() != expectedSha ||
        _asInt(event['protocolVersion']) != _protocolVersion) {
      await _failTransfer(id, 'Resume metadata bilgisi eşleşmedi.', reset: true, incoming: _incomingTransfer);
      return;
    }
    if (_incomingTransfer) return;
    final seq = _asInt(event['lastReceivedSeq']);
    final maxSeq = (_fileSize + _chunkSize - 1) ~/ _chunkSize - 1;
    if (seq < -1 || seq > maxSeq) {
      await _failTransfer(id, 'Geçersiz resume sequence bilgisi.', reset: true);
      return;
    }
    _lastAckSeq = seq;
    _nextSendSeq = seq + 1;
    _sentBytes = _lastAckedBytes(seq);
    final waiter = _ackWaiter;
    _ackWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> _startOutgoingTransfer() async {
    final id = _transferId;
    final file = _sendingFile;
    if (_disposed || id == null || file == null || !_accepted || _sending || _terminalEventHandled) {
      _diag('SEND_START_BLOCKED transfer=${id ?? ''} hasFile=${file != null} accepted=$_accepted sending=$_sending terminal=$_terminalEventHandled');
      return;
    }

    _sending = true;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _startTransferTimeout(id);
    _diag('SEND_START_ENTERED transfer=$id fileSize=$_fileSize');

    try {
      final raf = await file.open();
      _sendingRaf = raf;
      try {
        while (!_disposed && !_terminalEventHandled && _transferId == id && _nextSendSeq * _chunkSize < _fileSize) {
          if (!ws.connected) {
            if (!await _waitForConnection(const Duration(seconds: 90))) {
              throw StateError('Dosya bağlantısı yeniden kurulamadı.');
            }
          }

          final seq = _nextSendSeq;
          final offset = seq * _chunkSize;
          await raf.setPosition(offset);
          _diag('CHUNK_READ_START transfer=$id seq=$seq offset=$offset');
          final bytes = await raf.read(_chunkSize);
          _diag('CHUNK_READ_OK transfer=$id seq=$seq bytes=${bytes.length}');
          if (bytes.isEmpty) throw StateError('Dosya okuma sırasında beklenmeyen son.');

          final frame = _encodeChunkFrame(id, seq, Uint8List.fromList(bytes));
          _diag('FIRST_CHUNK_SEND_ATTEMPT transfer=$id seq=$seq bytes=${bytes.length}');
          if (!ws.sendBinary(frame)) {
            throw StateError('Dosya parçası karşı tarafa gönderilemedi.');
          }
          _diag('FIRST_CHUNK_SENT transfer=$id seq=$seq bytes=${bytes.length}');

          _nextSendSeq = seq + 1;
          _sentBytes = mathMin(_fileSize, offset + bytes.length);
          _emitProgress(transferId: id, sentBytes: _lastAckedBytes(seq - 1), totalBytes: _fileSize, status: 'transferring');
          _touchTransferTimeout(id);

          await _waitForAck(id, seq);
        }
      } finally {
        if (identical(_sendingRaf, raf)) _sendingRaf = null;
        await raf.close();
      }

      await _sendEndAndWaitForCompletion(id);
    } catch (e) {
      await _failTransfer(id, 'Dosya gönderilirken hata oluştu: $e', reset: true);
    }
  }

  Future<void> _waitForAck(String id, int seq) async {
    if (_lastAckSeq >= seq) return;
    _ackWaiter?.complete();
    final waiter = Completer<void>();
    _ackWaiter = waiter;
    final deadline = DateTime.now().add(
      backgroundTransferMode
          ? const Duration(minutes: 3)
          : const Duration(seconds: 90),
    );
    while (!_disposed && _transferId == id && !_terminalEventHandled && _lastAckSeq < seq) {
      if (DateTime.now().isAfter(deadline)) throw TimeoutException('Dosya ACK zaman aşımına uğradı.');
      await Future.any<void>(<Future<void>>[
        waiter.future,
        Future<void>.delayed(const Duration(seconds: 1)),
      ]);
    }
    if (_lastAckSeq < seq) throw StateError('Dosya ACK alınamadı.');
  }

  Future<void> _sendEndAndWaitForCompletion(String id) async {
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    _completionAcknowledged = false;
    while (!_disposed && _transferId == id && !_terminalEventHandled && DateTime.now().isBefore(deadline)) {
      if (!ws.connected) {
        await _waitForConnection(const Duration(seconds: 30));
        continue;
      }
      final sent = ws.send({
        'type': 'fileTransferEnd',
        'from': me,
        'to': peer,
        'transferId': id,
        'fileSize': _fileSize,
        'sha256': _sourceSha256,
      });
      if (!sent) {
        await Future<void>.delayed(const Duration(seconds: 1));
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_terminalEventHandled) return;
    }
    if (!_terminalEventHandled) throw TimeoutException('Dosya tamamlanma onayı alınamadı.');
  }

  Future<void> _sendCompletionWithRetry(String id, int fileSize, String sha256) async {
    final deadline = DateTime.now().add(backgroundTransferMode ? const Duration(minutes: 15) : const Duration(minutes: 5));
    _completionAcknowledged = false;
    while (!_disposed && _transferId == id && DateTime.now().isBefore(deadline)) {
      if (_completionAcknowledged) return;
      if (ws.connected) {
        ws.send({'type': 'fileTransferComplete', 'from': me, 'to': peer, 'transferId': id, 'fileSize': fileSize, 'sha256': sha256});
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!_completionAcknowledged) throw TimeoutException('Dosya tamamlandı ancak sunucu onayı alınamadı.');
  }

  Future<bool> _waitForConnection(Duration timeout) async {
    if (ws.connected) return true;
    final end = DateTime.now().add(timeout);
    while (!_disposed && DateTime.now().isBefore(end)) {
      if (ws.connected) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return ws.connected;
  }

  Future<void> _sendResumeHandshake() async {
    final id = _transferId;
    if (_disposed || id == null || id.isEmpty || !ws.connected) return;
    final role = _incomingTransfer ? 'receiver' : 'sender';
    ws.send({
      'type': 'fileTransferResume',
      'from': me,
      'to': peer,
      'transferId': id,
      'role': role,
      'lastReceivedSeq': _incomingTransfer ? _lastReceivedSeq : _lastAckSeq,
      'fileName': _fileName,
      'fileSize': _fileSize,
      'sha256': _sourceSha256,
      'protocolVersion': _protocolVersion,
    });
  }

  Future<void> _prepareIncomingFile(String id) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/received_files');
    await dir.create(recursive: true);
    final temp = File('${dir.path}/${_sanitizeId(id)}.part');
    final manifest = await _readReceiveManifest(id);
    if (manifest != null) {
      final seq = _asInt(manifest['lastReceivedSeq']);
      final bytes = _asInt(manifest['receivedBytes']);
      if (seq >= -1 && bytes >= 0 && bytes <= _fileSize) {
        _lastReceivedSeq = seq;
        _receivedBytes = bytes;
      }
    }
    final raf = await temp.open(mode: FileMode.writeOnlyAppend);
    final length = await temp.length();
    final expected = _lastReceivedSeq < 0 ? 0 : _lastReceivedSeq * _chunkSize +
        ((_lastReceivedSeq == ((_fileSize + _chunkSize - 1) ~/ _chunkSize - 1)) ? _fileSize - _lastReceivedSeq * _chunkSize : _chunkSize);
    if (length != expected) {
      await raf.close();
      if (await temp.exists()) await temp.delete();
      _lastReceivedSeq = -1;
      _receivedBytes = 0;
      _incomingTempFile = temp;
      _incomingFile = await temp.open(mode: FileMode.writeOnlyAppend);
    } else {
      _incomingTempFile = temp;
      _incomingFile = raf;
    }
  }

  Future<Map<String, dynamic>?> _readReceiveManifest(String id) async {
    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/received_files/${_sanitizeId(id)}.manifest.json');
    if (!await file.exists()) return null;
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map ? Map<String, dynamic>.from(value) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistReceiveManifest(String id) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/received_files');
    await dir.create(recursive: true);
    final file = File('${dir.path}/${_sanitizeId(id)}.manifest.json');
    await file.writeAsString(jsonEncode({
      'transferId': id,
      'fileName': _fileName,
      'fileSize': _fileSize,
      'sha256': _sourceSha256,
      'lastReceivedSeq': _lastReceivedSeq,
      'receivedBytes': _receivedBytes,
    }));
  }

  Future<void> _deleteReceiveManifest(String id) async {
    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/received_files/${_sanitizeId(id)}.manifest.json');
    if (await file.exists()) await file.delete();
  }

  Future<void> _failTransfer(String id, String reason, {bool reset = false, bool incoming = false}) async {
    if (id.isEmpty) return;
    if (!_terminalEventHandled && ws.connected) {
      ws.send({'type': 'fileTransferFailed', 'from': me, 'to': peer, 'transferId': id, 'reason': reason});
    }
    _terminalEventHandled = true;
    _diag('FAILED transfer=$id incoming=${incoming || _incomingTransfer} reason=$reason');
    _emitIncomingStatus(transferId: id, status: 'failed');
    if (reset) await _resetTransferState();
  }

  Future<void> _resetTransferState({bool keepFinalFile = false}) async {
    _cancelTimers();
    _ackWaiter = null;
    final rafIn = _incomingFile;
    _incomingFile = null;
    if (rafIn != null) {
      try { await rafIn.close(); } catch (_) {}
    }
    final rafOut = _sendingRaf;
    _sendingRaf = null;
    if (rafOut != null) {
      try { await rafOut.close(); } catch (_) {}
    }
    final temp = _incomingTempFile;
    _incomingTempFile = null;
    if (!keepFinalFile && temp != null) {
      try { if (await temp.exists()) await temp.delete(); } catch (_) {}
      if (_transferId != null) await _deleteReceiveManifest(_transferId!);
    }
    _transferId = null;
    _fileName = null;
    _fileSize = 0;
    _sentBytes = 0;
    _receivedBytes = 0;
    _sourceSha256 = null;
    _sendingFile = null;
    _incomingTransfer = false;
    _accepted = false;
    _sending = false;
    _terminalEventHandled = false;
    _completionAcknowledged = false;
    _completionSending = false;
    _nextSendSeq = 0;
    _lastAckSeq = -1;
    _lastReceivedSeq = -1;
  }

  void _startConnectionTimeout(String id) {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: 180), () {
      if (_transferId == id && !_accepted) {
        unawaited(_failTransfer(id, 'Karşı taraf bağlantısı zaman aşımına uğradı.', reset: true, incoming: _incomingTransfer));
      }
    });
  }

  void _startTransferTimeout(String id) {
    _transferTimer?.cancel();
    _transferTimer = Timer(
      backgroundTransferMode
          ? const Duration(minutes: 5)
          : const Duration(seconds: 90),
      () {
        if (_transferId == id && !_terminalEventHandled) {
          unawaited(_failTransfer(id, 'Dosya transferi zaman aşımına uğradı.', reset: true, incoming: _incomingTransfer));
        }
      },
    );
  }

  void _touchTransferTimeout(String id) {
    if (_transferId != id) return;
    _startTransferTimeout(id);
  }

  void _cancelTimers() {
    _connectionTimer?.cancel();
    _transferTimer?.cancel();
    _connectionTimer = null;
    _transferTimer = null;
  }

  int _lastAckedBytes(int seq) {
    if (seq < 0) return 0;
    final end = (seq + 1) * _chunkSize;
    return end > _fileSize ? _fileSize : end;
  }

  Uint8List _encodeChunkFrame(String id, int seq, Uint8List payload) {
    // Must match WsClient._decodeFileTransferChunk and the server's ZLF2
    // relay parser exactly: magic(4) + version(1) + idLength(2) + id + seq(4).
    final idBytes = utf8.encode(id);
    if (idBytes.isEmpty || idBytes.length > 256) {
      throw StateError('Transfer ID çok uzun.');
    }
    final prefix = ByteData(7);
    prefix.setUint8(0, 0x5a);
    prefix.setUint8(1, 0x4c);
    prefix.setUint8(2, 0x46);
    prefix.setUint8(3, 0x32);
    prefix.setUint8(4, _protocolVersion);
    prefix.setUint16(5, idBytes.length, Endian.big);
    final sequence = ByteData(4);
    sequence.setUint32(0, seq, Endian.big);
    final frame = BytesBuilder(copy: false);
    frame.add(prefix.buffer.asUint8List());
    frame.add(idBytes);
    frame.add(sequence.buffer.asUint8List());
    frame.add(payload);
    return frame.takeBytes();
  }

  Future<String> _calculateFileSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  bool _validSha(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? -999999;
  }

  String _safeRandomPart() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  String _sanitizeId(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  String _fileExtension(String name) {
    final index = name.lastIndexOf('.');
    if (index <= 0 || index == name.length - 1) return '';
    final ext = name.substring(index).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
    return ext.length <= 16 ? ext : '';
  }

  int mathMin(int a, int b) => a < b ? a : b;

  @override
  String toString() => 'FileTransfer($me->$peer)';

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventsSub?.cancel();
    _eventsSub = null;
    await _resetTransferState();
    _callbackBindings.clear();
    final key = _sharedKey(me, peer);
    if (identical(_sharedTransfers[key], this)) _sharedTransfers.remove(key);
  }
}
