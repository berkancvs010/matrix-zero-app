import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
  runApp(const MatrixZeroWebApp());
}

class MatrixZeroWebApp extends StatelessWidget {
  const MatrixZeroWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Zero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const WebNicknameScreen(),
    );
  }
}

// ============================================================
// WEBSOCKET
// ============================================================

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  bool connected = false;
  String? nickname;

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

final WebSocketService webSocketService = WebSocketService();

// ============================================================
// LOGIN
// ============================================================

class WebNicknameScreen extends StatefulWidget {
  const WebNicknameScreen({super.key});

  @override
  State<WebNicknameScreen> createState() =>
      _WebNicknameScreenState();
}

class _WebNicknameScreenState
    extends State<WebNicknameScreen> {
  final TextEditingController _controller =
      TextEditingController();

  bool _loading = false;

  Future<void> _connect() async {
    final nick = _controller.text.trim();

    if (nick.length < 2) {
      _message('Lütfen en az 2 karakterlik bir rumuz girin.');
      return;
    }

    setState(() {
      _loading = true;
    });

    final success =
        await webSocketService.connect(nick);

    if (!mounted) return;

    setState(() {
      _loading = false;
    });

    if (!success) {
      _message('Sunucuya bağlanılamadı.');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WebHomeScreen(
          nickname: nick,
        ),
      ),
    );
  }

  void _message(String text) {
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 430,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 70,
                  color: Colors.greenAccent,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Matrix Zero',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Rumuzunu seç ve sohbete katıl.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction:
                      TextInputAction.done,
                  onSubmitted: (_) => _connect(),
                  decoration:
                      const InputDecoration(
                    labelText: 'Rumuz',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed:
                        _loading ? null : _connect,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child:
                                CircularProgressIndicator(
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
// HOME
// ============================================================

class WebHomeScreen extends StatefulWidget {
  final String nickname;

  const WebHomeScreen({
    super.key,
    required this.nickname,
  });

  @override
  State<WebHomeScreen> createState() =>
      _WebHomeScreenState();
}

class _WebHomeScreenState
    extends State<WebHomeScreen> {
  final List<String> _onlineUsers = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        webSocketService.events.listen(_handleEvent);
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'userList') {
      final users = data['users'];

      if (users is List) {
        setState(() {
          _onlineUsers
            ..clear()
            ..addAll(
              users
                  .map((e) => e.toString())
                  .where(
                    (e) =>
                        e.toLowerCase() !=
                        widget.nickname.toLowerCase(),
                  )
                  .toSet(),
            );
        });
      }
    }
  }

  void _openRoom(String room) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebRoomScreen(
          nickname: widget.nickname,
          room: room,
        ),
      ),
    );
  }

  void _openPrivate(String user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebPrivateScreen(
          nickname: widget.nickname,
          target: user,
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
              itemCount: rooms.length,
              padding: const EdgeInsets.all(10),
              itemBuilder: (_, index) {
                final room = rooms[index];

                return Card(
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
                      'Çevrimiçi kullanıcı yok.',
                    ),
                  )
                : ListView.builder(
                    itemCount: _onlineUsers.length,
                    padding: const EdgeInsets.all(10),
                    itemBuilder: (_, index) {
                      final user =
                          _onlineUsers[index];

                      return Card(
                        child: ListTile(
                          leading:
                              const Icon(
                            Icons.circle,
                            color:
                                Colors.greenAccent,
                            size: 12,
                          ),
                          title: Text(user),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.chat_outlined,
                            ),
                            onPressed: () =>
                                _openPrivate(user),
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
// ROOM
// ============================================================

class WebRoomScreen extends StatefulWidget {
  final String nickname;
  final String room;

  const WebRoomScreen({
    super.key,
    required this.nickname,
    required this.room,
  });

  @override
  State<WebRoomScreen> createState() =>
      _WebRoomScreenState();
}

class _WebRoomScreenState
    extends State<WebRoomScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final List<WebMessage> _messages = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        webSocketService.events.listen(_handleEvent);

    webSocketService.send({
      'type': 'joinRoom',
      'room': widget.room,
    });
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) return;

    if (data['type'] == 'roomHistory' &&
        data['room'] == widget.room) {
      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _add(
              WebMessage(
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
        data['room'] == widget.room) {
      _add(
        WebMessage(
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

  void _add(WebMessage message) {
    if (message.text.isEmpty) return;

    final duplicate = _messages.any(
      (item) =>
          item.sender == message.sender &&
          item.text == message.text,
    );

    if (duplicate) return;

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
                const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      },
    );
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    webSocketService.send({
      'type': 'message',
      'room': widget.room,
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
        title: Text(widget.room),
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
                    message.sender
                            .toLowerCase() ==
                        widget.nickname
                            .toLowerCase();

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
                              color:
                                  Colors.greenAccent,
                              fontSize: 11,
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
          _InputBar(
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

class WebPrivateScreen extends StatefulWidget {
  final String nickname;
  final String target;

  const WebPrivateScreen({
    super.key,
    required this.nickname,
    required this.target,
  });

  @override
  State<WebPrivateScreen> createState() =>
      _WebPrivateScreenState();
}

class _WebPrivateScreenState
    extends State<WebPrivateScreen> {
  final TextEditingController _controller =
      TextEditingController();

  final ScrollController _scrollController =
      ScrollController();

  final List<WebMessage> _messages = [];

  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  @override
  void initState() {
    super.initState();

    _subscription =
        webSocketService.events.listen(_handleEvent);
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
              widget.target.toLowerCase()) {
        return;
      }

      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _add(
              WebMessage(
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

      if (sender.toLowerCase() !=
          widget.target.toLowerCase()) {
        return;
      }

      _add(
        WebMessage(
          sender: sender,
          text:
              (data['text'] ?? '').toString(),
        ),
      );
    }
  }

  void _add(WebMessage message) {
    if (message.text.isEmpty) return;

    final duplicate = _messages.any(
      (item) =>
          item.sender == message.sender &&
          item.text == message.text,
    );

    if (duplicate) return;

    setState(() {
      _messages.add(message);
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position
                .maxScrollExtent,
          );
        }
      },
    );
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    webSocketService.send({
      'type': 'message',
      'target': widget.target,
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
        title: Text(widget.target),
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
                    message.sender
                            .toLowerCase() ==
                        widget.nickname
                            .toLowerCase();

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
                    child: Text(
                      message.text,
                    ),
                  ),
                );
              },
            ),
          ),
          _InputBar(
            controller: _controller,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// INPUT
// ============================================================

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({
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

class WebMessage {
  final String sender;
  final String text;

  WebMessage({
    required this.sender,
    required this.text,
  });
}
