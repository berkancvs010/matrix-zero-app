import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String wsUrl = 'wss://zerolog.giize.com:8443';

const List<String> rooms = [
  '1p09aq66zx6Qr9',
  '8k22bm91wx3Pt4',
  '9x44cn18yv7Ls2',
  '3z88dp52zu1Km8',
  '7v11er39xt5Jn3',
  '5m66fs84yq9Hb6',
  '2q33gt71zp2Wv1',
  '4w55hy03xr8Dc9',
  '6j99jx25yv4Fg5',
  '0n77kz46zt0Tq7',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatrixZeroApp());
}

// ============================================================
// APP
// ============================================================

class MatrixZeroApp extends StatelessWidget {
  const MatrixZeroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Zero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const NicknameScreen(),
    );
  }
}

// ============================================================
// WEBSOCKET SERVICE
// ============================================================

class WsClient {
  WsClient._();

  static final WsClient instance = WsClient._();

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  String? nickname;
  bool connected = false;

  Stream<Map<String, dynamic>> get events => _events.stream;

  Future<bool> connect(String nick) async {
    nickname = nick.trim();

    await disconnect();

    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel = channel;

      _subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw.toString());

            if (decoded is Map) {
              final data = Map<String, dynamic>.from(decoded);

              if (data['type'] == 'registered') {
                connected = data['success'] != false;
              }

              _events.add(data);
            }
          } catch (_) {
            // Bozuk paket sunucuyu/uygulamayı düşürmez.
          }
        },
        onError: (_) {
          connected = false;
          _events.add({
            'type': 'connectionError',
            'message': 'WebSocket bağlantısı kesildi.',
          });
        },
        onDone: () {
          connected = false;
          _events.add({
            'type': 'connectionClosed',
          });
        },
        cancelOnError: false,
      );

      await channel.ready;

      channel.sink.add(
        jsonEncode({
          'type': 'register',
          'nick': nickname,
        }),
      );

      connected = true;
      return true;
    } catch (_) {
      connected = false;
      return false;
    }
  }

  void send(Map<String, dynamic> data) {
    if (!connected || _channel == null) return;

    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (_) {
      connected = false;
    }
  }

  Future<void> disconnect() async {
    connected = false;

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
  }
}

// ============================================================
// NICKNAME
// ============================================================

class NicknameScreen extends StatefulWidget {
  const NicknameScreen({super.key});

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _connecting = false;

