-- RueDex V3 - Base Supabase minimale pour saisons, équipes et captures.
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

create table if not exists public.clans (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tag text not null,
  owner_player_id uuid not null references public.players(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (tag)
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

create table if not exists public.clan_members (
  clan_id uuid not null references public.clans(id) on delete cascade,
  player_id uuid not null references public.players(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (clan_id, player_id)
);

create table if not exists public.street_ownership (
  season_id text not null references public.seasons(id) on delete cascade,
  street_id text not null,
  team_id text not null references public.teams(id),
  captured_by uuid not null references public.players(id) on delete cascade,
  captured_at timestamptz not null default now(),
  capture_count integer not null default 1,
  primary key (season_id, street_id)
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
alter table public.clans enable row level security;
alter table public.clan_members enable row level security;
alter table public.street_ownership enable row level security;
alter table public.scan_events enable row level security;

drop policy if exists "teams readable" on public.teams;
create policy "teams readable" on public.teams
  for select using (true);

drop policy if exists "seasons readable" on public.seasons;
create policy "seasons readable" on public.seasons
  for select using (true);

drop policy if exists "players can read own profile" on public.players;
create policy "players can read own profile" on public.players
  for select using (auth.uid() = id);

drop policy if exists "players can create own profile" on public.players;
create policy "players can create own profile" on public.players
  for insert with check (auth.uid() = id);

drop policy if exists "players can update own profile" on public.players;
create policy "players can update own profile" on public.players
  for update using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "street ownership readable" on public.street_ownership;
create policy "street ownership readable" on public.street_ownership
  for select using (true);

drop policy if exists "scan events readable by owner" on public.scan_events;
create policy "scan events readable by owner" on public.scan_events
  for select using (auth.uid() = player_id);

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

grant execute on function public.capture_street(text, text, double precision, double precision, double precision) to authenticated;
