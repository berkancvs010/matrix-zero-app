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

  int _nextSendSeq = 0;
  int _lastAckSeq = -1;
  int _lastReceivedSeq = -1;

  final Set<String> _terminalTransferTombstones = <String>{};

  Timer? _connectionTimeoutTimer;
  Timer? _transferTimeoutTimer;

  // At most 32 chunks can be outstanding. This keeps memory bounded even
  // when the receiver is slower than the sender.
  Completer<void>? _windowWaiter;

  Future<void> _receiveQueue = Future<void>.value();

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
      unawaited(_handleEvent(event));
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
    _sourceSha256 = await _calculateFileSha256(file);
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
  }) async {
    if (_disposed || transferId.trim().isEmpty || fileSize <= 0) return false;

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
    if (_disposed || _transferId != transferId || _accepted) return;

    try {
      if (_incomingTempFile == null || _incomingFile == null) {
        await _prepareIncomingFile(transferId);
      }

      _accepted = true;

      onIncomingStatus?.call(transferId: transferId, status: 'accepting');

      final sent = ws.send({
        'type': 'fileTransferAccept',
        'from': me,
        'to': peer,
        'transferId': transferId,
      });

      if (!sent) {
        throw StateError('Dosya kabulü sunucuya iletilemedi.');
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

  Future<void> rejectIncoming(String transferId) async {
    if (_disposed || _transferId != transferId) return;

    ws.send({
      'type': 'fileTransferReject',
      'from': me,
      'to': peer,
      'transferId': transferId,
    });

    onIncomingStatus?.call(transferId: transferId, status: 'rejected');

    await _resetTransferState();
  }

  Future<void> handleExternalEvent(Map<String, dynamic> event) async {
    await _handleEvent(event);
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    if (_disposed) return;

    final type = (event['type'] ?? '').toString();

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
      if (size <= 0 || name.isEmpty) return;

      if (_transferId != null && _transferId != id) return;

      if (_transferId == id) {
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

        if (receivedSeq > _lastAckSeq) {
          _lastAckSeq = receivedSeq;
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

      case 'fileTransferReject':
        if (!_incomingTransfer) {
          await _failTransfer(id, 'Karşı taraf dosyayı reddetti.', reset: true);
        }
        break;

      case 'fileTransferFailed':
        await _failTransfer(
          id,
          'Dosya transferi karşı tarafta başarısız oldu.',
          reset: true,
          incoming: _incomingTransfer,
        );
        break;

      case 'fileTransferChunk':
        final bytes = event['bytes'];
        if (bytes is Uint8List) {
          _receiveQueue = _receiveQueue.then(
            (_) => _receiveChunk(bytes, event['seq']),
          );
        } else if (bytes is List<int>) {
          _receiveQueue = _receiveQueue.then(
            (_) => _receiveChunk(Uint8List.fromList(bytes), event['seq']),
          );
        }
        break;

      case 'fileTransferEnd':
        await _receiveQueue;
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
    _startTransferTimeout(id);

    try {
      final raf = await file.open();
      try {
        const chunkSize = 32 * 1024;
        const windowSize = 32;

        while (true) {
          if (_disposed ||
              _terminalEventHandled ||
              _transferId != id ||
              !ws.connected) {
            throw StateError('Dosya bağlantısı kesildi.');
          }

          final bytes = await raf.read(chunkSize);
          if (bytes.isEmpty) break;

          final seq = _nextSendSeq++;

          final frame = _encodeChunkFrame(
            transferId: id,
            seq: seq,
            payload: Uint8List.fromList(bytes),
          );

          if (!ws.sendBinary(frame)) {
            throw StateError('Dosya parçası karşı tarafa gönderilemedi.');
          }

          _sentBytes += bytes.length;

          onProgress?.call(
            transferId: id,
            sentBytes: _sentBytes,
            totalBytes: _fileSize,
            status: 'transferring',
          );

          _touchTransferTimeout(id);

          if (seq - _lastAckSeq >= windowSize) {
            await _waitForAck(id, seq);
          }
        }
      } finally {
        await raf.close();
      }

      final sentEnd = ws.send({
        'type': 'fileTransferEnd',
        'from': me,
        'to': peer,
        'transferId': id,
        'fileSize': _sentBytes,
        'sha256': _sourceSha256,
      });

      if (!sentEnd) {
        throw StateError('Dosya bitiş bildirimi gönderilemedi.');
      }

      onProgress?.call(
        transferId: id,
        sentBytes: _sentBytes,
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

  Future<void> _waitForAck(String transferId, int targetSeq) async {
    if (_lastAckSeq >= targetSeq) return;

    final waiter = Completer<void>();
    _windowWaiter = waiter;

    final timeout = Timer(const Duration(seconds: 30), () {
      if (!waiter.isCompleted) {
        waiter.completeError(
          TimeoutException('Dosya alıcısından parça onayı alınamadı.'),
        );
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

    if (_disposed || _transferId != transferId) {
      throw StateError('Dosya transferi sonlandı.');
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

    if (seq < 0) {
      throw StateError('Geçersiz dosya parça numarası.');
    }

    if (seq <= _lastReceivedSeq) {
      // Duplicate delivery is harmless because the receiver is ordered.
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

    // ACK every 8 chunks and at the end. This gives the sender enough
    // throughput while keeping the outstanding frame window bounded.
    if (seq % 8 == 7 || _receivedBytes == _fileSize) {
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
      await _receiveQueue;

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

      // Dosya doğrulandı ve kalıcı konuma başarıyla taşındı.
      // COMPLETE bildirimi yalnızca karşı tarafa durum bilgisidir.
      // Gönderilememesi yerel olarak tamamlanmış dosyayı FAILED yapmamalıdır.
      ws.send({
        'type': 'fileTransferComplete',
        'from': me,
        'to': peer,
        'transferId': id,
        'fileSize': _receivedBytes,
        'sha256': actualSha,
      });

      onIncomingStatus?.call(
        transferId: id,
        status: 'completed',
        localUri: finalFile.path,
      );

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

    if (await temp.exists()) {
      await temp.delete();
    }

    final raf = await temp.open(mode: FileMode.write);

    _incomingTempFile = temp;
    _incomingFile = raf;
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

    if (reset) {
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
    _connectionTimeoutTimer = Timer(const Duration(seconds: 90), () {
      if (_disposed || _transferId != id || _terminalEventHandled) {
        return;
      }

      unawaited(
        _failTransfer(
          id,
          'Dosya bağlantısı 90 saniye içinde kurulamadı.',
          reset: true,
          incoming: _incomingTransfer,
        ),
      );
    });
  }

  void _startTransferTimeout(String id) {
    _transferTimeoutTimer?.cancel();
    _transferTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_disposed || _transferId != id || _terminalEventHandled) {
        return;
      }

      unawaited(
        _failTransfer(
          id,
          'Dosya aktarımı 60 saniye boyunca ilerlemedi.',
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
    _nextSendSeq = 0;
    _lastAckSeq = -1;
    _lastReceivedSeq = -1;
    _receiveQueue = Future<void>.value();
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
        final bytes = await raf.read(64 * 1024);
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
