// ثيمات المحادثة: 8 ثيمات (4 ليلية و4 نهارية).
// يُستخدم بشاشة مظهر المحادثة (theme_settings.dart).
part of 'main.dart';

class ChatTheme {
  const ChatTheme({
    required this.id,
    required this.name,
    required this.dark,
    required this.top,
    required this.bottom,
    required this.mine,
    required this.theirs,
    required this.accent,
    required this.text,
  });

  final int id;
  final String name;
  final bool dark; // true = ليلي
  final Color top; // لون الخلفية من فوق
  final Color bottom; // لون الخلفية من تحت
  final Color mine; // فقاعة رسالتك
  final Color theirs; // فقاعة الطرف الثاني
  final Color accent; // الزر والتمييز
  final Color text; // لون النص
}

const _lightText = Color(0xFF1C1B1F);
const _darkText = Color(0xFFFFFFFF);

const chatThemes = <ChatTheme>[
  // ---- ليلية ----
  ChatTheme(id: 1, name: 'ليلي هادئ', dark: true, top: Color(0xFF0B1B3A), bottom: Color(0xFF2B2A7A), mine: Color(0xFF0A84FF), theirs: Color(0x33FFFFFF), accent: Color(0xFF0A84FF), text: _darkText),
  ChatTheme(id: 2, name: 'منتصف الليل', dark: true, top: Color(0xFF05070D), bottom: Color(0xFF1A1F3A), mine: Color(0xFF5E6AD2), theirs: Color(0x26FFFFFF), accent: Color(0xFF8C9EFF), text: _darkText),
  ChatTheme(id: 3, name: 'غروب ليلي', dark: true, top: Color(0xFF2A1B3D), bottom: Color(0xFF7A3E5C), mine: Color(0xFFE0568F), theirs: Color(0x33FFFFFF), accent: Color(0xFFFF8A65), text: _darkText),
  ChatTheme(id: 4, name: 'غابة ليلية', dark: true, top: Color(0xFF0F2A1F), bottom: Color(0xFF2E5E4E), mine: Color(0xFF3FA37C), theirs: Color(0x33FFFFFF), accent: Color(0xFFA7E3B8), text: _darkText),
  // ---- نهارية ----
  ChatTheme(id: 5, name: 'صباح هادئ', dark: false, top: Color(0xFFF4EFE6), bottom: Color(0xFFE8DCCB), mine: Color(0xFF8E7CC3), theirs: Color(0xFFFFFFFF), accent: Color(0xFF8E7CC3), text: _lightText),
  ChatTheme(id: 6, name: 'سماء صافية', dark: false, top: Color(0xFFEAF6FF), bottom: Color(0xFFBFE3FF), mine: Color(0xFF2196F3), theirs: Color(0xFFFFFFFF), accent: Color(0xFF1976D2), text: _lightText),
  ChatTheme(id: 7, name: 'نعناع', dark: false, top: Color(0xFFEEF8F2), bottom: Color(0xFFC8EBD6), mine: Color(0xFF3FA37C), theirs: Color(0xFFFFFFFF), accent: Color(0xFF2E7D5B), text: _lightText),
  ChatTheme(id: 8, name: 'وردي فاتح', dark: false, top: Color(0xFFFFF1F5), bottom: Color(0xFFFAD4E1), mine: Color(0xFFE0568F), theirs: Color(0xFFFFFFFF), accent: Color(0xFFC2185B), text: _lightText),
];

/// يرجّع الثيم حسب رقمه. إذا الرقم غلط يرجّع الافتراضي (ليلي هادئ).
ChatTheme chatThemeById(int id) =>
    chatThemes.firstWhere((t) => t.id == id, orElse: () => chatThemes.first);
