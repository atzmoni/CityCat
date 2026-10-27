-- CityCat · Supabase schema
-- Paste this whole file into Supabase → SQL Editor → New query → Run. Safe to run again.
--
-- Who sees what:
--   * Signed-in users see the shared map (cats, reports, feeding stations) and the leaderboard.
--   * Volunteer sign-ups and adoption requests (names, phone numbers) are visible only to
--     the person who sent them and to the app admin.
--   * Only the admin can delete records, change report statuses or edit a cat's care fields.
--   * Nobody who is not signed in can read or write anything.

create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;
grant execute on function public.is_admin() to authenticated;

drop policy if exists "admins: self check" on public.admins;
create policy "admins: self check" on public.admins for select to authenticated using (user_id = auth.uid());

-- Shared map data: one row per record, the record itself in `doc`.
create table if not exists public.cats (
  id text primary key, doc jsonb not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz default now()
);
create table if not exists public.reports (like public.cats including all);
create table if not exists public.stations (like public.cats including all);

-- Points and display name, one row per user.
create table if not exists public.players (
  id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  doc jsonb not null, updated_at timestamptz default now()
);

-- Private requests: volunteers and adoptions.
create table if not exists public.private_requests (
  id text primary key, kind text not null check (kind in ('vol', 'adopt')), doc jsonb not null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz default now()
);

alter table public.cats enable row level security;
alter table public.reports enable row level security;
alter table public.stations enable row level security;
alter table public.players enable row level security;
alter table public.private_requests enable row level security;

do $$ declare t text; begin
  foreach t in array array['cats', 'reports', 'stations', 'players', 'private_requests'] loop
    execute format('drop policy if exists "read" on public.%I', t);
    execute format('drop policy if exists "insert" on public.%I', t);
    execute format('drop policy if exists "update" on public.%I', t);
    execute format('drop policy if exists "delete" on public.%I', t);
  end loop;
end $$;

-- cats and reports: every signed-in user can add and update (sightings, likes, a lost dog's trail); only the admin deletes.
create policy "read" on public.cats for select to authenticated using (true);
create policy "insert" on public.cats for insert to authenticated with check (true);
create policy "update" on public.cats for update to authenticated using (true) with check (true);
create policy "delete" on public.cats for delete to authenticated using (public.is_admin());

create policy "read" on public.reports for select to authenticated using (true);
create policy "insert" on public.reports for insert to authenticated with check (true);
create policy "update" on public.reports for update to authenticated using (true) with check (true);
create policy "delete" on public.reports for delete to authenticated using (public.is_admin());

-- feeding stations: admin only.
create policy "read" on public.stations for select to authenticated using (true);
create policy "insert" on public.stations for insert to authenticated with check (public.is_admin());
create policy "update" on public.stations for update to authenticated using (public.is_admin());
create policy "delete" on public.stations for delete to authenticated using (public.is_admin());

-- players: everyone sees the leaderboard, each user writes only their own row.
create policy "read" on public.players for select to authenticated using (true);
create policy "insert" on public.players for insert to authenticated with check (id = auth.uid());
create policy "update" on public.players for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "delete" on public.players for delete to authenticated using (public.is_admin());

-- private requests: the sender and the admin read; only the admin updates or deletes.
create policy "read" on public.private_requests for select to authenticated using (created_by = auth.uid() or public.is_admin());
create policy "insert" on public.private_requests for insert to authenticated with check (created_by = auth.uid());
create policy "update" on public.private_requests for update to authenticated using (public.is_admin());
create policy "delete" on public.private_requests for delete to authenticated using (public.is_admin());

-- Care fields stay in the admin's hands even though users can update the record.
create or replace function public.guard_admin_fields() returns trigger
language plpgsql security definer set search_path = public as $$
declare f text;
begin
  new.updated_at := now();
  new.created_by := old.created_by;
  if public.is_admin() then return new; end if;
  foreach f in array case tg_table_name
    when 'cats' then array['neutered', 'adoptable', 'notes', 'verified']
    when 'reports' then array['status']
    else array[]::text[] end
  loop
    if old.doc ? f then new.doc := jsonb_set(new.doc, array[f], old.doc -> f);
    else new.doc := new.doc - f; end if;
  end loop;
  return new;
end $$;

drop trigger if exists guard_admin_fields on public.cats;
create trigger guard_admin_fields before update on public.cats for each row execute function public.guard_admin_fields();
drop trigger if exists guard_admin_fields on public.reports;
create trigger guard_admin_fields before update on public.reports for each row execute function public.guard_admin_fields();

-- Live updates on the map.
do $$ declare t text; begin
  foreach t in array array['cats', 'reports', 'stations', 'players'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- After you sign up in the app, make yourself the admin (put your own email):
--   insert into public.admins select id from auth.users where email = 'YOUR_EMAIL' on conflict do nothing;
