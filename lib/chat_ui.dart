part of 'main.dart';

// واجهة المحادثة: الهيدر والرسائل وشريط الإدخال
extension _ChatUi on _ChatState {
  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Glass(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(
              child: InkWell(
                onTap: _partnerInfo,
                child: Row(children: [
                  _Avatar(path: _pAvatar, radius: 20, gender: _pGender),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_title(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        if (_status().isNotEmpty)
                          Text(_status(),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _online
                                      ? const Color(0xFF5BE584)
                                      : _t.text.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
            IconButton(
                onPressed: () => _call(false), icon: const Icon(Icons.call)),
            IconButton(
                onPressed: () => _call(true), icon: const Icon(Icons.videocam)),
            IconButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ThemeSettingsScreen(chatId: widget.chat.id))),
                icon: const Icon(Icons.palette_outlined)),
            IconButton(
                onPressed: _openProfile,
                icon: const Icon(Icons.settings_outlined)),
          ]),
        ),
      );

  Widget _messages() => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('تعذر تحميل الرسائل. تأكد من الإنترنت.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xAAFFFFFF))),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          _hasMore = rows.length >= _limit;
          _checkUnread(rows);
          final msgs = rows
              .map((r) => Msg.fromRow(r, _uid))
              .where((m) => !_hidden.contains(m.id))
              .toList();
          if (msgs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('ما في رسائل بعد. ابدأ المحادثة!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xAAFFFFFF))),
              ),
            );
          }
          return ListView.builder(
            controller: _scroll,
            reverse: true,
            padding: const EdgeInsets.all(16),
            itemCount: msgs.length,
            itemBuilder: (_, i) => _Bubble(
              key: ValueKey(msgs[i].id),
              m: msgs[i],
              onLongPress: () => _msgMenu(msgs[i]),
              t: _t,
            ),
          );
        },
      );

  Widget _inputBar(bool typing) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Glass(
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: _recording ? _recordingRow() : _typingRow(typing),
        ),
      );

  Widget _recordingRow() => Row(children: [
        IconButton(
          onPressed: () => unawaited(_finishRec(false)),
          icon: const Icon(Icons.delete_outline, color: Color(0xFFFF6B60)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.fiber_manual_record, color: Color(0xFFFF3B30), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text('جاري التسجيل... ${_mmss(_recSecs * 1000)}',
              style: const TextStyle(fontSize: 15)),
        ),
        IconButton(
          onPressed: () => unawaited(_finishRec(true)),
          icon: const Icon(Icons.arrow_upward_rounded, color: _blue),
        ),
      ]);

  Widget _typingRow(bool typing) => Row(children: [
        IconButton(
          onPressed: _uploading ? null : _attach,
          icon: _uploading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_circle_outline),
        ),
        Expanded(
          child: TextField(
            controller: _c,
            style: TextStyle(color: _t.text),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _send(),
            inputFormatters: [LengthLimitingTextInputFormatter(4000)],
            decoration: const InputDecoration(
                hintText: 'اكتب رسالة', border: InputBorder.none),
          ),
        ),
        IconButton(
          onPressed: typing ? _send : _startRec,
          icon: Icon(typing ? Icons.arrow_upward_rounded : Icons.mic,
              color: typing ? _t.accent : null),
        ),
      ]);
}

// ---------- مظهر المحادثة: الثيم والخلفية ----------

extension _ChatLook on _ChatState {
  void _watchLook() {
    _lookSub = _db
        .from('chats')
        .stream(primaryKey: ['id'])
        .eq('id', widget.chat.id)
        .listen((rows) {
      if (rows.isNotEmpty) _applyLook(rows.first);
    });
  }

  void _applyLook(Map<String, dynamic> r) {
    if (!mounted) return;
    final path = r['bg_path'] as String?;
    final pathChanged = path != _bgPath;
    setState(() {
      _t = chatThemeById((r['theme_id'] as num?)?.toInt() ?? 1);
      _bgKind = (r['bg_kind'] as String?) ?? 'gradient';
      _bgStrength = (r['bg_strength'] as num?)?.toInt() ?? 10;
      _bgPath = path;
      if (pathChanged) _bgUrl = null;
    });
    if (pathChanged && path != null) unawaited(_loadBgUrl(path));
  }

  Future<void> _loadBgUrl(String path) async {
    final url = await MediaUrls.get('chat-bg', path);
    if (!mounted || _bgPath != path) return;
    setState(() => _bgUrl = url);
  }

  Widget _chatBackground() {
    final t = _t;
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.top, t.bottom],
        ),
      ),
    );
    final url = _bgUrl;
    if (_bgKind == 'gradient' || url == null) return gradient;
    final img = Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => gradient,
    );
    if (_bgKind == 'plain') return img;
    final s = _bgStrength.toDouble();
    final blurred = ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s),
      child: img,
    );
    if (_bgKind == 'blur') return blurred;
    // زجاجية: ضبابية + طبقة شفافة بلون الثيم
    return Stack(fit: StackFit.expand, children: [
      blurred,
      ColoredBox(color: t.top.withValues(alpha: 0.45)),
    ]);
  }
}
