-- =====================================================================
-- NACRÉA · Script 10 : dépenses et fournisseurs
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- - Fournisseurs : communs à toutes les boutiques de l'entreprise.
-- - Une entrée de stock peut indiquer son fournisseur (stock_lots.supplier_id).
-- - Dépenses : loyer, électricité, salaires… par boutique. Une dépense payée
--   « avec l'argent de la caisse » diminue l'argent attendu à la clôture.
-- =====================================================================

-- ---------- Fournisseurs ----------
create table suppliers (
  id         uuid primary key default gen_random_uuid(),
  account_id uuid not null references accounts(id) on delete cascade,
  name       text not null,
  phone      text,
  note       text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
create index on suppliers (account_id);

alter table suppliers enable row level security;
create policy suppliers_read on suppliers for select using (is_account_member(account_id));
-- Une employée peut ajouter un fournisseur au moment d'une livraison.
create policy suppliers_add  on suppliers for insert with check (is_account_member(account_id));
create policy suppliers_edit on suppliers for update using (is_account_member(account_id));
create policy suppliers_del  on suppliers for delete using (is_account_owner(account_id));

-- ---------- Fournisseur d'une entrée de stock ----------
alter table stock_lots add column supplier_id uuid references suppliers(id) on delete set null;

drop function receive_stock(uuid, uuid, integer, integer, date, text, uuid, timestamptz);

create function receive_stock(
  p_shop_id     uuid,
  p_product_id  uuid,
  p_quantity    integer,
  p_cost_price  integer default 0,
  p_expiry      date    default null,
  p_reason      text    default null,
  p_lot_id      uuid    default null,
  p_received_at timestamptz default null,
  p_supplier_id uuid    default null
) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  lot uuid := coalesce(p_lot_id, gen_random_uuid());
begin
  -- Déjà reçue (envoi répété après une coupure) : rien à refaire.
  if exists (select 1 from stock_lots where id = lot) then
    return lot;
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'La quantité doit être supérieure à zéro';
  end if;
  if p_supplier_id is not null and not exists (
    select 1 from suppliers f join shops s on s.account_id = f.account_id
     where f.id = p_supplier_id and s.id = p_shop_id
  ) then
    raise exception 'Fournisseur inconnu pour cette boutique';
  end if;

  insert into stock_lots (id, shop_id, product_id, quantity, cost_price, expiry_date, received_at, supplier_id)
  values (lot, p_shop_id, p_product_id, p_quantity, coalesce(p_cost_price, 0), p_expiry,
          coalesce(p_received_at, now()), p_supplier_id);

  insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
  values (p_shop_id, p_product_id, lot, 'purchase', p_quantity, p_reason, auth.uid(),
          coalesce(p_received_at, now()));
  return lot;
end $$;

revoke execute on function receive_stock(uuid, uuid, integer, integer, date, text, uuid, timestamptz, uuid) from public, anon;
grant execute on function receive_stock(uuid, uuid, integer, integer, date, text, uuid, timestamptz, uuid) to authenticated;

-- ---------- Dépenses ----------
create table expenses (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid references accounts(id) on delete cascade,
  shop_id     uuid not null references shops(id) on delete cascade,
  category    text not null check (category in
                ('loyer', 'electricite_eau', 'salaires', 'transport', 'internet_telephone',
                 'entretien', 'publicite', 'taxes', 'autre')),
  -- Pas de « marchandises » : leur coût est déjà compté à la vente (prix d'achat des lots).
  label       text,
  amount      integer not null check (amount > 0),
  method      text not null default 'cash' check (method in ('cash', 'mobile_money', 'card')),
  from_till   boolean not null default false,  -- payée avec l'argent de la caisse
  supplier_id uuid references suppliers(id) on delete set null,
  spent_on    date not null default current_date,
  user_id     uuid references auth.users(id) default auth.uid(),
  created_at  timestamptz not null default now()
);
create index on expenses (shop_id, spent_on);

create trigger fill_account_expenses before insert or update of shop_id on expenses
for each row execute function fill_account_id();

alter table expenses enable row level security;
create policy expenses_read on expenses for select using (can_access_shop(shop_id));
create policy expenses_add  on expenses for insert with check (can_access_shop(shop_id));
-- Corriger ou supprimer une dépense : réservé à la patronne.
create policy expenses_edit on expenses for update using (is_account_owner(account_id));
create policy expenses_del  on expenses for delete using (is_account_owner(account_id));

grant select on suppliers, expenses to powersync_role;

notify pgrst, 'reload schema';
