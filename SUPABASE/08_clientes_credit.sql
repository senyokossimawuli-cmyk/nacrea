-- =====================================================================
-- NACRÉA · Script 08 : clientes et crédit
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- - Une vente peut être rattachée à une cliente (sales.customer_id).
-- - La partie non payée d'une vente est un paiement de type « credit ».
-- - Les remboursements de la cliente sont enregistrés dans customer_payments.
-- - Ce que doit une cliente = ses crédits (ventes non annulées) - ses remboursements.
-- =====================================================================

-- ---------- Remboursements des clientes ----------
create table customer_payments (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid references accounts(id) on delete cascade,
  shop_id     uuid not null references shops(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  amount      integer not null check (amount > 0),
  method      text not null check (method in ('cash', 'mobile_money', 'card')),
  note        text,
  user_id     uuid references auth.users(id),
  created_at  timestamptz not null default now()
);
create index on customer_payments (customer_id);
create index on customer_payments (shop_id, created_at);

create trigger fill_account_customer_payments before insert or update of shop_id on customer_payments
for each row execute function fill_account_id();

-- La cliente doit appartenir à la même entreprise que la boutique.
create function check_customer_payment() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (
    select 1 from customers c join shops s on s.account_id = c.account_id
     where c.id = new.customer_id and s.id = new.shop_id
  ) then
    raise exception 'Cliente inconnue pour cette boutique';
  end if;
  return new;
end $$;
create trigger check_customer_payment before insert on customer_payments
for each row execute function check_customer_payment();

alter table customer_payments enable row level security;
create policy customer_payments_read on customer_payments for select
  using (is_account_member(account_id));
create policy customer_payments_add on customer_payments for insert
  with check (can_access_shop(shop_id));
-- Corriger une erreur de saisie : réservé à la patronne.
create policy customer_payments_del on customer_payments for delete
  using (is_account_owner(account_id));

-- ---------- Une vente à crédit doit avoir une cliente ----------
create function check_credit_customer() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.method = 'credit' and not exists (
    select 1 from sales where id = new.sale_id and customer_id is not null
  ) then
    raise exception 'Une vente à crédit doit être rattachée à une cliente';
  end if;
  return new;
end $$;
create trigger check_credit_customer before insert on payments
for each row execute function check_credit_customer();

-- La cliente d'une vente doit appartenir à la même entreprise.
create function check_sale_customer() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.customer_id is not null and not exists (
    select 1 from customers c join shops s on s.account_id = c.account_id
     where c.id = new.customer_id and s.id = new.shop_id
  ) then
    raise exception 'Cliente inconnue pour cette boutique';
  end if;
  return new;
end $$;
create trigger check_sale_customer before insert on sales
for each row execute function check_sale_customer();

grant select on customer_payments to powersync_role;

notify pgrst, 'reload schema';
