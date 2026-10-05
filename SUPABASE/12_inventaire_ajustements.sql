-- =====================================================================
-- NACRÉA · Script 12 : inventaire et ajustements de stock
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- - Ajustement : casse, vol ou perte, cadeau, échantillon / testeur,
--   produit périmé jeté, correction. La valeur perdue (au prix d'achat)
--   est déduite du bénéfice dans les rapports.
-- - Inventaire : on compte les produits en rayon ; chaque écart avec le
--   stock du logiciel devient un ajustement « inventaire ».
-- - Comme les ventes, tout fonctionne hors ligne et est rejoué une seule fois.
-- =====================================================================

create table inventories (
  id           uuid primary key,
  account_id   uuid references accounts(id) on delete cascade,
  shop_id      uuid not null references shops(id) on delete cascade,
  nb_products  integer not null default 0,  -- produits comptés
  nb_ecarts    integer not null default 0,  -- produits avec une différence
  ecart_valeur integer not null default 0,  -- valeur des écarts au prix d'achat (négatif = manque)
  note         text,
  user_id      uuid references auth.users(id),
  created_at   timestamptz not null default now()
);
create index on inventories (shop_id, created_at);

create table stock_adjustments (
  id           uuid primary key,
  account_id   uuid references accounts(id) on delete cascade,
  shop_id      uuid not null references shops(id) on delete cascade,
  product_id   uuid not null references products(id) on delete cascade,
  quantity     integer not null check (quantity <> 0),   -- positif = ajouté, négatif = retiré
  reason       text not null check (reason in
                 ('casse', 'vol', 'cadeau', 'echantillon', 'perime', 'correction', 'inventaire')),
  cost_value   integer not null default 0,               -- valeur au prix d'achat (négatif = perte)
  note         text,
  inventory_id uuid references inventories(id) on delete set null,
  user_id      uuid references auth.users(id),
  created_at   timestamptz not null default now()
);
create index on stock_adjustments (shop_id, created_at);

create trigger fill_account_inventories before insert on inventories
for each row execute function fill_account_id();
create trigger fill_account_adjustments before insert on stock_adjustments
for each row execute function fill_account_id();
create trigger same_account_adjustments before insert on stock_adjustments
for each row execute function check_same_account();

alter table inventories enable row level security;
alter table stock_adjustments enable row level security;
create policy inventories_read on inventories for select using (can_access_shop(shop_id));
create policy adjustments_read on stock_adjustments for select using (can_access_shop(shop_id));
-- Les écritures passent uniquement par les fonctions ci-dessous.

-- ---------- Applique un ajustement au stock (lots) ----------
-- Retrait : le lot qui périme le plus tôt d'abord ; s'il n'y a pas assez, le stock devient négatif.
-- Ajout : comble d'abord un stock négatif, puis crée un lot au prix d'achat du produit.
-- Renvoie la valeur de l'ajustement au prix d'achat (négative pour un retrait).
create function _apply_adjustment(
  p_id uuid, p_shop_id uuid, p_product_id uuid, p_quantity integer, p_reason text,
  p_note text, p_inventory_id uuid, p_quand timestamptz
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_restant integer := abs(p_quantity);
  v_prend   integer;
  v_valeur  integer := 0;
  v_cout    integer;
  lot record;
  v_lot uuid;
  v_type movement_type := case when p_quantity < 0 and p_reason in ('casse', 'vol', 'perime') then 'loss'
                               else 'adjustment' end;
begin
  select coalesce(purchase_price, 0) into v_cout from products where id = p_product_id;

  if p_quantity < 0 then
    for lot in
      select id, quantity, cost_price from stock_lots
       where shop_id = p_shop_id and product_id = p_product_id and quantity > 0
       order by expiry_date asc nulls last, received_at asc
       for update
    loop
      exit when v_restant = 0;
      v_prend := least(lot.quantity, v_restant);
      update stock_lots set quantity = quantity - v_prend where id = lot.id;
      insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
      values (p_shop_id, p_product_id, lot.id, v_type, -v_prend, p_reason, auth.uid(), p_quand);
      v_valeur := v_valeur - v_prend * lot.cost_price;
      v_restant := v_restant - v_prend;
    end loop;
    if v_restant > 0 then
      insert into stock_lots (shop_id, product_id, quantity, cost_price, received_at)
      values (p_shop_id, p_product_id, -v_restant, v_cout, p_quand) returning id into v_lot;
      insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
      values (p_shop_id, p_product_id, v_lot, v_type, -v_restant, p_reason, auth.uid(), p_quand);
      v_valeur := v_valeur - v_restant * v_cout;
    end if;
  else
    for lot in
      select id, quantity from stock_lots
       where shop_id = p_shop_id and product_id = p_product_id and quantity < 0
       order by received_at asc
       for update
    loop
      exit when v_restant = 0;
      v_prend := least(-lot.quantity, v_restant);
      update stock_lots set quantity = quantity + v_prend where id = lot.id;
      v_restant := v_restant - v_prend;
    end loop;
    if v_restant > 0 then
      insert into stock_lots (shop_id, product_id, quantity, cost_price, received_at)
      values (p_shop_id, p_product_id, v_restant, v_cout, p_quand) returning id into v_lot;
    end if;
    insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
    values (p_shop_id, p_product_id, v_lot, 'adjustment', p_quantity, p_reason, auth.uid(), p_quand);
    v_valeur := p_quantity * v_cout;
  end if;

  insert into stock_adjustments (id, shop_id, product_id, quantity, reason, cost_value, note, inventory_id, user_id, created_at)
  values (p_id, p_shop_id, p_product_id, p_quantity, p_reason, v_valeur, nullif(trim(p_note), ''),
          p_inventory_id, auth.uid(), p_quand);
  return v_valeur;
end $$;

-- ---------- Un ajustement (casse, vol, cadeau…) ----------
create function adjust_stock(
  p_adjustment_id uuid, p_shop_id uuid, p_product_id uuid, p_quantity integer,
  p_reason text, p_note text default null, p_created_at timestamptz default null
) returns integer
language plpgsql security definer set search_path = public as $$
begin
  if not can_access_shop(p_shop_id) then raise exception 'Accès refusé à cette boutique'; end if;
  -- Déjà enregistré (envoi répété après une coupure) : rien à refaire.
  if exists (select 1 from stock_adjustments where id = p_adjustment_id) then return 0; end if;
  if coalesce(p_quantity, 0) = 0 then raise exception 'Quantité invalide'; end if;
  if p_reason = 'inventaire' then raise exception 'Motif invalide'; end if;
  return _apply_adjustment(p_adjustment_id, p_shop_id, p_product_id, p_quantity, p_reason, p_note,
                           null, coalesce(p_created_at, now()));
end $$;

-- ---------- Un inventaire validé ----------
-- p_lines : [{"adjustment_id": "...", "product_id": "...", "delta": -2}, …] (seulement les écarts)
create function record_inventory(
  p_inventory_id uuid, p_shop_id uuid, p_lines jsonb, p_nb_products integer,
  p_note text default null, p_created_at timestamptz default null
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  ligne jsonb;
  v_quand timestamptz := coalesce(p_created_at, now());
  v_total integer := 0;
  v_nb integer := 0;
begin
  if not can_access_shop(p_shop_id) then raise exception 'Accès refusé à cette boutique'; end if;
  if exists (select 1 from inventories where id = p_inventory_id) then return 0; end if;

  insert into inventories (id, shop_id, nb_products, note, user_id, created_at)
  values (p_inventory_id, p_shop_id, coalesce(p_nb_products, 0), nullif(trim(p_note), ''), auth.uid(), v_quand);

  for ligne in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    if coalesce((ligne->>'delta')::integer, 0) <> 0
       and not exists (select 1 from stock_adjustments where id = (ligne->>'adjustment_id')::uuid) then
      v_total := v_total + _apply_adjustment(
        (ligne->>'adjustment_id')::uuid, p_shop_id, (ligne->>'product_id')::uuid,
        (ligne->>'delta')::integer, 'inventaire', null, p_inventory_id, v_quand);
      v_nb := v_nb + 1;
    end if;
  end loop;

  update inventories set nb_ecarts = v_nb, ecart_valeur = v_total where id = p_inventory_id;
  return v_total;
end $$;

revoke execute on function _apply_adjustment(uuid, uuid, uuid, integer, text, text, uuid, timestamptz) from public, anon, authenticated;
revoke execute on function adjust_stock(uuid, uuid, uuid, integer, text, text, timestamptz) from public, anon;
grant execute on function adjust_stock(uuid, uuid, uuid, integer, text, text, timestamptz) to authenticated;
revoke execute on function record_inventory(uuid, uuid, jsonb, integer, text, timestamptz) from public, anon;
grant execute on function record_inventory(uuid, uuid, jsonb, integer, text, timestamptz) to authenticated;

grant select on inventories, stock_adjustments to powersync_role;

notify pgrst, 'reload schema';
