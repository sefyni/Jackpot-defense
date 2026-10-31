-- Jackpot Defense v16.9 : la sauvegarde en ligne (compte facultatif, par mail + mot de passe).
-- À coller UNE FOIS dans Supabase > SQL Editor > New query > Run.
-- Ajoute une table (une sauvegarde par compte) et 2 fonctions. Ne touche pas au classement.

-- une sauvegarde par compte : la progression du profil relié (même contenu que le code de sauvegarde)
create table if not exists public.saves (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null,
  rev int not null default 1,
  updated_at timestamptz not null default now()
);
alter table public.saves enable row level security;

-- chacun ne voit et ne modifie que SA sauvegarde
drop policy if exists saves_select_own on public.saves;
drop policy if exists saves_insert_own on public.saves;
drop policy if exists saves_update_own on public.saves;
create policy saves_select_own on public.saves for select to authenticated using ((select auth.uid()) = user_id);
create policy saves_insert_own on public.saves for insert to authenticated with check ((select auth.uid()) = user_id);
create policy saves_update_own on public.saves for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
revoke all on public.saves from anon;
grant select, insert, update on public.saves to authenticated;

-- envoyer sa sauvegarde : refusée (« conflit ») si un autre appareil a sauvegardé entre-temps
create or replace function public.save_put(p_data jsonb, p_rev int)
returns table(new_rev int, saved_at timestamptz)
language plpgsql
security invoker
set search_path to 'public'
as $function$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'non_connecte'; end if;
  if octet_length(p_data::text) > 3000000 then raise exception 'trop_gros'; end if;
  if coalesce(p_rev, 0) = 0 then
    insert into saves (user_id, data, rev) values (me, p_data, 1)
    on conflict (user_id) do nothing;
    if not found then raise exception 'conflit'; end if;
  else
    update saves s set data = p_data, rev = s.rev + 1, updated_at = now()
    where s.user_id = me and s.rev = p_rev;
    if not found then raise exception 'conflit'; end if;
  end if;
  return query select s.rev, s.updated_at from saves s where s.user_id = me;
end
$function$;
revoke all on function public.save_put(jsonb, int) from public, anon;
grant execute on function public.save_put(jsonb, int) to authenticated;

-- supprimer son compte (et sa sauvegarde en ligne, effacée avec lui)
create or replace function public.delete_me()
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
begin
  if auth.uid() is null then raise exception 'non_connecte'; end if;
  delete from auth.users where id = auth.uid();
end
$function$;
revoke all on function public.delete_me() from public, anon;
grant execute on function public.delete_me() to authenticated;
