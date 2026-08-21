import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileTransfer {
  static const MethodChannel _systemChannel =
      MethodChannel('zerolog/system');
  final dynamic ws;
  final String me;
  final String peer;

  String? turnUsername;
  String? turnPassword;
  List<String> turnUrls;

  final void Function({
    required String transferId,
    required int sentBytes,
    required int totalBytes,
    required String status,
  })?
  onProgress;

  final void Function({
    required String transferId,
    required String fileName,
    required int fileSize,
    required String sender,
  })?
  onIncomingOffer;

  final void Function({required String transferId, required String status})?
  onIncomingStatus;

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
  bool _accepted = false;
  bool _disposed = false;

  final List<RTCIceCandidate> _pendingIce = [];
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

  Future<void> initialize() async {
    await _createPeer();
  }

  Future<void> sendFile() async {
    final files = await FilePicker.pickFiles();

    if (files.isEmpty || files.first.path == null) return;

    final selected = files.first;
    final file = File(selected.path!);
    final size = await file.length();

    if (size <= 0) {
      throw StateError('Seçilen dosya boş.');
    }

    await _resetTransferState();

    await _createPeer();

    final transferId = '${DateTime.now().microsecondsSinceEpoch}-$me';

    _transferId = transferId;
    _fileName = selected.name;
    _fileSize = size;
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

      onIncomingStatus?.call(
        transferId: transferId,
        status: 'accepting',
      );

      ws.send({
        'type': 'fileTransferAccept',
        'from': me,
        'to': peer,
        'transferId': transferId,
      });
    } catch (e) {
      _accepted = false;

      onIncomingStatus?.call(
        transferId: transferId,
        status: 'failed',
      );
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
        unawaited(_sendFileBytes(file));
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
          await Future<void>.delayed(
            const Duration(milliseconds: 20),
          );

          if (_disposed || _transferId != transferId) return;
        }

        await channel.send(
          RTCDataChannelMessage.fromBinary(
            Uint8List.fromList(bytes),
          ),
        );

        _sentBytes += bytes.length;

        onProgress?.call(
          transferId: transferId,
          sentBytes: _sentBytes,
          totalBytes: _fileSize,
          status: 'transferring',
        );
      }

      await channel.send(
        RTCDataChannelMessage(
          '{"type":"file-end","transferId":"$transferId"}',
        ),
      );

      onProgress?.call(
        transferId: transferId,
        sentBytes: _fileSize,
        totalBytes: _fileSize,
        status: 'completed',
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
    _remoteDescriptionSet = false;

    final iceServers = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:92.5.38.220:3478',
        ],
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
      final transferId = _transferId;

      if (candidate.candidate == null || transferId == null) {
        return;
      }

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

        unawaited(_receiveChunk(message));
      };
    };

    _eventsSub = ws.events.listen(_handleEvent);
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    if (_disposed) return;

    final type = event['type']?.toString();

    final from = (event['from'] ?? '').toString().trim();
    final to = (event['to'] ?? '').toString().trim();

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

      // SDP offer yalnızca kabulden sonra gönderilen gerçek
      // WebRTC offer'ı olarak işlenir.
      if (!hasSdp) {
        if (_transferId != null &&
            _transferId!.isNotEmpty &&
            _transferId != incomingId) {
          return;
        }

        await _prepareIncomingOffer(event);
        return;
      }

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
          await _startOutgoingTransfer();
        }
        break;

      case 'fileTransferReject':
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
    }
  }

  Future<void> _prepareIncomingOffer(Map<String, dynamic> event) async {
    final incomingId = event['transferId']?.toString();

    if (incomingId == null || incomingId.isEmpty) return;

    await _resetTransferState();
    await _createPeer();

    _transferId = incomingId;
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

    if (transferId == null || !_accepted) return;

    if (message.isBinary) {
      try {
        final bytes = message.binary;

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

        onProgress?.call(
          transferId: transferId,
          sentBytes: _receivedBytes,
          totalBytes: _fileSize,
          status: 'transferring',
        );
      } catch (_) {
        onIncomingStatus?.call(
          transferId: transferId,
          status: 'failed',
        );
      }

      return;
    }

    try {
      final data = message.text;

      if (data.contains('"file-end"')) {
        final closed = await _systemChannel.invokeMethod<bool>(
          'closeIncomingFile',
        );

        _nativeFileOpen = false;

        final actualSize = _receivedBytes;

        if (closed == true && actualSize == _fileSize) {
          onProgress?.call(
            transferId: transferId,
            sentBytes: actualSize,
            totalBytes: _fileSize,
            status: 'completed',
          );

          onIncomingStatus?.call(
            transferId: transferId,
            status: 'completed',
          );
        } else {
          onProgress?.call(
            transferId: transferId,
            sentBytes: actualSize,
            totalBytes: _fileSize,
            status: 'failed',
          );

          onIncomingStatus?.call(
            transferId: transferId,
            status: 'failed',
          );
        }

        await _resetTransferState();
      }
    } catch (_) {}
  }

  Future<void> _openOutput() async {
    final safeName = (_fileName ?? 'received_file').replaceAll(
      RegExp(r'[/\\]'),
      '_',
    );

    final result = await _systemChannel.invokeMethod<dynamic>(
      'requestIncomingFileSave',
      <String, dynamic>{
        'fileName': safeName,
      },
    );

    if (result == null) {
      throw StateError('Dosya kayıt konumu seçilmedi.');
    }

    _nativeFileOpen = true;
  }

  Future<void> _resetTransferState() async {
    if (_nativeFileOpen) {
      try {
        await _systemChannel.invokeMethod<bool>(
          'closeIncomingFile',
        );
      } catch (_) {}

      _nativeFileOpen = false;
    }

    _channel = null;
    _pendingIce.clear();
    _remoteDescriptionSet = false;

    _transferId = null;
    _fileName = null;
    _fileSize = 0;
    _receivedBytes = 0;
    _sentBytes = 0;

    _sendingFile = null;
    _sending = false;
    _accepted = false;

    await _pc?.close();
    _pc = null;
  }

  Future<void> dispose() async {
    _disposed = true;

    await _eventsSub?.cancel();

    if (_nativeFileOpen) {
      try {
        await _systemChannel.invokeMethod<bool>(
          'closeIncomingFile',
        );
      } catch (_) {}

      _nativeFileOpen = false;
    }

    await _pc?.close();

    _eventsSub = null;
    _channel = null;
    _pc = null;

    _pendingIce.clear();
    _remoteDescriptionSet = false;

    _transferId = null;
    _fileName = null;
    _fileSize = 0;
    _receivedBytes = 0;
    _sentBytes = 0;

    _sendingFile = null;
    _sending = false;
    _accepted = false;
  }

}
