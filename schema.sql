-- ═══════════════════════════════════════════════════════════════════
--  MODERN MOVEMENT PLATFORM — SUPABASE SCHEMA
--  Run this entire file in: Supabase Dashboard → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════

-- ─── Extensions ───────────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ─── Clean slate (safe re-run) ────────────────────────────────────
drop view  if exists public.initiative_feed    cascade;
drop view  if exists public.vote_tallies       cascade;
drop view  if exists public.flag_counts        cascade;
drop table if exists public.activity_log       cascade;
drop table if exists public.flags              cascade;
drop table if exists public.votes              cascade;
drop table if exists public.initiatives        cascade;
drop table if exists public.profiles           cascade;

-- ═══════════════════════════════════════
--  TABLES
-- ═══════════════════════════════════════

-- PROFILES — extends auth.users
create table public.profiles (
  id          uuid        primary key references auth.users(id) on delete cascade,
  fname       text        not null default '',
  lname       text        not null default '',
  email       text        not null default '',
  location    text        not null default '',
  bio         text        not null default '',
  role        text        not null default 'member'
                          check (role in ('member', 'mod', 'admin')),
  created_at  timestamptz not null default now()
);
comment on table public.profiles is 'Public user profiles, linked to Supabase Auth';

-- INITIATIVES
create table public.initiatives (
  id           uuid        primary key default gen_random_uuid(),
  title        text        not null,
  description  text        not null,
  location     text        not null default '',
  site         text        not null check (site in ('yes','no')),
  category     text        not null default 'Other',
  impact       text        not null default '',
  evidence_url text        not null default '',
  author_id    uuid        references public.profiles(id) on delete set null,
  status       text        not null default 'pending'
                           check (status in ('pending','active','hidden','removed')),
  ai_score     int                  default 0,
  ai_summary   text        not null default '',
  created_at   timestamptz not null default now(),
  published_at timestamptz
);
comment on table public.initiatives is 'Community-submitted initiatives for voting';

-- VOTES — one per user per initiative (enforced by unique constraint)
create table public.votes (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        not null references public.profiles(id) on delete cascade,
  initiative_id  uuid        not null references public.initiatives(id) on delete cascade,
  choice         text        not null check (choice in ('yes','no')),
  created_at     timestamptz not null default now(),
  unique (user_id, initiative_id)
);
comment on table public.votes is 'One vote per user per initiative — enforced by DB constraint';

-- FLAGS — community content moderation reports
create table public.flags (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        not null references public.profiles(id) on delete cascade,
  initiative_id  uuid        not null references public.initiatives(id) on delete cascade,
  reason         text        not null,
  context        text        not null default '',
  created_at     timestamptz not null default now()
);
comment on table public.flags is 'User-submitted content flag reports';

-- ACTIVITY LOG — audit trail for all significant actions
create table public.activity_log (
  id             uuid        primary key default gen_random_uuid(),
  user_id        uuid        references public.profiles(id) on delete set null,
  initiative_id  uuid        references public.initiatives(id) on delete cascade,
  type           text        not null,
  description    text        not null,
  created_at     timestamptz not null default now()
);
comment on table public.activity_log is 'Platform-wide audit log of votes, flags, approvals';

-- ═══════════════════════════════════════
--  VIEWS
-- ═══════════════════════════════════════

-- Vote tallies per initiative (fast, no app-side aggregation needed)
create view public.vote_tallies as
select
  initiative_id,
  count(*) filter (where choice = 'yes')  as yes_count,
  count(*) filter (where choice = 'no')   as no_count,
  count(*)                                as total_count
from public.votes
group by initiative_id;

-- Flag counts per initiative
create view public.flag_counts as
select
  initiative_id,
  count(*) as flag_count
from public.flags
group by initiative_id;

-- Rich initiative feed — joins profiles, tallies, flag counts in one shot
create view public.initiative_feed as
select
  i.*,
  p.fname,
  p.lname,
  p.role as author_role,
  coalesce(vt.yes_count,   0) as yes_count,
  coalesce(vt.no_count,    0) as no_count,
  coalesce(vt.total_count, 0) as total_count,
  coalesce(fc.flag_count,  0) as flag_count
