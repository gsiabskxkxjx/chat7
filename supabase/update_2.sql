-- بيناتنا تحديث 2: طلب ارتباط باسم المستخدم + الرسائل المفضلة + إحصائيات + عيد الميلاد
-- + عدّ تنازلي + تعديل الرسالة + حد للبلاغات. شغّله مرة وحدة كامل. آمن لو انعاد.

-- ========== 1) طلب ارتباط باسم المستخدم ==========
create table if not exists public.pair_requests (
  id bigint generated always as identity primary key,
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at timestamptz not null default now()
);
create unique index if not exists pair_requests_pending_uidx
  on public.pair_requests (from_id, to_id) where status = 'pending';
create index if not exists pair_requests_to_idx on public.pair_requests (to_id, status);
alter table public.pair_requests enable row level security;
revoke all on public.pair_requests from anon, authenticated;
grant select on public.pair_requests to authenticated;
drop policy if exists pair_requests_select_own on public.pair_requests;
create policy pair_requests_select_own on public.pair_requests
  for select to authenticated using (auth.uid() in (from_id, to_id));

do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pair_requests') then
    alter publication supabase_realtime add table public.pair_requests;
  end if;
end $$;

create or replace function public.pair_request(p_username text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  target uuid;
  n int;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists (select 1 from chats where uid in (user_a, user_b)) then raise exception 'already_paired'; end if;
  select id into target from profiles where lower(username) = lower(btrim(p_username, ' @'));
  if target is null then raise exception 'no_user'; end if;
  if target = uid then raise exception 'self'; end if;
  if exists (select 1 from chats where target in (user_a, user_b))
     or exists (select 1 from blocks where (blocker = uid and blocked = target) or (blocker = target and blocked = uid)) then
    raise exception 'unavailable';
  end if;
  select count(*) into n from pair_requests where from_id = uid and created_at > now() - interval '1 day';
  if n >= 10 then raise exception 'daily_limit'; end if;
  insert into pair_requests (from_id, to_id) values (uid, target) on conflict do nothing;
end; $$;

-- الطلبات الواصلة لي (مع اسم وصورة المرسل)
create or replace function public.pair_inbox()
returns table (id bigint, username text, display_name text, avatar_path text, gender text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, p.username, p.display_name, p.avatar_path, p.gender, r.created_at
  from pair_requests r join profiles p on p.id = r.from_id
  where r.to_id = auth.uid() and r.status = 'pending' and r.created_at > now() - interval '7 days'
  order by r.created_at desc
$$;

-- طلبي المرسل (إذا موجود)
create or replace function public.pair_outbox()
returns table (id bigint, username text, display_name text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select r.id, p.username, p.display_name, r.created_at
  from pair_requests r join profiles p on p.id = r.to_id
  where r.from_id = auth.uid() and r.status = 'pending' and r.created_at > now() - interval '7 days'
  order by r.created_at desc
$$;

create or replace function public.pair_respond(p_id bigint, p_ok boolean) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r pair_requests%rowtype;
  cid uuid;
begin
  select * into r from pair_requests where id = p_id and to_id = uid and status = 'pending' for update;
  if not found then raise exception 'no_request'; end if;
  if not p_ok then
    update pair_requests set status = 'declined' where id = r.id;
    return null;
  end if;
  if exists (select 1 from chats where user_a in (r.from_id, r.to_id) or user_b in (r.from_id, r.to_id)) then
    update pair_requests set status = 'cancelled' where id = r.id;
    raise exception 'unavailable';
  end if;
  insert into chats (user_a, user_b) values (r.from_id, r.to_id) returning id into cid;
  update pair_requests set status = 'accepted' where id = r.id;
  update pair_requests set status = 'cancelled'
    where status = 'pending' and id <> r.id
      and (from_id in (r.from_id, r.to_id) or to_id in (r.from_id, r.to_id));
  delete from invites where owner in (r.from_id, r.to_id);
  delete from match_queue where user_id in (r.from_id, r.to_id);
  return cid;
end; $$;

create or replace function public.pair_cancel(p_id bigint) returns void
language sql security definer set search_path = public as $$
  update pair_requests set status = 'cancelled'
  where id = p_id and from_id = auth.uid() and status = 'pending';
$$;

-- صورة المرسل تبين بالطلب
drop policy if exists avatars_select_request on storage.objects;
create policy avatars_select_request on storage.objects for select to authenticated using (
  bucket_id = 'avatars' and exists (
    select 1 from public.pair_requests r
    where r.status = 'pending' and auth.uid() in (r.from_id, r.to_id)
      and (storage.foldername(name))[1] in (r.from_id::text, r.to_id::text)));

-- ========== 2) الرسائل المفضلة (نجمة) ==========
create table if not exists public.message_stars (
  user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  message_id bigint not null references public.messages(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, message_id)
);
alter table public.message_stars enable row level security;
revoke all on public.message_stars from anon, authenticated;
grant select, insert, delete on public.message_stars to authenticated;
drop policy if exists message_stars_select_own on public.message_stars;
create policy message_stars_select_own on public.message_stars
  for select to authenticated using (user_id = auth.uid());
drop policy if exists message_stars_insert_own on public.message_stars;
create policy message_stars_insert_own on public.message_stars
  for insert to authenticated with check (
    user_id = auth.uid() and exists (
      select 1 from public.messages m join public.chats c on c.id = m.chat_id
      where m.id = message_id and auth.uid() in (c.user_a, c.user_b)));
drop policy if exists message_stars_delete_own on public.message_stars;
create policy message_stars_delete_own on public.message_stars
  for delete to authenticated using (user_id = auth.uid());

-- ========== 3) إحصائيات المحادثة ==========
create or replace function public.chat_stats(p_chat uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  res jsonb;
begin
  if not exists (select 1 from chats where id = p_chat and auth.uid() in (user_a, user_b)) then
    return null;
  end if;
  select jsonb_build_object(
    'total', count(*) filter (where kind not in ('call')),
    'mine', count(*) filter (where kind not in ('call') and sender_id = auth.uid()),
    'theirs', count(*) filter (where kind not in ('call') and sender_id <> auth.uid()),
    'photos', count(*) filter (where kind = 'image'),
    'videos', count(*) filter (where kind = 'video'),
    'voice', count(*) filter (where kind = 'audio'),
    'calls', count(*) filter (where kind = 'call'),
    'hearts', count(*) filter (where kind = 'think'),
    'days', count(distinct (created_at at time zone 'Asia/Baghdad')::date),
    'first_at', min(created_at))
  into res from messages where chat_id = p_chat;
  return res;
end; $$;

-- ========== 4) عيد ميلاد الطرف الثاني (بدون كشف التاريخ) ==========
create or replace function public.partner_birthday(p_chat uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  other uuid;
  b date;
  today date := (now() at time zone 'Asia/Baghdad')::date;
  next_b date;
begin
  select case when user_a = auth.uid() then user_b else user_a end into other
    from chats where id = p_chat and auth.uid() in (user_a, user_b);
  if other is null then return null; end if;
  select birth_date into b from profiles where id = other;
  if b is null then return jsonb_build_object('known', false); end if;
  next_b := make_date(extract(year from today)::int, extract(month from b)::int,
                      least(extract(day from b)::int, 28 + (extract(month from b)::int <> 2)::int * 3));
  if next_b < today then next_b := (next_b + interval '1 year')::date; end if;
  return jsonb_build_object('known', true, 'today', next_b = today, 'soon', next_b - today between 1 and 3,
                            'in_days', next_b - today);
end; $$;

-- ========== 5) عدّ تنازلي لموعد قادم ==========
alter table public.chats add column if not exists countdown_title text;
alter table public.chats add column if not exists countdown_at date;
alter table public.chats drop constraint if exists chats_countdown_title_len;
alter table public.chats add constraint chats_countdown_title_len
  check (countdown_title is null or char_length(countdown_title) between 1 and 40);

-- ========== 6) تعديل الرسالة خلال 15 دقيقة ==========
alter table public.messages add column if not exists edited_at timestamptz;
create or replace function public.edit_message(p_id bigint, p_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(btrim(p_body)) not between 1 and 4000 then raise exception 'bad_body'; end if;
  update messages set body = btrim(p_body), edited_at = now()
    where id = p_id and sender_id = auth.uid() and kind = 'text'
      and created_at > now() - interval '15 minutes';
  if not found then raise exception 'too_late'; end if;
end; $$;

-- ========== 7) حد للبلاغات: 5 باليوم ==========
create or replace function public.report_partner(p_reason text, p_details text) returns void
language plpgsql security definer set search_path = public as $$
declare
  other uuid;
  n int;
