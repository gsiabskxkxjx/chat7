part of 'main.dart';

// ---------- تحديد عدة رسائل، حذف عندي، وقت القراءة، لصق صورة من الكيبورد، فاصل غير المقروء ----------

/// رسائل محذوفة عندي بس (تنحفظ بالجوال، والطرف الثاني تبقى عنده)
class _HiddenForMe {
  static Future<File> _file(String chatId) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/hidden_$chatId.json');
  }

  static Future<Set<int>> load(String chatId) async {
    try {
      final f = await _file(chatId);
      if (!await f.exists()) return {};
      return (jsonDecode(await f.readAsString()) as List)
          .map((e) => (e as num).toInt())
          .toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String chatId, Set<int> ids) async {
    try {
      final list = ids.toList()..sort();
      final keep = list.length > 5000 ? list.sublist(list.length - 5000) : list;
      await (await _file(chatId)).writeAsString(jsonEncode(keep));
    } catch (_) {}
  }
}

/// علامة "رسائل جديدة" فوق أول رسالة ما قريتها
class _UnreadMarker {
  const _UnreadMarker();
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          const Expanded(child: Divider(color: Color(0x55FFFFFF))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: _Sp.md, vertical: _Sp.xs),
            decoration: BoxDecoration(
              color: const Color(0x55FF5FA2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: const Text('رسائل جديدة',
                style: TextStyle(fontSize: _Fs.small, color: Colors.white)),
          ),
          const Expanded(child: Divider(color: Color(0x55FFFFFF))),
        ]),
      );
}

String _clockOf(DateTime d) => _Fmt.time(d);

extension _ChatMore on _ChatState {
  Future<void> _loadHiddenMine() async {
    final s = await _HiddenForMe.load(widget.chat.id);
    if (mounted && s.isNotEmpty) setState(() => _hiddenMine = s);
  }

  Future<void> _hideForMe(Iterable<int> ids) async {
    setState(() => _hiddenMine = {..._hiddenMine, ...ids});
    await _HiddenForMe.save(widget.chat.id, _hiddenMine);
  }