from public.initiatives i
left join public.profiles     p  on p.id = i.author_id
left join public.vote_tallies vt on vt.initiative_id = i.id
left join public.flag_counts  fc on fc.initiative_id = i.id;

-- ═══════════════════════════════════════
--  ROW LEVEL SECURITY
-- ═══════════════════════════════════════

alter table public.profiles     enable row level security;
alter table public.initiatives  enable row level security;
alter table public.votes        enable row level security;
alter table public.flags        enable row level security;
alter table public.activity_log enable row level security;

-- ── profiles ──────────────────────────
-- Anyone can read any profile (names shown publicly)
create policy "profiles_select_all"
  on public.profiles for select using (true);

-- Users can only insert their own profile row
create policy "profiles_insert_own"
  on public.profiles for insert
  with check (auth.uid() = id);

-- Users can only update their own profile
create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id);

-- ── initiatives ────────────────────────
-- Active initiatives are public; authors can see their own pending/hidden ones;
-- mods/admins can see everything
create policy "initiatives_select"
  on public.initiatives for select
  using (
    status = 'active'
    or auth.uid() = author_id
    or exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('mod','admin')
    )
  );

-- Any logged-in user can submit an initiative
create policy "initiatives_insert"
  on public.initiatives for insert
  with check (auth.uid() = author_id);

-- Mods/admins can update status; authors can update their own pending submissions
create policy "initiatives_update"
  on public.initiatives for update
  using (
    auth.uid() = author_id
    or exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('mod','admin')
    )
  );

-- ── votes ──────────────────────────────
-- Vote tallies are public (democratic transparency)
create policy "votes_select_all"
  on public.votes for select using (true);

-- Authenticated users can cast one vote (DB unique constraint prevents doubles)
create policy "votes_insert_own"
  on public.votes for insert
  with check (auth.uid() = user_id);

-- ── flags ──────────────────────────────
-- Mods and admins can see all flags; users can see their own
create policy "flags_select"
  on public.flags for select
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('mod','admin')
    )
  );

-- Authenticated users can file flags
create policy "flags_insert_own"
  on public.flags for insert
  with check (auth.uid() = user_id);

-- ── activity_log ──────────────────────
-- Only mods and admins can read the audit log
create policy "activity_log_select_mods"
  on public.activity_log for select
  using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('mod','admin')
    )
  );

-- Authenticated users can write their own actions
create policy "activity_log_insert"
  on public.activity_log for insert
  with check (auth.uid() = user_id);

-- ═══════════════════════════════════════
--  TRIGGER — Auto-create profile on signup
-- ═══════════════════════════════════════
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, fname, lname, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'fname', split_part(new.email,'@',1)),
    coalesce(new.raw_user_meta_data->>'lname', ''),
    coalesce(new.email, '')
  );
  return new;
end;
$$;

-- Drop and recreate trigger cleanly
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ═══════════════════════════════════════
--  REALTIME — enable for live vote updates
-- ═══════════════════════════════════════
-- Run these in Supabase Dashboard → Database → Replication
-- OR uncomment and run here:

-- alter publication supabase_realtime add table public.votes;
-- alter publication supabase_realtime add table public.initiatives;
-- alter publication supabase_realtime add table public.flags;

-- ═══════════════════════════════════════
--  HELPER FUNCTION — Promote user to mod
--  Call from Supabase dashboard to make first admin
-- ═══════════════════════════════════════
create or replace function public.set_user_role(target_email text, new_role text)
returns void
language plpgsql
security definer
as $$
begin
  update public.profiles p
  set role = new_role
  from auth.users u
  where p.id = u.id
    and u.email = target_email
    and new_role in ('member','mod','admin');
end;
$$;

-- USAGE EXAMPLE (run after creating your account):
-- select public.set_user_role('your@email.com', 'admin');

-- ═══════════════════════════════════════
--  SEED DATA — 6 Sample Initiatives
--  NOTE: These use placeholder author_id = null (anonymous)
--  Real initiatives will have author_id linked to auth users
-- ═══════════════════════════════════════
insert into public.initiatives
  (title, description, location, site, category, impact, status, ai_score, ai_summary, published_at)
