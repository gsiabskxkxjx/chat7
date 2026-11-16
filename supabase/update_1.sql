-- بيناتنا تحديث 1: الملف الشخصي + البحث عن شريك (ذكر وأنثى) + قفل الوسائط للمطابقات + تأثيرات + السلسلة + سؤال اليوم
-- شغّله مرة وحدة كامل من SQL Editor في Supabase. آمن لو انعاد تشغيله.

-- ========== 1) الملف الشخصي ==========
alter table public.profiles add column if not exists birth_date date;

create or replace function public.lock_profile_fields() returns trigger language plpgsql as $$
begin
  if old.gender is not null and new.gender is distinct from old.gender then
    raise exception 'gender_locked';
  end if;
  if old.birth_date is not null and new.birth_date is distinct from old.birth_date then
    raise exception 'birth_locked';
  end if;
  if new.birth_date is distinct from old.birth_date and new.birth_date is not null
     and (new.birth_date > current_date - interval '13 years' or new.birth_date < date '1920-01-01') then
    raise exception 'bad_birth';
  end if;
  if new.display_name is distinct from old.display_name and new.display_name is not null
     and char_length(btrim(new.display_name)) not between 2 and 30 then
    raise exception 'bad_name';
  end if;
  return new;
end; $$;
drop trigger if exists profiles_lock_fields on public.profiles;
create trigger profiles_lock_fields before update on public.profiles
  for each row execute function public.lock_profile_fields();

create or replace function public.is_adult(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select birth_date <= current_date - interval '18 years' from profiles where id = p), false)
$$;

-- ========== 2) علامات المحادثة المطابقة والثقة ==========
alter table public.chats add column if not exists matched boolean not null default false;
alter table public.chats add column if not exists trust_a boolean not null default false;
alter table public.chats add column if not exists trust_b boolean not null default false;

-- كل طرف يفعّل ثقته بنفسه فقط، وما ينلغى، و"matched" ما يتغير
create or replace function public.guard_chat_flags() returns trigger language plpgsql as $$
begin
  if new.matched is distinct from old.matched then raise exception 'matched_locked'; end if;
  if new.trust_a is distinct from old.trust_a
     and (auth.uid() is distinct from old.user_a or new.trust_a = false) then
    raise exception 'trust_locked';
  end if;
  if new.trust_b is distinct from old.trust_b
     and (auth.uid() is distinct from old.user_b or new.trust_b = false) then
    raise exception 'trust_locked';
  end if;
  return new;
end; $$;
drop trigger if exists chats_guard_flags on public.chats;
create trigger chats_guard_flags before update on public.chats
  for each row execute function public.guard_chat_flags();

-- الصور والفيديو والصوت مقفلة بالمطابقة الجديدة لين الطرفين يضغطون "أثق فيه"
create or replace function public.guard_match_media() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('image', 'video', 'audio') and exists (
       select 1 from chats where id = new.chat_id and matched and not (trust_a and trust_b)) then
    raise exception 'media_locked';
  end if;
  return new;
end; $$;
drop trigger if exists messages_guard_match on public.messages;
create trigger messages_guard_match before insert on public.messages
  for each row execute function public.guard_match_media();

-- والمكالمات كذلك
create or replace function public.guard_match_call() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind = 'offer' and exists (
       select 1 from chats where id = new.chat_id and matched and not (trust_a and trust_b)) then
    raise exception 'calls_locked';
  end if;
  return new;
end; $$;
drop trigger if exists call_signals_guard_match on public.call_signals;
create trigger call_signals_guard_match before insert on public.call_signals
  for each row execute function public.guard_match_call();

-- ========== 3) طابور البحث والعروض ==========
create table if not exists public.match_queue (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  gender text not null check (gender in ('male', 'female')),
  created_at timestamptz not null default now(),
  seen_at timestamptz not null default now()
);
alter table public.match_queue enable row level security;
revoke all on public.match_queue from anon, authenticated;

create table if not exists public.match_offers (
  id bigint generated always as identity primary key,
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  a_ok boolean,
  b_ok boolean,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'expired')),
  chat_id uuid,
  created_at timestamptz not null default now()
);
alter table public.match_offers enable row level security;
revoke all on public.match_offers from anon, authenticated;
grant select on public.match_offers to authenticated;
drop policy if exists match_offers_select_own on public.match_offers;
create policy match_offers_select_own on public.match_offers
  for select to authenticated using (auth.uid() in (user_a, user_b));
create index if not exists match_offers_a_idx on public.match_offers (user_a, status);
create index if not exists match_offers_b_idx on public.match_offers (user_b, status);

create table if not exists public.match_skips (
  user_id uuid not null references public.profiles(id) on delete cascade,
  other_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, other_id)
);
alter table public.match_skips enable row level security;
revoke all on public.match_skips from anon, authenticated;

create table if not exists public.match_attempts (
  user_id uuid not null references public.profiles(id) on delete cascade,
  at timestamptz not null default now()
);
alter table public.match_attempts enable row level security;
revoke all on public.match_attempts from anon, authenticated;

