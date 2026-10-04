-- =====================================================================
-- NACRÉA · Script 11 : espace administrateur (pour toi, l'éditeur de Nacréa)
-- À coller dans Supabase > SQL Editor > New query.
--
-- AVANT DE CLIQUER SUR « Run » : tout en bas, remplace VOTRE_EMAIL_ICI par
-- l'adresse e-mail avec laquelle tu te connectes à Nacréa.
--
-- - Toi seul vois toutes les clientes, leurs boutiques et leurs abonnements.
-- - Tu enregistres les paiements reçus (Mobile Money, espèces…) : l'abonnement
--   est prolongé automatiquement.
-- - Les statuts se mettent à jour seuls :
--     essai ou actif terminé → « en retard » ;
--     7 jours de retard     → « suspendu » (la boutique ne peut plus vendre).
-- =====================================================================

-- ---------- Administrateurs de la plateforme ----------
create table platform_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table platform_admins enable row level security;
-- Aucune règle : personne ne lit cette table directement.

create function is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from platform_admins where user_id = auth.uid());
$$;

-- ---------- Paiements d'abonnement reçus ----------
create table subscription_payments (
  id          uuid primary key default gen_random_uuid(),
  shop_id     uuid not null references shops(id) on delete cascade,
  account_id  uuid references accounts(id) on delete cascade,
  amount      integer not null check (amount > 0),
  months      integer not null check (months between 1 and 36),
  method      text not null check (method in ('mobile_money', 'cash', 'bank', 'other')),
  note        text,
  period_end  timestamptz not null,  -- nouvelle fin d'abonnement après ce paiement
  recorded_by uuid references auth.users(id) default auth.uid(),
  paid_at     timestamptz not null default now()
);
create index on subscription_payments (account_id, paid_at);

create trigger fill_account_subscription_payments before insert on subscription_payments
for each row execute function fill_account_id();

alter table subscription_payments enable row level security;
-- La patronne peut voir ses propres paiements ; seule l'admin en crée (par les fonctions ci-dessous).
create policy subscription_payments_read on subscription_payments for select
  using (is_account_owner(account_id));

-- Délai de grâce avant suspension
create function nacrea_grace() returns interval language sql immutable as $$ select interval '7 days' $$;

-- ---------- Mise à jour automatique des statuts ----------
create function refresh_subscription_statuses() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n1 integer;
  n2 integer;
begin
  update subscriptions set status = 'late'
   where status in ('trial', 'active') and current_period_end < now();
  get diagnostics n1 = row_count;
  update subscriptions set status = 'suspended'
   where status = 'late' and current_period_end < now() - nacrea_grace();
  get diagnostics n2 = row_count;
  return n1 + n2;
end $$;

-- Toutes les heures, si l'extension pg_cron est disponible (sinon : à chaque ouverture de l'espace admin).
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('nacrea-abonnements', '7 * * * *', 'select public.refresh_subscription_statuses()');
exception when others then
  raise notice 'pg_cron indisponible (%), les statuts seront mis à jour depuis l''espace admin.', sqlerrm;
end $$;

-- ---------- Fonctions de l'espace admin ----------
create function _exiger_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_platform_admin() then
    raise exception 'Réservé à l''administrateur de Nacréa';
  end if;
end $$;

-- Chiffres globaux
create function admin_overview() returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  r jsonb;
begin
  perform _exiger_admin();
  perform refresh_subscription_statuses();
  select jsonb_build_object(
    'comptes',        (select count(*) from accounts),
    'boutiques',      (select count(*) from shops),
    'essai',          (select count(*) from subscriptions where status = 'trial'),
    'actives',        (select count(*) from subscriptions where status = 'active'),
    'en_retard',      (select count(*) from subscriptions where status = 'late'),
    'suspendues',     (select count(*) from subscriptions where status = 'suspended'),
    'revenu_mensuel', (select coalesce(sum(monthly_price), 0) from subscriptions where status in ('active', 'late')),
    'encaisse_mois',  (select coalesce(sum(amount), 0) from subscription_payments
                        where paid_at >= date_trunc('month', now())),
    'essais_fin_proche', (select count(*) from subscriptions
                           where status = 'trial' and current_period_end < now() + interval '3 days')
  ) into r;
  return r;
