-- RueDex V4 - Comptes, équipes, clans, carte personnelle et carte de conquête.
-- À exécuter dans Supabase > SQL Editor > New query > Run.

create extension if not exists pgcrypto;

create table if not exists public.teams (
  id text primary key,
  label text not null,
  color_hex text not null
);

insert into public.teams (id, label, color_hex) values
  ('red', 'Rouge', '#E74C3C'),
  ('blue', 'Bleue', '#3498DB'),
  ('green', 'Verte', '#2ECC71'),
  ('yellow', 'Jaune', '#F1C40F')
on conflict (id) do update set
  label = excluded.label,
  color_hex = excluded.color_hex;

create table if not exists public.seasons (
  id text primary key,
  name text not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default false,
  created_at timestamptz not null default now()
);

insert into public.seasons (id, name, is_active)
values ('season_001_paris', 'Saison 1 - Paris', true)
on conflict (id) do update set
  name = excluded.name,
  is_active = excluded.is_active;

create table if not exists public.players (
  id uuid primary key references auth.users(id) on delete cascade,
  pseudo text not null default 'Joueur',
  team_id text references public.teams(id),
  clan_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.player_seasons (
  player_id uuid not null references public.players(id) on delete cascade,
  season_id text not null references public.seasons(id) on delete cascade,
  team_id text not null references public.teams(id),
  joined_at timestamptz not null default now(),
  primary key (player_id, season_id)
);

create table if not exists public.clans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tag text not null,
  team_id text references public.teams(id),
  owner_player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (tag)
);

alter table public.clans add column if not exists team_id text references public.teams(id);

