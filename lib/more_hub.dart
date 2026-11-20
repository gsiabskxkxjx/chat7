part of 'main.dart';

// ---------- صفحة «المزيد»: كل الميزات بمكان واحد بدل القوائم الطويلة ----------
// الإجراءات السريعة وأدوات المحادثة (تنفّذ داخل المحادثة فتسكّر الصفحة أول)،
// وبعدها الميزات الأكثر استعمالاً، وبعدها كل الأقسام. وفي الأعلى بحث بكل شي.

class MoreHubScreen extends StatefulWidget {
  const MoreHubScreen({
    super.key,
    required this.chatId,
    required this.chatContext,
    required this.quick,
    required this.tools,
  });

  final String chatId;

  /// سياق المحادثة: القوائم الجاهزة (الألعاب، الخطط...) تفتح شاشاتها منه
  final BuildContext chatContext;

  /// إجراءات سريعة تنفّذ داخل المحادثة (موقعي، أنا بطريقي...)
  final List<_MenuItem> quick;

  /// أدوات المحادثة (انتقل لتاريخ، صدّر المحادثة، رسائل تختفي...)
  final List<_MenuItem> tools;

  @override
  State<MoreHubScreen> createState() => _MoreHubState();
}

class _MoreHubState extends State<MoreHubScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _push(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  /// ينفّذ عنصر يعمل داخل المحادثة: نسكّر الصفحة أول ثم ننفّذ
  void _runInChat(_MenuItem it) {
    Navigator.of(context).pop();
    it.$4();
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap, {String? emoji}) =>
      Semantics(
        button: true,
        label: label,
        child: _Press(
          onTap: onTap,
          child: Glass(
            radius: 22,
            shadow: false,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              emoji != null
                  ? Text(emoji, style: const TextStyle(fontSize: 26))
                  : Icon(icon, size: 28),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: _Fs.meta, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  Widget _title(String t) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 18, 6, 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: _Fs.meta, fontWeight: FontWeight.w700, color: Color(0xB3FFFFFF))),
      );

  Widget _grid(List<Widget> kids) => GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 104,
        ),
        children: kids,
      );

  @override
  Widget build(BuildContext context) {
    final id = widget.chatId;
    final tabs = _gamesTabs(widget.chatContext, id);
    final q = _q.text.trim();

    final search = Padding(
      padding: const EdgeInsets.only(bottom: _Sp.sm),
      child: TextField(
        controller: _q,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'ابحث عن ميزة (لعبة، ميزانية، يوميات...)',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: q.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(_q.clear)),
          filled: true,
          fillColor: const Color(0x1FFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: _edge),
          ),
        ),
      ),
    );

    final children = <Widget>[search];

    if (q.isNotEmpty) {
      // نتائج البحث: الأدوات أول (تسكّر الصفحة)، وبعدها الباقي
      final hits = <Widget>[];
      for (final it in [...widget.quick, ...widget.tools]) {
        if (it.$2.contains(q) || it.$3.contains(q)) {
          hits.add(ListTile(
            leading: Icon(it.$1),
            title: Text(it.$2),
            subtitle: it.$3.isEmpty ? null : Text(it.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _runInChat(it),
          ));
        }
      }
      for (final t in tabs) {
        for (final it in t.$2) {
          if (it.$2.contains(q) || it.$3.contains(q)) {
            hits.add(ListTile(
              leading: Icon(it.$1),
              title: Text(it.$2),
              subtitle: Text(it.$3, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: it.$4,
            ));
          }
        }
      }
      children.add(hits.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(_Sp.xl),
              child: Center(child: Text('ما لقينا ميزة بهالاسم.')))
          : Glass(
              radius: 24,
              padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
              child: Column(children: hits)));
    } else {
      // إجراءات سريعة
      children.add(_title('سريع'));
      children.add(Row(children: [
        for (var i = 0; i < widget.quick.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 92,
              child: _tile(widget.quick[i].$1, widget.quick[i].$2, () => _runInChat(widget.quick[i])),
            ),
          ),
        ],
      ]));

      // الأكثر استعمالاً
      void category(int i) => _push(_MoreCategoryScreen(title: tabs[i].$1, items: tabs[i].$2));
      children.add(_title('الأكثر استعمالاً'));
      children.add(_grid([
        _tile(Icons.push_pin_rounded, 'لمسات حب', () => _push(LoveNotesScreen(chatId: id)), emoji: '💗'),
        _tile(Icons.sports_esports_rounded, 'ألعاب', () => category(0), emoji: '🎮'),
        _tile(Icons.photo_library_rounded, 'معرض المحادثة', () => _push(GalleryScreen(chatId: id)), emoji: '🖼️'),
        _tile(Icons.calendar_month_rounded, 'خطط ومواعيد', () => _push(CalendarScreen(chatId: id)), emoji: '🗓️'),
        _tile(Icons.account_balance_wallet_rounded, 'ميزانيتنا', () => _push(BudgetScreen(chatId: id)), emoji: '💰'),
        _tile(Icons.photo_album_rounded, 'ألبومات وذكريات', () => _push(MemoriesScreen(chatId: id)), emoji: '📸'),
        _tile(Icons.menu_book_rounded, 'يومياتنا', () => _push(DiaryScreen(chatId: id)), emoji: '📖'),
        _tile(Icons.lock_clock_rounded, 'كبسولة زمنية', () => _push(CapsulesScreen(chatId: id)), emoji: '⏳'),
        _tile(Icons.checklist_rounded, 'قوائم مشتركة', () => _push(SharedListsScreen(chatId: id)), emoji: '✅'),
      ]));

      // كل الأقسام
      children.add(_title('كل الميزات'));
      children.add(Glass(
        radius: 24,
        padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
        child: Column(children: [
          for (var i = 0; i < tabs.length; i++)
            ListTile(
              title: Text(tabs[i].$1, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${tabs[i].$2.length} ميزة'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => category(i),
            ),
          ListTile(
            leading: const Icon(Icons.build_rounded),
            title: const Text('أدوات المحادثة', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${widget.tools.length} أداة'),
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () => _push(_MoreCategoryScreen(
                title: 'أدوات المحادثة', items: widget.tools, closeFirst: true)),
          ),
        ]),
      ));
    }

    return _R2Page(
      title: 'المزيد',
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(_Sp.lg, _Sp.sm, _Sp.lg, _Sp.xl),
        children: children,
      ),
    );
  }
}

/// قائمة ميزات قسم واحد. [closeFirst]: العنصر ينفّذ داخل المحادثة، فنسكّر الصفحتين أول
class _MoreCategoryScreen extends StatelessWidget {
  const _MoreCategoryScreen({required this.title, required this.items, this.closeFirst = false});
  final String title;
  final List<_MenuItem> items;
  final bool closeFirst;

  @override
  Widget build(BuildContext context) => _R2Page(
        title: title,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: _Sp.lg, vertical: _Sp.sm),
          children: [
            Glass(
              radius: 24,
              padding: const EdgeInsets.symmetric(vertical: _Sp.xs),
              child: Column(children: [
                for (final it in items)
                  ListTile(
                    leading: Icon(it.$1),
                    title: Text(it.$2),
                    subtitle: it.$3.isEmpty
                        ? null
                        : Text(it.$3, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      if (closeFirst) {
                        // نرجع للمحادثة (نسكّر هالصفحة وصفحة المزيد) وبعدها ننفّذ
                        final nav = Navigator.of(context);
                        nav.pop();
                        nav.pop();
                      }
                      it.$4();
                    },
                  ),
              ]),
            ),
          ],
        ),
      );
}
