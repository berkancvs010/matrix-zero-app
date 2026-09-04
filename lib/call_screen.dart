part of 'main.dart';

class CallScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final bool outgoing;
  final String? callId;
  final String? incomingOffer;

  const CallScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
    required this.outgoing,
    this.callId,
    this.incomingOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<RTCIceCandidate> _pendingIceCandidates = [];
  final List<RTCIceCandidate> _pendingOutgoingIceCandidates = [];

  bool _accepted = false;
  bool _connected = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _closing = false;
  bool _remoteDescriptionSet = false;

  Timer? _outgoingTimeoutTimer;
  Timer? _callDurationTimer;
  DateTime? _connectedAt;
  Duration _callDuration = Duration.zero;

  StreamSubscription<int>? _proximitySubscription;
  bool _proximityScreenOffEnabled = false;

  Future<void> _initProximitySensor() async {
    if (_proximitySubscription != null ||
        _proximityScreenOffEnabled ||
        _closing ||
        !mounted) {
      return;
    }

    try {
      // Proximity ekran kontrolünü yalnızca aktif aramada başlat.
      await ProximitySensor.setProximityScreenOff(true);

      if (!mounted || _closing) {
        try {
          await ProximitySensor.setProximityScreenOff(false);
        } catch (_) {}
        return;
      }

      _proximityScreenOffEnabled = true;

      _proximitySubscription = ProximitySensor.events.listen((value) {
        if (!mounted || _closing) return;

        // 0 = uzak, >0 = yakın.
        // Ekran kontrolünü proximity_sensor'ın kendi mekanizması yapar.
        final isNear = value > 0;

        if (isNear) {
          // Telefon kulağa yaklaştırıldı.
        } else {
          // Telefon kulaktan uzaklaştırıldı.
        }
      });
    } catch (_) {}
  }

  void _flushPendingOutgoingIce() {
    if (_closing || _pendingOutgoingIceCandidates.isEmpty) return;

    final pending =
        List<RTCIceCandidate>.from(_pendingOutgoingIceCandidates);
    _pendingOutgoingIceCandidates.clear();

    for (final candidate in pending) {
      if (_closing || widget.callId == null || widget.callId!.isEmpty) {
        break;
      }

      final sent = WsClient.instance.send({
        'type': 'callIce',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });

      if (!sent) {
        _pendingOutgoingIceCandidates.add(candidate);
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    if (widget.outgoing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startOutgoingCall();
      });
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null || _closing) return;

    try {
      // Android voice communication audio session must be configured
      // before creating the WebRTC peer connection.
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );

      if (_closing) return;

      final iceServers = <Map<String, dynamic>>[
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ];

      final client = WsClient.instance;
      if (client.turnUsername != null &&
          client.turnUsername!.isNotEmpty &&
          client.turnPassword != null &&
          client.turnPassword!.isNotEmpty &&
          client.turnUrls.isNotEmpty) {
        iceServers.add({
          'urls': client.turnUrls,
          'username': client.turnUsername,
          'credential': client.turnPassword,
        });
      }

      final configuration = <String, dynamic>{
        'iceServers': iceServers,
        'iceTransportPolicy': 'all',
        'sdpSemantics': 'unified-plan',
      };

      final peer = await createPeerConnection(configuration);

      if (_closing) {
        try {
          await peer.close();
        } catch (_) {}
        try {
          await peer.dispose();
        } catch (_) {}
        return;
      }

      _peerConnection = peer;

      peer.onIceCandidate = (RTCIceCandidate candidate) {
        if (_closing || candidate.candidate == null) return;

        final sent = WsClient.instance.send({
          'type': 'callIce',
          'from': widget.myNick,
          'to': widget.targetNick,
          'callId': widget.callId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });

        if (!sent && !_closing) {
          _pendingOutgoingIceCandidates.add(candidate);
        }
      };

      peer.onConnectionState = (RTCPeerConnectionState state) {
        if (!mounted || _closing) return;

        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _startCallDuration();
          setState(() {
            _connected = true;
          });
        } else if (state ==
                RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
            state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          setState(() {
            _connected = false;
          });
        }
      };

      // Audio only. No camera is requested.
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });

      if (_closing) {
        for (final track in stream.getTracks()) {
          try {
            await track.stop();
          } catch (_) {}
        }
        try {
          await stream.dispose();
        } catch (_) {}
        return;
      }

      _localStream = stream;

      for (final track in stream.getAudioTracks()) {
        if (_closing) break;
        await peer.addTrack(track, stream);
      }

      if (_closing) return;

      // Start with normal handset audio. Speaker can be enabled
      // explicitly from the call screen.
      try {
        await Helper.setSpeakerphoneOn(false);
      } catch (_) {}
    } catch (e) {
      // Keep the failure inside the Flutter layer instead of leaving
      // partially initialized WebRTC objects behind.
      final peer = _peerConnection;
      _peerConnection = null;

      if (peer != null) {
        try {
          await peer.close();
        } catch (_) {}
        try {
          await peer.dispose();
        } catch (_) {}
      }

      rethrow;
    }
  }

  Future<void> _startOutgoingCall() async {
    if (_closing) return;

    // Mikrofon iznini ve proximity sensörünü çağrı tuşuna
    // basıldığı anda hazırla. Karşı tarafın cevap vermesini bekleme.
    final microphoneGranted = await ZeroLogPushService.requestCallPermissions();

    if (!microphoneGranted) {
      if (mounted && !_closing) {
        _showError('Mikrofon izni gerekli.');
      }
      return;
    }

    if (!_closing && mounted) {
      await _initProximitySensor();
    }

    await ZeroLogPushService.startOutgoingCallTone();

    final callId = widget.callId;
    if (callId == null || callId.isEmpty) {
      if (mounted) {
        _showError('Arama kimliği oluşturulamadı.');
      }
      return;
    }

    final inviteSent = WsClient.instance.send({
      'type': 'callInvite',
      'from': widget.myNick,
      'to': widget.targetNick,
      'callId': callId,
    });

    if (!inviteSent) {
      await ZeroLogPushService.stopOutgoingCallTone();
      if (mounted && !_closing) {
        _showError('Arama başlatılamadı: bağlantı hazır değil.');
      }
      await _finish(sendSignal: false);
      return;
    }

    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (_closing || !widget.outgoing) return;

      ZeroLogPushService.stopOutgoingCallTone();

      WsClient.instance.send({
        'type': 'callTimeout',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
      });

      if (mounted) {
        _showError('Cevap yok. Arama sonlandırıldı.');
      }

      _finish(sendSignal: false);
    });
  }

  Future<void> _startOutgoingOffer() async {
    if (_closing) return;

    debugPrint(
      '[CALL][OFFER] _startOutgoingOffer entered '
      'from=${widget.myNick} to=${widget.targetNick} '
      'callId=${widget.callId}',
    );

    try {
      await _createPeerConnection();

      final peer = _peerConnection;
      if (peer == null || _closing) return;

      final offer = await peer.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await peer.setLocalDescription(offer);

      if (_closing) return;

      final sent = WsClient.instance.send({
        'type': 'callOffer',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
        'sdp': offer.sdp,
      });

      if (!sent) {
        throw StateError('Arama bağlantı teklifi gönderilemedi.');
      }

      if (mounted) {
        setState(() {
          _accepted = true;
        });

        await _initProximitySensor();
      }
    } catch (e) {
      debugPrint('[CALL][OFFER] failed: $e');
      if (mounted && !_closing) {
        _showError('Arama başlatılamadı.');
      }
      if (!_closing) {
        await _finish(sendSignal: false);
      }
    }
  }

  Future<void> _acceptIncoming() async {
    if (_closing) return;

    final granted = await ZeroLogPushService.requestCallPermissions();

    if (!granted) {
      if (mounted) {
        _showError('Arama için mikrofon izni gerekiyor.');
      }
      await _finish(sendSignal: false);
      return;
    }

    final incomingOffer = widget.incomingOffer;

    try {
      if (incomingOffer == null || incomingOffer.isEmpty) {
        debugPrint(
          '[CALL][ACCEPT] sending callAccept '
          'from=${widget.myNick} to=${widget.targetNick} '
          'callId=${widget.callId}',
        );

        final sent = WsClient.instance.send({
          'type': 'callAccept',
          'from': widget.myNick,
          'to': widget.targetNick,
          'callId': widget.callId,
        });

        if (!sent) {
          throw StateError('Arama kabulü gönderilemedi.');
        }

        if (mounted) {
          setState(() {
            _accepted = true;
          });

          await _initProximitySensor();
        }

        await ZeroLogPushService.cancelIncomingCallNotification();
        return;
      }

      await _handleIncomingOffer(incomingOffer);
    } catch (e) {
      debugPrint('[CALL][ACCEPT] failed: $e');
      if (mounted && !_closing) {
        _showError('Arama kabul edilemedi.');
      }
      if (!_closing) {
        await _finish(sendSignal: false);
      }
    }
  }

  Future<void> _handleIncomingOffer(String incomingOffer) async {
    if (_closing) return;

    try {
      await _createPeerConnection();

      final peer = _peerConnection;
      if (peer == null || _closing) return;

      await peer.setRemoteDescription(
        RTCSessionDescription(incomingOffer, 'offer'),
      );

      _remoteDescriptionSet = true;

      await _flushPendingIceCandidates();

      final answer = await peer.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await peer.setLocalDescription(answer);

      if (_closing) return;

      final sent = WsClient.instance.send({
        'type': 'callAnswer',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
        'sdp': answer.sdp,
      });

      if (!sent) {
        throw StateError('Arama cevabı gönderilemedi.');
      }

      if (mounted) {
        setState(() {
          _accepted = true;
        });

        await _initProximitySensor();
      }

      await ZeroLogPushService.cancelIncomingCallNotification();
    } catch (e) {
      debugPrint('[CALL][ANSWER] failed: $e');
      if (mounted && !_closing) {
        _showError('Arama bağlantısı kurulamadı.');
      }
      if (!_closing) {
        await _finish(sendSignal: false);
      }
    }
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
    if (!mounted || _closing) return;

    final type = data['type'];

    if (type == 'connectionRestored' || type == 'registered') {
      _flushPendingOutgoingIce();
      if (_remoteDescriptionSet) {
        unawaited(_flushPendingIceCandidates());
      }
      return;
    }

    final from = (data['from'] ?? '').toString();
    final to = (data['to'] ?? '').toString();

    if (from.toLowerCase() != widget.targetNick.toLowerCase()) {
      return;
    }

    if (to.isNotEmpty && to.toLowerCase() != widget.myNick.toLowerCase()) {
      return;
    }

    final eventCallId = (data['callId'] ?? '').toString().trim();

    if (widget.callId != null &&
        widget.callId!.isNotEmpty &&
        eventCallId != widget.callId) {
      return;
    }

    if (type == 'callAccepted') {
      debugPrint(
        '[CALL][ACCEPTED] received '
        'from=$from to=$to callId=$eventCallId '
        'outgoing=${widget.outgoing}',
      );

      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      if (widget.outgoing) {
        _outgoingTimeoutTimer?.cancel();
        _outgoingTimeoutTimer = null;

        await ZeroLogPushService.stopOutgoingCallTone();

        debugPrint(
          '[CALL][ACCEPTED] starting outgoing offer '
          'callId=${widget.callId}',
        );

        await _startOutgoingOffer();
      }
    } else if (type == 'callRejected') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      _outgoingTimeoutTimer?.cancel();
      _outgoingTimeoutTimer = null;

      await ZeroLogPushService.stopOutgoingCallTone();

      if (mounted) {
        _showError('Arama reddedildi.');
      }

      await Future.delayed(const Duration(milliseconds: 700));

      if (!_closing) {
        _finish(sendSignal: false);
      }
    } else if (type == 'callAnswer') {
      _handleAnswer(data);
    } else if (type == 'callOffer') {
      if (!widget.outgoing && _accepted) {
        final sdp = data['sdp']?.toString();

        if (sdp != null && sdp.isNotEmpty) {
          _handleIncomingOffer(sdp);
        }
      }
    } else if (type == 'callIce') {
      _handleIceCandidate(data);
    } else if (type == 'callTimeout') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      _outgoingTimeoutTimer?.cancel();
      _outgoingTimeoutTimer = null;

      await ZeroLogPushService.stopOutgoingCallTone();

      if (!_closing) {
        _finish(sendSignal: false);
      }
    } else if (type == 'callEnded') {
      ZeroLogPushService.clearPendingCall();
      ZeroLogPushService.cancelIncomingCallNotification();
      ZeroLogPushService.clearCallLockScreen();
      _finish(sendSignal: false);
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final sdp = data['sdp']?.toString();
    final peer = _peerConnection;

    if (sdp == null || sdp.isEmpty || peer == null || _closing) {
      return;
    }

    try {
      await peer.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));

      _remoteDescriptionSet = true;
      await _flushPendingIceCandidates();
    } catch (e) {
      debugPrint('[CALL][ANSWER] remote description failed: $e');
      if (mounted && !_closing) {
        _showError('Arama bağlantı cevabı işlenemedi.');
        await _finish(sendSignal: false);
      }
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    final candidateText = data['candidate']?.toString();

    if (candidateText == null || candidateText.isEmpty || _closing) {
      return;
    }

    final ice = RTCIceCandidate(
      candidateText,
      data['sdpMid']?.toString(),
      data['sdpMLineIndex'] is int ? data['sdpMLineIndex'] as int : null,
    );

    final peer = _peerConnection;

    if (peer == null || !_remoteDescriptionSet) {
      _pendingIceCandidates.add(ice);
      return;
    }

    try {
      await peer.addCandidate(ice);
    } catch (e) {
      debugPrint('[CALL][ICE] add candidate failed: $e');
      _pendingIceCandidates.add(ice);
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    final peer = _peerConnection;

    if (peer == null ||
        !_remoteDescriptionSet ||
        _pendingIceCandidates.isEmpty) {
      return;
    }

    final pending = List<RTCIceCandidate>.from(_pendingIceCandidates);

    _pendingIceCandidates.clear();

    for (final candidate in pending) {
      try {
        await peer.addCandidate(candidate);
      } catch (e) {
        debugPrint('[CALL][ICE] pending candidate failed: $e');
        _pendingIceCandidates.add(candidate);
      }
    }
  }

  void _startCallDuration() {
    if (_connectedAt != null || _closing) return;

    _connectedAt = DateTime.now();
    _callDurationTimer?.cancel();

    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _closing || _connectedAt == null) return;

      setState(() {
        _callDuration = DateTime.now().difference(_connectedAt!);
      });
    });
  }

  String _formatCallDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _toggleMute() {
    final stream = _localStream;
    if (stream == null) return;

    final nextMuted = !_muted;

    for (final track in stream.getAudioTracks()) {
      track.enabled = !nextMuted;
    }

    if (mounted) {
      setState(() {
        _muted = nextMuted;
      });
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_closing) return;

    final next = !_speakerOn;

    try {
      await Helper.setSpeakerphoneOn(next);

      if (!mounted) return;

      setState(() {
        _speakerOn = next;
      });
    } catch (_) {
      if (mounted) {
        _showError('Ses çıkışı değiştirilemedi.');
      }
    }
  }

  void _reject() {
    if (_closing) return;

    WsClient.instance.send({
      'type': 'callReject',
      'from': widget.myNick,
      'to': widget.targetNick,
      'callId': widget.callId,
    });

    _finish(sendSignal: false);
  }

  Future<void> _finish({bool sendSignal = true}) async {
    if (_closing) return;

    _closing = true;

    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = null;

    _callDurationTimer?.cancel();
    _callDurationTimer = null;

    await ZeroLogPushService.stopOutgoingCallTone();
    await ZeroLogPushService.cancelIncomingCallNotification();
    await ZeroLogPushService.clearCallLockScreen();

    await _proximitySubscription?.cancel();
    _proximitySubscription = null;

    if (_proximityScreenOffEnabled) {
      try {
        await ProximitySensor.setProximityScreenOff(false);
      } catch (_) {}
      _proximityScreenOffEnabled = false;
    }

    _pendingOutgoingIceCandidates.clear();

    if (sendSignal) {
      WsClient.instance.send({
        'type': 'callEnd',
        'from': widget.myNick,
        'to': widget.targetNick,
        'callId': widget.callId,
      });
    }

    final stream = _localStream;
    _localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          track.enabled = false;
        } catch (_) {}

        try {
          await track.stop();
        } catch (_) {}
      }

      try {
        await stream.dispose();
      } catch (_) {}
    }

    final peer = _peerConnection;
    _peerConnection = null;

    if (peer != null) {
      try {
        await peer.close();
      } catch (_) {}

      try {
        await peer.dispose();
      } catch (_) {}
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showError(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _outgoingTimeoutTimer?.cancel();
    _outgoingTimeoutTimer = null;

    _callDurationTimer?.cancel();
    _callDurationTimer = null;

    ZeroLogPushService.stopOutgoingCallTone();
    ZeroLogPushService.clearCallLockScreen();

    _subscription.cancel();
    _proximitySubscription?.cancel();

    if (_proximityScreenOffEnabled) {
      ProximitySensor.setProximityScreenOff(false);
      _proximityScreenOffEnabled = false;
    }

    final stream = _localStream;
    _localStream = null;

    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          track.stop();
        } catch (_) {}
      }

      try {
        stream.dispose();
      } catch (_) {}
    }

    final peer = _peerConnection;
    _peerConnection = null;

    if (peer != null) {
      try {
        peer.close();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeController.instance.data;
    final waitingIncoming = !widget.outgoing && !_accepted;

    final status = waitingIncoming
        ? 'Gelen çağrı'
        : _connected
        ? 'Bağlandı'
        : widget.outgoing
        ? 'Aranıyor…'
        : 'Bağlanıyor…';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          elevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Text(
            'Şifreli Bağlantı',
            style: TextStyle(
              color: theme.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              children: [
                const Spacer(),

                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    color: theme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.primary.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: theme.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.targetNick.isEmpty
                              ? '?'
                              : widget.targetNick
                                    .trim()
                                    .substring(0, 1)
                                    .toUpperCase(),
                          style: TextStyle(
                            color: theme.primary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Text(
                  widget.targetNick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),

                const SizedBox(height: 9),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _connected
                            ? theme.primary
                            : theme.text.withValues(alpha: 0.30),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _connected
                          ? '$status • ${_formatCallDuration(_callDuration)}'
                          : status,
                      style: TextStyle(
                        color: _connected
                            ? theme.primary
                            : theme.text.withValues(alpha: 0.52),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 38),

                if (waitingIncoming)
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: _acceptIncoming,
                            icon: const Icon(Icons.call_rounded),
                            label: const Text(
                              'Kabul Et',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: FilledButton.tonalIcon(
                            onPressed: _reject,
                            icon: const Icon(Icons.call_end_rounded),
                            label: const Text(
                              'Reddet',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _callControl(
                        theme,
                        icon: _muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _muted ? 'Sessiz' : 'Mikrofon',
                        active: _muted,
                        onTap: _toggleMute,
                      ),
                      const SizedBox(width: 16),
                      _callControl(
                        theme,
                        icon: _speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.volume_down_rounded,
                        label: _speakerOn ? 'Hoparlör' : 'Kulaklık',
                        active: _speakerOn,
                        onTap: _toggleSpeaker,
                      ),
                      const SizedBox(width: 16),
                      _callControl(
                        theme,
                        icon: Icons.call_end_rounded,
                        label: 'Bitir',
                        destructive: true,
                        onTap: _finish,
                      ),
                    ],
                  ),

                const Spacer(),

                if (!waitingIncoming)
                  Text(
                    _connected
                        ? 'Görüşme güvenli bağlantı üzerinden devam ediyor.'
                        : 'Bağlantı kuruluyor, lütfen bekleyin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.text.withValues(alpha: 0.32),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _callControl(
    ZeroLogThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    bool destructive = false,
  }) {
    final foreground = destructive
        ? theme.text
        : active
        ? theme.primary
        : theme.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: destructive
              ? theme.text.withValues(alpha: 0.12)
              : active
              ? theme.primary.withValues(alpha: 0.14)
              : theme.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(icon, color: foreground, size: 23),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            color: theme.text.withValues(alpha: 0.46),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// INPUT
// ============================================================
