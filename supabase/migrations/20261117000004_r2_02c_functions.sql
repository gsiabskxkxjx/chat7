-- الجولة الثانية / 2ج: دوال (RPC) وصيانة

-- إرسال إشعار لكل أجهزة مستخدم (داخلي فقط)
create or replace function public.push_user(p_user uuid, p_title text, p_body text,
  p_type text default 'message', p_chat uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare toks jsonb; jwt text; sec text;
begin
  select coalesce(jsonb_agg(token), '[]'::jsonb) into toks from public.push_tokens where user_id = p_user;
  if jsonb_array_length(toks) = 0 then return; end if;
  select v into jwt from public.app_config where k = 'anon_jwt';
  select v into sec from public.app_config where k = 'push_secret';
  perform net.http_post(
    url := 'https://tbmrikxmlnpbcqycjvco.supabase.co/functions/v1/push',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(jwt, ''), 'x-push-secret', coalesce(sec, '')),
    body := jsonb_build_object('tokens', toks, 'title', p_title, 'body', p_body,
      'chat', coalesce(p_chat::text, ''), 'type', p_type));
exception when others then null;
end $$;
revoke execute on function public.push_user(uuid, text, text, text, uuid) from public, anon, authenticated;

-- (294/210) تسجيل أعطال وأداء
create or replace function public.log_error(p_context text, p_message text, p_stack text,
  p_version text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
declare h text; n int;
begin
  if auth.uid() is null then return; end if;
  h := md5(auth.uid()::text);
  select count(*) into n from public.error_logs where uid_hash = h and created_at > now() - interval '1 hour';
  if n >= 30 then return; end if;
  insert into public.error_logs (uid_hash, context, message, stack, app_version, platform)
  values (h, left(p_context, 60), left(p_message, 600), left(p_stack, 3000), left(p_version, 20), left(p_platform, 20));
end $$;
revoke execute on function public.log_error(text, text, text, text, text) from public, anon;
grant execute on function public.log_error(text, text, text, text, text) to authenticated;

create or replace function public.log_perf(p_name text, p_ms integer, p_version text, p_platform text) returns void
language plpgsql security definer set search_path = public as $$
declare h text; n int;
begin
  if auth.uid() is null or p_ms is null then return; end if;
  h := md5(auth.uid()::text);
  select count(*) into n from public.perf_events where uid_hash = h and created_at > now() - interval '1 hour';
  if n >= 40 then return; end if;
  insert into public.perf_events (uid_hash, name, ms, app_version, platform)
  values (h, left(p_name, 40), greatest(0, least(p_ms, 600000)), left(p_version, 20), left(p_platform, 20));
end $$;
revoke execute on function public.log_perf(text, integer, text, text) from public, anon;
grant execute on function public.log_perf(text, integer, text, text) to authenticated;

-- (282/283) الأجهزة
create or replace function public.register_device(p_device_id text, p_name text, p_platform text, p_version text)
returns boolean language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); sid uuid; was_new boolean; others int;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  begin sid := nullif(auth.jwt() ->> 'session_id', '')::uuid; exception when others then sid := null; end;
  insert into public.devices (user_id, device_id, name, platform, app_version, session_id)
  values (uid, p_device_id, left(p_name, 60), left(p_platform, 20), left(p_version, 20), sid)
  on conflict (user_id, device_id) do update
    set name = excluded.name, platform = excluded.platform, app_version = excluded.app_version,
        session_id = excluded.session_id, last_seen = now()
  returning (xmax = 0) into was_new;
  if was_new then
    select count(*) into others from public.devices where user_id = uid and device_id <> p_device_id;
    if others > 0 then
      perform public.push_user(uid, 'بيناتنا', '🔐 دخول من جهاز جديد: ' || coalesce(nullif(left(p_name, 40), ''), 'جهاز'), 'device', null);
    end if;
  end if;
  return coalesce(was_new, false);
end $$;
revoke execute on function public.register_device(text, text, text, text) from public, anon;
grant execute on function public.register_device(text, text, text, text) to authenticated;

create or replace function public.list_devices()
returns table (device_id text, name text, platform text, app_version text, last_seen timestamptz,
  created_at timestamptz, is_current boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  begin sid := nullif(auth.jwt() ->> 'session_id', '')::uuid; exception when others then sid := null; end;
  return query
    select d.device_id, d.name, d.platform, d.app_version, d.last_seen, d.created_at,
           (sid is not null and d.session_id = sid)
      from public.devices d where d.user_id = auth.uid() order by d.last_seen desc;
end $$;
revoke execute on function public.list_devices() from public, anon;
grant execute on function public.list_devices() to authenticated;

create or replace function public.sign_out_other_devices(p_keep_device text default null) returns integer
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); sid uuid; n int;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  begin sid := nullif(auth.jwt() ->> 'session_id', '')::uuid; exception when others then sid := null; end;
  if sid is null then raise exception 'no_session'; end if;
  delete from auth.sessions where user_id = uid and id <> sid;
  get diagnostics n = row_count;
  delete from public.devices where user_id = uid and (p_keep_device is null or device_id <> p_keep_device);
  return n;
