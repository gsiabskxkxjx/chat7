part of 'main.dart';

// عمليات المحادثة: إرسال، مكالمات، صور، تسجيل، إبلاغ، حظر
extension _ChatActions on _ChatState {
  void _partnerInfo() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _Avatar(path: _pAvatar, radius: 48, gender: _pGender),
            const SizedBox(height: 12),
            Text(_title(),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('@${widget.chat.partner}',
                textDirection: TextDirection.ltr,
                style: const TextStyle(color: Color(0xAAFFFFFF))),
            const SizedBox(height: 8),
            Text(_status(),
                style: TextStyle(
                    color: _online
                        ? const Color(0xFF5BE584)
                        : const Color(0xAAFFFFFF))),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _reportPartner();
                },
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('إبلاغ'),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _blockPartner();
                },
                icon: const Icon(Icons.block,
                    size: 18, color: Color(0xFFFF6B60)),
                label: const Text('حظر',
                    style: TextStyle(color: Color(0xFFFF6B60))),
              ),
            ]),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => MemoriesScreen(chatId: widget.chat.id)));
              },
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('معرض الذكريات'),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _reportPartner() async {
    const reasons = [
      'محتوى مسيء',
      'مضايقة أو تهديد',
      'انتحال شخصية',
      'احتيال أو إزعاج',
      'سبب آخر',
    ];
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('سبب الإبلاغ'),
        children: [
          for (final x in reasons)
            SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, x), child: Text(x)),
        ],
      ),
    );
    if (r == null || !mounted) return;
    try {
      await _db.rpc('report_partner',
          params: {'p_reason': r, 'p_details': null});
      if (mounted) _toast(context, 'وصل بلاغك، شكراً.');
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال البلاغ.');
    }
  }

  Future<void> _blockPartner() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حظر @${widget.chat.partner}؟'),
        content: const Text(
            'راح تنحذف المحادثة عند الطرفين، وما يقدر يرتبط معك مرة ثانية.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حظر',
                  style: TextStyle(color: Color(0xFFFF6B60)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      try {
        final files =
            await _db.storage.from('chat-media').list(path: widget.chat.id);
        if (files.isNotEmpty) {
          await _db.storage.from('chat-media').remove(
              files.map((f) => '${widget.chat.id}/${f.name}').toList());
        }
      } catch (_) {}
      await _wipeChatBg(widget.chat.id);
      await _db.rpc('block_partner');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => PairScreen(me: widget.chat.me)),
        (_) => false,
      );
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الحظر، جرّب مرة ثانية.');
    }
  }

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(chat: widget.chat)));
    // رجعنا من الإعدادات: نحدّث جنسي إذا تغيّر
    if (mounted) unawaited(_reloadMyGender());
  }

  Future<void> _markRead() async {
    if (_markBusy || !_pulse.foreground || !mounted) return;
    _markBusy = true;
    try {
      await _db.rpc('mark_read', params: {'p_chat': widget.chat.id});
    } catch (_) {}
    _markBusy = false;
  }

  void _checkUnread(List<Map<String, dynamic>> rows) {
    var newest = -1;
    for (final r in rows) {
      if (r['sender_id'] != _uid && r['read_at'] == null) {
        final id = (r['id'] as num).toInt();
        if (id > newest) newest = id;
      }
    }
    if (newest > _markedUpTo) {
      _markedUpTo = newest;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => unawaited(_markRead()));
    }
  }

  void _incoming(CallSession s) {
    if (!mounted) {
      unawaited(s.end('مكالمة فائتة.', send: 'decline'));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            IncomingCallScreen(session: s, partner: widget.chat.partner)));
  }

  Future<void> _call(bool video) async {
    if (_hub.current != null) return;
    if (!_hub.ready) {
      _toast(context, 'الاتصال بالسيرفر غير جاهز، جرّب بعد ثواني.');
      return;
    }
    final s = CallSession.outgoing(_hub, video);
    s.hint =
        _online ? null : 'الطرف الثاني غير متصل الآن، أرسلنا له إشعار مكالمة.';
    _hub.current = s;
    try {
      await s.startOutgoing();
    } catch (_) {
      await s.end(
          'تعذر بدء المكالمة. اسمح للتطبيق بالمايك والكاميرا من إعدادات الجوال.');
      if (mounted) _toast(context, s.endReason ?? 'تعذر بدء المكالمة.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CallScreen(session: s, partner: widget.chat.partner)));
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    final reply = _replyTo;
    _c.clear();
    setState(() => _replyTo = null);
    try {
      await _db.from('messages').insert({
        'chat_id': widget.chat.id,
        'body': t,
        if (reply != null) 'reply_to_id': reply.id,
      });
    } catch (_) {
      if (!mounted) return;
      _c.text = t;
      setState(() => _replyTo = reply);
      _toast(context, 'تعذر الإرسال، حاول مرة ثانية.');
    }
  }

  Future<String?> _attachSheet() => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('صورة من المعرض'),
              onTap: () => Navigator.pop(ctx, 'photo_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('تصوير صورة'),
              onTap: () => Navigator.pop(ctx, 'photo_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('فيديو من المعرض'),
              onTap: () => Navigator.pop(ctx, 'video_gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('تسجيل فيديو'),
              onTap: () => Navigator.pop(ctx, 'video_camera'),
            ),
          ]),
        ),
      );

  Future<void> _attach() async {
    final act = await _attachSheet();
    if (!mounted || act == null) return;
    setState(() => _uploading = true);
    try {
      final camera = act.endsWith('camera');
      final src = camera ? ImageSource.camera : ImageSource.gallery;
      if (act.startsWith('photo')) {
        final x = await _picker.pickImage(
            source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
        if (x != null) {
          await _sendMedia(
              chatId: widget.chat.id,
              file: File(x.path),
              kind: 'image',
              ext: _extFor(x.path),
              mime: _mimeFor(x.path));
        }
      } else {
        final x = await _picker.pickVideo(
            source: src, maxDuration: const Duration(minutes: 2));
        if (x != null) {
          final file = File(x.path);
          if (await file.length() > 50 * 1024 * 1024) {
            if (mounted) _toast(context, 'الفيديو كبير، الحد الأقصى 50 ميجا.');
          } else {
            await _sendMedia(
                chatId: widget.chat.id,
                file: file,
                kind: 'video',
                ext: _extOf(x.path),
                mime: _mimeForVideo(x.path));
          }
        }
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر الإرسال. جرّب مرة ثانية.');
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _startRec() async {
    if (_recording || _uploading) return;
    try {
      final ok = await _rec.start();
      if (!ok) {
        if (mounted) _toast(context, 'اسمح للتطبيق بالمايك من إعدادات الجوال.');
        return;
      }
    } catch (_) {
      if (mounted) _toast(context, 'تعذر بدء التسجيل.');
      return;
    }
    if (!mounted) {
      await _rec.cancel();
      return;
    }
    _recSecs = 0;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recSecs++);
      if (_recSecs >= 300) unawaited(_finishRec(true));
    });
    setState(() => _recording = true);
  }

  Future<void> _finishRec(bool send) async {
    if (!_recording) return;
    _recTimer?.cancel();
    if (mounted) setState(() => _recording = false);
    if (!send) {
      await _rec.cancel();
      return;
    }
    final clip = await _rec.stop();
    if (clip == null || clip.ms < 800) {
      if (mounted) _toast(context, 'التسجيل قصير جداً.');
      return;
    }
    if (mounted) setState(() => _uploading = true);
    try {
      await _sendMedia(
          chatId: widget.chat.id,
          file: clip.file,
          kind: 'audio',
          ext: 'm4a',
          mime: 'audio/mp4',
          durationMs: clip.ms);
    } catch (_) {
      if (mounted) _toast(context, 'تعذر إرسال الرسالة الصوتية.');
    }
    try {
      await clip.file.delete();
    } catch (_) {}
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _msgMenu(Msg m) async {
    if (m.kind == 'call') return;
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              for (final e in _reactEmojis)
                InkWell(
                  onTap: () => Navigator.pop(ctx, 'react:$e'),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(e, style: const TextStyle(fontSize: 26)),
                  ),
                ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('رد'),
            onTap: () => Navigator.pop(ctx, 'reply'),
          ),
          if (m.kind == 'text')
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('نسخ'),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          if (m.mine)
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFFF6B60)),
              title: const Text('حذف عند الطرفين'),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
        ]),
      ),
    );
    if (!mounted || act == null) return;
    if (act.startsWith('react:')) {
      await _react(m.id, act.substring(6));
    } else if (act == 'reply') {
      setState(() => _replyTo = m);
    } else if (act == 'copy') {
      await Clipboard.setData(ClipboardData(text: m.text));
      if (mounted) _toast(context, 'تم النسخ');
    } else if (act == 'del') {
      await _delete(m);
    }
  }

  Future<void> _delete(Msg m) async {
    setState(() => _hidden.add(m.id));
    try {
      final path = m.mediaPath;
      if (path != null) {
        try {
          await _db.storage.from('chat-media').remove([path]);
        } catch (_) {}
      }
      await _db.from('messages').delete().eq('id', m.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hidden.remove(m.id));
      _toast(context, 'تعذر الحذف.');
    }
  }
}
