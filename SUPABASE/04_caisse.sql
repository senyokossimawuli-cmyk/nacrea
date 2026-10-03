-- =====================================================================
-- NACRÉA · Script 04 : la caisse (ventes, paiements, annulations)
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- =====================================================================

-- ---------- Enregistrer une vente ----------
-- p_items    : [{"product_id": "...", "quantity": 2, "unit_price": 3500, "discount": 0}, ...]
-- p_payments : [{"method": "cash", "amount": 7000}, ...]   (la somme doit égaler le total)
-- Le stock est retiré lot par lot, en commençant par celui qui périme le plus tôt.
-- Si le stock ne suffit pas, la vente passe quand même et le stock devient négatif.
create function record_sale(
  p_shop_id     uuid,
  p_items       jsonb,
  p_payments    jsonb,
  p_discount    integer default 0,
  p_customer_id uuid    default null
) returns jsonb
language plpgsql security invoker set search_path = public as $$
declare
  v_sale      uuid;
  v_ticket    text;
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
  if not can_access_shop(p_shop_id) then
    raise exception 'Accès refusé à cette boutique';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Le panier est vide';
  end if;

  -- 1. Total de la vente
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

  -- 2. Numéro de ticket : AAAAMMJJ-0001, par boutique et par jour
  select to_char(now(), 'YYYYMMDD') || '-' || lpad((count(*) + 1)::text, 4, '0')
    into v_ticket
    from sales
   where shop_id = p_shop_id and created_at::date = now()::date;

  insert into sales (shop_id, customer_id, user_id, ticket_number, status, subtotal, discount, total)
  values (p_shop_id, p_customer_id, auth.uid(), v_ticket, 'completed', v_subtotal,
          coalesce(p_discount, 0), v_total)
  returning id into v_sale;

  -- 3. Lignes de vente et sortie de stock (lot qui périme le plus tôt d'abord)
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
      insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id)
      values (p_shop_id, v_product, lot.id, 'sale', -v_prend, 'Ticket ' || v_ticket, auth.uid());
      v_restant := v_restant - v_prend;
    end loop;

    -- Stock insuffisant : on vend quand même, le stock passe en négatif.
    if v_restant > 0 then
      select purchase_price into v_cout from products where id = v_product;
      insert into stock_lots (shop_id, product_id, quantity, cost_price)
      values (p_shop_id, v_product, -v_restant, coalesce(v_cout, 0))
      returning id into lot;
      insert into sale_items (sale_id, shop_id, product_id, lot_id, quantity, unit_price, cost_price, discount)
      values (v_sale, p_shop_id, v_product, lot.id, v_restant, v_price, coalesce(v_cout, 0),
              case when v_restant = v_qty then v_line_disc else 0 end);
      insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id)
      values (p_shop_id, v_product, lot.id, 'sale', -v_restant,
              'Ticket ' || v_ticket || ' (stock insuffisant)', auth.uid());
    end if;
  end loop;

  -- 4. Paiements
  for pay in select * from jsonb_array_elements(p_payments) loop
    if (pay->>'amount')::integer > 0 then
      insert into payments (sale_id, shop_id, method, amount)
      values (v_sale, p_shop_id, (pay->>'method')::payment_method, (pay->>'amount')::integer);
    end if;
  end loop;

  return jsonb_build_object('sale_id', v_sale, 'ticket_number', v_ticket, 'total', v_total);
end $$;

revoke execute on function record_sale(uuid, jsonb, jsonb, integer, uuid) from public, anon;
grant execute on function record_sale(uuid, jsonb, jsonb, integer, uuid) to authenticated;

-- ---------- Annuler une vente (réservé à la patronne) ----------
-- Le stock est remis dans les lots d'origine ; la vente reste visible, marquée "annulée".
create function cancel_sale(p_sale_id uuid, p_reason text default null)
returns void
language plpgsql security invoker set search_path = public as $$
declare
  v_shop   uuid;
  v_ticket text;
  v_status sale_status;
  ligne    record;
begin
  select shop_id, ticket_number, status into v_shop, v_ticket, v_status
    from sales where id = p_sale_id for update;
  if v_shop is null then raise exception 'Vente introuvable'; end if;
  if not is_shop_owner(v_shop) then
    raise exception 'Seule la patronne peut annuler une vente';
  end if;
  if v_status <> 'completed' then raise exception 'Cette vente est déjà annulée'; end if;

  for ligne in select product_id, lot_id, quantity from sale_items where sale_id = p_sale_id loop
    if ligne.lot_id is not null then
      update stock_lots set quantity = quantity + ligne.quantity where id = ligne.lot_id;
    end if;
    insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id)
    values (v_shop, ligne.product_id, ligne.lot_id, 'return', ligne.quantity,
            'Annulation ticket ' || v_ticket || coalesce(' : ' || p_reason, ''), auth.uid());
  end loop;

  update sales set status = 'cancelled' where id = p_sale_id;
end $$;

revoke execute on function cancel_sale(uuid, text) from public, anon;
grant execute on function cancel_sale(uuid, text) to authenticated;
