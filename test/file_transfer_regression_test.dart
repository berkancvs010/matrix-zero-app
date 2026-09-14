import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final serverSource = File('server/server.js').readAsStringSync();
  final transferSource = File('lib/file_transfer.dart').readAsStringSync();

  test('server pending-byte accounting decrements each chunk exactly once', () {
    expect(
      RegExp(
        r'session\.pendingBytes=Math\.max\(0,\(Number\(session\.pendingBytes\)\|\|0\)-sentLength\);',
      ).allMatches(serverSource).length,
      1,
    );
    expect(
      RegExp(
        r'reliablePendingTotalBytes=Math\.max\(0,reliablePendingTotalBytes-sentLength\);',
      ).allMatches(serverSource).length,
      1,
    );
    expect(
      serverSource,
      contains('const RELIABLE_FILE_MAX_PENDING_BYTES=64*1024*1024;'),
    );
  });

  test('client transfer has defensive event cleanup and manifest normalization', () {
    expect(transferSource, contains('FILE_EVENT_QUEUE_CLEANUP_FAILED'));
    expect(transferSource, contains('RECEIVE_MANIFEST_NORMALIZED'));
    expect(transferSource, contains('Dosya SHA-256 bilgisi geçersiz.'));
    expect(transferSource, contains(r"RegExp(r'^[a-f0-9]{64}$')"));
  });

  test('legacy file push helpers never suppress FCM from stale presence alone', () {
    expect(
      serverSource,
      contains(
        'const liveForeground=socketFor(target);\n  if(liveForeground && isForegroundActive(target))return false;',
      ),
    );
    expect(
      serverSource,
      isNot(contains(
        'if(isForegroundActive(target))return false;\n\n  const transferId=String(',
      )),
    );
  });

  test('server sends a background wake-up when presence is stale and no live socket exists', () {
    expect(
      serverSource,
      contains(
        'const pushed=await sendFcmPush(session.to,{',
      ),
    );
    expect(
      serverSource,
      contains(
        'const foreground=socketFor(session.to);',
      ),
    );
    expect(
      serverSource,
      contains(
        'if(endpoint || foreground)continue;',
      ),
    );
    expect(
      serverSource,
      isNot(contains(
        'if(isForegroundActive(session.to)){\n    return false;\n  }\n\n  const pushed=await sendFcmPush',
      )),
    );
  });

}
