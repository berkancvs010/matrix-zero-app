import 'package:flutter/material.dart';

void main() {
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

// 1. Aşama: Rumuz Giriş Ekranı
class NicknameScreen extends StatefulWidget {
  const NicknameScreen({Key? key}) : super(key: key);

  @override
  State<NicknameScreen> createState() => _NicknameScreenState();
}

class _NicknameScreenState extends State<NicknameScreen> {
  final TextEditingController _controller = TextEditingController();

  void _enterApp() {
    if (_controller.text.trim().isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => RoomScreen(nickname: _controller.text.trim()),
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

// 2. Aşama: Oda Seçim Ekranı
class RoomScreen extends StatelessWidget {
  final String nickname;
  const RoomScreen({Key? key, required this.nickname}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<String> rooms = ['Genel Merkez', 'Siber Güvenlik', 'Matrix', 'Gizli Kanal'];

    return Scaffold(
      appBar: AppBar(title: Text('Odalar - Rumuz: $nickname')),
      body: ListView.builder(
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          return Card(
            color: Colors.grey[900],
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(rooms[index], style: const TextStyle(color: Colors.greenAccent, fontSize: 18)),
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

// 3. Aşama: Mesajlaşma Ekranı
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

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    setState(() {
      _messages.add({
        'sender': widget.nickname,
        'text': _messageController.text.trim(),
      });
      _messageController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('#${widget.roomName}')),
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
