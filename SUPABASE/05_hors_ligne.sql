-- =====================================================================
-- NACRÉA · Script 05 : préparation du mode hors ligne (PowerSync)
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- AVANT DE LANCER : remplacez REMPLACEZ_PAR_UN_MOT_DE_PASSE (2 lignes plus bas)
-- par un long mot de passe inventé (lettres et chiffres, sans espace ni apostrophe).
-- Notez-le : il servira une seule fois, dans PowerSync. Ne le partagez avec personne.
-- =====================================================================

-- ---------- 1. Accès en lecture pour PowerSync ----------
create role powersync_role with replication bypassrls login password '7979Roland.';
grant select on all tables in schema public to powersync_role;
alter default privileges in schema public grant select on tables to powersync_role;

create publication powersync for all tables;

-- ---------- 2. Le compte de chaque boutique recopié sur les tables de boutique ----------
-- (permet de synchroniser toutes les boutiques d'une patronne d'un coup)
alter table subscriptions add column account_id uuid references accounts(id) on delete cascade;
alter table stock_lots    add column account_id uuid references accounts(id) on delete cascade;
alter table sales         add column account_id uuid references accounts(id) on delete cascade;
alter table sale_items    add column account_id uuid references accounts(id) on delete cascade;
alter table payments      add column account_id uuid references accounts(id) on delete cascade;

update subscriptions t set account_id = s.account_id from shops s where s.id = t.shop_id;
update stock_lots    t set account_id = s.account_id from shops s where s.id = t.shop_id;
update sales         t set account_id = s.account_id from shops s where s.id = t.shop_id;
update sale_items    t set account_id = s.account_id from shops s where s.id = t.shop_id;
update payments      t set account_id = s.account_id from shops s where s.id = t.shop_id;

create function fill_account_id() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  select account_id into new.account_id from shops where id = new.shop_id;
  return new;
end $$;

create trigger fill_account_subscriptions before insert or update of shop_id on subscriptions
for each row execute function fill_account_id();
create trigger fill_account_lots before insert or update of shop_id on stock_lots
for each row execute function fill_account_id();
create trigger fill_account_sales before insert or update of shop_id on sales
for each row execute function fill_account_id();
create trigger fill_account_items before insert or update of shop_id on sale_items
for each row execute function fill_account_id();
create trigger fill_account_payments before insert or update of shop_id on payments
for each row execute function fill_account_id();

-- ---------- 3. Entrée de stock rejouable (identifiant du lot fourni par le logiciel) ----------
drop function receive_stock(uuid, uuid, integer, integer, date, text);