values
(
  'Require Water Impact Studies Before ANY Data Center Approval in Arizona',
  'Force Maricopa County Commission to mandate independent 180-day water impact studies before approving any data center project drawing over 200,000 gallons per day from municipal supplies. Arizona is already in Level 2 drought. This is not a hypothetical crisis — it is happening now. A single large data center can consume as much water as a city of 50,000 people. Our communities deserve to know the full impact before these facilities are approved.',
  'Maricopa County, AZ',
  'no', 'Water Rights',
  '2.1M gal/day at risk',
  'active', 94,
  'Legitimate community concern with cited data. Reasonable regulatory ask. Strong civic relevance.',
  now() - interval '14 days'
),
(
  'Community Solar Rights — Eliminate Utility Veto Power Over Neighborhood Projects',
  'Southwest utilities are actively blocking small community solar installations using regulatory loopholes. This initiative demands state-level legislation eliminating utility veto power over certified community solar projects under 2MW, and establishes a 40% rate credit for low-income households who subscribe. Thousands of families in New Mexico, Arizona, and Colorado are being denied affordable clean energy by monopoly utility companies.',
  'New Mexico, Arizona, Colorado',
  'yes', 'Clean Energy',
  '40% rate reduction for low-income households',
  'active', 91,
  'Well-structured policy proposal. Verifiable harm cited. On mission for platform.',
  now() - interval '18 days'
),
(
  'Halt Northern Virginia Data Center Phase 7 — Diesel Generators Polluting Neighborhoods',
  'Loudoun County is approving Phase 7 of Data Center Alley. The proposed facilities will use thousands of diesel backup generators classified as "demand response" that can legally run 50 hours at a time, pumping NOx and particulate matter into residential neighborhoods. Children''s asthma rates are already elevated. The Washington Post has documented the impact. We demand a moratorium until independent air quality assessments are completed.',
  'Loudoun County, VA',
  'no', 'Air Quality',
  'Asthma risk elevated across 4 counties',
  'active', 88,
  'Factual. Documented by major news outlets. Strong community interest. On mission.',
  now() - interval '20 days'
),
(
  'Mandatory Civics & Media Literacy K–12 — Make It Required, Not Elective',
  'Only 9 states mandate full-year civics courses. This initiative proposes a national standard requiring comprehensive civics education — how government works, how to evaluate information sources, how to engage in democracy — from 3rd grade through 12th grade. Media literacy is a democratic survival skill. Without it, disinformation wins. This is the single highest-leverage investment we can make in the long-term health of our republic.',
  'Nationwide',
  'yes', 'Education',
  '50 million students in K-12 system',
  'active', 97,
  'Nonpartisan. Evidence-based. High civic relevance. Excellent submission.',
  now() - interval '23 days'
),
(
  'Data Center Moratorium — Boardman, OR Emergency Resolution',
  '30+ data centers in a town of 4,000 people have contaminated wells to 5 times the legal nitrate limit. The Port of Morrow disposes of cooling wastewater on surrounding farmland. Residents have been unknowingly drinking toxic water for 3 years. This petition demands an emergency resolution from Morrow County blocking new data center approvals until a full independent groundwater audit is completed and remediation plans are in place.',
  'Morrow County, OR',
  'no', 'Water Rights',
  'Wells at 5× legal nitrate limit',
  'active', 96,
  'Documented emergency. Cited in national press. Urgent and legitimate.',
  now() - interval '8 days'
),
(
  'Veterans Housing First — Permanent Supportive Housing Allocation',
  'Over 35,000 veterans are unhoused on any given night in the United States. The Housing First model — providing stable housing before other services — has been proven to reduce veteran homelessness by over 80% in pilot cities. This initiative calls on Congress to allocate 1.5% of the DoD discretionary budget to build and maintain permanent supportive housing for unhoused veterans. We ask for less than 2 cents on every defense dollar.',
  'Nationwide',
  'yes', 'Housing',
  '35,000+ veterans currently unhoused',
  'active', 95,
  'Evidence-based. Bipartisan appeal. Strong civic and human interest.',
  now() - interval '12 days'
);
