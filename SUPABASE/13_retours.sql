-- =====================================================================
-- NACRÉA · Script 13 : retours et échanges
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- - Un retour part d'un reçu : tout ou partie des articles.
-- - Article en bon état : remis en stock. Abîmé : non remis (c'est une perte).
-- - Remboursement : espèces (pris dans la caisse), Mobile Money, carte,
--   ou déduit de la dette de la cliente (vente à crédit).
-- - Échange : retour remboursé en espèces, puis nouvelle vente.
-- - Fonctionne hors ligne, rejoué une seule fois.
-- =====================================================================

create table sale_returns (
  id            uuid primary key,
  account_id    uuid references accounts(id) on delete cascade,
  shop_id       uuid not null references shops(id) on delete cascade,
  sale_id       uuid not null references sales(id) on delete cascade,
  customer_id   uuid references customers(id) on delete set null,
  refund_amount integer not null default 0 check (refund_amount >= 0),
  refund_method text not null check (refund_method in ('cash', 'mobile_money', 'card', 'debt')),
  note          text,
  user_id       uuid references auth.users(id),
  created_at    timestamptz not null default now()
);
create index on sale_returns (shop_id, created_at);
create index on sale_returns (sale_id);

create table sale_return_items (
  id          uuid primary key default gen_random_uuid(),
  return_id   uuid not null references sale_returns(id) on delete cascade,
  account_id  uuid references accounts(id) on delete cascade,
  shop_id     uuid not null references shops(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  quantity    integer not null check (quantity > 0),
  unit_refund integer not null default 0,   -- remboursé par article (remise de la vente comprise)
  cost_price  integer not null default 0,   -- prix d'achat de l'article
  restocked   boolean not null default true -- remis en rayon ?
);
create index on sale_return_items (return_id);

create trigger fill_account_returns before insert on sale_returns
for each row execute function fill_account_id();
create trigger fill_account_return_items before insert on sale_return_items
for each row execute function fill_account_id();

alter table sale_returns enable row level security;
alter table sale_return_items enable row level security;
create policy returns_read on sale_returns for select using (can_access_shop(shop_id));
create policy return_items_read on sale_return_items for select using (can_access_shop(shop_id));

-- Le remboursement « déduit de la dette » est enregistré comme un règlement de la cliente.
alter table customer_payments drop constraint if exists customer_payments_method_check;
alter table customer_payments add constraint customer_payments_method_check
  check (method in ('cash', 'mobile_money', 'card', 'return'));

-- ---------- Enregistrer un retour ----------
-- p_items : [{"product_id": "...", "quantity": 1, "restock": true}, …]
create function record_return(
  p_return_id uuid, p_shop_id uuid, p_sale_id uuid, p_items jsonb, p_refund_method text,
  p_note text default null, p_created_at timestamptz default null, p_debt_payment_id uuid default null
) returns integer
language plpgsql security definer set search_path = public as $$
declare
  v_vente sales;
  v_quand timestamptz := coalesce(p_created_at, now());
  v_ratio numeric;
  ligne jsonb;
  v_produit uuid;
  v_qte integer;
  v_vendu integer;
  v_deja integer;
  v_prix numeric;
  v_cout integer;
  v_unitaire integer;
  v_total integer := 0;
  v_restant integer;
  v_prend integer;
  lot record;
begin
  if not can_access_shop(p_shop_id) then raise exception 'Accès refusé à cette boutique'; end if;
  if exists (select 1 from sale_returns where id = p_return_id) then return 0; end if;

  select * into v_vente from sales where id = p_sale_id and shop_id = p_shop_id;
  if v_vente.id is null then raise exception 'Reçu introuvable dans cette boutique'; end if;
  if v_vente.status = 'cancelled' then raise exception 'Ce reçu a été annulé'; end if;
  if p_refund_method = 'debt' and v_vente.customer_id is null then
    raise exception 'Pas de cliente sur ce reçu : remboursez en espèces ou Mobile Money';
  end if;
  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then raise exception 'Aucun article à retourner'; end if;

  -- La remise globale du reçu est répartie sur chaque article.
  v_ratio := case when v_vente.subtotal > 0 then v_vente.total::numeric / v_vente.subtotal else 1 end;

  insert into sale_returns (id, shop_id, sale_id, customer_id, refund_method, note, user_id, created_at)
  values (p_return_id, p_shop_id, p_sale_id, v_vente.customer_id, p_refund_method,
          nullif(trim(p_note), ''), auth.uid(), v_quand);

  for ligne in select * from jsonb_array_elements(p_items) loop
    v_produit := (ligne->>'product_id')::uuid;
    v_qte := coalesce((ligne->>'quantity')::integer, 0);
    if v_qte <= 0 then continue; end if;

    select coalesce(sum(quantity), 0),
           case when sum(quantity) > 0 then sum(quantity * unit_price - discount)::numeric / sum(quantity) else 0 end,
           case when sum(quantity) > 0 then round(sum(quantity * cost_price)::numeric / sum(quantity)) else 0 end
      into v_vendu, v_prix, v_cout
      from sale_items where sale_id = p_sale_id and product_id = v_produit;
    select coalesce(sum(i.quantity), 0) into v_deja
      from sale_return_items i join sale_returns r on r.id = i.return_id
     where r.sale_id = p_sale_id and i.product_id = v_produit;
    if v_qte > v_vendu - v_deja then
      raise exception 'Quantité retournée trop grande (vendu : %, déjà retourné : %)', v_vendu, v_deja;
    end if;

    v_unitaire := round(v_prix * v_ratio);
    v_total := v_total + v_unitaire * v_qte;

    insert into sale_return_items (return_id, shop_id, product_id, quantity, unit_refund, cost_price, restocked)
    values (p_return_id, p_shop_id, v_produit, v_qte, v_unitaire, v_cout,
            coalesce((ligne->>'restock')::boolean, true));

    if coalesce((ligne->>'restock')::boolean, true) then
      -- Remise en rayon : comble d'abord un stock négatif, puis nouveau lot.
      v_restant := v_qte;
      for lot in
        select id, quantity from stock_lots
         where shop_id = p_shop_id and product_id = v_produit and quantity < 0
         order by received_at for update
      loop
        exit when v_restant = 0;
        v_prend := least(-lot.quantity, v_restant);
        update stock_lots set quantity = quantity + v_prend where id = lot.id;
        v_restant := v_restant - v_prend;
      end loop;
      if v_restant > 0 then
        insert into stock_lots (shop_id, product_id, quantity, cost_price, received_at)
        values (p_shop_id, v_produit, v_restant, v_cout, v_quand);
      end if;
      insert into stock_movements (shop_id, product_id, type, quantity, reason, user_id, created_at)
      values (p_shop_id, v_produit, 'return', v_qte, 'Retour reçu ' || v_vente.ticket_number, auth.uid(), v_quand);
    end if;
  end loop;

  update sale_returns set refund_amount = v_total where id = p_return_id;

  if p_refund_method = 'debt' and v_total > 0 then
    insert into customer_payments (id, shop_id, customer_id, amount, method, note, user_id, created_at)
    values (coalesce(p_debt_payment_id, gen_random_uuid()), p_shop_id, v_vente.customer_id, v_total, 'return',
            'Retour du reçu ' || v_vente.ticket_number, auth.uid(), v_quand)
    on conflict (id) do nothing;
  end if;
  return v_total;
end $$;

revoke execute on function record_return(uuid, uuid, uuid, jsonb, text, text, timestamptz, uuid) from public, anon;
grant execute on function record_return(uuid, uuid, uuid, jsonb, text, text, timestamptz, uuid) to authenticated;

grant select on sale_returns, sale_return_items to powersync_role;

notify pgrst, 'reload schema';
