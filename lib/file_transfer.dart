import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class FileTransfer {
  final dynamic ws;
  final String me;
  final String peer;

  RTCPeerConnection? _pc;
  RTCDataChannel? _channel;
  StreamSubscription? _eventsSub;

  String? _transferId;
  String? _fileName;
  IOSink? _sink;
  File? _outputFile;

  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteDescriptionSet = false;

  FileTransfer({required this.ws, required this.me, required this.peer});

  Future<void> initialize() async {
    await _createPeer();
  }

  Future<void> sendFile() async {
    final files = await FilePicker.pickFiles();

    if (files.isEmpty || files.first.path == null) return;

    // Yeni transfer başlamadan önce önceki transfer state'ini temizle.
    await _resetTransferState();

    // Eski PeerConnection kapatıldığı için yeni transfer için
    // temiz bir WebRTC signaling oturumu oluştur.
    await _createPeer();

    final selected = files.first;
    final file = File(selected.path!);
    final size = await file.length();

    if (size <= 0) return;

    final transferId = '${DateTime.now().microsecondsSinceEpoch}-$me';

    _transferId = transferId;
    _fileName = selected.name;

    final channel = await _pc!.createDataChannel(
      'file-$transferId',
      RTCDataChannelInit()..ordered = true,
    );

    _channel = channel;

    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _sendFileBytes(file);
      }
    };

    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': 0,
      'offerToReceiveVideo': 0,
    });

    await _pc!.setLocalDescription(offer);

    ws.send({
      'type': 'fileTransferOffer',
      'from': me,
      'to': peer,
      'transferId': transferId,
      'fileName': _fileName,
      'fileSize': size,
      'sdp': {'type': offer.type, 'sdp': offer.sdp},
    });
  }

  Future<void> _sendFileBytes(File file) async {
    final channel = _channel;
    if (channel == null) return;

    await for (final chunk in file.openRead()) {
      final bytes = Uint8List.fromList(chunk);

      while (await channel.getBufferedAmount() > 4 * 1024 * 1024) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      channel.send(RTCDataChannelMessage.fromBinary(bytes));
    }

    channel.send(
      RTCDataChannelMessage('{"type":"file-end","transferId":"$_transferId"}'),
    );
  }

  Future<void> _createPeer() async {
    await _eventsSub?.cancel();
    await _pc?.close();

    _pendingIce.clear();
    _remoteDescriptionSet = false;

    _pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _transferId == null) return;

      ws.send({
        'type': 'fileTransferIce',
        'from': me,
        'to': peer,
        'transferId': _transferId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    _pc!.onDataChannel = (channel) {
      _channel = channel;

      channel.onMessage = (message) {
        _receiveChunk(message);
      };
    };

    _eventsSub = ws.events.listen(_handleEvent);
  }

  Future<void> _handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();

    final from = (event['from'] ?? '').toString().trim();
    final to = (event['to'] ?? '').toString().trim();

    // Yalnızca beklenen peer ile ilgili dosya transfer sinyallerini kabul et.
    if (from.isNotEmpty && from.toLowerCase() != peer.toLowerCase()) {
      return;
    }

    if (to.isNotEmpty && to.toLowerCase() != me.toLowerCase()) {
      return;
    }

    if (type == 'fileTransferOffer') {
      final incomingId = event['transferId']?.toString();
      if (incomingId == null || incomingId.isEmpty) return;

      // Aynı oturumda farklı bir transfer mevcutsa yeni offer'ı kabul etme.
      if (_transferId != null &&
          _transferId!.isNotEmpty &&
          _transferId != incomingId) {
        return;
      }
      await _handleOffer(event);
      return;
    }

    if (event['transferId']?.toString() != _transferId) return;

    switch (type) {
      case 'fileTransferAnswer':
        await _handleAnswer(event);
        break;

      case 'fileTransferIce':
        await _handleIce(event);
        break;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> event) async {
    final incomingId = event['transferId']?.toString();
    if (incomingId == null || incomingId.isEmpty) return;

    if (_pc == null) {
      await _createPeer();
    }

    _transferId = incomingId;
    _fileName = event['fileName']?.toString() ?? 'received_file';

    final sdp = Map<String, dynamic>.from(event['sdp']);

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
  }

  Future<void> _handleAnswer(Map<String, dynamic> event) async {
    final sdp = Map<String, dynamic>.from(event['sdp']);

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
    if (message.isBinary) {
      _sink ??= await _openOutput();

      final bytes = message.binary;
      _sink!.add(bytes);
      return;
    }

    try {
      final data = message.text;
      if (data.contains('"file-end"')) {
        await _sink?.flush();
        await _sink?.close();
        _sink = null;

        // Dosya alımı tamamlandı; sonraki transfer temiz state ile başlasın.
        await _resetTransferState();
      }
    } catch (_) {}
  }

  Future<IOSink> _openOutput() async {
    final safeName = (_fileName ?? 'received_file').replaceAll(
      RegExp(r'[/\\]'),
      '_',
    );

    final path = await FilePicker.saveFile(
      dialogTitle: 'ZeroLog dosyasını kaydet',
      fileName: safeName,
      bytes: Uint8List(0),
    );

    if (path == null) {
      throw StateError('Dosya kayıt konumu seçilmedi.');
    }

    _outputFile = File.fromUri(path);

    return _outputFile!.openWrite();
  }

  Future<void> _resetTransferState() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;

    _channel = null;
    _pendingIce.clear();
    _remoteDescriptionSet = false;
    _transferId = null;
    _fileName = null;

    // Yeni transfer için mevcut PeerConnection yeniden oluşturulacak.
    await _pc?.close();
    _pc = null;
  }

  Future<void> dispose() async {
    await _eventsSub?.cancel();
    await _sink?.flush();
    await _sink?.close();
    await _pc?.close();

    _eventsSub = null;
    _channel = null;
    _pc = null;

    _pendingIce.clear();
    _remoteDescriptionSet = false;
    _transferId = null;
    _fileName = null;
  }
}
