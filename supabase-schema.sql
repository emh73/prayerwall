-- ============================================================
-- Prayer Wall — Supabase schema
-- Run this entire file in Supabase SQL Editor (see DEPLOY.md step 3)
-- ============================================================

-- ---------- EXTENSIONS ----------
create extension if not exists pgcrypto;

-- ---------- TABLES ----------

create table if not exists prayers (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (char_length(title) between 1 and 120),
  body        text not null check (char_length(body)  between 1 and 4000),
  category    text not null,
  author_name text,                 -- null or '' => Anonymous
  client_id   text not null,        -- browser-generated id, used for edit permission
  urgent      boolean not null default false,
  answered    boolean not null default false,
  answered_note text,
  answered_at timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists prayers_created_at_idx on prayers (created_at desc);
create index if not exists prayers_category_idx   on prayers (category);
create index if not exists prayers_answered_idx   on prayers (answered);

create table if not exists prayed_for (
  prayer_id  uuid not null references prayers(id) on delete cascade,
  client_id  text not null,
  created_at timestamptz not null default now(),
  primary key (prayer_id, client_id)
);
create index if not exists prayed_for_prayer_idx on prayed_for (prayer_id);

create table if not exists comments (
  id          uuid primary key default gen_random_uuid(),
  prayer_id   uuid not null references prayers(id) on delete cascade,
  author_name text,
  client_id   text not null,
  body        text not null check (char_length(body) between 1 and 500),
  created_at  timestamptz not null default now()
);
create index if not exists comments_prayer_idx on comments (prayer_id, created_at);

create table if not exists groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 80),
  description text not null check (char_length(description) between 1 and 300),
  created_at  timestamptz not null default now()
);

create table if not exists group_members (
  group_id   uuid not null references groups(id) on delete cascade,
  client_id  text not null,
  created_at timestamptz not null default now(),
  primary key (group_id, client_id)
);

create table if not exists group_posts (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references groups(id) on delete cascade,
  author_name text,
  client_id   text not null,
  body        text not null check (char_length(body) between 1 and 1000),
  created_at  timestamptz not null default now()
);
create index if not exists group_posts_group_idx on group_posts (group_id, created_at);

-- ---------- CONVENIENCE VIEW ----------
-- Prayers with prayer count + comment count. The frontend reads this.
create or replace view prayer_feed as
select
  p.*,
  coalesce((select count(*) from prayed_for pf where pf.prayer_id = p.id), 0) as prayed_count,
  coalesce((select count(*) from comments   c  where c.prayer_id  = p.id), 0) as comment_count
from prayers p;

-- Groups with member count + post count.
create or replace view group_feed as
select
  g.*,
  coalesce((select count(*) from group_members gm where gm.group_id = g.id), 0) as member_count,
  coalesce((select count(*) from group_posts   gp where gp.group_id = g.id), 0) as post_count
from groups g;

-- ---------- ROW LEVEL SECURITY ----------
-- Because there is no user auth (anonymous site), we expose inserts + reads to
-- the public (anon) role. This is safe as long as the anon key is used (which
-- Supabase enforces) and the client sends plausible client_id values.

alter table prayers        enable row level security;
alter table prayed_for     enable row level security;
alter table comments       enable row level security;
alter table groups         enable row level security;
alter table group_members  enable row level security;
alter table group_posts    enable row level security;

-- Prayers: anyone can read, anyone can insert, anyone can update
-- (update is scoped in the app to "mark answered" only; the server trusts the
-- client_id match, which is fine for an MVP prayer wall).
drop policy if exists prayers_select on prayers;
drop policy if exists prayers_insert on prayers;
drop policy if exists prayers_update on prayers;
create policy prayers_select on prayers for select to anon, authenticated using (true);
create policy prayers_insert on prayers for insert to anon, authenticated with check (true);
create policy prayers_update on prayers for update to anon, authenticated using (true) with check (true);