create table if not exists public.clan_members (
  clan_id uuid not null references public.clans(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (clan_id, player_id)
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'players_clan_id_fkey'
      and conrelid = 'public.players'::regclass
  ) then
    alter table public.players
      add constraint players_clan_id_fkey
      foreign key (clan_id) references public.clans(id)
      on delete set null;
  end if;
end $$;

create table if not exists public.street_ownership (
  season_id text not null references public.seasons(id) on delete cascade,
  street_id text not null,
  team_id text not null references public.teams(id),
  captured_by uuid not null references public.players(id) on delete cascade,
  captured_at timestamptz not null default now(),
  capture_count integer not null default 1,
  primary key (season_id, street_id)
);

create table if not exists public.personal_discoveries (
  season_id text not null references public.seasons(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  street_id text not null,
  discovered_at timestamptz not null default now(),
  primary key (season_id, player_id, street_id)
);

create table if not exists public.scan_events (
  id uuid primary key default gen_random_uuid(),
  season_id text not null references public.seasons(id) on delete cascade,
  street_id text not null,
  player_id uuid not null references public.players(id) on delete cascade,
  team_id text not null references public.teams(id),
  previous_team_id text references public.teams(id),
  distance_meters double precision,
  ocr_score double precision not null,
  plate_score double precision not null,
  accepted boolean not null default false,
  rejection_reason text,
  created_at timestamptz not null default now()
);

alter table public.teams enable row level security;
alter table public.seasons enable row level security;
alter table public.players enable row level security;
alter table public.player_seasons enable row level security;
alter table public.clans enable row level security;
alter table public.clan_members enable row level security;
alter table public.street_ownership enable row level security;
alter table public.personal_discoveries enable row level security;
alter table public.scan_events enable row level security;

drop policy if exists "teams readable" on public.teams;
create policy "teams readable" on public.teams for select using (true);

drop policy if exists "seasons readable" on public.seasons;
create policy "seasons readable" on public.seasons for select using (true);

drop policy if exists "players can read own profile" on public.players;
create policy "players can read own profile" on public.players
  for select using (auth.uid() = id);

drop policy if exists "players can create own profile" on public.players;
create policy "players can create own profile" on public.players
  for insert with check (auth.uid() = id);

drop policy if exists "players can update own profile" on public.players;
create policy "players can update own profile" on public.players
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "player seasons readable by owner" on public.player_seasons;
create policy "player seasons readable by owner" on public.player_seasons
  for select using (auth.uid() = player_id);

drop policy if exists "clans readable" on public.clans;
create policy "clans readable" on public.clans for select using (true);

drop policy if exists "clan members readable" on public.clan_members;
create policy "clan members readable" on public.clan_members for select using (true);

drop policy if exists "street ownership readable" on public.street_ownership;
create policy "street ownership readable" on public.street_ownership
  for select using (true);

drop policy if exists "personal discoveries readable by owner" on public.personal_discoveries;
create policy "personal discoveries readable by owner" on public.personal_discoveries
  for select using (auth.uid() = player_id);

drop policy if exists "scan events readable by owner" on public.scan_events;
create policy "scan events readable by owner" on public.scan_events
  for select using (auth.uid() = player_id);

-- Realtime pour que la carte de conquête se mette à jour sur tous les téléphones.
alter table public.street_ownership replica identity full;
alter table public.personal_discoveries replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.street_ownership;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.personal_discoveries;
exception when duplicate_object then null;
end $$;

create or replace function public.active_season_id()
returns text
language sql
stable
as $$
  select id from public.seasons where is_active = true order by starts_at desc limit 1;
$$;

drop function if exists public.choose_team(text);
create or replace function public.choose_team(p_team_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_season_id text;
  v_existing_team text;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;

  select * into v_player from public.players where id = auth.uid();
  if not found then
    return jsonb_build_object('accepted', false, 'message', 'Profil joueur introuvable.');
  end if;

  if not exists (select 1 from public.teams where id = p_team_id) then
    return jsonb_build_object('accepted', false, 'message', 'Équipe inconnue.');
  end if;

  v_season_id := public.active_season_id();
  if v_season_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Aucune saison active.');
  end if;

  select team_id into v_existing_team
  from public.player_seasons
  where player_id = v_player.id and season_id = v_season_id;

  if v_existing_team is not null and v_existing_team <> p_team_id then
    return jsonb_build_object('accepted', false, 'message', 'Équipe déjà choisie pour cette saison.');
  end if;

  insert into public.player_seasons (player_id, season_id, team_id)
  values (v_player.id, v_season_id, p_team_id)
  on conflict (player_id, season_id) do nothing;

  update public.players
  set team_id = p_team_id, updated_at = now()
  where id = v_player.id;

  return jsonb_build_object('accepted', true, 'message', 'Équipe choisie.', 'team_id', p_team_id);
end;
$$;

drop function if exists public.create_clan(text, text);
create or replace function public.create_clan(p_name text, p_tag text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_tag text;
  v_clan_id uuid;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;
  select * into v_player from public.players where id = auth.uid();
  if not found then
    return jsonb_build_object('accepted', false, 'message', 'Profil joueur introuvable.');
  end if;
  if v_player.team_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Choisis une équipe avant de créer un clan.');
  end if;
  if v_player.clan_id is not null then
    return jsonb_build_object('accepted', false, 'message', 'Tu es déjà dans un clan.');
  end if;

  v_tag := upper(regexp_replace(trim(p_tag), '[^A-Za-z0-9]', '', 'g'));
  if length(trim(p_name)) < 3 then
    return jsonb_build_object('accepted', false, 'message', 'Nom de clan trop court.');
  end if;
  if length(v_tag) < 2 or length(v_tag) > 8 then
    return jsonb_build_object('accepted', false, 'message', 'Tag de clan invalide.');
  end if;

  insert into public.clans (name, tag, team_id, owner_player_id)
  values (left(trim(p_name), 40), v_tag, v_player.team_id, v_player.id)
  returning id into v_clan_id;

  insert into public.clan_members (clan_id, player_id, role)
  values (v_clan_id, v_player.id, 'owner');

  update public.players set clan_id = v_clan_id, updated_at = now() where id = v_player.id;

  return jsonb_build_object('accepted', true, 'message', 'Clan créé.', 'clan_id', v_clan_id);
exception when unique_violation then
  return jsonb_build_object('accepted', false, 'message', 'Ce tag de clan existe déjà.');
end;
$$;

drop function if exists public.join_clan(text);
create or replace function public.join_clan(p_tag text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_clan public.clans%rowtype;
  v_tag text;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;
  select * into v_player from public.players where id = auth.uid();
  if not found then
    return jsonb_build_object('accepted', false, 'message', 'Profil joueur introuvable.');
  end if;
  if v_player.team_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Choisis une équipe avant de rejoindre un clan.');
  end if;
  if v_player.clan_id is not null then
    return jsonb_build_object('accepted', false, 'message', 'Tu es déjà dans un clan.');
  end if;

  v_tag := upper(regexp_replace(trim(p_tag), '[^A-Za-z0-9]', '', 'g'));
  select * into v_clan from public.clans where tag = v_tag;
  if not found then
    return jsonb_build_object('accepted', false, 'message', 'Clan introuvable.');
  end if;
  if v_clan.team_id <> v_player.team_id then
    return jsonb_build_object('accepted', false, 'message', 'Ce clan appartient à une autre équipe.');
  end if;

  insert into public.clan_members (clan_id, player_id, role)
  values (v_clan.id, v_player.id, 'member');
  update public.players set clan_id = v_clan.id, updated_at = now() where id = v_player.id;

  return jsonb_build_object('accepted', true, 'message', 'Clan rejoint.', 'clan_id', v_clan.id);
end;
$$;

drop function if exists public.leave_clan();
create or replace function public.leave_clan()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_role text;
  v_member_count integer;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;
  select * into v_player from public.players where id = auth.uid();
  if not found or v_player.clan_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Aucun clan à quitter.');
  end if;

  select role into v_role from public.clan_members where clan_id = v_player.clan_id and player_id = v_player.id;
  select count(*) into v_member_count from public.clan_members where clan_id = v_player.clan_id;

  if v_role = 'owner' and v_member_count > 1 then
    return jsonb_build_object('accepted', false, 'message', 'Le chef ne peut pas quitter un clan qui contient encore des membres.');
  end if;

  if v_role = 'owner' then
    delete from public.clans where id = v_player.clan_id;
  else
    delete from public.clan_members where clan_id = v_player.clan_id and player_id = v_player.id;
    update public.players set clan_id = null, updated_at = now() where id = v_player.id;
  end if;

  return jsonb_build_object('accepted', true, 'message', 'Clan quitté.');
end;
$$;

drop function if exists public.capture_street(text, text, double precision, double precision, double precision);
create or replace function public.capture_street(
  p_season_id text,
  p_street_id text,
  p_distance_meters double precision,
  p_ocr_score double precision,
  p_plate_score double precision
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_previous_team_id text;
  v_is_active boolean;
  v_reason text;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;

  select * into v_player from public.players where id = auth.uid();
  if not found then
    return jsonb_build_object('accepted', false, 'message', 'Profil joueur introuvable.');
  end if;

  if v_player.team_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Aucune équipe choisie.');
  end if;

  select is_active into v_is_active from public.seasons where id = p_season_id;
  if coalesce(v_is_active, false) is false then
    return jsonb_build_object('accepted', false, 'message', 'Saison inactive.');
  end if;

  if coalesce(length(trim(p_street_id)), 0) = 0 then
    v_reason := 'Rue invalide.';
  elsif p_distance_meters is null or p_distance_meters > 80 then
    v_reason := 'Rue trop éloignée.';
  elsif p_ocr_score < 0.80 then
    v_reason := 'Score OCR insuffisant.';
  elsif p_plate_score < 0.35 then
    v_reason := 'Plaque trop peu probable.';
  end if;

  if v_reason is not null then
    insert into public.scan_events (
      season_id, street_id, player_id, team_id,
      distance_meters, ocr_score, plate_score,
      accepted, rejection_reason
    ) values (
      p_season_id, p_street_id, v_player.id, v_player.team_id,
      p_distance_meters, p_ocr_score, p_plate_score,
      false, v_reason
    );

    return jsonb_build_object('accepted', false, 'message', v_reason);
  end if;

  select team_id into v_previous_team_id
  from public.street_ownership
  where season_id = p_season_id and street_id = p_street_id;

  insert into public.scan_events (
    season_id, street_id, player_id, team_id, previous_team_id,
    distance_meters, ocr_score, plate_score, accepted
  ) values (
    p_season_id, p_street_id, v_player.id, v_player.team_id, v_previous_team_id,
    p_distance_meters, p_ocr_score, p_plate_score, true
  );

  insert into public.personal_discoveries (season_id, player_id, street_id, discovered_at)
  values (p_season_id, v_player.id, p_street_id, now())
  on conflict (season_id, player_id, street_id) do nothing;

  insert into public.street_ownership (
    season_id, street_id, team_id, captured_by, captured_at, capture_count
  ) values (
    p_season_id, p_street_id, v_player.team_id, v_player.id, now(), 1
  )
  on conflict (season_id, street_id) do update set
    team_id = excluded.team_id,
    captured_by = excluded.captured_by,
    captured_at = now(),
    capture_count = public.street_ownership.capture_count + 1;

  return jsonb_build_object(
    'accepted', true,
    'message', 'Rue capturée pour ton équipe.',
    'team_id', v_player.team_id,
    'previous_team_id', v_previous_team_id
  );
end;
$$;

grant execute on function public.choose_team(text) to authenticated;
grant execute on function public.create_clan(text, text) to authenticated;
grant execute on function public.join_clan(text) to authenticated;
grant execute on function public.leave_clan() to authenticated;
grant execute on function public.capture_street(text, text, double precision, double precision, double precision) to authenticated;
