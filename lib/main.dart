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
        colorScheme: const ColorScheme.dark(
          primary: Colors.green,
          secondary: Colors.greenAccent,
        ),
      ),
      home: const NicknameScreen(),
    );
  }
}

// 1. Rumuz Giriş Ekranı
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({Key? key}) : super(key: key);

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();

  void _enterApp() {
    final nickname = _controller.text.trim();
    if (nickname.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RoomScreen(nickname: nickname),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZERO LOG CHAT - GİRİŞ')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Sisteme Giriş İçin Rumuz Belirleyin',
              style: TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold),
            ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _enterApp,
              child: const Text('Bağlan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. 10 Adet Rastgele Oda Seçim Ekranı
class RoomScreen extends StatelessWidget {
  final String nickname;
  const RoomScreen({Key? key, required this.nickname}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<String> rooms = [
      '1p09aq66zx6Qr9', '8k22bm91wx3Pt4', '9x44cn18yv7Ls2',
      '3z88dp52zu1Km8', '7v11er39xt5Jn3', '5m66fs84yq9Hb6',
      '2q33gt71zp2Wv1', '4w55hy03xr8Dc9', '6j99jx25yv4Fg5',
      '0n77kz46zt0Tq7'
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Odalar - Rumuz: $nickname')),
      body: ListView.builder(
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          return Card(
            color: Colors.grey[900],
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(
                'Oda #${index + 1}: ${rooms[index]}',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, color: Colors.green),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(roomName: rooms[index], nickname: nickname),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// 3. Canlı Mesajlaşma ve Sesli Arama Ekranı
class ChatScreen extends StatefulWidget {
  final String roomName;
  final String nickname;
  const ChatScreen({Key? key, required this.roomName, required this.nickname}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  late WebSocketChannel _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _inCall = false;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://zerolog.giize.com:8443'),
    );
    _channel.stream.listen((message) {
      final data = jsonDecode(message);
      if (data['room'] == widget.roomName) {
        if (data['type'] == 'text') {
          if (data['sender'] != widget.nickname) {
            setState(() {
              _messages.add({
                'sender': data['sender'],
                'text': data['text'],
              });
            });
          }
        } else if (data['type'] == 'offer' && data['sender'] != widget.nickname) {
          _handleOffer(data['sdp']);
        } else if (data['type'] == 'answer' && data['sender'] != widget.nickname) {
          _handleAnswer(data['sdp']);
        } else if (data['type'] == 'candidate' && data['sender'] != widget.nickname) {
          _handleCandidate(data['candidate']);
        }
      }
    });
  }

  Future<void> _createPeerConnection() async {
    await Permission.microphone.request();
    Map<String, dynamic> configuration = {
      "iceServers": [
        {"urls": "stun:stun.l.google.com:19302"}
      ]
    };
    _peerConnection = await createPeerConnection(configuration);
    _peerConnection?.onIceCandidate = (candidate) {
      _channel.sink.add(jsonEncode({
        'room': widget.roomName,
        'sender': widget.nickname,
        'type': 'candidate',
        'candidate': candidate.toMap(),
      }));
    };
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    final text = _messageController.text.trim();
    _channel.sink.add(jsonEncode({
      'room': widget.roomName,
      'sender': widget.nickname,
      'type': 'text',
      'text': text,
    }));
    setState(() {
      _messages.add({
        'sender': widget.nickname,
        'text': text,
      });
      _messageController.clear();
    });
  }

  Future<void> _startCall() async {
    await _createPeerConnection();
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    _channel.sink.add(jsonEncode({
      'room': widget.roomName,
      'sender': widget.nickname,
      'type': 'offer',
      'sdp': offer.sdp,
    }));
    setState(() {
      _inCall = true;
    });
  }

  Future<void> _handleOffer(String sdp) async {
    await _createPeerConnection();
    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    _channel.sink.add(jsonEncode({
      'room': widget.roomName,
      'sender': widget.nickname,
      'type': 'answer',
      'sdp': answer.sdp,
    }));
    setState(() {
      _inCall = true;
    });
  }

  Future<void> _handleAnswer(String sdp) async {
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  Future<void> _handleCandidate(Map<String, dynamic> candidateMap) async {
    RTCIceCandidate candidate = RTCIceCandidate(
      candidateMap['candidate'],
      candidateMap['sdpMid'],
      candidateMap['sdpMLineIndex'],
    );
    await _peerConnection!.addCandidate(candidate);
  }

  void _endCall() {
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.close();
    _peerConnection = null;
    setState(() {
      _inCall = false;
    });
  }

  @override
  void dispose() {
    _endCall();
    _channel.sink.close();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('#${widget.roomName}', style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: Icon(
              _inCall ? Icons.call_end : Icons.call,
              color: _inCall ? Colors.red : Colors.greenAccent,
            ),
            onPressed: _inCall ? _endCall : _startCall,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
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
                        Text(
                          msg['sender']!,
                          style: const TextStyle(fontSize: 10, color: Colors.greenAccent),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['text']!,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Mesaj yaz...',
                      hintStyle: TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.green)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.greenAccent)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.greenAccent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
