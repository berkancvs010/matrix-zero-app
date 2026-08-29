import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:proximity_sensor/proximity_sensor.dart';
import 'file_transfer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';


part 'app_bootstrap.dart';
part 'push_service.dart';
part 'theme.dart';
part 'app_shell.dart';
part 'welcome.dart';
part 'networking.dart';
part 'login.dart';
part 'nickname.dart';
part 'main_screen.dart';
part 'chat_room.dart';
part 'private_chat.dart';
part 'call_screen.dart';
part 'message_input.dart';
part 'models.dart';
part 'profile_controller.dart';

const String wsUrl = 'wss://zerolog.giize.com:8443/ws';
final GlobalKey<NavigatorState> zeroLogNavigatorKey =
    GlobalKey<NavigatorState>();

const List<String> rooms = [
  'genel',
  'sohbet',
  'teknoloji',
  'oyun',
  'müzik',
  'film',
  'spor',
  'gece',
];
