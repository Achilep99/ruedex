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

-- RueDex V4.2 - collection par compte, clans avancés, chat, scores et recherche.

alter table public.clans add column if not exists min_discoveries integer not null default 0;
alter table public.clans add column if not exists member_count integer not null default 1;
alter table public.clans add column if not exists score integer not null default 0;
alter table public.clans add column if not exists level integer not null default 1;

create table if not exists public.player_scores (
  season_id text not null references public.seasons(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  personal_score integer not null default 0,
  conquest_score integer not null default 0,
  clan_score integer not null default 0,
  personal_discoveries integer not null default 0,
  conquest_captures integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (season_id, player_id)
);

create table if not exists public.clan_messages (
  id uuid primary key default gen_random_uuid(),
  clan_id uuid not null references public.clans(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  content text not null,
  reported boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.clan_message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.clan_messages(id) on delete cascade,
  clan_id uuid not null references public.clans(id) on delete cascade,
  reported_by uuid not null references public.players(id) on delete cascade,
  reason text not null default 'Signalé depuis l’application',
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  unique (message_id, reported_by)
);

create table if not exists public.clan_journal (
  id uuid primary key default gen_random_uuid(),
  clan_id uuid not null references public.clans(id) on delete cascade,
  event_type text not null,
  message text not null,
  created_at timestamptz not null default now()
);

alter table public.player_scores enable row level security;
alter table public.clan_messages enable row level security;
alter table public.clan_message_reports enable row level security;
alter table public.clan_journal enable row level security;

drop policy if exists "players public profile readable" on public.players;
create policy "players public profile readable" on public.players
  for select using (true);

drop policy if exists "player scores readable by owner" on public.player_scores;
create policy "player scores readable by owner" on public.player_scores
  for select using (auth.uid() = player_id);

drop policy if exists "clan messages readable by clan members" on public.clan_messages;
create policy "clan messages readable by clan members" on public.clan_messages
  for select using (
    exists (
      select 1 from public.clan_members member
      where member.clan_id = clan_messages.clan_id
        and member.player_id = auth.uid()
    )
  );

drop policy if exists "clan reports readable by reporter" on public.clan_message_reports;
create policy "clan reports readable by reporter" on public.clan_message_reports
  for select using (auth.uid() = reported_by);

drop policy if exists "clan journal readable by members" on public.clan_journal;
create policy "clan journal readable by members" on public.clan_journal
  for select using (
    exists (
      select 1 from public.clan_members member
      where member.clan_id = clan_journal.clan_id
        and member.player_id = auth.uid()
    )
  );

alter table public.clan_messages replica identity full;
alter table public.clan_journal replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.clan_messages;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.clan_journal;
exception when duplicate_object then null;
end $$;

-- Met à jour les compteurs existants si le script est relancé sur une base déjà utilisée.
update public.clans clan
set member_count = greatest(1, coalesce(counts.count, 0))
from (
  select clan_id, count(*)::integer as count
  from public.clan_members
  group by clan_id
) counts
where counts.clan_id = clan.id;

-- Nouvelle version de create_clan avec prérequis.
drop function if exists public.create_clan(text, text);
drop function if exists public.create_clan(text, text, integer);
create or replace function public.create_clan(
  p_name text,
  p_tag text,
  p_min_discoveries integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_tag text;
  v_clan_id uuid;
  v_min integer;
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
  v_min := greatest(0, least(coalesce(p_min_discoveries, 0), 9999));

  if length(trim(p_name)) < 3 then
    return jsonb_build_object('accepted', false, 'message', 'Nom de clan trop court.');
  end if;
  if length(v_tag) < 2 or length(v_tag) > 8 then
    return jsonb_build_object('accepted', false, 'message', 'Tag de clan invalide.');
  end if;

  insert into public.clans (
    name, tag, team_id, owner_player_id, min_discoveries, member_count
  ) values (
    left(trim(p_name), 40), v_tag, v_player.team_id, v_player.id, v_min, 1
  ) returning id into v_clan_id;

  insert into public.clan_members (clan_id, player_id, role)
  values (v_clan_id, v_player.id, 'owner');

  update public.players set clan_id = v_clan_id, updated_at = now() where id = v_player.id;

  return jsonb_build_object('accepted', true, 'message', 'Clan créé.', 'clan_id', v_clan_id);
exception when unique_violation then
  return jsonb_build_object('accepted', false, 'message', 'Ce tag de clan existe déjà.');
end;
$$;

-- Nouvelle version de join_clan avec prérequis et équipe obligatoire.
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
  v_season_id text;
  v_discoveries integer;
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

  v_season_id := public.active_season_id();
  select count(*)::integer into v_discoveries
  from public.personal_discoveries
  where player_id = v_player.id
    and season_id = v_season_id;

  if coalesce(v_discoveries, 0) < coalesce(v_clan.min_discoveries, 0) then
    return jsonb_build_object(
      'accepted', false,
      'message', 'Ce clan demande au moins ' || v_clan.min_discoveries || ' rues découvertes.'
    );
  end if;

  insert into public.clan_members (clan_id, player_id, role)
  values (v_clan.id, v_player.id, 'member');
  update public.players set clan_id = v_clan.id, updated_at = now() where id = v_player.id;
  update public.clans set member_count = member_count + 1 where id = v_clan.id;

  return jsonb_build_object('accepted', true, 'message', 'Clan rejoint.', 'clan_id', v_clan.id);
end;
$$;

-- Quitter le clan en maintenant les compteurs.
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
  select count(*)::integer into v_member_count from public.clan_members where clan_id = v_player.clan_id;

  if v_role = 'owner' and v_member_count > 1 then
    return jsonb_build_object('accepted', false, 'message', 'Le chef ne peut pas quitter un clan qui contient encore des membres.');
  end if;

  if v_role = 'owner' then
    delete from public.clans where id = v_player.clan_id;
  else
    delete from public.clan_members where clan_id = v_player.clan_id and player_id = v_player.id;
    update public.players set clan_id = null, updated_at = now() where id = v_player.id;
    update public.clans set member_count = greatest(0, member_count - 1) where id = v_player.clan_id;
  end if;

  return jsonb_build_object('accepted', true, 'message', 'Clan quitté.');
end;
$$;


-- Le chef peut modifier les paramètres simples du clan.
drop function if exists public.update_clan_settings(integer);
create or replace function public.update_clan_settings(p_min_discoveries integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_min integer;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;

  select * into v_player from public.players where id = auth.uid();
  if not found or v_player.clan_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Tu n’es pas dans un clan.');
  end if;

  if not exists (
    select 1 from public.clan_members
    where clan_id = v_player.clan_id and player_id = v_player.id and role = 'owner'
  ) then
    return jsonb_build_object('accepted', false, 'message', 'Seul le chef peut modifier les paramètres du clan.');
  end if;

  v_min := greatest(0, least(coalesce(p_min_discoveries, 0), 9999));
  update public.clans
  set min_discoveries = v_min,
      updated_at = now()
  where id = v_player.clan_id;

  return jsonb_build_object('accepted', true, 'message', 'Paramètres du clan mis à jour.');
end;
$$;

-- Le chef peut expulser un membre de son clan.
drop function if exists public.kick_clan_member(uuid);
create or replace function public.kick_clan_member(p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner public.players%rowtype;
  v_target_role text;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;

  select * into v_owner from public.players where id = auth.uid();
  if not found or v_owner.clan_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Tu n’es pas dans un clan.');
  end if;

  if not exists (
    select 1 from public.clan_members
    where clan_id = v_owner.clan_id and player_id = v_owner.id and role = 'owner'
  ) then
    return jsonb_build_object('accepted', false, 'message', 'Seul le chef peut supprimer un membre.');
  end if;

  if p_player_id = v_owner.id then
    return jsonb_build_object('accepted', false, 'message', 'Le chef ne peut pas se supprimer lui-même.');
  end if;

  select role into v_target_role
  from public.clan_members
  where clan_id = v_owner.clan_id and player_id = p_player_id;

  if v_target_role is null then
    return jsonb_build_object('accepted', false, 'message', 'Membre introuvable.');
  end if;
  if v_target_role = 'owner' then
    return jsonb_build_object('accepted', false, 'message', 'Impossible de supprimer le chef.');
  end if;

  delete from public.clan_members where clan_id = v_owner.clan_id and player_id = p_player_id;
  update public.players set clan_id = null, updated_at = now() where id = p_player_id;
  update public.clans set member_count = greatest(0, member_count - 1) where id = v_owner.clan_id;

  return jsonb_build_object('accepted', true, 'message', 'Membre supprimé.');
end;
$$;

-- Chat : insertion + nettoyage des vieux messages non signalés.
drop function if exists public.post_clan_message(text);
create or replace function public.post_clan_message(p_content text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_content text;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;
  select * into v_player from public.players where id = auth.uid();
  if not found or v_player.clan_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Tu n’es dans aucun clan.');
  end if;

  v_content := trim(coalesce(p_content, ''));
  if length(v_content) < 1 then
    return jsonb_build_object('accepted', false, 'message', 'Message vide.');
  end if;
  if length(v_content) > 500 then
    return jsonb_build_object('accepted', false, 'message', 'Message trop long.');
  end if;

  insert into public.clan_messages (clan_id, player_id, content)
  values (v_player.clan_id, v_player.id, left(v_content, 500));

  delete from public.clan_messages message
  where message.clan_id = v_player.clan_id
    and message.reported = false
    and message.created_at < now() - interval '2 days';

  delete from public.clan_messages message
  where message.clan_id = v_player.clan_id
    and message.reported = false
    and message.id not in (
      select kept.id
      from public.clan_messages kept
      where kept.clan_id = v_player.clan_id
        and kept.reported = false
      order by kept.created_at desc
      limit 50
    );

  return jsonb_build_object('accepted', true, 'message', 'Message envoyé.');
end;
$$;

-- Signaler un message : le message ne sera plus nettoyé automatiquement.
drop function if exists public.report_clan_message(uuid, text);
create or replace function public.report_clan_message(p_message_id uuid, p_reason text default 'Signalé depuis l’application')
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_player public.players%rowtype;
  v_message public.clan_messages%rowtype;
begin
  if auth.uid() is null then
    return jsonb_build_object('accepted', false, 'message', 'Joueur non connecté.');
  end if;
  select * into v_player from public.players where id = auth.uid();
  if not found or v_player.clan_id is null then
    return jsonb_build_object('accepted', false, 'message', 'Tu n’es dans aucun clan.');
  end if;

  select * into v_message from public.clan_messages where id = p_message_id;
  if not found or v_message.clan_id <> v_player.clan_id then
    return jsonb_build_object('accepted', false, 'message', 'Message introuvable dans ton clan.');
  end if;

  insert into public.clan_message_reports (message_id, clan_id, reported_by, reason)
  values (v_message.id, v_message.clan_id, v_player.id, left(trim(coalesce(p_reason, 'Signalé')), 200))
  on conflict (message_id, reported_by) do nothing;

  update public.clan_messages set reported = true where id = v_message.id;

  return jsonb_build_object('accepted', true, 'message', 'Message signalé.');
end;
$$;

-- Capture avec collection par compte, score perso, score clan et carte conquête.
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
  v_personal_new boolean;
  v_old_clan_score integer;
  v_new_clan_score integer;
  v_old_level integer;
  v_new_level integer;
  v_clan_gain integer := 5;
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

  v_personal_new := not exists (
    select 1 from public.personal_discoveries
    where season_id = p_season_id
      and player_id = v_player.id
      and street_id = p_street_id
  );

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

  insert into public.player_scores (
    season_id, player_id,
    personal_score, conquest_score, clan_score,
    personal_discoveries, conquest_captures, updated_at
  ) values (
    p_season_id, v_player.id,
    case when v_personal_new then 10 else 0 end,
    5,
    case when v_player.clan_id is null then 0 else v_clan_gain end,
    case when v_personal_new then 1 else 0 end,
    1,
    now()
  ) on conflict (season_id, player_id) do update set
    personal_score = public.player_scores.personal_score + case when v_personal_new then 10 else 0 end,
    conquest_score = public.player_scores.conquest_score + 5,
    clan_score = public.player_scores.clan_score + case when v_player.clan_id is null then 0 else v_clan_gain end,
    personal_discoveries = public.player_scores.personal_discoveries + case when v_personal_new then 1 else 0 end,
    conquest_captures = public.player_scores.conquest_captures + 1,
    updated_at = now();

  if v_player.clan_id is not null then
    select score, level into v_old_clan_score, v_old_level
    from public.clans
    where id = v_player.clan_id;

    update public.clans
    set score = score + v_clan_gain,
        level = greatest(1, floor((score + v_clan_gain) / 1000.0)::integer + 1)
    where id = v_player.clan_id
    returning score, level into v_new_clan_score, v_new_level;

    if coalesce(v_new_level, 1) > coalesce(v_old_level, 1) then
      insert into public.clan_journal (clan_id, event_type, message)
      values (v_player.clan_id, 'level', 'Le clan atteint le niveau ' || v_new_level || '.');
    elsif floor(coalesce(v_old_clan_score, 0) / 1000.0)::integer < floor(coalesce(v_new_clan_score, 0) / 1000.0)::integer then
      insert into public.clan_journal (clan_id, event_type, message)
      values (
        v_player.clan_id,
        'score',
        'Le clan atteint ' || ((floor(v_new_clan_score / 1000.0)::integer) * 1000)::text || ' points.'
      );
    end if;
  end if;

  return jsonb_build_object(
    'accepted', true,
    'message', 'Rue capturée pour ton équipe.',
    'team_id', v_player.team_id,
    'previous_team_id', v_previous_team_id,
    'personal_discovery_new', v_personal_new
  );
end;
$$;

grant execute on function public.create_clan(text, text, integer) to authenticated;
grant execute on function public.update_clan_settings(integer) to authenticated;
grant execute on function public.kick_clan_member(uuid) to authenticated;
grant execute on function public.post_clan_message(text) to authenticated;
grant execute on function public.report_clan_message(uuid, text) to authenticated;
grant execute on function public.capture_street(text, text, double precision, double precision, double precision) to authenticated;