-- تحديثات العروض توصل للتطبيق مباشرة
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'match_offers') then
    alter publication supabase_realtime add table public.match_offers;
  end if;
end $$;

-- يبدأ البحث أو يكمله (التطبيق يناديها كل 20 ثانية وقت البحث)
create or replace function public.match_start() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  me profiles%rowtype;
  other uuid;
  oid bigint;
  n int;
  pend match_offers%rowtype;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  perform pg_advisory_xact_lock(424242);
  select * into me from profiles where id = uid;
  if not found then raise exception 'no_profile'; end if;
  if me.gender is null or coalesce(btrim(me.display_name), '') = '' then
    raise exception 'profile_incomplete';
  end if;
  if not public.is_adult(uid) then raise exception 'under_18'; end if;
  if exists (select 1 from chats where uid in (user_a, user_b)) then raise exception 'already_paired'; end if;

  update match_offers set status = 'expired'
    where status = 'pending' and created_at < now() - interval '2 minutes';
  select * into pend from match_offers
    where status = 'pending' and uid in (user_a, user_b) order by id desc limit 1;
  if found then
    delete from match_queue where user_id = uid;
    return jsonb_build_object('status', 'offer', 'offer_id', pend.id);
  end if;

  if not exists (select 1 from match_queue where user_id = uid) then
    delete from match_attempts where at < now() - interval '1 day';
    select count(*) into n from match_attempts where user_id = uid;
    if n >= 10 then raise exception 'daily_limit'; end if;
    insert into match_attempts (user_id) values (uid);
    insert into match_queue (user_id, gender) values (uid, me.gender);
  else
    update match_queue set seen_at = now() where user_id = uid;
  end if;

  select q.user_id into other from match_queue q
    where q.user_id <> uid
      and q.gender <> me.gender
      and q.seen_at > now() - interval '45 seconds'
      and not exists (select 1 from chats c where q.user_id in (c.user_a, c.user_b))
      and not exists (select 1 from match_skips s
                      where (s.user_id = uid and s.other_id = q.user_id)
                         or (s.user_id = q.user_id and s.other_id = uid))
      and not exists (select 1 from blocks b
                      where (b.blocker = uid and b.blocked = q.user_id)
                         or (b.blocker = q.user_id and b.blocked = uid))
      and public.is_adult(q.user_id)
    order by q.created_at
    limit 1;
  if other is null then
    return jsonb_build_object('status', 'waiting');
  end if;

  delete from match_queue where user_id in (uid, other);
  insert into match_offers (user_a, user_b) values (other, uid) returning id into oid;
  return jsonb_build_object('status', 'offer', 'offer_id', oid);
end; $$;

create or replace function public.match_cancel() returns void
language sql security definer set search_path = public as $$
  delete from match_queue where user_id = auth.uid();
$$;

-- بطاقة الطرف الثاني بالعرض: الاسم والصورة فقط
create or replace function public.match_card(p_offer bigint) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  o match_offers%rowtype;
  other uuid;
  p profiles%rowtype;
begin
  select * into o from match_offers where id = p_offer and uid in (user_a, user_b);
  if not found then return null; end if;
  other := case when o.user_a = uid then o.user_b else o.user_a end;
  select * into p from profiles where id = other;
  return jsonb_build_object(
    'name', p.display_name,
    'avatar', p.avatar_path,
    'gender', p.gender,
    'status', case when o.status = 'pending' and o.created_at < now() - interval '2 minutes'
                   then 'expired' else o.status end,
    'seconds_left', greatest(0, extract(epoch from (o.created_at + interval '2 minutes' - now()))::int),
    'my_ok', case when o.user_a = uid then o.a_ok else o.b_ok end,
    'their_ok', case when o.user_a = uid then o.b_ok else o.a_ok end,
    'chat_id', o.chat_id);
end; $$;

