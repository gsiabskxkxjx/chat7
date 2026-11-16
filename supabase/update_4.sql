-- بيناتنا تحديث 4: جدار ملاحظات الحب، تقويم مشترك، تحدي الصورة اليومي،
-- أسبوع التعارف «نكمل؟»، رسالة وداع، تواريخ لبنود القوائم، ألعاب جديدة،
-- بطاقات ملوّنة، فيديو دائري، ملفات
-- شغّله بعد update_1 و update_2 و update_3. آمن لو انعاد.

-- دالة مساعدة: هل أنا طرف بهذي المحادثة؟
create or replace function public.is_member(p_chat uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chats c where c.id = p_chat and auth.uid() in (c.user_a, c.user_b));
$$;
revoke execute on function public.is_member(uuid) from public, anon;
grant execute on function public.is_member(uuid) to authenticated;

-- ===== 1) تواريخ لبنود القوائم المشتركة =====
alter table public.shared_items add column if not exists due_on date;

-- ===== 2) جدار ملاحظات الحب =====
create table if not exists public.love_notes (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 140),
  color smallint not null default 0 check (color between 0 and 7),
  created_at timestamptz not null default now()
);
create index if not exists love_notes_chat on public.love_notes (chat_id, id desc);
alter table public.love_notes enable row level security;
grant select, insert, delete on public.love_notes to authenticated;
drop policy if exists love_notes_select on public.love_notes;
create policy love_notes_select on public.love_notes for select to authenticated
  using (public.is_member(chat_id));
drop policy if exists love_notes_insert on public.love_notes;
create policy love_notes_insert on public.love_notes for insert to authenticated
  with check (author = auth.uid() and public.is_member(chat_id));
drop policy if exists love_notes_delete on public.love_notes;
create policy love_notes_delete on public.love_notes for delete to authenticated
  using (author = auth.uid());
do $$ begin alter publication supabase_realtime add table public.love_notes;
exception when duplicate_object then null; end $$;

-- ===== 3) التقويم المشترك =====
create table if not exists public.chat_events (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 60),
  on_date date not null check (on_date >= date '2000-01-01' and on_date <= date '2100-01-01'),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists chat_events_chat on public.chat_events (chat_id, on_date);
alter table public.chat_events enable row level security;
grant select, insert, delete on public.chat_events to authenticated;
drop policy if exists chat_events_member on public.chat_events;
create policy chat_events_member on public.chat_events for select to authenticated
  using (public.is_member(chat_id));
drop policy if exists chat_events_insert on public.chat_events;
create policy chat_events_insert on public.chat_events for insert to authenticated
  with check (created_by = auth.uid() and public.is_member(chat_id));
drop policy if exists chat_events_delete on public.chat_events;
create policy chat_events_delete on public.chat_events for delete to authenticated
  using (public.is_member(chat_id));
do $$ begin alter publication supabase_realtime add table public.chat_events;
exception when duplicate_object then null; end $$;

-- ===== 4) تحدي الصورة اليومي: الصورتين تنكشف لما الاثنين يرسلون =====
create table if not exists public.photo_challenge (
  chat_id uuid not null references public.chats(id) on delete cascade,
  day date not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  media_path text not null check (char_length(media_path) between 5 and 200),
  created_at timestamptz not null default now(),
  primary key (chat_id, day, user_id)
);
alter table public.photo_challenge enable row level security;
revoke all on public.photo_challenge from anon, authenticated; -- عن طريق الدوال بس

