-- =============================================================================
-- Agenda Inteligente (PokulAI) — esquema de nuvem com RLS
--
-- Modelo: cada "organização" é uma agenda compartilhada (pessoal ou de equipe).
--   * admin  (gestor): vê e edita tudo da organização, cadastra profissionais e convida membros
--   * member (médico): vê locais e profissionais da organização, mas só vê/edita os PRÓPRIOS lançamentos
-- O papel fica em agenda_members (servidor), nunca em dados enviados pelo cliente.
-- Todas as tabelas usam o prefixo agenda_ para conviver com outros apps no mesmo projeto.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Tabelas
-- -----------------------------------------------------------------------------
create table if not exists public.agenda_orgs (
    id          uuid primary key default gen_random_uuid(),
    name        text not null check (char_length(name) between 1 and 120),
    created_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
    created_at  timestamptz not null default now()
);

create table if not exists public.agenda_professionals (
    org_id      uuid not null references public.agenda_orgs(id) on delete cascade,
    id          bigint not null,
    name        text not null check (char_length(name) between 1 and 120),
    spec        text not null default '' check (char_length(spec) <= 120),
    crm         text not null default '' check (char_length(crm) <= 40),
    email       text not null default '' check (char_length(email) <= 200),
    updated_at  timestamptz not null default now(),
    primary key (org_id, id)
);

create table if not exists public.agenda_members (
    org_id      uuid not null references public.agenda_orgs(id) on delete cascade,
    user_id     uuid not null references auth.users(id) on delete cascade,
    role        text not null default 'member' check (role in ('admin', 'member')),
    prof_id     bigint,
    created_at  timestamptz not null default now(),
    primary key (org_id, user_id),
    foreign key (org_id, prof_id) references public.agenda_professionals(org_id, id) on delete set null (prof_id)
);