end $$;
revoke execute on function public.sign_out_other_devices(text) from public, anon;
grant execute on function public.sign_out_other_devices(text) to authenticated;

create or replace function public.remove_device(p_device_id text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); sid uuid; cur uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  begin cur := nullif(auth.jwt() ->> 'session_id', '')::uuid; exception when others then cur := null; end;
  select session_id into sid from public.devices where user_id = uid and device_id = p_device_id;
  if sid is not null and sid is distinct from cur then
    delete from auth.sessions where id = sid and user_id = uid;
  end if;
  delete from public.devices where user_id = uid and device_id = p_device_id;
end $$;
revoke execute on function public.remove_device(text) from public, anon;
grant execute on function public.remove_device(text) to authenticated;

-- (284) كود الاستعادة يبطل بعد الاستخدام
create or replace function public.reset_password_with_code(p_username text, p_code text, p_new text)
returns boolean language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare uid uuid; h text; n int;
begin
  if char_length(coalesce(p_new, '')) < 6 then return false; end if;
  select id into uid from profiles where username = lower(trim(p_username));
  if uid is null then return false; end if;
  delete from recovery_attempts where at < now() - interval '1 day';
  select count(*) into n from recovery_attempts where user_id = uid and at > now() - interval '1 hour';
  if n >= 5 then return false; end if;
  select code_hash into h from recovery_codes where user_id = uid;
  if h is null or h <> crypt(upper(trim(p_code)), h) then
    insert into recovery_attempts (user_id) values (uid);
    return false;
  end if;
  update auth.users set encrypted_password = crypt(p_new, gen_salt('bf', 10)), updated_at = now() where id = uid;
  delete from auth.sessions where user_id = uid;
  delete from public.devices where user_id = uid;
  delete from recovery_attempts where user_id = uid;
  delete from recovery_codes where user_id = uid;
  return true;
end $$;

create or replace function public.has_recovery_code() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.recovery_codes where user_id = auth.uid());
$$;
revoke execute on function public.has_recovery_code() from public, anon;
grant execute on function public.has_recovery_code() to authenticated;

-- (259) بياناتي
create or replace function public.export_my_data() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  return jsonb_build_object(
    'exported_at', now(),
    'profile', (select to_jsonb(p) - 'id' from public.profiles p where p.id = uid),
    'chats', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'created_at', c.created_at,
        'started_on', c.started_on, 'partner', (select pr.username from public.profiles pr
          where pr.id = case when c.user_a = uid then c.user_b else c.user_a end))), '[]'::jsonb)
      from public.chats c where uid in (c.user_a, c.user_b)),
    'messages_sent', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'chat_id', m.chat_id,
        'kind', m.kind, 'body', m.body, 'created_at', m.created_at) order by m.id), '[]'::jsonb)
      from (select * from public.messages where sender_id = uid order by id desc limit 50000) m),
    'love_notes', (select coalesce(jsonb_agg(to_jsonb(x) - 'author'), '[]'::jsonb) from public.love_notes x where x.author = uid),
    'diary', (select coalesce(jsonb_agg(to_jsonb(x) - 'author'), '[]'::jsonb) from public.diary_entries x where x.author = uid),
    'budget_paid', (select coalesce(jsonb_agg(to_jsonb(x) - 'paid_by'), '[]'::jsonb) from public.budget_items x where x.paid_by = uid),
    'events', (select coalesce(jsonb_agg(to_jsonb(x) - 'created_by'), '[]'::jsonb) from public.chat_events x where x.created_by = uid),
    'plans', (select coalesce(jsonb_agg(to_jsonb(x) - 'created_by'), '[]'::jsonb) from public.plans x where x.created_by = uid),
    'reactions', (select count(*) from public.reactions where user_id = uid),
    'stars', (select count(*) from public.message_stars where user_id = uid),
    'devices', (select coalesce(jsonb_agg(jsonb_build_object('name', d.name, 'platform', d.platform,
        'created_at', d.created_at, 'last_seen', d.last_seen)), '[]'::jsonb) from public.devices d where d.user_id = uid),
    'push_tokens', (select count(*) from public.push_tokens where user_id = uid),
    'capsules_written', (select count(*) from public.time_capsules where author = uid)
  );
end $$;
revoke execute on function public.export_my_data() from public, anon;
grant execute on function public.export_my_data() to authenticated;

-- (311/317) الكبسولة الزمنية
create or replace function public.capsules_list(p_chat uuid)
returns table (id bigint, author uuid, to_user uuid, unlock_at timestamptz, created_at timestamptz,
  opened_at timestamptz, locked boolean, body text, media_path text)
language sql stable security definer set search_path = public as $$
  select t.id, t.author, t.to_user, t.unlock_at, t.created_at, t.opened_at,
         (t.unlock_at > now()),
         case when t.unlock_at <= now() or (t.author = auth.uid() and t.to_user <> t.author) then t.body end,
         case when t.unlock_at <= now() or (t.author = auth.uid() and t.to_user <> t.author) then t.media_path end
    from public.time_capsules t
   where t.chat_id = p_chat and public.is_member(p_chat)
     and (t.author = auth.uid() or t.to_user = auth.uid())
   order by t.unlock_at desc;
