-- =====================================================================
-- NACRÉA · Script 03 : produits, stock et photos
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- =====================================================================

-- ---------- Garde-fou : un produit ne peut être stocké ou vendu
-- que dans une boutique du même compte ----------
create function check_same_account() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from products p join shops s on s.account_id = p.account_id
    where p.id = new.product_id and s.id = new.shop_id
  ) then
    raise exception 'Produit et boutique de comptes différents';
  end if;
  return new;
end $$;

create trigger same_account_lots before insert or update on stock_lots
for each row execute function check_same_account();
create trigger same_account_movements before insert or update on stock_movements
for each row execute function check_same_account();
create trigger same_account_sale_items before insert or update on sale_items
for each row execute function check_same_account();

-- ---------- Vue : stock total par produit et par boutique ----------
-- security_invoker = les règles de sécurité de chaque personne s'appliquent.
create view product_stock with (security_invoker = true) as
select
  l.shop_id,
  l.product_id,
  coalesce(sum(l.quantity), 0)::integer                       as quantity,
  min(l.expiry_date) filter (where l.quantity > 0)            as next_expiry
from stock_lots l
group by l.shop_id, l.product_id;

-- ---------- Entrée de stock : un lot + son mouvement, en une seule opération ----------
create function receive_stock(
  p_shop_id    uuid,
  p_product_id uuid,
  p_quantity   integer,
  p_cost_price integer default 0,
  p_expiry     date    default null,
  p_reason     text    default null
) returns uuid
language plpgsql security invoker set search_path = public as $$
declare
  lot uuid;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'La quantité doit être supérieure à zéro';
  end if;

  insert into stock_lots (shop_id, product_id, quantity, cost_price, expiry_date)
  values (p_shop_id, p_product_id, p_quantity, coalesce(p_cost_price, 0), p_expiry)
  returning id into lot;

  insert into stock_movements (shop_id, product_id, lot_id, type, quantity, reason, user_id)
  values (p_shop_id, p_product_id, lot, 'purchase', p_quantity, p_reason, auth.uid());

  return lot;
end $$;

revoke execute on function receive_stock(uuid, uuid, integer, integer, date, text) from public, anon;
grant execute on function receive_stock(uuid, uuid, integer, integer, date, text) to authenticated;

-- ---------- Photos des produits ----------
-- Dossier par compte : product-photos/<id du compte>/<fichier>
insert into storage.buckets (id, name, public)
values ('product-photos', 'product-photos', true)
on conflict (id) do nothing;

create policy "photos produits : lecture"
on storage.objects for select
using (bucket_id = 'product-photos');

create policy "photos produits : ajout"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'product-photos'
  and public.is_account_member(((storage.foldername(name))[1])::uuid)
);

create policy "photos produits : modification"
on storage.objects for update to authenticated
using (
  bucket_id = 'product-photos'
  and public.is_account_member(((storage.foldername(name))[1])::uuid)
);

create policy "photos produits : suppression"
on storage.objects for delete to authenticated
using (
  bucket_id = 'product-photos'
  and public.is_account_member(((storage.foldername(name))[1])::uuid)
);