create table if not exists public.agenda_invites (
    org_id      uuid not null references public.agenda_orgs(id) on delete cascade,
    email       text not null check (email = lower(email) and email like '%@%' and char_length(email) <= 200),
    role        text not null default 'member' check (role in ('admin', 'member')),
    prof_id     bigint,
    invited_by  uuid not null default auth.uid() references auth.users(id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (org_id, email),
    foreign key (org_id, prof_id) references public.agenda_professionals(org_id, id) on delete cascade
);

create table if not exists public.agenda_locations (
    org_id       uuid not null references public.agenda_orgs(id) on delete cascade,
    id           bigint not null,
    name         text not null check (char_length(name) between 1 and 120),
    city         text not null default '' check (char_length(city) <= 120),
    lat          double precision check (lat between -90 and 90),
    lng          double precision check (lng between -180 and 180),
    loc_type     text not null default 'plantao' check (loc_type in ('plantao', 'exame', 'cliente', 'outro')),
    hourly_rate  numeric(10, 2) not null default 0 check (hourly_rate >= 0),
    exam_rate    numeric(10, 2) not null default 0 check (exam_rate >= 0),
    shift_hours  numeric(5, 2) not null default 0 check (shift_hours between 0 and 48),
    shift_start  smallint check (shift_start between 0 and 1439),
    color_class  text not null default 'bg-blue-600' check (char_length(color_class) <= 60),
    dot_color    text not null default 'blue' check (char_length(dot_color) <= 20),
    updated_at   timestamptz not null default now(),
    primary key (org_id, id)
);

create table if not exists public.agenda_events (
    org_id       uuid not null references public.agenda_orgs(id) on delete cascade,
    id           bigint not null,
    prof_id      bigint not null,
    loc_id       bigint not null,
    day          date not null,
    text         text not null default '' check (char_length(text) <= 300),
    type         text not null default 'plantao' check (type in ('plantao', 'exame', 'cliente', 'outro')),
    hours        numeric(5, 2) not null default 0 check (hours between 0 and 24),
    exams_count  integer not null default 0 check (exams_count between 0 and 10000),
    group_id     bigint,
    start_min    smallint check (start_min between 0 and 1440),
    end_min      smallint check (end_min between 0 and 2880),
    updated_at   timestamptz not null default now(),
    updated_by   uuid default auth.uid() references auth.users(id) on delete set null,
    primary key (org_id, id),
    foreign key (org_id, prof_id) references public.agenda_professionals(org_id, id) on delete cascade,
    foreign key (org_id, loc_id) references public.agenda_locations(org_id, id) on delete cascade
);

create index if not exists agenda_events_org_day_idx on public.agenda_events (org_id, day);
create index if not exists agenda_events_org_prof_day_idx on public.agenda_events (org_id, prof_id, day);
create index if not exists agenda_events_org_loc_idx on public.agenda_events (org_id, loc_id);
create index if not exists agenda_members_user_idx on public.agenda_members (user_id);
create index if not exists agenda_members_org_prof_idx on public.agenda_members (org_id, prof_id);
create index if not exists agenda_invites_email_idx on public.agenda_invites (email);
create index if not exists agenda_invites_org_prof_idx on public.agenda_invites (org_id, prof_id);
create index if not exists agenda_orgs_created_by_idx on public.agenda_orgs (created_by);
create index if not exists agenda_events_updated_by_idx on public.agenda_events (updated_by);
create index if not exists agenda_invites_invited_by_idx on public.agenda_invites (invited_by);

create table if not exists public.agenda_user_settings (
    user_id     uuid primary key default auth.uid() references auth.users(id) on delete cascade,
    data        jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object' and pg_column_size(data) < 20000),
    updated_at  timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- updated_at automático
-- -----------------------------------------------------------------------------
create or replace function public.agenda_touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

do $$
declare t text;
begin
    foreach t in array array['agenda_professionals', 'agenda_locations', 'agenda_events', 'agenda_user_settings'] loop
        execute format('drop trigger if exists %I_touch on public.%I', t, t);
        execute format('create trigger %I_touch before update on public.%I for each row execute function public.agenda_touch_updated_at()', t, t);
    end loop;
end $$;

-- Quem alterou o lançamento é sempre o usuário autenticado (não pode ser forjado)
create or replace function public.agenda_events_set_author()
returns trigger language plpgsql set search_path = '' as $$
begin
    new.updated_by := auth.uid();
    return new;
end;
$$;
drop trigger if exists agenda_events_author on public.agenda_events;
create trigger agenda_events_author before insert or update on public.agenda_events
    for each row execute function public.agenda_events_set_author();

-- -----------------------------------------------------------------------------
-- Funções auxiliares para RLS (security definer evita recursão nas políticas)
-- -----------------------------------------------------------------------------
create or replace function public.agenda_is_member(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
    select exists (select 1 from public.agenda_members m where m.org_id = p_org and m.user_id = (select auth.uid()));
$$;

create or replace function public.agenda_is_admin(p_org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
    select exists (select 1 from public.agenda_members m where m.org_id = p_org and m.user_id = (select auth.uid()) and m.role = 'admin');
$$;

create or replace function public.agenda_my_prof(p_org uuid)
returns bigint language sql stable security definer set search_path = '' as $$
    select m.prof_id from public.agenda_members m where m.org_id = p_org and m.user_id = (select auth.uid());
$$;

-- Impede que a organização fique sem nenhum administrador
create or replace function public.agenda_keep_one_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if old.role = 'admin' and (tg_op = 'DELETE' or new.role <> 'admin') then
        -- Exclusão em cascata da própria organização é permitida
        if tg_op = 'DELETE' and not exists (select 1 from public.agenda_orgs o where o.id = old.org_id) then
            return old;
        end if;
        if not exists (select 1 from public.agenda_members m where m.org_id = old.org_id and m.role = 'admin' and m.user_id <> old.user_id) then
            raise exception 'A organização precisa de pelo menos um administrador.';
        end if;
    end if;
    return case when tg_op = 'DELETE' then old else new end;
end;
$$;
drop trigger if exists agenda_members_keep_admin on public.agenda_members;
create trigger agenda_members_keep_admin before update or delete on public.agenda_members
    for each row execute function public.agenda_keep_one_admin();

-- -----------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------
-- Cria uma organização e torna o usuário atual administrador dela
create or replace function public.agenda_create_org(p_name text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
    v_uid uuid := auth.uid();
    v_org uuid;
begin
    if v_uid is null then raise exception 'Não autenticado.'; end if;
    if (select count(*) from public.agenda_orgs o where o.created_by = v_uid) >= 10 then
        raise exception 'Limite de organizações atingido.';
    end if;
    insert into public.agenda_orgs (name, created_by) values (left(coalesce(nullif(trim(p_name), ''), 'Minha agenda'), 120), v_uid)
        returning id into v_org;
    insert into public.agenda_members (org_id, user_id, role) values (v_org, v_uid, 'admin');
    return v_org;
end;
$$;

-- Aceita convites pendentes para o e-mail CONFIRMADO do usuário atual
create or replace function public.agenda_accept_invites()
returns integer language plpgsql security definer set search_path = '' as $$
declare
    v_uid uuid := auth.uid();
    v_email text;
    v_count integer := 0;
    r record;
begin
    if v_uid is null then return 0; end if;
    select lower(u.email) into v_email from auth.users u where u.id = v_uid and u.email_confirmed_at is not null;
    if v_email is null then return 0; end if;
    for r in select * from public.agenda_invites i where i.email = v_email loop
        insert into public.agenda_members (org_id, user_id, role, prof_id)
            values (r.org_id, v_uid, r.role, r.prof_id)
            on conflict (org_id, user_id) do update set prof_id = coalesce(public.agenda_members.prof_id, excluded.prof_id);
        delete from public.agenda_invites i where i.org_id = r.org_id and i.email = r.email;
        v_count := v_count + 1;
    end loop;
    return v_count;
end;
$$;

-- Membro sem profissional vinculado cria o próprio cadastro (não precisa ser admin)
create or replace function public.agenda_claim_professional(p_org uuid, p_id bigint, p_name text, p_crm text default '', p_spec text default '')
returns bigint language plpgsql security definer set search_path = '' as $$
declare
    v_uid uuid := auth.uid();
    v_email text;
begin
    if not exists (select 1 from public.agenda_members m where m.org_id = p_org and m.user_id = v_uid) then
        raise exception 'Sem acesso a esta organização.';
    end if;
    if (select m.prof_id from public.agenda_members m where m.org_id = p_org and m.user_id = v_uid) is not null then
        raise exception 'Você já está vinculado a um profissional.';
    end if;
    select coalesce(u.email, '') into v_email from auth.users u where u.id = v_uid;
    insert into public.agenda_professionals (org_id, id, name, crm, spec, email)
        values (p_org, p_id, left(coalesce(nullif(trim(p_name), ''), 'Profissional'), 120), left(coalesce(p_crm, ''), 40), left(coalesce(p_spec, ''), 120), left(v_email, 200));
    update public.agenda_members m set prof_id = p_id where m.org_id = p_org and m.user_id = v_uid;
    return p_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Permissões e RLS
-- -----------------------------------------------------------------------------
revoke all on public.agenda_orgs, public.agenda_members, public.agenda_invites, public.agenda_professionals,
              public.agenda_locations, public.agenda_events, public.agenda_user_settings from anon, public;
grant select, insert, update, delete on public.agenda_orgs, public.agenda_members, public.agenda_invites, public.agenda_professionals,
              public.agenda_locations, public.agenda_events, public.agenda_user_settings to authenticated;

revoke execute on function public.agenda_is_member(uuid), public.agenda_is_admin(uuid), public.agenda_my_prof(uuid),
    public.agenda_create_org(text), public.agenda_accept_invites(), public.agenda_claim_professional(uuid, bigint, text, text, text),
    public.agenda_keep_one_admin(), public.agenda_touch_updated_at(), public.agenda_events_set_author() from public, anon;
grant execute on function public.agenda_is_member(uuid), public.agenda_is_admin(uuid), public.agenda_my_prof(uuid),
    public.agenda_create_org(text), public.agenda_accept_invites(), public.agenda_claim_professional(uuid, bigint, text, text, text) to authenticated;

alter table public.agenda_orgs enable row level security;
alter table public.agenda_members enable row level security;
alter table public.agenda_invites enable row level security;
alter table public.agenda_professionals enable row level security;
alter table public.agenda_locations enable row level security;
alter table public.agenda_events enable row level security;
alter table public.agenda_user_settings enable row level security;

-- Organizações: membros leem; admin renomeia/exclui; criação só via agenda_create_org
drop policy if exists agenda_orgs_select on public.agenda_orgs;
create policy agenda_orgs_select on public.agenda_orgs for select to authenticated using (public.agenda_is_member(id));
drop policy if exists agenda_orgs_update on public.agenda_orgs;
create policy agenda_orgs_update on public.agenda_orgs for update to authenticated using (public.agenda_is_admin(id)) with check (public.agenda_is_admin(id));
drop policy if exists agenda_orgs_delete on public.agenda_orgs;
create policy agenda_orgs_delete on public.agenda_orgs for delete to authenticated using (public.agenda_is_admin(id));

-- Membros: membros veem a equipe; só admin altera
drop policy if exists agenda_members_select on public.agenda_members;
create policy agenda_members_select on public.agenda_members for select to authenticated using (public.agenda_is_member(org_id));
drop policy if exists agenda_members_insert on public.agenda_members;
create policy agenda_members_insert on public.agenda_members for insert to authenticated with check (public.agenda_is_admin(org_id));
drop policy if exists agenda_members_update on public.agenda_members;
create policy agenda_members_update on public.agenda_members for update to authenticated using (public.agenda_is_admin(org_id)) with check (public.agenda_is_admin(org_id));
drop policy if exists agenda_members_delete on public.agenda_members;
create policy agenda_members_delete on public.agenda_members for delete to authenticated using (public.agenda_is_admin(org_id) or user_id = (select auth.uid()));

-- Convites: só admin
drop policy if exists agenda_invites_all on public.agenda_invites;
create policy agenda_invites_all on public.agenda_invites for all to authenticated using (public.agenda_is_admin(org_id)) with check (public.agenda_is_admin(org_id));

-- Profissionais: membros leem; admin gerencia; o próprio médico atualiza seu cadastro
drop policy if exists agenda_prof_select on public.agenda_professionals;
create policy agenda_prof_select on public.agenda_professionals for select to authenticated using (public.agenda_is_member(org_id));
drop policy if exists agenda_prof_insert on public.agenda_professionals;
create policy agenda_prof_insert on public.agenda_professionals for insert to authenticated with check (public.agenda_is_admin(org_id));
drop policy if exists agenda_prof_update on public.agenda_professionals;
create policy agenda_prof_update on public.agenda_professionals for update to authenticated
    using (public.agenda_is_admin(org_id) or id = public.agenda_my_prof(org_id))
    with check (public.agenda_is_admin(org_id) or id = public.agenda_my_prof(org_id));
drop policy if exists agenda_prof_delete on public.agenda_professionals;
create policy agenda_prof_delete on public.agenda_professionals for delete to authenticated using (public.agenda_is_admin(org_id));

-- Locais: membros leem e cadastram (lançamento por voz cria locais); só admin exclui
drop policy if exists agenda_loc_select on public.agenda_locations;
create policy agenda_loc_select on public.agenda_locations for select to authenticated using (public.agenda_is_member(org_id));
drop policy if exists agenda_loc_insert on public.agenda_locations;
create policy agenda_loc_insert on public.agenda_locations for insert to authenticated with check (public.agenda_is_member(org_id));
drop policy if exists agenda_loc_update on public.agenda_locations;
create policy agenda_loc_update on public.agenda_locations for update to authenticated using (public.agenda_is_member(org_id)) with check (public.agenda_is_member(org_id));
drop policy if exists agenda_loc_delete on public.agenda_locations;
create policy agenda_loc_delete on public.agenda_locations for delete to authenticated using (public.agenda_is_admin(org_id));

-- Lançamentos: admin vê/edita todos; médico só os próprios
drop policy if exists agenda_events_select on public.agenda_events;
create policy agenda_events_select on public.agenda_events for select to authenticated
    using (public.agenda_is_admin(org_id) or prof_id = public.agenda_my_prof(org_id));
drop policy if exists agenda_events_insert on public.agenda_events;
create policy agenda_events_insert on public.agenda_events for insert to authenticated
    with check (public.agenda_is_admin(org_id) or prof_id = public.agenda_my_prof(org_id));
drop policy if exists agenda_events_update on public.agenda_events;
create policy agenda_events_update on public.agenda_events for update to authenticated
    using (public.agenda_is_admin(org_id) or prof_id = public.agenda_my_prof(org_id))
    with check (public.agenda_is_admin(org_id) or prof_id = public.agenda_my_prof(org_id));
drop policy if exists agenda_events_delete on public.agenda_events;
create policy agenda_events_delete on public.agenda_events for delete to authenticated
    using (public.agenda_is_admin(org_id) or prof_id = public.agenda_my_prof(org_id));

-- Preferências: cada usuário só as próprias
drop policy if exists agenda_settings_all on public.agenda_user_settings;
create policy agenda_settings_all on public.agenda_user_settings for all to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- -----------------------------------------------------------------------------
-- Tempo real (atualiza a agenda do gestor quando um médico lança algo)
-- -----------------------------------------------------------------------------
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        begin execute 'alter publication supabase_realtime add table public.agenda_events'; exception when duplicate_object then null; end;
        begin execute 'alter publication supabase_realtime add table public.agenda_locations'; exception when duplicate_object then null; end;
        begin execute 'alter publication supabase_realtime add table public.agenda_professionals'; exception when duplicate_object then null; end;
        begin execute 'alter publication supabase_realtime add table public.agenda_members'; exception when duplicate_object then null; end;
    end if;
end $$;
