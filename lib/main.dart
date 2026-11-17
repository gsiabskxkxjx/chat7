import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Int64List;
import 'dart:io' show Directory, File, HttpClient, HttpDate;
import 'dart:math' show Random;
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart' show GoogleFonts;
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;
import 'package:image_picker/image_picker.dart'
    show CameraDevice, ImagePicker, ImageSource, XFile;
import 'package:file_selector/file_selector.dart' show openFile;
import 'package:qr_flutter/qr_flutter.dart' show QrImageView;
import 'package:app_links/app_links.dart' show AppLinks;
import 'package:quick_actions/quick_actions.dart' show QuickActions, ShortcutItem;
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_10y.dart' as tz_data;
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
import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
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
        CountOption,
        FileOptions,
        FunctionException,
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
part 'games_screens.dart';
part 'quiz_screen.dart';
part 'lists_screens.dart';
part 'search_screens.dart';
part 'quick_replies.dart';
part 'app_look.dart';
part 'profile_setup.dart';
part 'match_bubble.dart';
part 'effects.dart';
part 'onboarding.dart';
part 'extras.dart';
part 'fun.dart';
part 'prefs.dart';
part 'chat_more.dart';
part 'net_more.dart';
part 'story.dart';
part 'together.dart';
part 'games2.dart';
part 'media_more.dart';
part 'extras2.dart';
part 'games3.dart';
part 'invite_more.dart';
part 'shared_more.dart';
part 'home_more.dart';
part 'whats_new.dart';
part 'tokens.dart';
part 'native_more.dart';
part 'voice_text.dart';
part 'phone_verify.dart';
part 'r2_core.dart';
part 'r2_settings.dart';
part 'r2_chat.dart';
part 'r2_plans.dart';
part 'r2_couple.dart';
part 'games4.dart';
part 'games5.dart';
part 'r2_ai.dart';
part 'r2_text.dart';
part 'r2_insights.dart';
part 'r2_gallery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _Crash.install();
  await _Prefs.load();
  await _R2Store.load();
  if (_configured) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }
  if (_configured) {
    _startAppLook();
    _db.auth.onAuthStateChange.listen((_) {
      _startAppLook();
      unawaited(_R2.onAuth());
    });
  }
  runApp(const App());
  _listenInvites();
  _setupShortcuts();
  // الإشعارات تبدأ بعد أول شاشة، حتى يفتح التطبيق أسرع
  unawaited(() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_bgCallMessage);
      await _initCallNotifier();
      if (_Prefs.dailyReminder.value >= 0) await _scheduleDailyReminder();
    } catch (_) {}
  }());
  if (_configured) {
    unawaited(Future.delayed(const Duration(seconds: 12), _Crash.sendPending));
    unawaited(Future.delayed(const Duration(seconds: 3), () {
      _R2.perf('first_frame');
      unawaited(_R2.onAuth());
      unawaited(_R2.checkClock());
    }));
  }
  unawaited(Future.delayed(const Duration(seconds: 8), _checkForUpdate));
}

final bool _configured = !supabaseUrl.startsWith('PASTE');
SupabaseClient get _db => Supabase.instance.client;

const _edge = Color(0x59FFFFFF);
const _blue = Color(0xFF0A84FF);

/// اسم التطبيق (يظهر بالشاشات وعلى الجوال).
const appName = 'بيناتنا';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_Prefs.arabicFont, _lightUi]),
        builder: (c, __) => _app(c, _Prefs.arabicFont.value, _lightUi.value),
      );

  Widget _app(BuildContext context, bool arabic, bool light) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: _messengerKey,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          // خط عربي حديث (IBM Plex Sans Arabic)، ولو ما انحمّل يرجع للخط العادي
          textTheme: arabic
              ? GoogleFonts.ibmPlexSansArabicTextTheme(
                  ThemeData(brightness: Brightness.dark).textTheme)
              : null,
          colorScheme: ColorScheme.fromSeed(
              seedColor: _blue, brightness: Brightness.dark),
          // الثيم النهاري: عنوان الشاشة وأيقوناتها غامقة فوق الخلفية الفاتحة
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            foregroundColor: light ? const Color(0xFF1C1B1F) : Colors.white,
            iconTheme: IconThemeData(color: light ? const Color(0xFF1C1B1F) : Colors.white),
          ),
          // نوافذ وتنبيهات وقوائم بشكل زجاجي بدل شكل أندرويد الافتراضي
          dialogTheme: DialogThemeData(
            backgroundColor: const Color(0xE6161C3A),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
              side: const BorderSide(color: Color(0x4DFFFFFF)),
            ),
          ),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xE6202A55),
            contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
            actionTextColor: Color(0xFF7CC0FF),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20)),
              side: BorderSide(color: Color(0x4DFFFFFF)),
            ),
          ),
          // انتقال بالتلاشي مع تكبير خفيف بين الشاشات
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: _FadePageTransitions(),
            TargetPlatform.iOS: _FadePageTransitions(),
          }),
          bottomSheetTheme: const BottomSheetThemeData(
            showDragHandle: true,
            dragHandleColor: Color(0x66FFFFFF),
            backgroundColor: Color(0xEB161C3A),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              side: BorderSide(color: Color(0x40FFFFFF)),
            ),
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: const Color(0xEB1B2247),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0x4DFFFFFF)),
            ),
          ),
        ),
        builder: (c, child) {
          // تكبير خط الجوال مسموح لحد معيّن، حتى ما يخرب التصميم
          final mq = MediaQuery.of(c);
          return MediaQuery(
            data: mq.copyWith(
                textScaler:
                    mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.3)),
            child: Directionality(
                textDirection: TextDirection.rtl,
                child: _LockGate(child: child!)),
          );
        },
        home: const Boot(),
      );
}

class _FadePageTransitions extends PageTransitionsBuilder {
  const _FadePageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final a = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(a), child: child),
    );
  }
}
