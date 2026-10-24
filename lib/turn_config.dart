// إعدادات خادم TURN (اختياري، بس مهم لمكالمات الجوال بين شبكات مختلفة).
// بدونه المكالمات تشتغل غالباً على نفس الواي فاي فقط.
// خذ القيم من حسابك بـ metered.ca (لوحة التحكم ← TURN Server)،
// وانسخ عناوين الـ urls واسم المستخدم والكلمة كما هي:
const turnUrls = <String>[
  // 'turn:...:80',
  // 'turn:...:443?transport=tcp',
  // 'turns:...:443?transport=tcp',
];
const turnUsername = '';
const turnCredential = '';