  Future<void> _enter() async {
    final nick = _controller.text.trim();

    if (nick.isEmpty) {
      _show('Lütfen bir rumuz girin.');
      return;
    }

    if (nick.length < 2) {
      _show('Rumuz en az 2 karakter olmalı.');
      return;
    }

    setState(() => _connecting = true);

    final ok = await WsClient.instance.connect(nick);

    if (!mounted) return;

    setState(() => _connecting = false);

    if (!ok) {
      _show('Sunucuya bağlanılamadı.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainScreen(nickname: nick),
      ),
    );
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZERO LOG'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 72,
                  color: Colors.greenAccent,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Matrix Zero',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sohbete katılmak için bir rumuz seçin.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _enter(),
                  decoration: const InputDecoration(
                    labelText: 'Rumuz',
                    hintText: 'Örn. Neo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _connecting ? null : _enter,
                    child: _connecting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('BAĞLAN'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// MAIN SCREEN
// ============================================================

class MainScreen extends StatefulWidget {
  final String nickname;

  const MainScreen({
    super.key,
    required this.nickname,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<String> _onlineUsers = [];
  bool _connected = false;

  @override
  void initState() {
    super.initState();

    _connected = WsClient.instance.connected;

    _subscription = WsClient.instance.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];

    if (type == 'registered') {
      setState(() {
        _connected = data['success'] != false;
      });
    }

    if (type == 'userList') {
      final rawUsers = data['users'];

      if (rawUsers is List) {
        final users = rawUsers
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .where((e) => e.toLowerCase() != widget.nickname.toLowerCase())
            .toSet()
            .toList();

        setState(() {
          _onlineUsers
            ..clear()
            ..addAll(users);
        });
      }
    }

    if (type == 'connectionError' || type == 'connectionClosed') {
      setState(() {
        _connected = false;
      });
    }
  }

  void _openRoom(String room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          nickname: widget.nickname,
          roomName: room,
        ),
      ),
    );
  }

  void _openPrivate(String target) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          myNick: widget.nickname,
          targetNick: target,
        ),
      ),
    );
  }

  void _call(String target) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: target,
          outgoing: true,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.nickname),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Icon(
                  Icons.circle,
                  size: 12,
                  color: _connected ? Colors.greenAccent : Colors.red,
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.forum_outlined),
                text: 'Odalar',
              ),
              Tab(
                icon: Icon(Icons.people_outline),
                text: 'Online',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: rooms.length,
              itemBuilder: (_, index) {
                final room = rooms[index];

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade900,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(room),
                    subtitle: const Text('Sohbet odası'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openRoom(room),
                  ),
                );
              },
            ),
            _onlineUsers.isEmpty
                ? const Center(
                    child: Text(
                      'Şu anda çevrimiçi kullanıcı görünmüyor.',
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: _onlineUsers.length,
                    itemBuilder: (_, index) {
                      final user = _onlineUsers[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading: const Icon(
                            Icons.circle,
                            color: Colors.greenAccent,
                            size: 13,
                          ),
                          title: Text(user),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Mesaj',
                                icon: const Icon(Icons.chat_outlined),
                                onPressed: () => _openPrivate(user),
                              ),
                              IconButton(
                                tooltip: 'Sesli ara',
                                icon: const Icon(
                                  Icons.call,
                                  color: Colors.greenAccent,
                                ),
                                onPressed: () => _call(user),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ROOM CHAT
// ============================================================

class ChatRoomScreen extends StatefulWidget {
  final String nickname;
  final String roomName;

  const ChatRoomScreen({
    super.key,
    required this.nickname,
    required this.roomName,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.send({
      'type': 'joinRoom',
      'room': widget.roomName,
    });
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];

    if (type == 'roomHistory' && data['room'] == widget.roomName) {
      final history = data['messages'];

      if (history is List) {
        for (final item in history) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                sender: (map['sender'] ?? map['from'] ?? '').toString(),
                text: (map['text'] ?? '').toString(),
              ),
            );
          }
        }
      }
    }

    if (type == 'roomMessage' && data['room'] == widget.roomName) {
      _addMessage(
        ChatMessage(
          sender: (data['sender'] ?? data['from'] ?? '').toString(),
          text: (data['text'] ?? '').toString(),
        ),
      );
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any(
      (m) =>
          m.sender == message.sender &&
          m.text == message.text,
    );

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    _scrollToBottom();
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    WsClient.instance.send({
      'type': 'message',
      'room': widget.roomName,
      'text': text,
    });

    _controller.clear();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomName),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[index];
                final mine =
                    message.sender.toLowerCase() ==
                        widget.nickname.toLowerCase();

                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 330),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.green.shade900
                          : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.sender,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.greenAccent,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(message.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _MessageInput(
            controller: _controller,
            hint: 'Mesaj yaz...',
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PRIVATE CHAT
// ============================================================

class PrivateChatScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;

  const PrivateChatScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];

    if (type == 'privateHistory') {
      final peer = (data['with'] ?? data['target'] ?? '').toString();

      if (peer.isNotEmpty &&
          peer.toLowerCase() != widget.targetNick.toLowerCase()) {
        return;
      }

      final history = data['messages'];

      if (history is List) {
        for (final item in history) {
          if (item is Map) {
            final map = Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                sender: (map['sender'] ?? map['from'] ?? '').toString(),
                text: (map['text'] ?? '').toString(),
              ),
            );
          }
        }
      }
    }

    if (type == 'privateMessage') {
      final sender = (data['sender'] ?? data['from'] ?? '').toString();

      if (sender.toLowerCase() !=
          widget.targetNick.toLowerCase()) {
        return;
      }

      _addMessage(
        ChatMessage(
          sender: sender,
          text: (data['text'] ?? '').toString(),
        ),
      );
    }
  }

  void _addMessage(ChatMessage message) {
    if (message.text.isEmpty) return;

    final exists = _messages.any(
      (m) =>
          m.sender == message.sender &&
          m.text == message.text,
    );

    if (exists) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(
          _scrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    // Sunucu mesajı hedefe ilettiği için
    // burada yerel olarak ikinci kez eklemiyoruz.
    WsClient.instance.send({
      'type': 'message',
      'target': widget.targetNick,
      'text': text,
    });

    _controller.clear();
  }

  void _call() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.myNick,
          targetNick: widget.targetNick,
          outgoing: true,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.targetNick),
        actions: [
          IconButton(
            tooltip: 'Sesli ara',
            icon: const Icon(
              Icons.call,
              color: Colors.greenAccent,
            ),
            onPressed: _call,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[index];

                final mine =
                    message.sender.toLowerCase() ==
                        widget.myNick.toLowerCase();

                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 330),
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.green.shade900
                          : Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(message.text),
                  ),
                );
              },
            ),
          ),
          _MessageInput(
            controller: _controller,
            hint: 'Özel mesaj yaz...',
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CALL
// ============================================================

class CallScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final bool outgoing;

  const CallScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
    required this.outgoing,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final List<RTCIceCandidate> _pendingCandidates = [];

  bool _connecting = false;
  bool _inCall = false;
  bool _muted = false;
  bool _ending = false;

  @override
  void initState() {
    super.initState();

    _subscription = WsClient.instance.events.listen(_handleEvent);

    _prepare();

    if (widget.outgoing) {
      _startOutgoingCall();
    }
  }

  Future<void> _prepare() async {
    try {
      final config = <String, dynamic>{
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302',
            ],
          },
        ],
      };

      final pc = await createPeerConnection(config);

      _peerConnection = pc;

      pc.onIceCandidate = (candidate) {
        final candidateMap = candidate.toMap();

        WsClient.instance.send({
          'type': 'callSignal',
          'target': widget.targetNick,
          'signal': {
            'type': 'candidate',
            'candidate': candidateMap,
          },
        });
      };

      pc.onConnectionState = (state) {
        if (!mounted) return;

        if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          setState(() {
            _inCall = true;
            _connecting = false;
          });
        }

        if (state ==
                RTCPeerConnectionState
                    .RTCPeerConnectionStateFailed ||
            state ==
                RTCPeerConnectionState
                    .RTCPeerConnectionStateDisconnected) {
          _endCall(sendSignal: false);
        }
      };

      if (widget.outgoing) {
        await _createLocalAudio();
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ses bağlantısı hazırlanamadı: $e'),
        ),
      );
    }
  }

  Future<void> _createLocalAudio() async {
    if (_localStream != null) return;

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    _localStream = stream;

    for (final track in stream.getTracks()) {
      await _peerConnection?.addTrack(track, stream);
    }
  }

  Future<void> _startOutgoingCall() async {
    setState(() {
      _connecting = true;
    });

    for (int i = 0; i < 40; i++) {
      if (_peerConnection != null) break;
      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      );
    }

    if (_peerConnection == null) {
      if (mounted) {
        setState(() => _connecting = false);
      }
      return;
    }

    try {
      await _createLocalAudio();

      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
      });

      await _peerConnection!.setLocalDescription(offer);

      WsClient.instance.send({
        'type': 'callSignal',
        'target': widget.targetNick,
        'signal': {
          'type': 'offer',
          'sdp': offer.sdp,
        },
      });
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _handleEvent(Map<String, dynamic> data) async {
    if (!mounted) return;

    if (data['type'] == 'callSignal') {
      final sender =
          (data['sender'] ?? data['from'] ?? '').toString();

      if (sender.toLowerCase() !=
          widget.targetNick.toLowerCase()) {
        return;
      }

      final signal = data['signal'];

      if (signal is Map) {
        await _handleSignal(
          Map<String, dynamic>.from(signal),
        );
      }

      return;
    }

    if (data['type'] == 'callEnded') {
      final sender =
          (data['sender'] ?? data['from'] ?? '').toString();

      if (sender.toLowerCase() ==
          widget.targetNick.toLowerCase()) {
        await _endCall(sendSignal: false);
      }
    }
  }

  Future<void> _handleSignal(
    Map<String, dynamic> signal,
  ) async {
    final type = signal['type'];

    if (type == 'offer') {
      await _acceptOffer(signal);
      return;
    }

    if (type == 'answer') {
      final sdp = signal['sdp'];

      if (sdp is String) {
        await _peerConnection?.setRemoteDescription(
          RTCSessionDescription(sdp, 'answer'),
        );

        await _flushPendingCandidates();

        if (mounted) {
          setState(() {
            _connecting = true;
          });
        }
      }

      return;
    }

    if (type == 'candidate') {
      final rawCandidate = signal['candidate'];

      if (rawCandidate is Map) {
        final map = Map<String, dynamic>.from(rawCandidate);

        final candidate = RTCIceCandidate(
          map['candidate']?.toString(),
          map['sdpMid']?.toString(),
          map['sdpMLineIndex'] is int
              ? map['sdpMLineIndex'] as int
              : int.tryParse(
                  map['sdpMLineIndex']?.toString() ?? '',
                ),
        );

        if (_peerConnection == null) return;

        final remoteDescription =
            await _peerConnection!.getRemoteDescription();

        if (remoteDescription == null) {
          _pendingCandidates.add(candidate);
        } else {
          await _peerConnection!.addCandidate(candidate);
        }
      }
    }
  }

  Future<void> _acceptOffer(
    Map<String, dynamic> signal,
  ) async {
    for (int i = 0; i < 40; i++) {
      if (_peerConnection != null) break;
      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      );
    }

    if (_peerConnection == null) return;

    try {
      await _createLocalAudio();

      final sdp = signal['sdp'];

      if (sdp is! String) return;

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(sdp, 'offer'),
      );

      await _flushPendingCandidates();

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
      });

      await _peerConnection!.setLocalDescription(answer);

      WsClient.instance.send({
        'type': 'callSignal',
        'target': widget.targetNick,
        'signal': {
          'type': 'answer',
          'sdp': answer.sdp,
        },
      });

      if (mounted) {
        setState(() {
          _connecting = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _flushPendingCandidates() async {
    if (_peerConnection == null) return;

    final candidates =
        List<RTCIceCandidate>.from(_pendingCandidates);

    _pendingCandidates.clear();

    for (final candidate in candidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (_) {}
    }
  }

  Future<void> _toggleMute() async {
    final stream = _localStream;

    if (stream == null) return;

    final tracks = stream.getAudioTracks();

    if (tracks.isEmpty) return;

    final nextMuted = !_muted;

    for (final track in tracks) {
      track.enabled = !nextMuted;
    }

    if (mounted) {
      setState(() {
        _muted = nextMuted;
      });
    }
  }

  Future<void> _endCall({
    required bool sendSignal,
  }) async {
    if (_ending) return;

    _ending = true;

    if (sendSignal) {
      WsClient.instance.send({
        'type': 'callEnded',
        'target': widget.targetNick,
      });
    }

    try {
      await _localStream?.dispose();
    } catch (_) {}

    try {
      await _peerConnection?.close();
    } catch (_) {}

    _localStream = null;
    _peerConnection = null;
    _pendingCandidates.clear();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _subscription.cancel();

    try {
      _localStream?.dispose();
    } catch (_) {}

    try {
      _peerConnection?.close();
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _endCall(sendSignal: true);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(widget.targetNick),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircleAvatar(
                radius: 55,
                child: Icon(
                  Icons.person,
                  size: 55,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.targetNick,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _inCall
                    ? 'Görüşme devam ediyor'
                    : _connecting
                        ? 'Bağlanıyor...'
                        : 'Arama başlatılıyor...',
              ),
              const SizedBox(height: 50),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton(
                    heroTag: 'mute',
                    backgroundColor:
                        _muted ? Colors.red : Colors.grey.shade800,
                    onPressed: _toggleMute,
                    child: Icon(
                      _muted ? Icons.mic_off : Icons.mic,
                    ),
                  ),
                  const SizedBox(width: 28),
                  FloatingActionButton(
                    heroTag: 'end',
                    backgroundColor: Colors.red,
                    onPressed: () => _endCall(
                      sendSignal: true,
                    ),
                    child: const Icon(Icons.call_end),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// COMMON MESSAGE INPUT
// ============================================================

class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

  const _MessageInput({
    required this.controller,
    required this.hint,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onSend,
              icon: const Icon(
                Icons.send,
                color: Colors.greenAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MODEL
// ============================================================

class ChatMessage {
  final String sender;
  final String text;

  ChatMessage({
    required this.sender,
    required this.text,
  });
}
