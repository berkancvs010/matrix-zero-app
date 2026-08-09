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
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatrixZeroWebApp());
}

// ============================================================
// APP
// ============================================================

class MatrixZeroWebApp extends StatelessWidget {
  const MatrixZeroWebApp({super.key});

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
      home: const WebNicknameScreen(),
    );
  }
}

// ============================================================
// WEBSOCKET SERVICE
// ============================================================

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  bool connected = false;
  String? nickname;

  Completer<bool>? _registrationCompleter;

  Future<bool> connect(String nick) async {
    final cleanNick = nick.trim();

    if (cleanNick.length < 2) {
      return false;
    }

    await disconnect();

    nickname = cleanNick;

    try {
      final channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
      );

      _channel = channel;

      _subscription = channel.stream.listen(
        _handleIncoming,
        onError: (Object error) {
          connected = false;

          if (_registrationCompleter != null &&
              !_registrationCompleter!.isCompleted) {
            _registrationCompleter!.complete(false);
          }

          _emit({
            'type': 'connectionError',
            'message': error.toString(),
          });
        },
        onDone: () {
          connected = false;

          if (_registrationCompleter != null &&
              !_registrationCompleter!.isCompleted) {
            _registrationCompleter!.complete(false);
          }

          _emit({
            'type': 'connectionClosed',
          });
        },
        cancelOnError: false,
      );

      await channel.ready;

      _registrationCompleter = Completer<bool>();

      channel.sink.add(
        jsonEncode({
          'type': 'register',
          'nick': cleanNick,
        }),
      );

      final registered = await _registrationCompleter!.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => false,
      );

      if (!registered) {
        await disconnect();
        return false;
      }

      connected = true;

      return true;
    } catch (_) {
      connected = false;
      await disconnect();
      return false;
    }
  }

  void _handleIncoming(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());

      if (decoded is! Map) {
        return;
      }

      final data = Map<String, dynamic>.from(decoded);

      final type = data['type'];

      if (type == 'registered') {
        final success = data['success'] != false;

        connected = success;

        if (_registrationCompleter != null &&
            !_registrationCompleter!.isCompleted) {
          _registrationCompleter!.complete(success);
        }
      }

      _emit(data);
    } catch (_) {
      // Geçersiz paket uygulamayı bozmaz.
    }
  }

  void _emit(Map<String, dynamic> data) {
    if (!_events.isClosed) {
      _events.add(data);
    }
  }

  bool send(Map<String, dynamic> data) {
    if (!connected || _channel == null) {
      return false;
    }

    try {
      _channel!.sink.add(jsonEncode(data));
      return true;
    } catch (_) {
      connected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    connected = false;

    if (_registrationCompleter != null &&
        !_registrationCompleter!.isCompleted) {
      _registrationCompleter!.complete(false);
    }

    _registrationCompleter = null;

    await _subscription?.cancel();
    _subscription = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}

    _channel = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _events.close();
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

class _WebNicknameScreenState extends State<WebNicknameScreen> {
  final TextEditingController _controller = TextEditingController();

  bool _loading = false;

  Future<void> _connect() async {
    if (_loading) {
      return;
    }

    final nick = _controller.text.trim();

    if (nick.isEmpty) {
      _message('Lütfen bir rumuz girin.');
      return;
    }

    if (nick.length < 2) {
      _message('Rumuz en az 2 karakter olmalı.');
      return;
    }

    setState(() {
      _loading = true;
    });

    final success = await webSocketService.connect(nick);

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
    });

    if (!success) {
      _message(
        'Sunucuya bağlanılamadı veya rumuz kabul edilmedi.',
      );
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
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
        ),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 430,
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
                    color: Colors.greenAccent,
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
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _connect(),
                  decoration: const InputDecoration(
                    labelText: 'Rumuz',
                    hintText: 'Örn. Neo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _connect,
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

class _WebHomeScreenState extends State<WebHomeScreen> {
  final List<String> _onlineUsers = [];

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  bool _connected = false;

  @override
  void initState() {
    super.initState();

    _connected = webSocketService.connected;

    _subscription = webSocketService.events.listen(
      _handleEvent,
    );
  }

  void _handleEvent(Map<String, dynamic> data) {
    if (!mounted) {
      return;
    }

    final type = data['type'];

    if (type == 'registered') {
      setState(() {
        _connected = data['success'] != false;
      });
      return;
    }

    if (type == 'connectionError' ||
        type == 'connectionClosed') {
      setState(() {
        _connected = false;
        _onlineUsers.clear();
      });
      return;
    }

    if (type == 'userList') {
      final users = data['users'];

      if (users is! List) {
        return;
      }

      final normalized = users
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .where(
            (e) =>
                e.toLowerCase() !=
                widget.nickname.toLowerCase(),
          )
          .toSet()
          .toList();

      normalized.sort(
        (a, b) => a.toLowerCase().compareTo(
              b.toLowerCase(),
            ),
      );

      setState(() {
        _onlineUsers
          ..clear()
          ..addAll(normalized);
      });
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

  Future<bool> _onWillPop() async {
    await webSocketService.disconnect();
    return true;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {
        // Bağlantının temizlenmesi dispose sırasında yapılır.
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Expanded(
                  child: Text(widget.nickname),
                ),
                Icon(
                  Icons.circle,
                  size: 11,
                  color: _connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ),
              ],
            ),
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
                        backgroundColor:
                            Colors.green.shade900,
                        child: Text('${index + 1}'),
                      ),
                      title: Text(room),
                      subtitle:
                          const Text('Sohbet odası'),
                      trailing: const Icon(
                        Icons.chevron_right,
                      ),
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
                            leading: const Icon(
                              Icons.circle,
                              color:
                                  Colors.greenAccent,
                              size: 12,
                            ),
                            title: Text(user),
                            trailing: IconButton(
                              tooltip: 'Mesaj gönder',
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
      ),
    );
  }
}

// ============================================================
// ROOM CHAT
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

  late final StreamSubscription<Map<String, dynamic>>
      _subscription;

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
    if (!mounted) {
      return;
    }

    final type = data['type'];

    if (type == 'roomHistory' &&
        data['room']?.toString() == widget.room) {
      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(item);

            _add(
              WebMessage(
                id: _messageId(map),
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

      return;
    }

    if (type == 'roomMessage' &&
        data['room']?.toString() == widget.room) {
      _add(
        WebMessage(
          id: _messageId(data),
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

  String _messageId(Map<dynamic, dynamic> data) {
    final id =
        data['id'] ??
        data['messageId'] ??
        data['timestamp'];

    if (id != null) {
      return id.toString();
    }

    return '${data['sender'] ?? data['from'] ?? ''}|'
        '${data['text'] ?? ''}|'
        '${data['time'] ?? data['createdAt'] ?? ''}';
  }

  void _add(WebMessage message) {
    if (message.text.trim().isEmpty) {
      return;
    }

    final duplicate = _messages.any(
      (item) => item.id == message.id,
    );

    if (duplicate) {
      return;
    }

    setState(() {
      _messages.add(message);
    });

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!_scrollController.hasClients) {
          return;
        }

        _scrollController.animateTo(
          _scrollController
              .position
              .maxScrollExtent,
          duration:
              const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      },
    );
  }

  void _send() {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      return;
    }

    if (!webSocketService.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sunucu bağlantısı yok.',
          ),
        ),
      );
      return;
    }

    final sent = webSocketService.send({
      'type': 'message',
      'room': widget.room,
      'text': text,
    });

    if (sent) {
      _controller.clear();
    }
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
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Henüz mesaj yok.',
                    ),
                  )
                : ListView.builder(
                    controller:
                        _scrollController,
                    padding:
                        const EdgeInsets.all(10),
                    itemCount:
                        _messages.length,
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
                            
