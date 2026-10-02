-- =====================================================================
-- NACRÉA · Script 01 : fondations de la base de données
-- À coller en entier dans Supabase > SQL Editor > New query, puis "Run".
-- Montants en FCFA, sans décimales (nombres entiers).
-- =====================================================================

-- ---------- Listes de valeurs ----------
create type member_role as enum ('owner', 'employee');            -- patronne, employée
create type subscription_status as enum ('trial', 'active', 'late', 'suspended');
create type payment_method as enum ('cash', 'mobile_money', 'card', 'credit');
create type sale_status as enum ('completed', 'on_hold', 'cancelled', 'returned');
create type movement_type as enum (
  'purchase', 'sale', 'return', 'adjustment', 'loss', 'transfer_in', 'transfer_out'
);

-- ---------- Comptes : une patronne = un compte ----------
create table accounts (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  owner_user_id uuid not null references auth.users(id),
  phone         text,
  created_at    timestamptz not null default now()
);

-- ---------- Boutiques (points de vente) d'un compte ----------
create table shops (
  id              uuid primary key default gen_random_uuid(),
  account_id      uuid not null references accounts(id) on delete cascade,
  name            text not null,
  address         text,
  phone           text,
  activation_code text unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_at      timestamptz not null default now()
);

-- ---------- Membres : patronne et employées ----------
-- La patronne n'a pas de shop_id : elle voit toutes ses boutiques.
-- Une employée est rattachée à une seule boutique.
create table members (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  account_id   uuid not null references accounts(id) on delete cascade,
  shop_id      uuid references shops(id) on delete cascade,
  role         member_role not null,
  display_name text not null,
  can_see_costs boolean not null default false,  -- voir prix d'achat et marges
  active       boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (user_id, account_id),
  check (role = 'owner' or shop_id is not null)
);

-- ---------- Abonnements : un par boutique, 22 000 FCFA / mois ----------
create table subscriptions (
  id                 uuid primary key default gen_random_uuid(),
  shop_id            uuid not null unique references shops(id) on delete cascade,
  status             subscription_status not null default 'trial',
  monthly_price      integer not null default 22000,
  current_period_end timestamptz,
  created_at         timestamptz not null default now()
);

