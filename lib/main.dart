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

final GlobalKey<NavigatorState> navigatorKey =
    GlobalKey<NavigatorState>();

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
      navigatorKey: navigatorKey,
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
        _handleMessage,
        onError: (Object error) {
          connected = false;

          _completeRegistration(false);

          _emit({
            'type': 'connectionError',
            'message': error.toString(),
          });
        },
        onDone: () {
          connected = false;

          _completeRegistration(false);

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

      final registered =
          await _registrationCompleter!.future.timeout(
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

  void _handleMessage(dynamic raw) {
    try {
      final decoded = jsonDecode(raw.toString());

      if (decoded is! Map) {
        return;
      }

      final data = Map<String, dynamic>.from(decoded);

      if (data['type'] == 'registered') {
        final success = data['success'] != false;

        connected = success;

        _completeRegistration(success);
      }

      _emit(data);
    } catch (_) {
      // Hatalı paket uygulamayı düşürmez.
    }
  }

  void _completeRegistration(bool value) {
    if (_registrationCompleter != null &&
        !_registrationCompleter!.isCompleted) {
      _registrationCompleter!.complete(value);
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

    _completeRegistration(false);
    _registrationCompleter = null;

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
  State<NicknameScreen> createState() =>
      _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller =
      TextEditingController();

  bool _connecting = false;

  Future<void> _enter() async {
    if (_connecting) {
      return;
    }

    final nick = _controller.text.trim();

    if (nick.isEmpty) {
      _show('Lütfen bir rumuz girin.');
      return;
    }

    if (nick.length < 2) {
      _show('Rumuz en az 2 karakter olmalı.');
      return;
    }

    setState(() {
      _connecting = true;
    });

    final success =
        await WsClient.instance.connect(nick);

    if (!mounted) {
      return;
    }

    setState(() {
      _connecting = false;
    });

    if (!success) {
      _show(
        'Sunucuya bağlanılamadı veya rumuz kabul edilmedi.',
      );
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.shield_outlined,
                  size: 72,
                  color: Colors.greenAccent,
                ),
                const SizedBox(height: 22),
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
                  'Sohbete katılmak için bir rumuz seçin.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction:
                      TextInputAction.done,
                  onSubmitted: (_) => _enter(),
                  decoration:
                      const InputDecoration(
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
                    onPressed:
                        _connecting ? null : _enter,
                    child: _connecting
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
// MAIN SCREEN
// ============================================================

class MainScreen extends StatefulWidget {
  final String nickname;

  const MainScreen({
    super.key,
    required this.nickname,
  });

  @override
  State<MainScreen> createState() =>
      _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late final StreamSubscription<
      Map<String, dynamic>> _subscription;

  final List<String> _onlineUsers = [];

  bool _connected = false;

  @override
  void initState() {
    super.initState();

    _connected = WsClient.instance.connected;

    _subscription =
        WsClient.instance.events.listen(_handleEvent);
  }

  void _handleEvent(
    Map<String, dynamic> data,
  ) {
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
      final raw = data['users'];

      if (raw is! List) {
        return;
      }

      final users = raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .where(
            (e) =>
                e.toLowerCase() !=
                widget.nickname.toLowerCase(),
          )
          .toSet()
          .toList();

      users.sort(
        (a, b) => a.toLowerCase().compareTo(
              b.toLowerCase(),
            ),
      );

      setState(() {
        _onlineUsers
          ..clear()
          ..addAll(users);
      });
    }

    if (type == 'callInvite') {
      _showIncomingCall(data);
    }
  }

  void _showIncomingCall(
    Map<String, dynamic> data,
  ) {
    final caller =
        (data['from'] ??
                data['caller'] ??
                data['sender'] ??
                '')
            .toString();

    if (caller.isEmpty ||
        caller.toLowerCase() ==
            widget.nickname.toLowerCase()) {
      return;
    }

    final context = navigatorKey.currentContext;

    if (context == null) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text('Gelen arama'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.phone_in_talk,
                size: 58,
                color: Colors.greenAccent,
              ),
              const SizedBox(height: 14),
              Text(
                '$caller seni arıyor.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();

                WsClient.instance.send({
                  'type': 'callReject',
                  'from': widget.nickname,
                  'target': caller,
                });
              },
              child: const Text(
                'REDDET',
                style: TextStyle(
                  color: Colors.redAccent,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();

                WsClient.instance.send({
                  'type': 'callAccept',
                  'from': widget.nickname,
                  'target': caller,
                });

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CallScreen(
                      myNick: widget.nickname,
                      targetNick: caller,
                      outgoing: false,
                    ),
                  ),
                );
              },
              child: const Text('KABUL ET'),
            ),
          ],
        );
      },
    );
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

  void _openPrivate(String user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          myNick: widget.nickname,
          targetNick: user,
        ),
      ),
    );
  }

  void _call(String user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          myNick: widget.nickname,
          targetNick: user,
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
                  margin:
                      const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          Colors.green.shade900,
                      child:
                          Text('${index + 1}'),
                    ),
                    title: Text(room),
                    subtitle:
                        const Text('Sohbet odası'),
                    trailing: const Icon(
                      Icons.chevron_right,
                    ),
                    onTap: () =>
                        _openRoom(room),
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
                    itemCount:
                        _onlineUsers.length,
                    padding:
                        const EdgeInsets.all(10),
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
                          trailing: Row(
                            mainAxisSize:
                                MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Mesaj',
                                icon: const Icon(
                                  Icons
                                      .chat_outlined,
                                ),
                                onPressed: () =>
                                    _openPrivate(
                                  user,
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    'Sesli ara',
                                icon:
                                    const Icon(
                                  Icons.call,
                                  color: Colors
                                      .greenAccent,
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
        WsClient.instance.events.listen(
      _handleEvent,
    );

    WsClient.instance.send({
      'type': 'joinRoom',
      'room': widget.roomName,
    });
  }

  void _handleEvent(
    Map<String, dynamic> data,
  ) {
    if (!mounted) {
      return;
    }

    final type = data['type'];

    if (type == 'roomHistory' &&
        data['room']?.toString() ==
            widget.roomName) {
      final list = data['messages'];

      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final map =
                Map<String, dynamic>.from(
              item,
            );

            _addMessage(
              ChatMessage(
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
        data['room']?.toString() ==
            widget.roomName) {
      _addMessage(
        ChatMessage(
          id: _messageId(data),
          sender:
              (
