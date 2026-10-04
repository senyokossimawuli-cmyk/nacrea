-- =====================================================================
-- NACRÉA · Script 06 : ouverture et clôture de caisse
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- =====================================================================

-- ---------- Sessions de caisse : du fond de caisse du matin au comptage du soir ----------
create table cash_sessions (
  id             uuid primary key default gen_random_uuid(),
  shop_id        uuid not null references shops(id) on delete cascade,
  account_id     uuid references accounts(id) on delete cascade,
  status         text not null default 'open' check (status in ('open', 'closed')),
  opened_by      uuid references auth.users(id),
  opened_at      timestamptz not null default now(),
  opening_float  integer not null default 0 check (opening_float >= 0),  -- fond de caisse
  closed_by      uuid references auth.users(id),
  closed_at      timestamptz,
  expected_cash  integer,   -- ce qui devrait être dans le tiroir
  counted_cash   integer,   -- ce qui a été compté
  difference     integer,   -- compté - attendu (négatif = manquant)
  note           text
);
create index on cash_sessions (shop_id, opened_at);
-- Une seule caisse ouverte à la fois par boutique.
create unique index cash_sessions_une_ouverte on cash_sessions (shop_id) where status = 'open';

-- ---------- Entrées et sorties d'argent hors ventes ----------
create table cash_movements (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid not null references cash_sessions(id) on delete cascade,
  shop_id     uuid not null references shops(id) on delete cascade,
  account_id  uuid references accounts(id) on delete cascade,
  type        text not null check (type in ('in', 'out')),
  amount      integer not null check (amount > 0),
  reason      text,
  user_id     uuid references auth.users(id),
  created_at  timestamptz not null default now()
);
create index on cash_movements (session_id);

create trigger fill_account_cash_sessions before insert or update of shop_id on cash_sessions
for each row execute function fill_account_id();
create trigger fill_account_cash_movements before insert or update of shop_id on cash_movements
for each row execute function fill_account_id();

-- ---------- Sécurité : réservé aux personnes de la boutique ----------
alter table cash_sessions  enable row level security;
alter table cash_movements enable row level security;

create policy cash_sessions_read   on cash_sessions for select using (can_access_shop(shop_id));
create policy cash_sessions_add    on cash_sessions for insert with check (can_access_shop(shop_id));
create policy cash_sessions_close  on cash_sessions for update
  using (can_access_shop(shop_id) and status = 'open')
  with check (can_access_shop(shop_id));

create policy cash_movements_read on cash_movements for select using (can_access_shop(shop_id));
create policy cash_movements_add  on cash_movements for insert with check (can_access_shop(shop_id));
-- Pas de modification ni de suppression : l'historique de la caisse reste intact.

-- PowerSync lit aussi ces nouvelles tables.
grant select on cash_sessions, cash_movements to powersync_role;