$$;
revoke execute on function public.capsules_list(uuid) from public, anon;
grant execute on function public.capsules_list(uuid) to authenticated;

create or replace function public.capsule_open(p_id bigint) returns void
language sql security definer set search_path = public as $$
  update public.time_capsules set opened_at = coalesce(opened_at, now())
   where id = p_id and to_user = auth.uid() and unlock_at <= now();
$$;
revoke execute on function public.capsule_open(bigint) from public, anon;
grant execute on function public.capsule_open(bigint) to authenticated;

-- (361-370) حصة الذكاء الاصطناعي
create or replace function public.ai_quota_take(p_limit integer default 40) returns boolean
language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  if auth.uid() is null then return false; end if;
  insert into public.ai_usage (user_id, day, n) values (auth.uid(), current_date, 1)
  on conflict (user_id, day) do update set n = public.ai_usage.n + 1 where public.ai_usage.n < p_limit
  returning n into v;
  return v is not null;
end $$;
revoke execute on function public.ai_quota_take(integer) from public, anon;
grant execute on function public.ai_quota_take(integer) to authenticated;

-- (346) التاريخ القادم لموعد متكرر
create or replace function public.event_next(p_on date, p_rep text, p_from date) returns date
language plpgsql immutable set search_path = public as $$
declare d date := p_on; i int := 0;
begin
  if p_rep = 'none' or d >= p_from then return d; end if;
  loop
    i := i + 1;
    d := case p_rep
      when 'weekly' then p_on + 7 * i
      when 'monthly' then (p_on + make_interval(months => i))::date
      when 'yearly' then (p_on + make_interval(years => i))::date
      else p_on end;
    exit when d >= p_from or i > 5000;
  end loop;
  return d;
end $$;
revoke execute on function public.event_next(date, text, date) from public, anon;
grant execute on function public.event_next(date, text, date) to authenticated;

-- (302/311) المرسل الدوري: رسائل مجدولة + إعلان الكبسولات
create or replace function public.dispatch_scheduled() returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select * from public.scheduled_messages
            where sent_at is null and send_at <= now() order by send_at limit 200 for update skip locked loop
    begin
      insert into public.messages (chat_id, sender_id, kind, body) values (r.chat_id, r.sender_id, 'text', r.body);
      update public.scheduled_messages set sent_at = now() where id = r.id;
      n := n + 1;
    exception when others then
      update public.scheduled_messages set sent_at = now(), failed = true where id = r.id;
    end;
  end loop;
  for r in select * from public.time_capsules
            where announced_at is null and unlock_at <= now() order by unlock_at limit 200 for update skip locked loop
    perform public.push_user(r.to_user, 'بيناتنا', '⏳ انفتحت كبسولة زمنية! افتحها من «معاً»', 'capsule', r.chat_id);
    update public.time_capsules set announced_at = now() where id = r.id;
  end loop;
  return n;
end $$;
revoke execute on function public.dispatch_scheduled() from public, anon, authenticated;

-- (347) تذكير قبل الموعد
create or replace function public.dispatch_reminders() returns integer
language plpgsql security definer set search_path = public as $$
declare r record; nx date; rem timestamptz; n int := 0;
begin
  for r in select e.id, e.chat_id, e.title, e.on_date, e.repeat_every, e.remind_before_h, e.last_reminded_for,
                  c.user_a, c.user_b
             from public.chat_events e join public.chats c on c.id = e.chat_id
            where e.remind_before_h > 0 loop
    nx := public.event_next(r.on_date, r.repeat_every, (now() at time zone 'Asia/Baghdad')::date);
    rem := ((nx + time '09:00') at time zone 'Asia/Baghdad') - make_interval(hours => r.remind_before_h);
    if now() >= rem and now() < ((nx + 1) + time '00:00') at time zone 'Asia/Baghdad'
       and r.last_reminded_for is distinct from nx then
      perform public.push_user(r.user_a, '📅 تذكير بموعد', r.title, 'reminder', r.chat_id);
      perform public.push_user(r.user_b, '📅 تذكير بموعد', r.title, 'reminder', r.chat_id);
      update public.chat_events set last_reminded_for = nx where id = r.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke execute on function public.dispatch_reminders() from public, anon, authenticated;

-- (303) حذف الرسائل المنتهية + تنظيف
create or replace function public.purge_expired() returns integer
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  delete from public.messages m using public.chats c
   where c.id = m.chat_id and c.expire_after_s is not null
     and m.created_at < now() - make_interval(secs => c.expire_after_s);
  get diagnostics n = row_count;
  delete from public.error_logs where created_at < now() - interval '30 days';
  delete from public.perf_events where created_at < now() - interval '30 days';
  delete from public.live_locations where expires_at < now() - interval '1 hour';
  delete from public.scheduled_messages where sent_at < now() - interval '7 days';
  delete from public.ai_usage where day < current_date - 7;
  return n;
end $$;
revoke execute on function public.purge_expired() from public, anon, authenticated;
