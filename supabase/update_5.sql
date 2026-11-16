-- بيناتنا تحديث 5: ألبومات الذكريات، ميزانية مشتركة، يوميات مشتركة
-- شغّله بعد update_1 إلى update_4. آمن لو انعاد.

-- ===== 1) الألبومات =====
create table if not exists public.albums (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 40),
  created_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists albums_chat on public.albums (chat_id, id desc);
alter table public.albums enable row level security;
grant select, insert, update, delete on public.albums to authenticated;
drop policy if exists albums_member on public.albums;
create policy albums_member on public.albums for all to authenticated
  using (public.is_member(chat_id))
  with check (public.is_member(chat_id));

create table if not exists public.album_items (
  album_id bigint not null references public.albums(id) on delete cascade,
  message_id bigint not null references public.messages(id) on delete cascade,
  added_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (album_id, message_id)
);
alter table public.album_items enable row level security;
grant select, insert, delete on public.album_items to authenticated;
drop policy if exists album_items_member on public.album_items;
create policy album_items_member on public.album_items for all to authenticated
  using (exists (select 1 from albums a where a.id = album_items.album_id and public.is_member(a.chat_id)))
  with check (exists (
    select 1 from albums a join messages m on m.id = album_items.message_id
    where a.id = album_items.album_id and public.is_member(a.chat_id)
      and m.chat_id = a.chat_id and m.kind in ('image', 'video')));

-- ===== 2) الميزانية المشتركة =====
create table if not exists public.budget_items (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 60),
  amount numeric(12, 2) not null check (amount > 0 and amount < 100000000),
  paid_by uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists budget_items_chat on public.budget_items (chat_id, id desc);
alter table public.budget_items enable row level security;
grant select, insert, delete on public.budget_items to authenticated;
drop policy if exists budget_select on public.budget_items;
create policy budget_select on public.budget_items for select to authenticated
  using (public.is_member(chat_id));
drop policy if exists budget_insert on public.budget_items;
create policy budget_insert on public.budget_items for insert to authenticated
  with check (paid_by = auth.uid() and public.is_member(chat_id));
drop policy if exists budget_delete on public.budget_items;
create policy budget_delete on public.budget_items for delete to authenticated
  using (paid_by = auth.uid());
do $$ begin alter publication supabase_realtime add table public.budget_items;
exception when duplicate_object then null; end $$;

-- ===== 3) اليوميات المشتركة =====
create table if not exists public.diary_entries (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  day date not null default current_date,
  mood smallint not null default 0 check (mood between 0 and 5),
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists diary_chat on public.diary_entries (chat_id, day desc, id desc);
alter table public.diary_entries enable row level security;
grant select, insert, update, delete on public.diary_entries to authenticated;
drop policy if exists diary_select on public.diary_entries;
create policy diary_select on public.diary_entries for select to authenticated
  using (public.is_member(chat_id));
drop policy if exists diary_write on public.diary_entries;
create policy diary_write on public.diary_entries for insert to authenticated
  with check (author = auth.uid() and public.is_member(chat_id));
drop policy if exists diary_edit on public.diary_entries;
create policy diary_edit on public.diary_entries for update to authenticated
  using (author = auth.uid()) with check (author = auth.uid());
drop policy if exists diary_delete on public.diary_entries;
create policy diary_delete on public.diary_entries for delete to authenticated
  using (author = auth.uid());
do $$ begin alter publication supabase_realtime add table public.diary_entries;
exception when duplicate_object then null; end $$;

-- فحص: لازم يطلع 4
select count(*) as tables_ok from information_schema.tables where table_schema = 'public'
  and table_name in ('albums', 'album_items', 'budget_items', 'diary_entries');
