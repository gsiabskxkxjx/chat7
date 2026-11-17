-- الجولة الثانية / 2ب: جداول جديدة (كلها RLS)

create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = public as $$
begin new.updated_at := now(); return new; end $$;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

-- ===== (294/210) سجل أعطال وأداء بدون بيانات شخصية =====
create table if not exists public.error_logs (
  id bigint generated always as identity primary key,
  uid_hash text,
  context text check (char_length(context) <= 60),
  message text check (char_length(message) <= 600),
  stack text check (char_length(stack) <= 3000),
  app_version text check (char_length(app_version) <= 20),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index if not exists error_logs_created_idx on public.error_logs (created_at desc);
create index if not exists error_logs_hash_idx on public.error_logs (uid_hash, created_at desc);
alter table public.error_logs enable row level security;
revoke all on public.error_logs from anon, authenticated;

create table if not exists public.perf_events (
  id bigint generated always as identity primary key,
  uid_hash text,
  name text not null check (char_length(name) <= 40),
  ms integer not null check (ms between 0 and 600000),
  app_version text check (char_length(app_version) <= 20),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);
create index if not exists perf_events_created_idx on public.perf_events (created_at desc);
create index if not exists perf_events_hash_idx on public.perf_events (uid_hash, created_at desc);
alter table public.perf_events enable row level security;
revoke all on public.perf_events from anon, authenticated;

-- ===== (282/283) الأجهزة المسجّلة =====
create table if not exists public.devices (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  device_id text not null check (char_length(device_id) between 8 and 80),
  name text check (char_length(name) <= 60),
  platform text check (char_length(platform) <= 20),
  app_version text check (char_length(app_version) <= 20),
  session_id uuid,
  created_at timestamptz not null default now(),
  last_seen timestamptz not null default now(),
  unique (user_id, device_id)
);
alter table public.devices enable row level security;
revoke all on public.devices from anon, authenticated;

-- ===== (301) تثبيت رسائل =====
create table if not exists public.pinned_messages (
  chat_id uuid not null references public.chats(id) on delete cascade,
  message_id bigint not null references public.messages(id) on delete cascade,
  pinned_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (chat_id, message_id)
);
create index if not exists pinned_messages_message_idx on public.pinned_messages (message_id);
create index if not exists pinned_messages_by_idx on public.pinned_messages (pinned_by);
alter table public.pinned_messages enable row level security;
revoke all on public.pinned_messages from anon;
create policy pins_select on public.pinned_messages for select to authenticated
  using (public.is_member(chat_id));
create policy pins_insert on public.pinned_messages for insert to authenticated
  with check (pinned_by = (select auth.uid()) and public.is_member(chat_id)
    and exists (select 1 from public.messages m where m.id = message_id and m.chat_id = pinned_messages.chat_id));
create policy pins_delete on public.pinned_messages for delete to authenticated
  using (public.is_member(chat_id));

create or replace function public.pins_limit() returns trigger
language plpgsql set search_path = public as $$
begin
  if (select count(*) from public.pinned_messages where chat_id = new.chat_id) >= 3 then
    raise exception 'pin_limit';
  end if;
  return new;
end $$;
revoke execute on function public.pins_limit() from public, anon, authenticated;
create trigger pins_limit_trg before insert on public.pinned_messages
  for each row execute function public.pins_limit();

-- ===== (302) رسائل مجدولة =====
create table if not exists public.scheduled_messages (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  send_at timestamptz not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  failed boolean not null default false
);
create index if not exists scheduled_due_idx on public.scheduled_messages (send_at) where sent_at is null;
create index if not exists scheduled_chat_idx on public.scheduled_messages (chat_id);
create index if not exists scheduled_sender_idx on public.scheduled_messages (sender_id, sent_at);
alter table public.scheduled_messages enable row level security;
revoke all on public.scheduled_messages from anon;
create policy sched_select on public.scheduled_messages for select to authenticated
  using (sender_id = (select auth.uid()));
create policy sched_insert on public.scheduled_messages for insert to authenticated
  with check (sender_id = (select auth.uid()) and public.is_member(chat_id)
    and send_at > now() - interval '1 minute' and send_at < now() + interval '1 year');
create policy sched_delete on public.scheduled_messages for delete to authenticated
  using (sender_id = (select auth.uid()) and sent_at is null);

create or replace function public.sched_limit() returns trigger
language plpgsql set search_path = public as $$
begin
  if (select count(*) from public.scheduled_messages where sender_id = new.sender_id and sent_at is null) >= 20 then
    raise exception 'sched_limit';
  end if;
  return new;
end $$;
revoke execute on function public.sched_limit() from public, anon, authenticated;
create trigger sched_limit_trg before insert on public.scheduled_messages
  for each row execute function public.sched_limit();

-- ===== (311/317) كبسولة زمنية ورسالة للمستقبل =====
create table if not exists public.time_capsules (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  author uuid not null default auth.uid() references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 3000),
  media_path text,
  unlock_at timestamptz not null,
  created_at timestamptz not null default now(),
  announced_at timestamptz,
  opened_at timestamptz,
  check (char_length(body) > 0 or media_path is not null)
);
create index if not exists capsules_chat_idx on public.time_capsules (chat_id, unlock_at);
create index if not exists capsules_author_idx on public.time_capsules (author);
create index if not exists capsules_to_idx on public.time_capsules (to_user);
create index if not exists capsules_due_idx on public.time_capsules (unlock_at) where announced_at is null;
alter table public.time_capsules enable row level security;
revoke all on public.time_capsules from anon, authenticated;
grant insert, delete on public.time_capsules to authenticated;
create policy capsules_insert on public.time_capsules for insert to authenticated
  with check (author = (select auth.uid()) and public.is_member(chat_id)
    and unlock_at > now() + interval '1 minute' and unlock_at < now() + interval '11 years'
    and exists (select 1 from public.chats c where c.id = chat_id and to_user in (c.user_a, c.user_b)));