end $$;

-- Liste des clientes (une ligne par entreprise)
create function admin_accounts() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  perform refresh_subscription_statuses();
  return coalesce((
    select jsonb_agg(x order by x->>'prochaine_fin' nulls last)
    from (
      select jsonb_build_object(
        'id', a.id,
        'nom', a.name,
        'cree_le', a.created_at,
        'patronne', (select m.display_name from members m where m.account_id = a.id and m.role = 'owner' limit 1),
        'email', (select u.email from auth.users u where u.id = a.owner_user_id),
        'telephone', coalesce(a.phone, (select s.phone from shops s where s.account_id = a.id and s.phone is not null limit 1)),
        'nb_boutiques', (select count(*) from shops s where s.account_id = a.id),
        'statuts', (select coalesce(jsonb_agg(su.status), '[]'::jsonb)
                      from subscriptions su join shops s on s.id = su.shop_id where s.account_id = a.id),
        'mensuel', (select coalesce(sum(su.monthly_price), 0)
                      from subscriptions su join shops s on s.id = su.shop_id where s.account_id = a.id),
        'prochaine_fin', (select min(su.current_period_end)
                      from subscriptions su join shops s on s.id = su.shop_id where s.account_id = a.id),
        'derniere_vente', (select max(v.created_at) from sales v join shops s on s.id = v.shop_id where s.account_id = a.id)
      ) as x
      from accounts a
    ) t
  ), '[]'::jsonb);
end $$;

-- Fiche détaillée d'une cliente
create function admin_account_detail(p_account_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  perform refresh_subscription_statuses();
  return (
    select jsonb_build_object(
      'id', a.id,
      'nom', a.name,
      'cree_le', a.created_at,
      'patronne', (select m.display_name from members m where m.account_id = a.id and m.role = 'owner' limit 1),
      'email', (select u.email from auth.users u where u.id = a.owner_user_id),
      'telephone', a.phone,
      'nb_employees', (select count(*) from members m where m.account_id = a.id and m.role = 'employee' and m.active),
      'boutiques', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', s.id,
          'nom', s.name,
          'adresse', s.address,
          'telephone', s.phone,
          'cree_le', s.created_at,
          'statut', su.status,
          'fin', su.current_period_end,
          'prix', su.monthly_price,
          'derniere_vente', (select max(v.created_at) from sales v where v.shop_id = s.id),
          'ventes_30j', (select count(*) from sales v where v.shop_id = s.id and v.status = 'completed'
                           and v.created_at > now() - interval '30 days')
        ) order by s.created_at), '[]'::jsonb)
        from shops s left join subscriptions su on su.shop_id = s.id where s.account_id = a.id),
      'paiements', (select coalesce(jsonb_agg(jsonb_build_object(
          'id', p.id, 'boutique', s.name, 'montant', p.amount, 'mois', p.months,
          'moyen', p.method, 'note', p.note, 'le', p.paid_at, 'jusqu_au', p.period_end
        ) order by p.paid_at desc), '[]'::jsonb)
        from subscription_payments p join shops s on s.id = p.shop_id where p.account_id = a.id)
    )
    from accounts a where a.id = p_account_id
  );
end $$;

-- Paiement reçu : prolonge l'abonnement de N mois
create function admin_record_payment(
  p_shop_id uuid, p_amount integer, p_months integer, p_method text, p_note text default null
) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  su subscriptions;
  v_debut timestamptz;
  v_fin timestamptz;
begin
  perform _exiger_admin();
  select * into su from subscriptions where shop_id = p_shop_id for update;
  if su.id is null then raise exception 'Boutique introuvable'; end if;
  if coalesce(p_amount, 0) <= 0 then raise exception 'Indiquez le montant reçu'; end if;
  if coalesce(p_months, 0) not between 1 and 36 then raise exception 'Nombre de mois invalide'; end if;

  -- Suspendue : on repart d'aujourd'hui. Sinon : à la suite de la période en cours.
  v_debut := case when su.status = 'suspended' or su.current_period_end is null
                  then now() else greatest(su.current_period_end, now() - nacrea_grace()) end;
  v_fin := v_debut + make_interval(months => p_months);

  update subscriptions set status = case when v_fin > now() then 'active' else 'late' end::subscription_status,
                           current_period_end = v_fin
   where id = su.id;
  insert into subscription_payments (shop_id, amount, months, method, note, period_end)
  values (p_shop_id, p_amount, p_months, p_method, nullif(trim(p_note), ''), v_fin);
  return v_fin;