  /// يتنادى من بناء القائمة: يعدّ الرسائل الجديدة وأنت فوق، ويحدد أول رسالة ما قريتها
  void _trackNew(List<Msg> msgs) {
    _lastMsgs = msgs;
    _ChatMedia.update(msgs);
    if (msgs.isEmpty) return;
    final newest = msgs.first.id;
    final prev = _newestSeen;
    _newestSeen = newest;
    if (!_unreadChecked) {
      _unreadChecked = true;
      final unread = msgs.where((m) => !m.mine && !m.read).toList();
      if (unread.length >= 3) _unreadFrom = unread.last.id;
    }
    if (prev == null || newest <= prev) {
      if (prev == null) unawaited(_HomeWidgets.photo(widget.chat.id));
      return;
    }
    for (final m in msgs) {
      if (m.id <= prev) break;
      if (!m.mine && m.kind == 'think') {
        unawaited(_HomeWidgets.think(m.at ?? DateTime.now()));
        break;
      }
    }
    if (_Prefs.autoSave.value) {
      for (final m in msgs) {
        if (m.id <= prev) break;
        final path = m.mediaPath;
        if (!m.mine && m.kind == 'image' && path != null) {
          unawaited(_autoSaveImage(path));
        }
      }
    }
    if (!_showDown) return;
    final n = msgs.where((m) => m.id > prev && !m.mine).length;
    if (n == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _newBelow.value += n;
    });
  }

  /// يضيف فاصل "رسائل جديدة" فوق أول رسالة غير مقروءة
  void _addUnreadMarker(List<Object> entries) {
    final id = _unreadFrom;
    if (id == null) return;
    final i = entries.indexWhere((e) => e is Msg && e.id == id);
    if (i >= 0) entries.insert(i + 1, const _UnreadMarker());
  }

  /// بوضع التحديد: الضغط يحدد/يلغي بدل ما يفتح الرسالة
  Widget _selectable(Msg m, Widget child) {
    if (_selected.isEmpty) return child;
    final on = _selected.contains(m.id);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSel(m.id),
      child: AbsorbPointer(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsetsDirectional.only(start: 4),
          decoration: BoxDecoration(
            color: on ? _t.accent.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            Icon(
                on
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: on ? _t.accent : const Color(0x88FFFFFF)),
            const SizedBox(width: 6),
            Expanded(child: child),
          ]),
        ),
      ),
    );
  }

  void _toggleSel(int id) => setState(() {
        final s = {..._selected};
        if (!s.remove(id)) s.add(id);
        _selected = s;
      });

  Widget _selectionBar() {
    final sel = _lastMsgs.where((m) => _selected.contains(m.id)).toList();
    final allMine = sel.isNotEmpty && sel.every((m) => m.mine);
    final hasText = sel.any((m) => m.kind == 'text');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Glass(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: _Sp.xs, vertical: 2),
        child: Row(children: [
          IconButton(
              tooltip: 'إلغاء التحديد',
              onPressed: () => setState(() => _selected = {}),
              icon: const Icon(Icons.close_rounded)),
          Expanded(
            child: Text('${_selected.length} محددة',
                style:
                    const TextStyle(fontSize: _Fs.titleL, fontWeight: FontWeight.w600)),
          ),
          if (hasText)
            IconButton(
                tooltip: 'نسخ',
                onPressed: () => _copySelected(sel),
                icon: const Icon(Icons.copy_rounded)),
          IconButton(
              tooltip: 'للمفضلة',
              onPressed: () => _starSelected(sel),
              icon: const Icon(Icons.star_border_rounded)),
          IconButton(
              tooltip: 'حذف',
              onPressed: () => _deleteMsgs(sel, allMine),
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFFF6B60))),
        ]),
      ),
    );
  }

  Future<void> _copySelected(List<Msg> sel) async {
    final texts = sel.where((m) => m.kind == 'text').toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    await Clipboard.setData(
        ClipboardData(text: texts.map((m) => m.text).join('\n')));
    if (!mounted) return;
    setState(() => _selected = {});
    _toast(context, texts.length == 1 ? 'تم النسخ' : 'تم نسخ ${texts.length} رسائل');
  }

  Future<void> _starSelected(List<Msg> sel) async {
    setState(() => _selected = {});
    for (final m in sel) {
      if (!_stars.contains(m.id) && m.kind != 'call') await _toggleStar(m);
    }
  }

  /// حذف رسالة أو أكثر: عندي بس، أو عند الطرفين (إذا كلها رسائلي)
  Future<void> _deleteMsgs(List<Msg> sel, bool canBoth) async {
    if (sel.isEmpty) return;
    final n = sel.length;
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n == 1 ? 'حذف الرسالة؟' : 'حذف $n رسائل؟'),
        content: Text(canBoth
            ? 'تقدر تحذفها عندك بس، أو عند الطرفين.'
            : 'تنحذف عندك بس، والطرف الثاني تبقى عنده.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'me'),
              child: const Text('حذف عندي')),
          if (canBoth)
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'both'),
                child: const Text('عند الطرفين',
                    style: TextStyle(color: Color(0xFFFF6B60)))),
        ],
      ),
    );
    if (act == null || !mounted) return;
    setState(() => _selected = {});
    if (act == 'me') {
      _undoableDelete(sel, () => _hideForMe(sel.map((m) => m.id)));
    } else {
      _undoableDelete(sel, () async {
        for (final m in sel) {
          await _delete(m);
        }
      });
    }
  }

  /// سطر الوقت بأعلى قائمة الرسالة: متى انرسلت ومتى انقرأت
  String _timesOf(Msg m) {
    final at = m.at;
    if (at == null) return '';
    final sent = '${m.mine ? 'انرسلت' : 'وصلت'} ${_dayLabel(at)} ${_clockOf(at)}';
    if (!m.mine) return sent;
    final r = m.readAt;
    if (r == null) return '$sent · ما انقرأت بعد';
    return '$sent · انقرأت ${_sameDay(r, at) ? '' : '${_dayLabel(r)} '}${_clockOf(r)}';
  }

  /// صورة أو GIF من الكيبورد (مثل حافظة Gboard)
  Future<void> _onKeyboardImage(KeyboardInsertedContent c) async {
    final data = c.data;
    if (data == null || data.isEmpty || _uploading) return;
    if (_blockedByTrust()) return;
    if (data.length > 15 * 1024 * 1024) {
      _toast(context, 'الصورة كبيرة، الحد 15 ميجا.');
      return;
    }
    final ext = c.mimeType.split('/').last.replaceAll('jpeg', 'jpg');
    setState(() => _uploading = true);
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/paste_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await f.writeAsBytes(data);
      await _sendMedia(
          chatId: widget.chat.id,
          file: f,
          kind: 'image',
          ext: ext,
          mime: c.mimeType);
    } on PostgrestException catch (e) {
      if (mounted) {
        _toast(
            context,
            e.message.contains('media_locked')
                ? 'الصور تنفتح لما الطرفين يضغطون «أثق فيه».'
                : 'تعذر إرسال الصورة.');
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال الصورة.');
    }
    if (mounted) setState(() => _uploading = false);
  }
}

/// يحفظ صورة وصلت بالمعرض (بصمت، بدون رسائل خطأ)
Future<void> _autoSaveImage(String path) async {
  try {
    final f = await _MediaFiles.get(path);
    if (f == null) return;
    final dir = await getTemporaryDirectory();
    final c = await f.copy(
        '${dir.path}/auto_${DateTime.now().microsecondsSinceEpoch}.${_extFor(path)}');
    await Gal.putImage(c.path, album: appName);
  } catch (_) {}
}
