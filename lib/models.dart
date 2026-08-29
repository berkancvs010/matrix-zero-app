part of 'main.dart';

class ChatMessage {
  final String id;
  final String sender;
  final String text;
  final String clientMessageId;
  final String status;
  final int timestamp;

  // Dosya mesajı metadata
  final bool isFile;
  final String fileId;
  final String fileName;
  final int fileSize;
  final int transferBytes;
  final int expiresAt;
  final String localPath;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    this.clientMessageId = '',
    this.status = 'sending',
    this.timestamp = 0,
    this.isFile = false,
    this.fileId = '',
    this.fileName = '',
    this.fileSize = 0,
    this.transferBytes = 0,
    this.expiresAt = 0,
    this.localPath = '',
  });

  ChatMessage copyWith({
    String? id,
    String? sender,
    String? text,
    String? clientMessageId,
    String? status,
    int? timestamp,
    bool? isFile,
    String? fileId,
    String? fileName,
    int? fileSize,
    int? transferBytes,
    int? expiresAt,
    String? localPath,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
      isFile: isFile ?? this.isFile,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      transferBytes: transferBytes ?? this.transferBytes,
      expiresAt: expiresAt ?? this.expiresAt,
      localPath: localPath ?? this.localPath,
    );
  }
}