create or replace function public.match_respond(p_offer bigint, p_ok boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  o match_offers%rowtype;
  cid uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  perform pg_advisory_xact_lock(424242);
  select * into o from match_offers where id = p_offer and uid in (user_a, user_b) for update;
  if not found then raise exception 'no_offer'; end if;
  if o.status <> 'pending' then
    return jsonb_build_object('status', o.status, 'chat_id', o.chat_id);
  end if;
  if o.created_at < now() - interval '2 minutes' then
    update match_offers set status = 'expired' where id = o.id;
    return jsonb_build_object('status', 'expired');
  end if;

  if not p_ok then
    update match_offers set status = 'declined' where id = o.id;
    insert into match_skips (user_id, other_id)
      values (o.user_a, o.user_b), (o.user_b, o.user_a) on conflict do nothing;
    return jsonb_build_object('status', 'declined');
  end if;

  if o.user_a = uid then o.a_ok := true; else o.b_ok := true; end if;
  if coalesce(o.a_ok, false) and coalesce(o.b_ok, false) then
    if exists (select 1 from chats
               where user_a in (o.user_a, o.user_b) or user_b in (o.user_a, o.user_b)) then
      update match_offers set status = 'expired' where id = o.id;
      return jsonb_build_object('status', 'expired');
    end if;
    insert into chats (user_a, user_b, matched) values (o.user_a, o.user_b, true) returning id into cid;
    update match_offers set a_ok = true, b_ok = true, status = 'accepted', chat_id = cid where id = o.id;
    delete from invites where owner in (o.user_a, o.user_b);
    insert into match_skips (user_id, other_id)
      values (o.user_a, o.user_b), (o.user_b, o.user_a) on conflict do nothing;
    return jsonb_build_object('status', 'accepted', 'chat_id', cid);
  end if;

  update match_offers set a_ok = o.a_ok, b_ok = o.b_ok where id = o.id;
  return jsonb_build_object('status', 'pending');
end; $$;

-- صورة الطرف الثاني تبين بالعرض قبل القبول
drop policy if exists avatars_select_offer on storage.objects;
create policy avatars_select_offer on storage.objects for select to authenticated using (
  bucket_id = 'avatars' and exists (
    select 1 from public.match_offers o
    where o.status = 'pending' and auth.uid() in (o.user_a, o.user_b)
      and (storage.foldername(name))[1] in (o.user_a::text, o.user_b::text)));

revoke execute on function public.match_start(), public.match_cancel(), public.match_card(bigint),
  public.match_respond(bigint, boolean), public.is_adult(uuid) from public, anon;
grant execute on function public.match_start(), public.match_cancel(), public.match_card(bigint),
  public.match_respond(bigint, boolean) to authenticated;

-- ========== 4) تأثيرات الرسائل ==========
alter table public.messages add column if not exists effect text;
alter table public.messages drop constraint if exists messages_effect_check;
alter table public.messages add constraint messages_effect_check
  check (effect is null or effect in ('hearts', 'confetti', 'stars'));

-- ========== 5) السلسلة: كم يوم متتالي تكلم فيه الطرفين ==========
create index if not exists messages_chat_created_idx on public.messages (chat_id, created_at);
create or replace function public.chat_streak(p_chat uuid, p_tz text default 'Asia/Baghdad') returns int
language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone p_tz)::date;
  d date := today;
  n int := 0;
  s int;
begin
  if not exists (select 1 from chats where id = p_chat and auth.uid() in (user_a, user_b)) then
    return 0;
  end if;
  loop
    select count(distinct sender_id) into s from messages
      where chat_id = p_chat and kind <> 'call'
        and created_at >= (d::timestamp at time zone p_tz)
        and created_at < ((d + 1)::timestamp at time zone p_tz);
    if s >= 2 then
      n := n + 1;
      d := d - 1;
    elsif n = 0 and d = today then
      d := d - 1; -- اليوم لسا ما خلص
    else
      exit;
    end if;
    exit when n > 3650;
  end loop;
  return n;
end; $$;

-- ========== 6) سؤال اليوم: الجواب ينكشف لما الاثنين يجاوبون ==========
create table if not exists public.daily_answers (
  chat_id uuid not null references public.chats(id) on delete cascade,
  day date not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  answer text not null check (char_length(answer) between 1 and 500),
  created_at timestamptz not null default now(),
  primary key (chat_id, day, user_id)
);
alter table public.daily_answers enable row level security;
revoke all on public.daily_answers from anon, authenticated;

create or replace function public.daily_answer(p_chat uuid, p_day date, p_answer text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chats where id = p_chat and auth.uid() in (user_a, user_b)) then
    raise exception 'not_member';
  end if;
  if abs(p_day - current_date) > 1 then raise exception 'bad_day'; end if;
  insert into daily_answers (chat_id, day, user_id, answer)
    values (p_chat, p_day, auth.uid(), left(btrim(p_answer), 500))
    on conflict do nothing;
end; $$;

create or replace function public.daily_get(p_chat uuid, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  mine text;
  theirs text;
begin
  if not exists (select 1 from chats where id = p_chat and auth.uid() in (user_a, user_b)) then
    return null;
  end if;
  select answer into mine from daily_answers
    where chat_id = p_chat and day = p_day and user_id = auth.uid();
  select answer into theirs from daily_answers
    where chat_id = p_chat and day = p_day and user_id <> auth.uid();
  return jsonb_build_object(
    'mine', mine,
    'theirs', case when mine is not null then theirs else null end,
    'their_done', theirs is not null);
end; $$;

revoke execute on function public.chat_streak(uuid, text), public.daily_answer(uuid, date, text),
  public.daily_get(uuid, date) from public, anon;
grant execute on function public.chat_streak(uuid, text), public.daily_answer(uuid, date, text),
  public.daily_get(uuid, date) to authenticated;

-- تأكيد: لازم يطلع 1 بكل عمود
select
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'birth_date') as birth_date,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'chats' and column_name = 'matched') as matched,
  (select count(*) from pg_proc where proname = 'match_start' and pronamespace = 'public'::regnamespace) as match_start,
  (select count(*) from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'match_offers') as realtime,
  (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'messages' and column_name = 'effect') as effect,
  (select count(*) from pg_proc where proname = 'daily_get' and pronamespace = 'public'::regnamespace) as daily;
