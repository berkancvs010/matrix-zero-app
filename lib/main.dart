import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MatrixZeroApp());
}

class MatrixZeroApp extends StatelessWidget {
  const MatrixZeroApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matrix Zero',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.green,
      ),
      home: const NicknameScreen(),
    );
  }
}

// ----- RUMUZ GİRİŞ -----
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({Key? key}) : super(key: key);
  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();

  void _enter() {
    final nick = _controller.text.trim();
    if (nick.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainScreen(nickname: nick)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZERO LOG - GİRİŞ')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Rumuzunuzu girin', style: TextStyle(color: Colors.green, fontSize: 18)),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                hintText: 'Örn: Neo',
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.black),
              onPressed: _enter,
              child: const Text('Bağlan'),
            ),
          ],
        ),
      ),
    );
  }
}

// ----- ANA EKRAN: ODALAR + ONLINE KULLANICILAR -----
class MainScreen extends StatefulWidget {
  final String nickname;
  const MainScreen({Key? key, required this.nickname}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late WebSocketChannel _channel;
  List<String> _onlineUsers = [];
  final List<String> _rooms = [
    '1p09aq66zx6Qr9', '8k22bm91wx3Pt4', '9x44cn18yv7Ls2',
    '3z88dp52zu1Km8', '7v11er39xt5Jn3', '5m66fs84yq9Hb6',
    '2q33gt71zp2Wv1', '4w55hy03xr8Dc9', '6j99jx25yv4Fg5',
    '0n77kz46zt0Tq7'
  ];

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://zerolog.giize.com:8443'),
      );
      _channel.stream.asBroadcastStream().listen((message) {
        try {
          final data = jsonDecode(message);
          print('MainScreen - Gelen mesaj: $data');
          if (data['type'] == 'userList') {
            setState(() {
              _onlineUsers = List<String>.from(data['users'] ?? []);
              _onlineUsers.remove(widget.nickname);
            });
          }
        } catch (e) {
          print('MainScreen - Hata: $e');
        }
      });
      _channel.sink.add(jsonEncode({
        'type': 'register',
        'nick': widget.nickname,
      }));
    } catch (e) {
      print('MainScreen - Bağlantı hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bağlantı hatası: $e')),
      );
    }
  }

  void _joinRoom(String room) {
    try {
      _channel.sink.add(jsonEncode({
        'type': 'joinRoom',
        'room': room,
      }));
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatRoomScreen(
            nickname: widget.nickname,
            roomName: room,
            channel: _channel,
          ),
        ),
      );
    } catch (e) {
      print('joinRoom hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Odaya giriş hatası: $e')),
      );
    }
  }

  void _startPrivateChat(String targetNick) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          myNick: widget.nickname,
          targetNick: targetNick,
          channel: _channel,
        ),
      ),
    );
  }

  void _startPrivateCall(String target) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateCallScreen(
          myNick: widget.nickname,
          targetNick: target,
          channel: _channel,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Merhaba, ${widget.nickname}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Odalar'),
              Tab(text: 'Online Kullanıcılar'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (ctx, idx) {
                return Card(
                  color: Colors.grey[900],
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text('Oda #${idx+1}: ${_rooms[idx]}', style: const TextStyle(color: Colors.greenAccent)),
                    trailing: const Icon(Icons.arrow_forward, color: Colors.green),
                    onTap: () => _joinRoom(_rooms[idx]),
                  ),
                );
              },
            ),
            ListView.builder(
              itemCount: _onlineUsers.length,
              itemBuilder: (ctx, idx) {
                final user = _onlineUsers[idx];
                return Card(
                  color: Colors.grey[900],
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(user, style: const TextStyle(color: Colors.greenAccent)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chat, color: Colors.blue),
                          onPressed: () => _startPrivateChat(user),
                        ),
                        IconButton(
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: () => _startPrivateCall(user),
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

// ----- ODA SOHBET EKRANI -----
class ChatRoomScreen extends StatefulWidget {
  final String nickname;
  final String roomName;
  final WebSocketChannel channel;
  const ChatRoomScreen({Key? key, required this.nickname, required this.roomName, required this.channel}) : super(key: key);

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _listenToChannel();
  }

  void _listenToChannel() {
    try {
      if (widget.channel == null) {
        setState(() {
          _errorMessage = 'Kanal bağlantısı yok!';
          _isLoading = false;
        });
        return;
      }

      widget.channel.stream.asBroadcastStream().listen((message) {
        try {
          final data = jsonDecode(message);
          print('ChatRoomScreen - Gelen mesaj: $data');
          if (data['type'] == 'roomMessage' && data['room'] == widget.roomName) {
            setState(() {
              _messages.add({ 'sender': data['from'], 'text': data['text'] });
            });
          }
          if (data['type'] == 'roomMessageSent' && data['room'] == widget.roomName) {
            setState(() {
              _messages.add({ 'sender': widget.nickname, 'text': data['text'] });
            });
          }
          setState(() {
            _isLoading = false;
          });
        } catch (e) {
          print('ChatRoomScreen - Mesaj işleme hatası: $e');
          setState(() {
            _errorMessage = 'Mesaj işleme hatası: $e';
            _isLoading = false;
          });
        }
      }, onError: (error) {
        print('ChatRoomScreen - Stream hatası: $error');
        setState(() {
          _errorMessage = 'Stream hatası: $error';
          _isLoading = false;
        });
      });
    } catch (e) {
      print('ChatRoomScreen - Başlangıç hatası: $e');
      setState(() {
        _errorMessage = 'Başlangıç hatası: $e';
        _isLoading = false;
      });
    }
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    try {
      widget.channel.sink.add(jsonEncode({
        'type': 'message',
        'room': widget.roomName,
        'text': text,
      }));
      _controller.clear();
    } catch (e) {
      print('Gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderme hatası: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Hata: ${widget.roomName}')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 60),
                const SizedBox(height: 20),
                Text(
                  'Hata oluştu!',
                  style: const TextStyle(color: Colors.red, fontSize: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Geri Dön'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Oda: ${widget.roomName}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (ctx, idx) {
                final msg = _messages[idx];
                final isMe = msg['sender'] == widget.nickname;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.green[900] : Colors.grey[850],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg['sender']!, style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
                        const SizedBox(height: 4),
                        Text(msg['text']!, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      border: OutlineInputBorder(borderSide: BorderSide(color: Colors.green)),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.greenAccent),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----- ÖZEL MESAJLAŞMA EKRANI -----
class PrivateChatScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final WebSocketChannel channel;
  const PrivateChatScreen({Key? key, required this.myNick, required this.targetNick, required this.channel}) : super(key: key);

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];

  @override
  void initState() {
    super.initState();
    widget.channel.stream.asBroadcastStream().listen((message) {
      try {
        final data = jsonDecode(message);
        if (data['type'] == 'privateMessage' && data['from'] == widget.targetNick) {
          setState(() {
            _messages.add({ 'sender': data['from'], 'text': data['text'] });
          });
        }
        if (data['type'] == 'privateMessageSent' && data['to'] == widget.targetNick) {
          setState(() {
            _messages.add({ 'sender': widget.myNick, 'text': data['text'] });
          });
        }
      } catch (e) {
        print('PrivateChat - Hata: $e');
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.channel.sink.add(jsonEncode({
      'type': 'message',
      'target': widget.targetNick,
      'text': text,
    }));
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Özel: ${widget.targetNick}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivateCallScreen(
                    myNick: widget.myNick,
                    targetNick: widget.targetNick,
                    channel: widget.channel,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (ctx, idx) {
                final msg = _messages[idx];
                final isMe = msg['sender'] == widget.myNick;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.green[900] : Colors.grey[850],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(msg['sender']!, style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
                        const SizedBox(height: 4),
                        Text(msg['text']!, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Özel mesaj yaz...',
                      border: OutlineInputBorder(borderSide: BorderSide(color: Colors.green)),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.greenAccent),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----- ÖZEL ARAMA EKRANI (WebRTC) -----
class PrivateCallScreen extends StatefulWidget {
  final String myNick;
  final String targetNick;
  final WebSocketChannel channel;
  const PrivateCallScreen({Key? key, required this.myNick, required this.targetNick, required this.channel}) : super(key: key);

  @override
  State<PrivateCallScreen> createState() => _PrivateCallScreenState();
}

class _PrivateCallScreenState extends State<PrivateCallScreen> {
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _inCall = false;

  @override
  void initState() {
    super.initState();
    _initWebRTC();
    widget.channel.stream.asBroadcastStream().listen((message) {
      try {
        final data = jsonDecode(message);
        if (data['type'] == 'callSignal' && data['from'] == widget.targetNick) {
          _handleSignal(data['signal']);
        }
      } catch (e) {
        print('Call - Hata: $e');
      }
    });
  }

  Future<void> _initWebRTC() async {
    await Permission.microphone.request();
    final config = {'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]};
    _pc = await createPeerConnection(config);
    _pc!.onIceCandidate = (candidate) {
      widget.channel.sink.add(jsonEncode({
        'type': 'callSignal',
        'target': widget.targetNick,
        'signal': {'type': 'candidate', 'candidate': candidate.toMap()},
      }));
    };
  }

  void _startCall() async {
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _localStream!.getTracks().forEach((track) => _pc!.addTrack(track, _localStream!));
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    widget.channel.sink.add(jsonEncode({
      'type': 'callSignal',
      'target': widget.targetNick,
      'signal': {'type': 'offer', 'sdp': offer.sdp},
    }));
    setState(() => _inCall = true);
  }

  void _handleSignal(signal) {
    if (signal['type'] == 'offer') {
      _pc!.setRemoteDescription(RTCSessionDescription(signal['sdp'], 'offer'));
      _pc!.createAnswer().then((answer) {
        _p
