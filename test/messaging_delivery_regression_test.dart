import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String path) => File(path).readAsStringSync();

  test(
    'background transport acknowledges pending batches with the exact token',
    () {
      final networking = read('lib/networking.dart');
      final batch = networking.indexOf(
        "incomingType == 'pendingPrivateMessages'",
      );
      expect(batch, greaterThanOrEqualTo(0));
      final end = networking.indexOf(
        "if (data['type'] == 'userBlocked')",
        batch,
      );
      final handler = networking.substring(batch, end);
      expect(handler, contains("'type': 'messageDelivered'"));
      expect(handler, contains("'deliveryToken': deliveryToken"));
      expect(handler, contains("recipient.toLowerCase() !="));
    },
  );

  test('live/private-list ACK paths retain server-issued delivery token', () {
    final main = read('lib/main_screen.dart');
    expect(
      main,
      contains("'deliveryToken': (data['deliveryToken'] ?? '').toString()"),
    );
    expect(
      main,
      contains("'deliveryToken': (map['deliveryToken'] ?? '').toString()"),
    );

    final chat = read('lib/private_chat.dart');
    expect(
      chat,
      contains("'deliveryToken': (map['deliveryToken'] ?? '').toString()"),
    );
  });

  test('server accepts only a valid receipt for the addressed recipient', () {
    final server = read('server/server.js');
    expect(server, contains("case 'messageDelivered':"));
    expect(
      server,
      contains(
        'String(target.deliveryToken||\'\')!==String(deliveryToken||\'\')',
      ),
    );
    expect(server, contains("req.url==='/delivery'"));
    expect(server, contains('deliveryToken'));
  });

  test(
    'native FCM fallback posts the token rather than treating push as delivery',
    () {
      final native = read(
        'android/app/src/main/kotlin/com/zerolog/app/ZeroLogFirebaseMessagingService.kt',
      );
      expect(native, contains('acknowledgePrivateMessageDelivery(message)'));
      expect(native, contains('put("deliveryToken", deliveryToken)'));
      expect(native, contains('"https://zerolog.giize.com/delivery"'));
    },
  );
}
