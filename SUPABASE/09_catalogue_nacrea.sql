-- =====================================================================
-- NACRÉA · Script 09 : catalogue Nacréa partagé (codes-barres)
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
--
-- Quand une boutique enregistre un produit avec son code-barres, Nacréa retient
-- son nom, sa marque, sa variante et sa photo. La boutique suivante qui scanne
-- ce code voit la fiche préremplie.
-- Seules ces 4 informations sont partagées : JAMAIS les prix, le stock ou les ventes.
-- =====================================================================

create table catalogue (
  barcode       text primary key,
  name          text not null,
  brand         text,
  variant_label text,
  photo_url     text,
  account_id    uuid references accounts(id) on delete set null, -- première boutique à l'avoir ajouté
  uses          integer not null default 1,                      -- nombre de boutiques qui l'ont enregistré
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table catalogue enable row level security;
-- Toute utilisatrice connectée peut consulter le catalogue ; personne ne l'écrit directement.
create policy catalogue_read on catalogue for select to authenticated using (true);
grant select on catalogue to authenticated;

create function share_to_catalogue() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_code text := nullif(trim(coalesce(new.barcode, '')), '');
begin
  if v_code is null or length(v_code) < 6 or coalesce(trim(new.name), '') = '' then
    return new;
  end if;

  insert into catalogue (barcode, name, brand, variant_label, photo_url, account_id)
  values (v_code, trim(new.name), nullif(trim(new.brand), ''), nullif(trim(new.variant_label), ''),
          new.photo_url, new.account_id)
  on conflict (barcode) do update set
    -- La première boutique peut corriger sa fiche ; les autres complètent seulement ce qui manque.
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

create trigger share_to_catalogue
after insert or update of barcode, name, brand, variant_label, photo_url on products
for each row execute function share_to_catalogue();

-- Produits déjà enregistrés avant ce script
insert into catalogue (barcode, name, brand, variant_label, photo_url, account_id, created_at)
select distinct on (trim(barcode))
       trim(barcode), trim(name), nullif(trim(brand), ''), nullif(trim(variant_label), ''),
       photo_url, account_id, created_at
  from products
 where length(trim(coalesce(barcode, ''))) >= 6 and coalesce(trim(name), '') <> ''
 order by trim(barcode), created_at
on conflict (barcode) do nothing;

notify pgrst, 'reload schema';
