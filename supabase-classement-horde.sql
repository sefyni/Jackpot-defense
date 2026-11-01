-- Jackpot Defense · le classement du mode HORDE
-- À coller une seule fois dans Supabase › SQL Editor › New query, puis « Run ».
-- Ça ne touche à rien d'existant : une nouvelle table et 3 fonctions.

create table if not exists public.hz_scores (
  id          text primary key,
  pseudo      text not null,
  secret      text not null,
  score       bigint not null default 0,
  lv          int not null default 0,
  deck        text not null default '',
  updated_at  timestamptz not null default now()
);
alter table public.hz_scores enable row level security;
-- (aucune règle d'accès direct : on passe uniquement par les fonctions ci-dessous)
create index if not exists hz_scores_score_idx on public.hz_scores (score desc);

-- envoyer un score (garde le meilleur) et renvoyer sa place
create or replace function public.hz_submit(p_id text, p_secret text, p_pseudo text, p_score bigint, p_round int, p_deck text default '')
returns table(place bigint, best bigint, best_round int)
language plpgsql security definer set search_path = public as $$
declare cur public.hz_scores;
begin
  if p_id is null or length(p_id) > 80 or p_secret is null or length(p_secret) > 200 then raise exception 'joueur'; end if;
  if p_score is null or p_score < 0 or p_score > 100000000000 then raise exception 'score'; end if;
  p_pseudo := left(coalesce(nullif(trim(p_pseudo), ''), '?'), 20);
  select * into cur from public.hz_scores h where h.id = p_id;
  if not found then
    insert into public.hz_scores (id, pseudo, secret, score, lv, deck) values (p_id, p_pseudo, p_secret, p_score, greatest(0, least(999, coalesce(p_round, 0))), left(coalesce(p_deck, ''), 30));
  else
    if cur.secret <> p_secret then raise exception 'joueur'; end if;
    update public.hz_scores h set pseudo = p_pseudo,
      score = greatest(h.score, p_score),
      lv = case when p_score > h.score then greatest(0, least(999, coalesce(p_round, 0))) else h.lv end,
      deck = case when p_score > h.score then left(coalesce(p_deck, ''), 30) else h.deck end,
      updated_at = now()
    where h.id = p_id;
  end if;
  return query select (select count(*) + 1 from public.hz_scores o where o.score > h.score), h.score, h.lv from public.hz_scores h where h.id = p_id;
end $$;

-- le top (10 ou 100)
create or replace function public.hz_top(p_limit int default 100)
returns table(place bigint, pseudo text, deck text, score bigint, round int)
language sql security definer set search_path = public as $$
  select rank() over (order by h.score desc), h.pseudo, h.deck, h.score, h.lv
  from public.hz_scores h where h.score > 0
  order by h.score desc, h.updated_at asc
  limit greatest(1, least(100, coalesce(p_limit, 100)));
$$;

-- ma place
create or replace function public.hz_me(p_id text)
returns table(place bigint, best bigint, best_round int)
language sql security definer set search_path = public as $$
  select (select count(*) + 1 from public.hz_scores o where o.score > h.score), h.score, h.lv
  from public.hz_scores h where h.id = p_id;
$$;

grant execute on function public.hz_submit(text, text, text, bigint, int, text) to anon, authenticated;
grant execute on function public.hz_top(int) to anon, authenticated;
grant execute on function public.hz_me(text) to anon, authenticated;
