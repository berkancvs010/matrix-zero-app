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

  Stream<Map<String, dynamic>> get events => _events.stream;

  String? nickname;
  bool connected = false;

  Future<bool> connect(String nick) async {
    await disconnect();

    nickname = nick.trim();

    try {
      final channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );

      _channel = channel;

      _subscription = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw.toString());

            if (decoded is Map) {
              _events.add(
                Map<String, dynamic>.from(decoded),
              );
            }
          } catch (_) {}
        },
        onError: (_) {
          connected = false;
          _events.add({
            'type': 'connectionError',
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
    if (!connected || _channel == null) {
      return;
    }

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
  final TextEditingController _controller =
      TextEditingController();

  bool _loading = false;

  Future<void> _enter() async {
    final nick = _controller.text.trim();

    if (nick.length < 2) {
      _show('Lütfen en az 2 karakterlik bir rumuz girin.');
      return;
    }

    setState(() {
      _loading = true;
    });

    final ok = await WsClient.instance.connect(nick);

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
    });

    if (!ok) {
      _show('Sunucuya bağlanılamadı.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainScreen(
          nickname: nick,
        ),
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
            constraints: const BoxConstraints(
              maxWidth: 480,
            ),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
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
                    onPressed: _loading ? null : _enter,
                    child: _loading
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
// MAIN
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
  late final StreamSubscription<Map<String, dynamic>>
      _subscription;

  final List<String> _onlineUsers = [];

  bool _connected = false;

  @override
  void initState() {
    super.initState();

    _connected = WsClient.instance.connected;

    _subscription =
        WsClient.instance.events.listen(_handleEvent);
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
      final raw = data['users'];

      if (raw is List) {
        final users = raw
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .where(
              (e) =>
                  e.toLowerCase() !=
                  widget.nickname.toLowerCase(),
            )
            .toSet()
            .toList();

        setState(() {
          _onlineUsers
            ..clear()
            ..addAll(users);
        });
      }
    }

    if (type == 'connectionError' ||
        type == 'connectionClosed') {
      setState(() {
        _connected = false;
      });
    }

    if (type == 'offer') {
      final from = (data['from'] ?? '').toString();
      final to = (data['to'] ?? '').toString();

      if (from.isEmpty || to.isEmpty) return;

      if (to.toLowerCase() !=
          widget.nickname.toLowerCase()) {
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            myNick: widget.nickname,
            targetNick: from,
            outgoing: false,
            incomingOffer: data['sdp']?.toString(),
          ),
        ),
      );
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
                  color: _connected
                      ? Colors.greenAccent
                      : Colors.red,
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
              padding: const EdgeInsets.symmetric(
                vertical: 10,
              ),
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
                      child: Text('${index + 1}'),
                    ),
                    title: Text(room),
                    subtitle:
                        const Text('Sohbet odası'),
                    trailing:
                        const Icon(Icons.chevron_right),
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
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    itemCount: _onlineUsers.length,
                    itemBuilder: (_, index) {
                      final user =
                          _onlineUsers[index];

                      return Card(
                        margin:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          leading:
                              const Icon(
                            Icons.circle,
                            color:
                                Colors.greenAccent,
                            size: 13,
                          ),
                          title: Text(user),
                          trailing: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Mesaj',
                                icon: const Icon(
                                  Icons.chat_outlined,
                                ),
                                onPressed: () =>
                                    _openPrivate(user),
                              ),
                              IconButton(
                                tooltip: 'Sesli ara',
                                icon: const Icon(
                                  Icons.call,
                                  color:
                                      Colors.greenAccent,
                                ),
                                onPressed: () =>
                                    _call(user),
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
  State<ChatRoomScreen> createState() =>
      _ChatRoomScreenState();
}

class _ChatRoomScreenState
    extends State<ChatRoomScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.send({
      'type': 'joinRoom',
      'room': widget.roomName,
    });
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'roomHistory' &&
        data['room'] == widget.roomName) {
      final history = data['messages'];

      if (history is List) {
        for (final item in history) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                sender:
                    (map['sender'] ??
                            map['from'] ??
                            '')
                        .toString(),
                text:
                    (map['text'] ?? '')
                        .toString(),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'roomMessage' &&
        data['room'] == widget.roomName) {
      _addMessage(
        ChatMessage(
          sender:
              (data['sender'] ??
                      data['from'] ??
                      '')
                  .toString(),
          text:
              (data['text'] ?? '').toString(),
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

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position
                .maxScrollExtent,
            duration:
                const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      },
    );
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
                final message =
                    _messages[index];

                final mine =
                    message.sender.toLowerCase() ==
                        widget.nickname.toLowerCase();

                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints:
                        const BoxConstraints(
                      maxWidth: 500,
                    ),
                    margin:
                        const EdgeInsets.symmetric(
                      vertical: 4,
                    ),
                    padding:
                        const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.green.shade900
                          : Colors.grey.shade900,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        if (!mine)
                          Text(
                            message.sender,
                            style:
                                const TextStyle(
                              fontSize: 11,
                              color:
                                  Colors.greenAccent,
                            ),
                          ),
                        if (!mine)
                          const SizedBox(height: 3),
                        Text(message.text),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          MessageInput(
            controller: _controller,
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
  State<PrivateChatScreen> createState() =>
      _PrivateChatScreenState();
}

class _PrivateChatScreenState
    extends State<PrivateChatScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final List<ChatMessage> _messages = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

    WsClient.instance.send({
      'type': 'privateHistory',
      'with': widget.targetNick,
    });
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'privateHistory') {
      final peer =
          (data['with'] ??
                  data['target'] ??
                  '')
              .toString();

      if (peer.isNotEmpty &&
          peer.toLowerCase() !=
              widget.targetNick.toLowerCase()) {
        return;
      }

      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _addMessage(
              ChatMessage(
                sender:
                    (map['sender'] ??
                            map['from'] ??
                            '')
                        .toString(),
                text:
                    (map['text'] ?? '')
                        .toString(),
              ),
            );
          }
        }
      }
    }

    if (data['type'] == 'privateMessage') {
      final sender =
          (data['sender'] ??
                  data['from'] ??
                  '')
              .toString();

      final target =
          (data['target'] ?? '').toString();

      final validSender =
          sender.toLowerCase() ==
              widget.targetNick.toLowerCase();

      final validTarget =
          target.isEmpty ||
          target.toLowerCase() ==
              widget.myNick.toLowerCase();

      if (!validSender || !validTarget) {
        return;
      }

      _addMessage(
        ChatMessage(
          sender: sender,
          text:
              (data['text'] ?? '').toString(),
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

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position
                .maxScrollExtent,
            duration:
                const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      },
    );
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    WsClient.instance.send({
      'type': 'message',
      'target': widget.targetNick,
      'text': text,
    });

    _controller.clear();
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
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(10),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message =
                    _messages[index];

                final mine =
                    message.sender.toLowerCase() ==
                        widget.myNick.toLowerCase();

                return Align(
                  alignment: mine
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    constraints:
                        const BoxConstraints(
                      maxWidth: 500,
                    ),
                    margin:
                        const EdgeInsets.symmetric(
                      vertical: 4,
                    ),
                    padding:
                        const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? Colors.green.shade900
                          : Colors.grey.shade900,
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Text(message.text),
                  ),
                );
              },
            ),
          ),
          MessageInput(
            controller: _controller,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WEBRTC CALL
// ============================================================

class CallScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final bool outgoing;
  final String? incomingOffer;

  const CallScreen({
    super.key,
    required this.myNick,
    required this.targetNick,
    required this.outgoing,
    this.incomingOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  bool _accepted = false;
  bool _connected = false;
  bool _muted = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();

    _subscription =
        WsClient.instance.events.listen(_handleEvent);

    if (widget.outgoing) {
      _startOutgoingCall();
    }
  }

  Future<void> _createPeerConnection() async {
    if (_peerConnection != null) return;

    final configuration = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection =
        await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate =
        (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;

      WsClient.instance.send({
        'type': 'ice-candidate',
        'from': widget.myNick,
        'to': widget.targetNick,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onConnectionState =
        (RTCPeerConnectionState state) {
      if (!mounted) return;

      if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          _connected = true;
        });
      }

      if (state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateFailed ||
          state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateDisconnected ||
          state ==
              RTCPeerConnectionState
                  .RTCPeerConnectionStateClosed) {
        setState(() {
          _connected = false;
        });
      }
    };

    _localStream =
        await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(
        track,
        _localStream!,
      );
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _createPeerConnection();

      final offer =
          await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await _peerConnection!.setLocalDescription(
        offer,
      );

      WsClient.instance.send({
        'type': 'offer',
        'from': widget.myNick,
        'to': widget.targetNick,
        'sdp': offer.sdp,
      });

      if (mounted) {
        setState(() {
          _accepted = true;
        });
      }
    } catch (_) {
      if (mounted) {
        _showError('Arama başlatılamadı.');
      }
    }
  }

  Future<void> _acceptIncoming() async {
    if (widget.incomingOffer == null) {
      return;
    }

    try {
      await _createPeerConnection();

      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
          widget.incomingOffer!,
          'offer',
        ),
      );

      final answer =
          await _peerConnection!.createAnswer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });

      await _peerConnection!.setLocalDescription(
        answer,
      );

      WsClient.instance.send({
        'type': 'answer',
        'from': widget.myNick,
        'to': widget.targetNick,
        'sdp': answer.sdp,
      });

      if (mounted) {
        setState(() {
          _accepted = true;
        });
      }
    } catch (_) {
      if (mounted) {
        _showError('Arama kabul edilemedi.');
      }
    }
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    final type = data['type'];
    final from = (data['from'] ?? '').toString();
    final to = (data['to'] ?? '').toString();

    if (from.toLowerCase() !=
            widget.targetNick.toLowerCase() &&
        type != 'answer') {
      return;
    }

    if (to.isNotEmpty &&
        to.toLowerCase() !=
            widget.myNick.toLowerCase()) {
      return;
    }

    if (type == 'answer') {
      _handleAnswer(data);
    }

    if (type == 'ice-candidate') {
      _handleIceCandidate(data);
    }

    if (type == 'call-end') {
      _finish(sendSignal: false);
    }
  }

  Future<void> _handleAnswer(
      Map<String, dynamic> data) async {
    final sdp = data['sdp']?.toString();

    if (sdp == null || _peerConnection == null) {
      return;
    }

    try {
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(
          sdp,
          'answer',
        ),
      );
    } catch (_) {}
  }

  Future<void> _handleIceCandidate(
      Map<String, dynamic> data) async {
    if (_peerConnection == null) return;

    final candidate =
        data['candidate']?.toString();

    if (candidate == null ||
        candidate.isEmpty) {
      return;
    }

    try {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          candidate,
          data['sdpMid']?.toString(),
          data['sdpMLineIndex'] is int
              ? data['sdpMLineIndex'] as int
              : null,
        ),
      );
    } catch (_) {}
  }

  void _toggleMute() {
    final stream = _localStream;

    if (stream == null) return;

    final tracks = stream.getAudioTracks();

    for (final track in tracks) {
      track.enabled = !track.enabled;
    }

    setState(() {
      _muted = !_muted;
    });
  }

  void _reject() {
    WsClient.instance.send({
      'type': 'call-end',
      'from': widget.myNick,
      'to': widget.targetNick,
    });

    _finish(sendSignal: false);
  }

  Future<void> _finish({
    bool sendSignal = true,
  }) async {
    if (_closing) return;

    _closing = true;

    if (sendSignal) {
      WsClient.instance.send({
        'type': 'call-end',
        'from': widget.myNick,
        'to': widget.targetNick,
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

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();

    if (!_closing) {
      try {
        _localStream?.dispose();
        _peerConnection?.close();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final waitingIncoming =
        !widget.outgoing && !_accepted;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) {
        if (!didPop) {
          _finish();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sesli Arama'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 55,
                  child: Icon(
                    Icons.person,
                    size: 60,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  widget.targetNick,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  waitingIncoming
                      ? 'Gelen arama'
                      : _connected
                          ? 'Bağlandı'
                          : 'Bağlanıyor...',
                ),
                const SizedBox(height: 40),
                if (waitingIncoming)
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            _acceptIncoming,
                        icon: const Icon(
                          Icons.call,
                        ),
                        label:
                            const Text('Kabul Et'),
                      ),
                      const SizedBox(width: 20),
                      FilledButton.tonalIcon(
                        onPressed: _reject,
                        icon: const Icon(
                          Icons.call_end,
                        ),
                        label:
                            const Text('Reddet'),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _toggleMute,
                        icon: Icon(
                          _muted
                              ? Icons.mic_off
                              : Icons.mic,
                        ),
                      ),
                      const SizedBox(width: 30),
                      IconButton.filled(
                        style:
                            IconButton.styleFrom(
                          backgroundColor:
                              Colors.red,
                        ),
                        onPressed: _finish,
                        icon: const Icon(
                          Icons.call_end,
                        ),
                      ),
                    ],
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
// INPUT
// ============================================================

class MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction:
                    TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration:
                    const InputDecoration(
                  hintText: 'Mesaj yaz...',
                  border: OutlineInputBorder(),
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

  const ChatMessage({
    required this.sender,
    required this.text,
  });
}