-- ---------- Catalogue (commun aux boutiques d'un même compte) ----------
create table categories (
  id         uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  name       text not null,
  created_at timestamptz not null default now()
);

create table products (
  id              uuid primary key default gen_random_uuid(),
  account_id      uuid not null references accounts(id) on delete cascade,
  category_id     uuid references categories(id) on delete set null,
  name            text not null,
  brand           text,
  variant_label   text,                 -- teinte, contenance, parfum…
  barcode         text,
  photo_url       text,
  purchase_price  integer not null default 0 check (purchase_price >= 0),
  sale_price      integer not null default 0 check (sale_price >= 0),
  wholesale_price integer check (wholesale_price >= 0),
  min_stock       integer not null default 0,
  active          boolean not null default true,
  created_at      timestamptz not null default now()
);
create index on products (account_id);
create index on products (barcode);

-- ---------- Stock par boutique, par lot (avec péremption) ----------
create table stock_lots (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  quantity    integer not null default 0,
  cost_price  integer not null default 0,
  expiry_date date,
  received_at timestamptz not null default now()
);
create index on stock_lots (shop_id, product_id);

create table stock_movements (
  id         uuid primary key default gen_random_uuid(),
  shop_id    uuid not null references shops(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  lot_id     uuid references stock_lots(id) on delete set null,
  type       movement_type not null,
  quantity   integer not null,          -- positif = entrée, négatif = sortie
  reason     text,
  user_id    uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index on stock_movements (shop_id, created_at);

-- ---------- Clientes ----------
create table customers (
  id             uuid primary key default gen_random_uuid(),
  account_id     uuid not null references accounts(id) on delete cascade,
  name           text not null,
  phone          text,
  birthday       date,
  notes          text,
  loyalty_points integer not null default 0,
  created_at     timestamptz not null default now()
);

-- ---------- Ventes ----------
create table sales (
  id            uuid primary key default gen_random_uuid(),
  shop_id       uuid not null references shops(id) on delete cascade,
  customer_id   uuid references customers(id) on delete set null,
  user_id       uuid references auth.users(id),
  ticket_number text,
  status        sale_status not null default 'completed',
  subtotal      integer not null default 0,
  discount      integer not null default 0,
  total         integer not null default 0,
  created_at    timestamptz not null default now()
);
create index on sales (shop_id, created_at);

create table sale_items (
  id         uuid primary key default gen_random_uuid(),
  sale_id    uuid not null references sales(id) on delete cascade,
  shop_id    uuid not null references shops(id) on delete cascade,
  product_id uuid not null references products(id),
  lot_id     uuid references stock_lots(id) on delete set null,
  quantity   integer not null check (quantity > 0),
  unit_price integer not null,
  cost_price integer not null default 0,
  discount   integer not null default 0
);
create index on sale_items (sale_id);

create table payments (
  id         uuid primary key default gen_random_uuid(),
  sale_id    uuid not null references sales(id) on delete cascade,
  shop_id    uuid not null references shops(id) on delete cascade,
  method     payment_method not null,
  amount     integer not null,
  created_at timestamptz not null default now()
);

-- =====================================================================
-- Automatismes
-- =====================================================================

-- Quand une patronne crée son compte, elle en devient membre "owner".
create function handle_new_account() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into members (user_id, account_id, role, display_name, can_see_costs)
  values (new.owner_user_id, new.id, 'owner', new.name, true);
  return new;
end $$;

create trigger on_account_created after insert on accounts
for each row execute function handle_new_account();

-- Chaque nouvelle boutique démarre en période d'essai (durée provisoire : 14 jours).
create function handle_new_shop() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into subscriptions (shop_id, status, current_period_end)
  values (new.id, 'trial', now() + interval '14 days');
  return new;
end $$;

create trigger on_shop_created after insert on shops
for each row execute function handle_new_shop();

-- =====================================================================
-- Sécurité : chaque patronne ne voit QUE ses données,
-- chaque employée ne voit QUE sa boutique.
-- =====================================================================

create function is_account_member(acc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members
    where account_id = acc and user_id = auth.uid() and active);
$$;

create function is_account_owner(acc uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members
    where account_id = acc and user_id = auth.uid() and active and role = 'owner');
$$;

create function can_access_shop(shp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from shops s join members m on m.account_id = s.account_id
    where s.id = shp and m.user_id = auth.uid() and m.active
      and (m.role = 'owner' or m.shop_id = s.id));
$$;

create function is_shop_owner(shp uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from shops s
    where s.id = shp and is_account_owner(s.account_id));
$$;

alter table accounts        enable row level security;
alter table shops           enable row level security;
alter table members         enable row level security;
alter table subscriptions   enable row level security;
alter table categories      enable row level security;
alter table products        enable row level security;
alter table stock_lots      enable row level security;
alter table stock_movements enable row level security;
alter table customers       enable row level security;
alter table sales           enable row level security;
alter table sale_items      enable row level security;
alter table payments        enable row level security;

-- Comptes
create policy accounts_read   on accounts for select using (is_account_member(id));
create policy accounts_create on accounts for insert with check (owner_user_id = auth.uid());
create policy accounts_update on accounts for update using (is_account_owner(id));

-- Boutiques : la patronne les gère, l'employée voit la sienne
create policy shops_read   on shops for select using (can_access_shop(id));
create policy shops_create on shops for insert with check (is_account_owner(account_id));
create policy shops_update on shops for update using (is_account_owner(account_id));
create policy shops_delete on shops for delete using (is_account_owner(account_id));

-- Membres : visibles par le compte, gérés par la patronne
create policy members_read  on members for select using (is_account_member(account_id));
create policy members_write on members for all
  using (is_account_owner(account_id)) with check (is_account_owner(account_id));

-- Abonnements : lecture seule pour la patronne (modifiés uniquement par toi, l'éditeur)
create policy subscriptions_read on subscriptions for select using (is_shop_owner(shop_id));

-- Catalogue et clientes : partagés au niveau du compte
create policy categories_rw on categories for all
  using (is_account_member(account_id)) with check (is_account_member(account_id));
create policy products_read  on products for select using (is_account_member(account_id));
create policy products_write on products for insert with check (is_account_member(account_id));
create policy products_edit  on products for update using (is_account_member(account_id));
create policy products_del   on products for delete using (is_account_owner(account_id));
create policy customers_rw on customers for all
  using (is_account_member(account_id)) with check (is_account_member(account_id));

-- Stock, ventes, paiements : limités à la boutique
create policy lots_rw on stock_lots for all
  using (can_access_shop(shop_id)) with check (can_access_shop(shop_id));
create policy movements_read on stock_movements for select using (can_access_shop(shop_id));
create policy movements_add  on stock_movements for insert with check (can_access_shop(shop_id));
create policy sales_read   on sales for select using (can_access_shop(shop_id));
create policy sales_add    on sales for insert with check (can_access_shop(shop_id));
create policy sales_edit   on sales for update using (can_access_shop(shop_id));
create policy items_read   on sale_items for select using (can_access_shop(shop_id));
create policy items_add    on sale_items for insert with check (can_access_shop(shop_id));
create policy payments_read on payments for select using (can_access_shop(shop_id));
create policy payments_add  on payments for insert with check (can_access_shop(shop_id));
-- Pas de suppression de ventes ni de mouvements de stock : on annule, on n'efface pas.