end $$;

-- Offrir des jours (prolonger un essai, geste commercial)
create function admin_extend(p_shop_id uuid, p_days integer) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  su subscriptions;
  v_fin timestamptz;
  v_deja_paye boolean;
begin
  perform _exiger_admin();
  if coalesce(p_days, 0) not between 1 and 365 then raise exception 'Nombre de jours invalide'; end if;
  select * into su from subscriptions where shop_id = p_shop_id for update;
  if su.id is null then raise exception 'Boutique introuvable'; end if;
  v_deja_paye := exists (select 1 from subscription_payments where shop_id = p_shop_id);
  v_fin := greatest(coalesce(su.current_period_end, now()), now()) + make_interval(days => p_days);
  update subscriptions
     set current_period_end = v_fin,
         status = (case when v_deja_paye then 'active' else 'trial' end)::subscription_status
   where id = su.id;
  return v_fin;
end $$;

-- Suspendre / réactiver à la main
create function admin_set_suspended(p_shop_id uuid, p_suspendre boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  su subscriptions;
  v_statut subscription_status;
begin
  perform _exiger_admin();
  select * into su from subscriptions where shop_id = p_shop_id for update;
  if su.id is null then raise exception 'Boutique introuvable'; end if;
  if p_suspendre then
    v_statut := 'suspended';
  elsif su.current_period_end is not null and su.current_period_end > now() then
    v_statut := case when exists (select 1 from subscription_payments where shop_id = p_shop_id)
                     then 'active' else 'trial' end;
  else
    v_statut := 'late'; -- réactivée, mais il faut un paiement ou des jours offerts
  end if;
  update subscriptions set status = v_statut where id = su.id;
  return v_statut::text;
end $$;

-- Prix mensuel personnalisé (remise négociée)
create function admin_set_price(p_shop_id uuid, p_price integer) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  if coalesce(p_price, -1) < 0 then raise exception 'Prix invalide'; end if;
  update subscriptions set monthly_price = p_price where shop_id = p_shop_id;
end $$;

-- Supprimer une boutique de test (efface aussi ses ventes et son stock)
create function admin_delete_shop(p_shop_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  if (select count(*) from shops where account_id = (select account_id from shops where id = p_shop_id)) <= 1 then
    raise exception 'C''est la seule boutique de cette cliente : impossible de la supprimer';
  end if;
  update members set shop_id = null where shop_id = p_shop_id;
  delete from shops where id = p_shop_id;
end $$;

-- Annuler un paiement saisi par erreur (sans toucher à la date de fin : corrige-la avec « Offrir des jours »)
create function admin_delete_payment(p_payment_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  delete from subscription_payments where id = p_payment_id;
end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'is_platform_admin()', 'admin_overview()', 'admin_accounts()', 'admin_account_detail(uuid)',
    'admin_record_payment(uuid, integer, integer, text, text)', 'admin_extend(uuid, integer)',
    'admin_set_suspended(uuid, boolean)', 'admin_set_price(uuid, integer)',
    'admin_delete_shop(uuid)', 'admin_delete_payment(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  revoke execute on function refresh_subscription_statuses() from public, anon, authenticated;
  revoke execute on function _exiger_admin() from public, anon;
end $$;

grant select on subscription_payments to powersync_role;

-- ---------- Toi, administrateur ----------
-- Remplace VOTRE_EMAIL_ICI par ton e-mail de connexion à Nacréa (entre les apostrophes).
insert into platform_admins (user_id)
select id from auth.users where lower(email) = lower(trim('VOTRE_EMAIL_ICI'))
on conflict do nothing;

select case when count(*) > 0 then 'OK : administrateur enregistré'
            else 'ATTENTION : e-mail introuvable, remplace VOTRE_EMAIL_ICI puis relance seulement les 3 dernières lignes'
       end as resultat
from platform_admins;

notify pgrst, 'reload schema';