create or replace function public.challenge_submit(p_chat uuid, p_day date, p_path text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_member(p_chat) then raise exception 'not_member'; end if;
  if p_day < current_date - 1 or p_day > current_date + 1 then raise exception 'bad_day'; end if;
  if split_part(p_path, '/', 1) <> p_chat::text then raise exception 'bad_path'; end if;
  if exists (select 1 from chats where id = p_chat and matched and not (trust_a and trust_b)) then
    raise exception 'media_locked';
  end if;
  insert into photo_challenge (chat_id, day, user_id, media_path)
  values (p_chat, p_day, auth.uid(), p_path)
  on conflict (chat_id, day, user_id) do update set media_path = excluded.media_path, created_at = now();
end $$;

create or replace function public.challenge_get(p_chat uuid, p_day date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare mine text; theirs text;
begin
  if not public.is_member(p_chat) then raise exception 'not_member'; end if;
  select media_path into mine from photo_challenge where chat_id = p_chat and day = p_day and user_id = auth.uid();
  select media_path into theirs from photo_challenge where chat_id = p_chat and day = p_day and user_id <> auth.uid();
  return jsonb_build_object(
    'mine', mine,
    'their_done', theirs is not null,
    'theirs', case when mine is not null then theirs end);
end $$;
revoke execute on function public.challenge_submit(uuid, date, text), public.challenge_get(uuid, date) from public, anon;
grant execute on function public.challenge_submit(uuid, date, text), public.challenge_get(uuid, date) to authenticated;

-- ===== 5) أسبوع التعارف: بعد 7 أيام من المطابقة كل طرف يجاوب «نكمل؟» =====
alter table public.chats add column if not exists continue_a boolean;
alter table public.chats add column if not exists continue_b boolean;
grant update (continue_a, continue_b) on public.chats to authenticated;

create or replace function public.guard_continue() returns trigger language plpgsql as $$
begin
  if new.continue_a is distinct from old.continue_a and auth.uid() is distinct from old.user_a then
    raise exception 'continue_locked';
  end if;
  if new.continue_b is distinct from old.continue_b and auth.uid() is distinct from old.user_b then
    raise exception 'continue_locked';
  end if;
  return new;
end $$;
drop trigger if exists chats_guard_continue on public.chats;
create trigger chats_guard_continue before update on public.chats
  for each row execute function public.guard_continue();

-- ===== 6) رسالة وداع: تنكتب قبل فك الارتباط وتوصل للطرف الثاني مرة وحدة =====
create table if not exists public.farewells (
  id bigint generated always as identity primary key,
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 200),
  created_at timestamptz not null default now()
);
alter table public.farewells enable row level security;
revoke all on public.farewells from anon, authenticated;

create or replace function public.say_farewell(p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  select case when user_a = uid then user_b else user_a end into other
  from chats where uid in (user_a, user_b) limit 1;
  if other is null or coalesce(btrim(p_body), '') = '' then return; end if;
  delete from farewells where from_user = uid and to_user = other;
  insert into farewells (from_user, to_user, body) values (uid, other, left(btrim(p_body), 200));
end $$;

create or replace function public.farewell_take() returns jsonb
language plpgsql security definer set search_path = public as $$
declare f farewells%rowtype; n text;
begin
  select * into f from farewells
  where to_user = auth.uid() and created_at > now() - interval '14 days'
  order by id desc limit 1;
  if not found then return null; end if;
  delete from farewells where to_user = auth.uid();
  select coalesce(nullif(btrim(display_name), ''), username) into n from profiles where id = f.from_user;
  return jsonb_build_object('body', f.body, 'name', n);
end $$;
revoke execute on function public.say_farewell(text), public.farewell_take() from public, anon;
grant execute on function public.say_farewell(text), public.farewell_take() to authenticated;

-- ===== 7) ألعاب جديدة: مين فينا، صح أو غلط، الذاكرة، 20 سؤال، خمّن من الإيموجي، داما =====
alter table public.chat_games drop constraint if exists chat_games_kind_check;
alter table public.chat_games add constraint chat_games_kind_check check (kind in
  ('tictactoe', 'rps', 'quiz', 'whoof', 'truefalse', 'memory', 'guess20', 'emoji', 'checkers', 'chess'));

-- ===== 8) أنواع رسائل جديدة: بطاقة ملوّنة، فيديو دائري، ملف =====
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in
  ('text', 'image', 'video', 'audio', 'call', 'think', 'card', 'vnote', 'file'));

-- الفيديو الدائري والملفات مقفلة بالمطابقة الجديدة مثل الصور
create or replace function public.guard_match_media() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kind in ('image', 'video', 'audio', 'vnote', 'file') and exists (
       select 1 from chats where id = new.chat_id and matched and not (trust_a and trust_b)) then
    raise exception 'media_locked';
  end if;
  return new;
end; $$;

-- فحص: لازم يطلع 4
select
  (select count(*) from information_schema.tables where table_schema = 'public'
     and table_name in ('love_notes', 'chat_events', 'photo_challenge', 'farewells')) as tables_ok;
