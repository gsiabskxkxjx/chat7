-- Run once in Supabase -> SQL Editor (after supabase_setup.sql). Safe to run again.

create table if not exists public.call_signals (
  id bigint generated always as identity primary key,
  chat_id uuid not null references public.chats(id) on delete cascade,
  sender_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('offer', 'answer', 'candidate', 'decline', 'hangup')),
  call_id text not null check (char_length(call_id) between 1 and 64),
  data jsonb not null default '{}'::jsonb check (octet_length(data::text) < 30000),
  created_at timestamptz not null default now()
);
create index if not exists call_signals_chat_idx on public.call_signals (chat_id, id);

alter table public.call_signals enable row level security;

grant select, insert, delete on public.call_signals to authenticated;

drop policy if exists call_signals_select_member on public.call_signals;
create policy call_signals_select_member on public.call_signals
  for select to authenticated
  using (exists (
    select 1 from public.chats c
    where c.id = call_signals.chat_id and auth.uid() in (c.user_a, c.user_b)
  ));

drop policy if exists call_signals_insert_member on public.call_signals;
create policy call_signals_insert_member on public.call_signals
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.chats c
      where c.id = call_signals.chat_id and auth.uid() in (c.user_a, c.user_b)
    )
  );

drop policy if exists call_signals_delete_member on public.call_signals;
create policy call_signals_delete_member on public.call_signals
  for delete to authenticated
  using (exists (
    select 1 from public.chats c
    where c.id = call_signals.chat_id and auth.uid() in (c.user_a, c.user_b)
  ));

do $$
begin
  alter publication supabase_realtime add table public.call_signals;
exception when duplicate_object then
  null;
end $$;