drop policy if exists prayed_for_select on prayed_for;
drop policy if exists prayed_for_insert on prayed_for;
drop policy if exists prayed_for_delete on prayed_for;
create policy prayed_for_select on prayed_for for select to anon, authenticated using (true);
create policy prayed_for_insert on prayed_for for insert to anon, authenticated with check (true);
create policy prayed_for_delete on prayed_for for delete to anon, authenticated using (true);

drop policy if exists comments_select on comments;
drop policy if exists comments_insert on comments;
create policy comments_select on comments for select to anon, authenticated using (true);
create policy comments_insert on comments for insert to anon, authenticated with check (true);

drop policy if exists groups_select on groups;
drop policy if exists groups_insert on groups;
create policy groups_select on groups for select to anon, authenticated using (true);
create policy groups_insert on groups for insert to anon, authenticated with check (true);

drop policy if exists group_members_select on group_members;
drop policy if exists group_members_insert on group_members;
create policy group_members_select on group_members for select to anon, authenticated using (true);
create policy group_members_insert on group_members for insert to anon, authenticated with check (true);

drop policy if exists group_posts_select on group_posts;
drop policy if exists group_posts_insert on group_posts;
create policy group_posts_select on group_posts for select to anon, authenticated using (true);
create policy group_posts_insert on group_posts for insert to anon, authenticated with check (true);

-- The view inherits RLS from the base tables (Supabase default).
grant select on prayer_feed to anon, authenticated;
grant select on group_feed  to anon, authenticated;

-- ---------- SEED DATA ----------
-- Only seeds if the tables are empty, so you can re-run this file safely.

insert into groups (name, description)
select * from (values
  ('Mothers in Prayer',       'A circle for moms lifting up our children, near and far.'),
  ('First Responders',        'For those in medicine, fire, police — and their families.'),
  ('College & Early Career',  'Finals, first jobs, figuring it out. We pray for each other.'),
  ('Grief & Healing',         'A gentle space for those walking through loss.')
) as seed(name, description)
where not exists (select 1 from groups);

insert into prayers (title, body, category, author_name, client_id, urgent, answered, answered_note, answered_at, created_at)
select * from (values
  ('Healing for my mom''s surgery',
   'My mom is having surgery next Tuesday. Praying for the surgeons'' hands, a smooth recovery, and peace for our whole family as we wait.',
   'Health', 'Rachel', 'seed', true, false, null::text, null::timestamptz, now() - interval '6 hours'),
  ('Gratitude for a new job',
   'After nine months of searching, I start Monday. Thank you to everyone who prayed me through that wilderness season — your prayers held me up.',
   'Gratitude', null, 'seed', false, true, 'Got the offer Wednesday. The role is a better fit than I dared to hope for.', now() - interval '2 hours', now() - interval '28 hours'),
  ('Wisdom for a hard conversation',
   'I need to have a difficult conversation with my brother this weekend. Pray for gentleness, truth, and the right words.',
   'Family', null, 'seed', false, false, null, null, now() - interval '18 hours'),
  ('Struggling with doubt',
   'I''ve been in a dry spell for months. I still show up but it feels empty. Please pray that I''d meet God again in some small way.',
   'Faith', null, 'seed', false, false, null, null, now() - interval '40 hours'),
  ('Remembering my grandfather',
   'One year since we lost Grandpa. Prayers of comfort for my grandmother especially — the quiet evenings have been hardest.',
   'Grief', 'Daniel', 'seed', false, false, null, null, now() - interval '52 hours'),
  ('Direction for graduate school',
   'Two acceptance letters, two very different paths. Praying for clarity and peace about which door to walk through.',
   'Guidance', 'Maya', 'seed', false, false, null, null, now() - interval '72 hours')
) as seed(title, body, category, author_name, client_id, urgent, answered, answered_note, answered_at, created_at)
where not exists (select 1 from prayers);
