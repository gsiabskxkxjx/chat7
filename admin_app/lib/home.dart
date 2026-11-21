part of 'main.dart';

// ---------- الواجهة الرئيسية: شريط سفلي بخمس صفحات ----------

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _i = 0;

  static const _titles = ['الرئيسية', 'المستخدمون', 'البلاغات والملاحظات', 'الأخطاء والسجل', 'التحكم عن بعد'];

  Future<void> _signOut() async {
    final ok = await _confirm(context,
        title: 'تسجيل الخروج', body: 'تطلع من حساب الأدمن على هالجهاز.', ok: 'خروج');
    if (ok) await _sb.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_i]),
        actions: [
          IconButton(
            tooltip: 'خروج',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _signOut,
          ),
        ],
      ),
      body: IndexedStack(
        index: _i,
        children: const [
          DashboardPage(),
          UsersPage(),
          ReportsPage(),
          ErrorsPage(),
          ControlPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.people_rounded), label: 'المستخدمون'),
          NavigationDestination(icon: Icon(Icons.flag_rounded), label: 'البلاغات'),
          NavigationDestination(icon: Icon(Icons.bug_report_rounded), label: 'الأخطاء'),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'التحكم'),
        ],
      ),
    );
  }
}