begin
  select case when user_a = auth.uid() then user_b else user_a end into other
    from chats where auth.uid() in (user_a, user_b) limit 1;
  if other is null then raise exception 'no_chat'; end if;
  select count(*) into n from reports where reporter = auth.uid() and created_at > now() - interval '1 day';
  if n >= 5 then raise exception 'too_many_reports'; end if;
  insert into reports (reporter, reported, reason, details)
    values (auth.uid(), other, left(p_reason, 40), left(p_details, 1000));
end; $$;

revoke execute on function public.pair_request(text), public.pair_inbox(), public.pair_outbox(),
  public.pair_respond(bigint, boolean), public.pair_cancel(bigint), public.chat_stats(uuid),
  public.partner_birthday(uuid), public.edit_message(bigint, text), public.report_partner(text, text)
  from public, anon;
grant execute on function public.pair_request(text), public.pair_inbox(), public.pair_outbox(),
  public.pair_respond(bigint, boolean), public.pair_cancel(bigint), public.chat_stats(uuid),
  public.partner_birthday(uuid), public.edit_message(bigint, text), public.report_partner(text, text)
  to authenticated;

-- تأكيد: لازم يطلع 1 بكل عمود
select
  (select count(*) from pg_proc where proname = 'pair_request' and pronamespace = 'public'::regnamespace) as pair_request,
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'message_stars') as stars,
  (select count(*) from pg_proc where proname = 'chat_stats' and pronamespace = 'public'::regnamespace) as stats,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'messages' and column_name = 'edited_at') as edited_at,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'chats' and column_name = 'countdown_at') as countdown;
