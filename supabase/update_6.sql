-- بيناتنا تحديث 6: إشعارات أوضح للأنواع الجديدة، وإشعار «صار متصل» (اختياري)
-- شغّله بعد update_1 إلى update_5. آمن لو انعاد.
-- ملاحظة: ما نكتب سر الإشعارات هنا. ننسخه من دالة الإشعارات الموجودة عندك.

-- 1) ننسخ سر الإشعارات للجدول الخاص app_config
do $do$
declare s text;
begin
  select substring(p.prosrc from 'x-push-secret'', ''([0-9a-f]+)''') into s
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'notify_push'
  limit 1;
  if s is not null then
    delete from public.app_config where k = 'push_secret';
    insert into public.app_config (k, v) values ('push_secret', s);
  end if;
end $do$;

-- 2) دالة إشعار الرسائل: نفس السابقة + أسماء الأنواع الجديدة (تتبدل بس لو السر انحفظ)
do $do$
begin
  if not exists (select 1 from public.app_config where k = 'push_secret' and v is not null) then
    raise notice 'push_secret not found, notify_push kept as is';
    return;
  end if;
  execute $fn$
create or replace function public.notify_push() returns trigger
language plpgsql security definer set search_path = public as $body$
declare rcpt uuid; toks jsonb; t text; b text; jwt text; sec text;
begin
  if new.kind = 'call' then return new; end if;
  select case when c.user_a = new.sender_id then c.user_b else c.user_a end into rcpt
  from chats c where c.id = new.chat_id;
  if rcpt is null then return new; end if;
  select coalesce(jsonb_agg(token), '[]'::jsonb) into toks from push_tokens
  where user_id = rcpt and not coalesce((select mute_messages from profiles where id = rcpt), false);
  if jsonb_array_length(toks) = 0 then return new; end if;
  select coalesce(nullif(display_name, ''), '@' || username) into t from profiles where id = new.sender_id;
  select v into jwt from app_config where k = 'anon_jwt';
  select v into sec from app_config where k = 'push_secret';
  b := case new.kind
    when 'image' then '📷 صورة'
    when 'video' then '🎬 فيديو'
    when 'audio' then '🎤 رسالة صوتية'
    when 'think' then '❤️ أفكر فيك'
    when 'card' then '💌 بطاقة'
    when 'vnote' then '⭕ فيديو دائري'
    when 'file' then '📎 ملف'
    else 'رسالة جديدة' end;
  perform net.http_post(
    url := 'https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(jwt, ''), 'x-push-secret', coalesce(sec, '')),
    body := jsonb_build_object('tokens', toks, 'title', coalesce(t, 'بيناتنا'), 'body', b, 'chat', new.chat_id));
  return new;
exception when others then return new;
end; $body$;
$fn$;
end $do$;
revoke execute on function public.notify_push() from public, anon, authenticated;

-- 3) «صار متصل»: الطرف الثاني يختار يوصله إشعار لما تفتح التطبيق (مرة كل 3 ساعات بالكثير)
alter table public.profiles add column if not exists notify_online boolean not null default false;
grant update (notify_online) on public.profiles to authenticated;

create table if not exists public.online_pings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  at timestamptz not null default now()
);
alter table public.online_pings enable row level security;
revoke all on public.online_pings from anon, authenticated;

create or replace function public.ping_online() returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rcpt uuid; cid uuid; toks jsonb; t text; jwt text; sec text; last timestamptz;
begin
  if uid is null then return; end if;
  select c.id, case when c.user_a = uid then c.user_b else c.user_a end into cid, rcpt
  from chats c where uid in (c.user_a, c.user_b) limit 1;
  if rcpt is null then return; end if;
  if not coalesce((select notify_online and not mute_messages from profiles where id = rcpt), false) then return; end if;
  select at into last from online_pings where user_id = uid;
  if last is not null and last > now() - interval '3 hours' then return; end if;
  insert into online_pings (user_id, at) values (uid, now())
  on conflict (user_id) do update set at = now();
  select coalesce(jsonb_agg(token), '[]'::jsonb) into toks from push_tokens where user_id = rcpt;
  if jsonb_array_length(toks) = 0 then return; end if;
  select coalesce(nullif(display_name, ''), '@' || username) into t from profiles where id = uid;
  select v into jwt from app_config where k = 'anon_jwt';
  select v into sec from app_config where k = 'push_secret';
  if sec is null then return; end if;
  perform net.http_post(
    url := 'https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(jwt, ''), 'x-push-secret', sec),
    body := jsonb_build_object('tokens', toks, 'title', coalesce(t, 'بيناتنا'),
      'body', 'صار متصل الحين 🟢', 'chat', cid, 'type', 'online', 'ttl', 300));
exception when others then return;
end; $$;
revoke execute on function public.ping_online() from public, anon;
grant execute on function public.ping_online() to authenticated;

-- فحص: لازم يطلع true
select exists (select 1 from public.app_config where k = 'push_secret') as push_secret_ok;
