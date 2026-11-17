-- Round 2: push notification when it becomes a player's turn in a chat game
create or replace function public.notify_game() returns trigger
language plpgsql security definer set search_path = public as $$
declare nm text; target uuid; msg text; pl jsonb;
begin
  nm := case new.kind
    when 'connect4' then 'أربعة بالصف' when 'battleship' then 'حرب السفن' when 'wordle' then 'كلمة اليوم'
    when 'whosaid' then 'من قال؟' when 'truthdare' then 'صراحة وجرأة' when 'wordchain' then 'سلسلة الكلمات'
    when 'story' then 'كمّل القصة' when 'canvas' then 'لوحة الرسم' when 'bingo' then 'بينغو' when 'weekly' then 'تحدي الأسبوع'
    when 'chess' then 'الشطرنج' when 'checkers' then 'الداما' when 'tictactoe' then 'إكس أو'
    else 'لعبة' end;
  if tg_op = 'INSERT' then
    pl := new.state -> 'players';
    if pl is not null and jsonb_typeof(pl) = 'array' and jsonb_array_length(pl) = 2 and new.turn is not null then
      select x::uuid into target from jsonb_array_elements_text(pl) x where x::uuid <> new.turn limit 1;
      msg := '🎮 بدأ لعبة ' || nm || '، تعال العب';
    end if;
  elsif new.turn is not null and new.turn is distinct from old.turn then
    target := new.turn;
    msg := '🎮 دورك بلعبة ' || nm;
  end if;
  if target is not null then
    perform public.push_user(target, 'بيناتنا', msg, 'game', new.chat_id);
  end if;
  return new;
exception when others then
  return new;
end $$;
revoke execute on function public.notify_game() from public, anon, authenticated;
create or replace trigger chat_games_notify after insert or update of turn on public.chat_games
  for each row execute function public.notify_game();