create policy capsules_delete on public.time_capsules for delete to authenticated
  using (author = (select auth.uid()) and unlock_at > now());

-- ===== (312) اسم الدلع =====
create table if not exists public.chat_nicknames (
  chat_id uuid not null references public.chats(id) on delete cascade,
  setter uuid not null default auth.uid() references auth.users(id) on delete cascade,
  nick text not null check (char_length(btrim(nick)) between 1 and 20),
  updated_at timestamptz not null default now(),
  primary key (chat_id, setter)
);
create index if not exists nicknames_setter_idx on public.chat_nicknames (setter);
alter table public.chat_nicknames enable row level security;
revoke all on public.chat_nicknames from anon;
create policy nick_select on public.chat_nicknames for select to authenticated
  using (public.is_member(chat_id));
create policy nick_insert on public.chat_nicknames for insert to authenticated
  with check (setter = (select auth.uid()) and public.is_member(chat_id));
create policy nick_update on public.chat_nicknames for update to authenticated
  using (setter = (select auth.uid())) with check (setter = (select auth.uid()) and public.is_member(chat_id));
create policy nick_delete on public.chat_nicknames for delete to authenticated
  using (setter = (select auth.uid()));

-- ===== (313/383) شنو أحتاج اليوم =====
create table if not exists public.daily_needs (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day date not null default current_date,
  need text not null check (char_length(btrim(need)) between 1 and 40),
  updated_at timestamptz not null default now(),
  primary key (chat_id, user_id, day)
);
create index if not exists daily_needs_user_idx on public.daily_needs (user_id);
alter table public.daily_needs enable row level security;
revoke all on public.daily_needs from anon;
create policy needs_select on public.daily_needs for select to authenticated
  using (public.is_member(chat_id));
create policy needs_insert on public.daily_needs for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_member(chat_id));
create policy needs_update on public.daily_needs for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()) and public.is_member(chat_id));
create policy needs_delete on public.daily_needs for delete to authenticated
  using (user_id = (select auth.uid()));

-- ===== جدول عام للخطط والأنشطة المشتركة =====
create table if not exists public.plans (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  kind text not null check (kind in ('trip','savings','chore','poll','sticky','reason','food','book',
    'bingo','photo','meet','wake','goal','wish','weekly')),
  title text not null default '' check (char_length(title) <= 120),
  data jsonb not null default '{}'::jsonb check (octet_length(data::text) <= 24000),
  done boolean not null default false,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists plans_chat_kind_idx on public.plans (chat_id, kind, created_at desc);
create index if not exists plans_creator_idx on public.plans (created_by);
alter table public.plans enable row level security;
revoke all on public.plans from anon;
create policy plans_select on public.plans for select to authenticated using (public.is_member(chat_id));
create policy plans_insert on public.plans for insert to authenticated
  with check (created_by = (select auth.uid()) and public.is_member(chat_id));
create policy plans_update on public.plans for update to authenticated
  using (public.is_member(chat_id)) with check (public.is_member(chat_id));
create policy plans_delete on public.plans for delete to authenticated
  using (public.is_member(chat_id));
create trigger plans_touch before update on public.plans
  for each row execute function public.touch_updated_at();

-- ===== (351) موقع لحظي مؤقت =====
create table if not exists public.live_locations (
  chat_id uuid not null references public.chats(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  lat double precision not null check (lat between -90 and 90),
  lng double precision not null check (lng between -180 and 180),
  label text check (char_length(label) <= 40),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null,
  primary key (chat_id, user_id)
);
create index if not exists live_loc_user_idx on public.live_locations (user_id);
alter table public.live_locations enable row level security;
revoke all on public.live_locations from anon;
create policy loc_select on public.live_locations for select to authenticated
  using (public.is_member(chat_id) and expires_at > now());
create policy loc_insert on public.live_locations for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_member(chat_id) and expires_at <= now() + interval '13 hours');
create policy loc_update on public.live_locations for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and public.is_member(chat_id) and expires_at <= now() + interval '13 hours');
create policy loc_delete on public.live_locations for delete to authenticated
  using (user_id = (select auth.uid()));

-- ===== (361-370) حصة الذكاء الاصطناعي اليومية =====
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null default current_date,
  n integer not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;
revoke all on public.ai_usage from anon, authenticated;

-- ===== realtime =====
do $$
declare t text;
begin
  foreach t in array array['pinned_messages','plans','chat_nicknames','daily_needs','live_locations','albums','album_items'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
