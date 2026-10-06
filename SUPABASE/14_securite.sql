-- =====================================================================
-- NACRÉA · Script 14 : renforcement de la sécurité
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- Résultat d'une revue de sécurité. Le logiciel Nacréa normal ne fait aucune
-- de ces opérations ; ce script garantit que le SERVEUR les refuse aussi,
-- même face à un logiciel modifié.
-- =====================================================================

-- ---------- 1. Une ligne ne peut jamais changer d'entreprise ----------
-- account_id est toujours recalculé depuis la boutique, à l'ajout ET à la modification.
do $$
declare t text;
begin
  foreach t in array array['subscriptions', 'stock_lots', 'sales', 'sale_items', 'payments', 'cash_sessions',
    'cash_movements', 'customer_payments', 'expenses', 'inventories', 'stock_adjustments', 'sale_returns',
    'sale_return_items', 'subscription_payments'] loop
    execute format('drop trigger if exists zz_force_account_id on %I', t);
    execute format('create trigger zz_force_account_id before insert or update on %I
                    for each row execute function fill_account_id()', t);
  end loop;
end $$;

-- ---------- 2. Ventes, paiements et stock : écrits uniquement par les fonctions du serveur ----------
drop policy if exists sales_add on sales;
drop policy if exists sales_edit on sales;
drop policy if exists items_add on sale_items;
drop policy if exists payments_add on payments;
drop policy if exists movements_add on stock_movements;
drop policy if exists lots_rw on stock_lots;
create policy lots_read on stock_lots for select using (can_access_shop(shop_id));

alter function cancel_sale(uuid, text) security definer;   -- vérifie déjà que c'est la patronne

-- Vente : contrôles d'accès en premier, abonnement suspendu refusé, ticket et date vérifiés.
create or replace function record_sale(
  p_shop_id     uuid,
  p_items       jsonb,
  p_payments    jsonb,
  p_discount    integer     default 0,
  p_customer_id uuid        default null,
  p_sale_id     uuid        default null,
  p_ticket      text        default null,
  p_created_at  timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  if not can_access_shop(p_shop_id) then
    raise exception 'Accès refusé à cette boutique';
  end if;

  -- Déjà enregistrée (envoi répété après une coupure) : on renvoie la même vente.
  if exists (select 1 from sales where id = v_sale) then
    select jsonb_build_object('sale_id', id, 'ticket_number', ticket_number, 'total', total)
      into item from sales where id = v_sale and shop_id = p_shop_id;
    if item is null then raise exception 'Identifiant de vente déjà utilisé'; end if;
    return item;
  end if;

  -- Boutique suspendue : plus de ventes après la date de blocage
  -- (les ventes faites hors ligne avant cette date restent acceptées).
  if exists (select 1 from subscriptions where shop_id = p_shop_id and status = 'suspended'
               and v_quand > coalesce(current_period_end, '-infinity'::timestamptz) + nacrea_grace()) then
    raise exception 'Abonnement suspendu : ventes impossibles';
  end if;
  -- Date de vente plausible (pas dans le futur, pas plus de 60 jours en arrière).
  if v_quand > now() + interval '1 day' or v_quand < now() - interval '60 days' then
    v_quand := now();
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

  if v_ticket is not null and v_ticket !~ '^\d{8}-\d{4}$' then
    v_ticket := null;
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

-- Entrée de stock
create or replace function receive_stock(
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
language plpgsql security definer set search_path = public as $$
declare
  lot uuid := coalesce(p_lot_id, gen_random_uuid());
begin
  if not can_access_shop(p_shop_id) then
    raise exception 'Accès refusé à cette boutique';
  end if;
  -- Déjà reçue (envoi répété après une coupure) : rien à refaire.
  if exists (select 1 from stock_lots where id = lot) then
    if not exists (select 1 from stock_lots where id = lot and shop_id = p_shop_id) then
      raise exception 'Identifiant de lot déjà utilisé';
    end if;
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

-- ---------- 3. Clientes et catégories : suppression réservée à la patronne ----------
drop policy if exists customers_rw on customers;
create policy customers_read on customers for select using (is_account_member(account_id));
create policy customers_add  on customers for insert with check (is_account_member(account_id));
create policy customers_edit on customers for update
  using (is_account_member(account_id)) with check (is_account_member(account_id));
create policy customers_del  on customers for delete using (is_account_owner(account_id));

drop policy if exists categories_rw on categories;
create policy categories_read on categories for select using (is_account_member(account_id));
create policy categories_add  on categories for insert with check (is_account_member(account_id));
create policy categories_edit on categories for update
  using (is_account_member(account_id)) with check (is_account_member(account_id));
create policy categories_del  on categories for delete using (is_account_owner(account_id));

-- Supprimer une cliente n'efface plus l'historique de ses remboursements.
alter table customer_payments drop constraint if exists customer_payments_customer_id_fkey;
alter table customer_payments add constraint customer_payments_customer_id_fkey
  foreign key (customer_id) references customers(id) on delete restrict;

-- ---------- 4. Prix des produits : modifiables uniquement par la patronne ----------
-- (une employée peut créer un produit et corriger son nom, sa photo, son code-barres…)
create or replace function protect_product_prices() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not is_account_owner(old.account_id) and (
       new.sale_price is distinct from old.sale_price
    or new.purchase_price is distinct from old.purchase_price
    or new.wholesale_price is distinct from old.wholesale_price
    or new.active is distinct from old.active
    or new.account_id is distinct from old.account_id) then
    raise exception 'Seule la patronne peut modifier les prix ou retirer un produit';
  end if;
  return new;
end $$;
drop trigger if exists protect_product_prices on products;
create trigger protect_product_prices before update on products
for each row execute function protect_product_prices();

-- ---------- 5. Caisse : une clôture ne peut pas réécrire l'ouverture ----------
create or replace function protect_cash_session() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.shop_id       := old.shop_id;
  new.opened_by     := old.opened_by;
  new.opened_at     := old.opened_at;
  new.opening_float := old.opening_float;
  if new.counted_cash is not null and new.expected_cash is not null then
    new.difference := new.counted_cash - new.expected_cash;   -- l'écart est toujours recalculé
  end if;
  return new;
end $$;
drop trigger if exists protect_cash_session on cash_sessions;
create trigger protect_cash_session before update on cash_sessions
for each row execute function protect_cash_session();

-- ---------- 6. Comptes et boutiques ----------
-- Création d'entreprise uniquement par l'écran prévu (une seule par personne).
drop policy if exists accounts_create on accounts;
-- Suppression d'une boutique : uniquement par l'administrateur Nacréa (espace admin).
drop policy if exists shops_delete on shops;

-- La propriétaire d'une entreprise ne change pas.
create or replace function protect_account_owner() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.owner_user_id is distinct from old.owner_user_id and not is_platform_admin() then
    new.owner_user_id := old.owner_user_id;
  end if;
  return new;
end $$;
drop trigger if exists protect_account_owner on accounts;
create trigger protect_account_owner before update on accounts
for each row execute function protect_account_owner();

-- La patronne ajoute des employées (par invitation), pas d'autres patronnes.
drop policy if exists members_write on members;
create policy members_insert on members for insert
  with check (is_account_owner(account_id) and role = 'employee');
create policy members_update on members for update
  using (is_account_owner(account_id))
  with check (is_account_owner(account_id) and (role = 'employee' or user_id = auth.uid()));
create policy members_delete on members for delete
  using (is_account_owner(account_id) and role = 'employee');

-- ---------- 7. Codes d'invitation : message unique et 10 essais par heure ----------
create table if not exists invitation_attempts (
  user_id    uuid not null,
  created_at timestamptz not null default now()
);
create index if not exists invitation_attempts_user on invitation_attempts (user_id, created_at);
alter table invitation_attempts enable row level security;

create or replace function join_with_invitation(p_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  inv invitations;
begin
  if auth.uid() is null then
    raise exception 'Utilisateur non connecté';
  end if;
  if exists (select 1 from members where user_id = auth.uid()) then
    raise exception 'Ce compte est déjà rattaché à une entreprise.';
  end if;
  if (select count(*) from invitation_attempts
       where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Trop d''essais. Réessayez dans une heure.';
  end if;

  select * into inv from invitations
   where code = upper(trim(p_code)) for update;

  if inv.id is null or inv.used_at is not null or inv.expires_at < now() then
    -- L'essai est noté (pas d'erreur levée, sinon la note serait annulée).
    insert into invitation_attempts (user_id) values (auth.uid());
    return null;
  end if;

  insert into members (user_id, account_id, shop_id, role, display_name, can_see_costs)
  values (auth.uid(), inv.account_id, inv.shop_id, 'employee', inv.display_name, inv.can_see_costs);

  update invitations set used_by = auth.uid(), used_at = now() where id = inv.id;
  return inv.account_id;
end $$;

-- ---------- 8. Catalogue partagé : on ne montre pas quelle boutique a ajouté quoi ----------
revoke select on catalogue from authenticated;
grant select (barcode, name, brand, variant_label, photo_url, uses) on catalogue to authenticated;

create or replace function share_to_catalogue() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_code text := nullif(trim(coalesce(new.barcode, '')), '');
  v_photo text := new.photo_url;
begin
  if v_code is null or length(v_code) < 6 or coalesce(trim(new.name), '') = '' then
    return new;
  end if;
  -- Photos acceptées : stockage Nacréa (Supabase) ou Open Beauty Facts uniquement.
  if v_photo is not null and v_photo !~ '^https://([a-z0-9]+\.supabase\.co/storage/|images\.openbeautyfacts\.org/|static\.openbeautyfacts\.org/)' then
    v_photo := null;
  end if;

  insert into catalogue (barcode, name, brand, variant_label, photo_url, account_id)
  values (v_code, trim(new.name), nullif(trim(new.brand), ''), nullif(trim(new.variant_label), ''),
          v_photo, new.account_id)
  on conflict (barcode) do update set
    name          = case when catalogue.account_id = excluded.account_id then excluded.name else catalogue.name end,
    brand         = case when catalogue.account_id = excluded.account_id
                         then coalesce(excluded.brand, catalogue.brand) else coalesce(catalogue.brand, excluded.brand) end,
    variant_label = case when catalogue.account_id = excluded.account_id
                         then coalesce(excluded.variant_label, catalogue.variant_label)
                         else coalesce(catalogue.variant_label, excluded.variant_label) end,
    photo_url     = coalesce(catalogue.photo_url, excluded.photo_url),
    uses          = catalogue.uses + case when tg_op = 'INSERT' then 1 else 0 end,
    updated_at    = now();
  return new;
end $$;

-- ---------- 9. Photos : pas de liste publique, suppression par la patronne ----------
drop policy if exists "photos produits : lecture" on storage.objects;
create policy "photos produits : lecture" on storage.objects for select to authenticated
using (bucket_id = 'product-photos' and public.is_account_member(((storage.foldername(name))[1])::uuid));
drop policy if exists "photos produits : suppression" on storage.objects;
create policy "photos produits : suppression" on storage.objects for delete to authenticated
using (bucket_id = 'product-photos' and public.is_account_owner(((storage.foldername(name))[1])::uuid));

-- ---------- 10. Correction : supprimer une boutique qui a des employées ----------
create or replace function admin_delete_shop(p_shop_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  if (select count(*) from shops where account_id = (select account_id from shops where id = p_shop_id)) <= 1 then
    raise exception 'C''est la seule boutique de cette cliente : impossible de la supprimer';
  end if;
  delete from members where shop_id = p_shop_id and role = 'employee';
  delete from shops where id = p_shop_id;
end $$;

-- ---------- 11. Fonctions internes : pas d'accès anonyme ----------
do $$
declare f text;
begin
  foreach f in array array['is_account_member(uuid)', 'is_account_owner(uuid)', 'can_access_shop(uuid)',
                           'is_shop_owner(uuid)', 'nacrea_grace()', 'is_platform_admin()'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

notify pgrst, 'reload schema';