create function receive_stock(
  p_shop_id    uuid,
  p_product_id uuid,
  p_quantity   integer,
  p_cost_price integer default 0,
  p_expiry     date    default null,
  p_reason     text    default null,
  p_lot_id     uuid    default null,
  p_received_at timestamptz default null
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

  insert into stock_lots (id, shop_id, product_id, quantity, cost_price, expiry_date, received_at)
  values (lot, p_shop_id, p_product_id, p_quantity, coalesce(p_cost_price, 0), p_expiry,
          coalesce(p_received_at, now()));

  insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
  values (p_shop_id, p_product_id, lot, 'purchase', p_quantity, p_reason, auth.uid(),
          coalesce(p_received_at, now()));
  return lot;
end $$;

revoke execute on function receive_stock(uuid, uuid, integer, integer, date, text, uuid, timestamptz) from public, anon;
grant execute on function receive_stock(uuid, uuid, integer, integer, date, text, uuid, timestamptz) to authenticated;

-- ---------- 4. Vente rejouable (identifiant, ticket et heure fournis par le logiciel) ----------
drop function record_sale(uuid, jsonb, jsonb, integer, uuid);

create function record_sale(
  p_shop_id     uuid,
  p_items       jsonb,
  p_payments    jsonb,
  p_discount    integer     default 0,
  p_customer_id uuid        default null,
  p_sale_id     uuid        default null,
  p_ticket      text        default null,
  p_created_at  timestamptz default null
) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare
  v_sale      uuid := coalesce(p_sale_id, gen_random_uuid());
  v_quand     timestamptz := coalesce(p_created_at, now());
  v_ticket    text := p_ticket;
  v_subtotal  integer := 0;
  v_total     integer;
  v_paid      integer := 0;
  item        jsonb;
  pay         jsonb;
  v_product   uuid;
  v_qty       integer;
  v_price     integer;
  v_line_disc integer;
  v_restant   integer;
  v_prend     integer;
  v_cout      integer;
  lot         record;
begin
  -- Déjà enregistrée (envoi répété après une coupure) : on renvoie la même vente.
  if exists (select 1 from sales where id = v_sale) then
    select jsonb_build_object('sale_id', id, 'ticket_number', ticket_number, 'total', total)
      into item from sales where id = v_sale;
    return item;
  end if;

  if not can_access_shop(p_shop_id) then
    raise exception 'Accès refusé à cette boutique';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Le panier est vide';
  end if;

  for item in select * from jsonb_array_elements(p_items) loop
    v_qty       := (item->>'quantity')::integer;
    v_price     := (item->>'unit_price')::integer;
    v_line_disc := coalesce((item->>'discount')::integer, 0);
    if v_qty is null or v_qty <= 0 then raise exception 'Quantité invalide'; end if;
    if v_price is null or v_price < 0 or v_line_disc < 0 then raise exception 'Prix invalide'; end if;
    v_subtotal := v_subtotal + v_qty * v_price - v_line_disc;
  end loop;

  v_total := v_subtotal - coalesce(p_discount, 0);
  if coalesce(p_discount, 0) < 0 or v_total < 0 then
    raise exception 'Remise invalide';
  end if;

  for pay in select * from jsonb_array_elements(p_payments) loop
    if (pay->>'amount')::integer < 0 then raise exception 'Montant de paiement invalide'; end if;
    v_paid := v_paid + (pay->>'amount')::integer;
  end loop;
  if v_paid <> v_total then
    raise exception 'Les paiements (%) ne correspondent pas au total (%)', v_paid, v_total;
  end if;

  if v_ticket is null then
    select to_char(v_quand, 'YYYYMMDD') || '-' || lpad((count(*) + 1)::text, 4, '0')
      into v_ticket
      from sales
     where shop_id = p_shop_id and created_at::date = v_quand::date;
  end if;

  insert into sales (id, shop_id, customer_id, user_id, ticket_number, status, subtotal, discount, total, created_at)
  values (v_sale, p_shop_id, p_customer_id, auth.uid(), v_ticket, 'completed', v_subtotal,
          coalesce(p_discount, 0), v_total, v_quand);

  for item in select * from jsonb_array_elements(p_items) loop
    v_product   := (item->>'product_id')::uuid;
    v_qty       := (item->>'quantity')::integer;
    v_price     := (item->>'unit_price')::integer;
    v_line_disc := coalesce((item->>'discount')::integer, 0);
    v_restant   := v_qty;

    for lot in
      select id, quantity, cost_price from stock_lots
       where shop_id = p_shop_id and product_id = v_product and quantity > 0
       order by expiry_date asc nulls last, received_at asc
       for update
    loop
      exit when v_restant = 0;
      v_prend := least(lot.quantity, v_restant);
      update stock_lots set quantity = quantity - v_prend where id = lot.id;
      insert into sale_items (sale_id, shop_id, product_id, lot_id, quantity, unit_price, cost_price, discount)
      values (v_sale, p_shop_id, v_product, lot.id, v_prend, v_price, lot.cost_price,
              case when v_restant = v_qty then v_line_disc else 0 end);
      insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
      values (p_shop_id, v_product, lot.id, 'sale', -v_prend, 'Ticket ' || v_ticket, auth.uid(), v_quand);
      v_restant := v_restant - v_prend;
    end loop;

    if v_restant > 0 then
      select purchase_price into v_cout from products where id = v_product;
      insert into stock_lots (shop_id, product_id, quantity, cost_price)
      values (p_shop_id, v_product, -v_restant, coalesce(v_cout, 0))
      returning id into lot;
      insert into sale_items (sale_id, shop_id, product_id, lot_id, quantity, unit_price, cost_price, discount)
      values (v_sale, p_shop_id, v_product, lot.id, v_restant, v_price, coalesce(v_cout, 0),
              case when v_restant = v_qty then v_line_disc else 0 end);
      insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id, created_at)
      values (p_shop_id, v_product, lot.id, 'sale', -v_restant,
              'Ticket ' || v_ticket || ' (stock insuffisant)', auth.uid(), v_quand);
    end if;
  end loop;

  for pay in select * from jsonb_array_elements(p_payments) loop
    if (pay->>'amount')::integer > 0 then
      insert into payments (sale_id, shop_id, method, amount, created_at)
      values (v_sale, p_shop_id, (pay->>'method')::payment_method, (pay->>'amount')::integer, v_quand);
    end if;
  end loop;

  return jsonb_build_object('sale_id', v_sale, 'ticket_number', v_ticket, 'total', v_total);
end $$;

revoke execute on function record_sale(uuid, jsonb, jsonb, integer, uuid, uuid, text, timestamptz) from public, anon;
grant execute on function record_sale(uuid, jsonb, jsonb, integer, uuid, uuid, text, timestamptz) to authenticated;

-- Les fonctions remplacées : PowerSync doit les voir dans son cache.
notify pgrst, 'reload schema';
