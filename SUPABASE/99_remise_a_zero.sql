-- =====================================================================
-- YDS BEAUTY · Script 99 : REMISE À ZÉRO (efface tout)
-- À coller dans Supabase > SQL Editor > New query, puis « Run ».
--
-- ⚠️  DANGER : ce script EFFACE
--   - tous les comptes de connexion (clientes, employées, administrateurs) ;
--   - toutes les boutiques, produits, stocks, ventes, clientes, dépenses ;
--   - toutes les licences et tous les paiements.
-- Il GARDE : la structure de la base, les fonctions, et la liste des
-- administrateurs (table admin_emails, script 18).
--
-- À utiliser UNE SEULE FOIS, avant le lancement officiel, pour repartir
-- d'une base propre. Ne JAMAIS l'exécuter quand de vraies clientes utilisent
-- le logiciel.
--
-- Ensuite : crée ton compte avec ydstechnolgy@gmail.com depuis l'application
-- (ou la page d'administration), puis c'est tout.
-- =====================================================================

do $$
declare
  t text;
begin
  for t in
    select tablename from pg_tables
     where schemaname = 'public' and tablename <> 'admin_emails'
  loop
    execute format('truncate table public.%I restart identity cascade', t);
  end loop;
end $$;

-- Tous les comptes de connexion (les sessions et identités suivent automatiquement).
delete from auth.users;

select (select count(*) from auth.users) as comptes_restants,
       (select count(*) from admin_emails) as administrateurs_gardes;
