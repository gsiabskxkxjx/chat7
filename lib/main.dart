import 'dart:async';
import 'dart:io' show File, HttpClient;
import 'dart:math' show Random;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart'
    show ImagePicker, ImageSource, XFile;
import 'package:path_provider/path_provider.dart'
    show getTemporaryDirectory, getApplicationSupportDirectory;
import 'package:local_auth/local_auth.dart'
    show LocalAuthentication, AuthenticationOptions;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gal/gal.dart' show Gal;
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'package:record/record.dart'
    show AudioEncoder, AudioRecorder, RecordConfig;
import 'package:video_player/video_player.dart'
    show VideoPlayer, VideoPlayerController, VideoProgressIndicator;
import 'package:firebase_core/firebase_core.dart' show Firebase;
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus, FirebaseMessaging, RemoteMessage;
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show
        Helper,
        MediaStream,
        MediaStreamTrack,
        RTCIceCandidate,
        RTCPeerConnection,
        RTCPeerConnectionState,
        RTCSessionDescription,
        RTCVideoRenderer,
        RTCVideoView,
        RTCVideoViewObjectFit,
        createPeerConnection,
        navigator;
import 'package:supabase_flutter/supabase_flutter.dart'
    show
        AuthException,
        AuthResponse,
        FileOptions,
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        PostgrestException,
        RealtimeChannel,
        RealtimeSubscribeStatus,
        Supabase,
        SupabaseClient,
        UserAttributes;

import 'config.dart';
import 'turn_config.dart';

part 'widgets.dart';
part 'start_screens.dart';
part 'pair_screen.dart';
part 'chat_screen.dart';
part 'chat_actions.dart';
part 'chat_ui.dart';
part 'profile_actions.dart';
part 'call_hub.dart';
part 'call_session.dart';
part 'call_screens.dart';
part 'media.dart';
part 'chat_pulse.dart';
part 'profile_screen.dart';
part 'gender_screen.dart';
part 'voice_video.dart';
part 'bubbles.dart';
part 'push.dart';
part 'auth_screens.dart';
part 'recovery_screens.dart';
part 'theme_palette.dart';
part 'theme_settings.dart';
part 'feedback_screen.dart';
part 'status_lines.dart';
part 'memories_screen.dart';
part 'lock_screens.dart';
part 'call_notify.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_configured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_bgCallMessage);
    await _initCallNotifier();
  } catch (_) {}
  runApp(const App());
}

final bool _configured = !supabaseUrl.startsWith('PASTE');
SupabaseClient get _db => Supabase.instance.client;

const _glass = Color(0x2EFFFFFF);
const _edge = Color(0x59FFFFFF);
const _blue = Color(0xFF0A84FF);

/// اسم التطبيق (يظهر بالشاشات وعلى الجوال).
const appName = 'بيناتنا';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _blue, brightness: Brightness.dark),
        ),
        builder: (c, child) => Directionality(
            textDirection: TextDirection.rtl, child: _LockGate(child: child!)),
        home: const Boot(),
      );
}
