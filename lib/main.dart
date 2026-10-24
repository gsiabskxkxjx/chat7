import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        PostgresChangeEvent,
        PostgresChangeFilter,
        PostgresChangeFilterType,
        PostgrestException,
        RealtimeChannel,
        RealtimeSubscribeStatus,
        Supabase,
        SupabaseClient;

import 'config.dart';
import 'turn_config.dart';

part 'widgets.dart';
part 'start_screens.dart';
part 'pair_screen.dart';
part 'chat_screen.dart';
part 'call_hub.dart';
part 'call_session.dart';
part 'call_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_configured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  runApp(const App());
}

final bool _configured = !supabaseUrl.startsWith('PASTE');
SupabaseClient get _db => Supabase.instance.client;

const _glass = Color(0x2EFFFFFF);
const _edge = Color(0x59FFFFFF);
const _blue = Color(0xFF0A84FF);

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'تواصل',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _blue, brightness: Brightness.dark),
        ),
        builder: (c, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const Boot(),
      );
}
