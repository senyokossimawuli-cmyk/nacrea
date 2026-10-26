-- =====================================================================
-- YDS BEAUTY · Script 18 : l'administrateur est l'e-mail de l'entreprise
-- À coller dans Supabase > SQL Editor > New query, puis « Run ».
--
-- Avant : l'administrateur était le compte créé avec l'ancien e-mail.
-- Maintenant : les droits d'administrateur sont donnés à une ADRESSE E-MAIL
-- (ydstechnolgy@gmail.com). L'ordre n'a plus d'importance :
--   - tu peux exécuter ce script avant ou après avoir créé le compte ;
--   - dès que tu te connectes avec cette adresse (code reçu par e-mail),
--     tu es administrateur.
-- Les anciens administrateurs (par compte) perdent leurs droits.
-- Pour ajouter ou retirer quelqu'un plus tard : voir les 2 lignes en bas.
-- =====================================================================

create table if not exists admin_emails (
  email      text primary key check (email = lower(trim(email))),
  created_at timestamptz not null default now()
);
alter table admin_emails enable row level security;
-- Aucune règle : personne ne lit cette table directement.

create or replace function is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from auth.users u
      join admin_emails e on e.email = lower(trim(u.email))
     where u.id = auth.uid()
       and u.email_confirmed_at is not null   -- l'adresse doit avoir été confirmée par le code reçu
  );
$$;

-- Anciens administrateurs (par compte) : retirés.
delete from platform_admins;

insert into admin_emails (email) values ('ydstechnolgy@gmail.com')
on conflict do nothing;

select email as administrateur from admin_emails;

-- Plus tard :
--   ajouter  : insert into admin_emails (email) values ('prenom@exemple.com');
--   retirer  : delete from admin_emails where email = 'prenom@exemple.com';

notify pgrst, 'reload schema';
