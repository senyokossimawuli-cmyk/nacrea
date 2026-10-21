-- =====================================================================
-- YDS BEAUTY · Script 17 : la licence devient l'abonnement
-- À coller dans Supabase > SQL Editor > New query, puis « Run ».
--
-- - Chaque licence a une date d'expiration (ou est illimitée).
-- - Durée choisie à la création (14 jours, 1 mois, 3 mois…) : elle démarre
--   le jour où la patronne active sa clé.
-- - Paiement reçu → la licence est prolongée. Une seule date à suivre.
-- - 7 jours avant la fin : bandeau d'avertissement. Après la fin : 7 jours
--   de grâce (bandeau rouge), puis YDS Beauty se bloque jusqu'au paiement.
-- - Les abonnements des boutiques suivent automatiquement la licence.
-- =====================================================================

alter table licenses add column if not exists expires_at timestamptz;
-- Durée en attente : appliquée au moment où la patronne active la clé.
alter table licenses add column if not exists pending_months integer check (pending_months between 0 and 120);
alter table licenses add column if not exists pending_days integer check (pending_days between 0 and 3650);

-- Licences déjà liées : elles reprennent la date de fin actuelle de l'abonnement.
update licenses l
   set expires_at = (select max(su.current_period_end) from subscriptions su where su.account_id = l.account_id)
 where l.account_id is not null and l.expires_at is null;

-- ---------- Les abonnements suivent la licence ----------

create or replace function _licence_statut_abonnement(lic licenses) returns subscription_status
language sql stable security definer set search_path = public as $$
  select (case
    when not lic.active then 'suspended'
    when lic.expires_at is null then 'active'
    when lic.expires_at >= now() then
      case when exists (select 1 from subscription_payments p where p.account_id = lic.account_id)
           then 'active' else 'trial' end
    when lic.expires_at >= now() - nacrea_grace() then 'late'
    else 'suspended'
  end)::subscription_status;
$$;

create or replace function _licence_vers_abonnements(p_account uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  lic licenses;
begin
  if p_account is null then return; end if;
  select * into lic from licenses where account_id = p_account;
  if lic.id is null then return; end if;
  update subscriptions
     set current_period_end = coalesce(lic.expires_at, '2999-12-31'::timestamptz),
         status = _licence_statut_abonnement(lic)
   where account_id = p_account;
end $$;

create or replace function _licence_apres_changement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op <> 'DELETE' then
    perform _licence_vers_abonnements(new.account_id);
  end if;
  if tg_op <> 'INSERT' and old.account_id is distinct from new.account_id then
    perform _licence_vers_abonnements(old.account_id);
  end if;
  return null;
end $$;

drop trigger if exists licence_vers_abonnements on licenses;
create trigger licence_vers_abonnements
after insert or update of account_id, expires_at, active on licenses
for each row execute function _licence_apres_changement();

-- Nouvelle boutique d'une cliente qui a déjà une licence : même date que la licence.
create or replace function _abonnement_depuis_licence() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  lic licenses;
begin
  select l.* into lic from licenses l join shops s on s.account_id = l.account_id where s.id = new.shop_id;
  if lic.id is not null then
    new.current_period_end := coalesce(lic.expires_at, '2999-12-31'::timestamptz);
    new.status := _licence_statut_abonnement(lic);
  end if;
  return new;
end $$;

drop trigger if exists zzz_licence_abonnement on subscriptions;
create trigger zzz_licence_abonnement before insert on subscriptions
for each row execute function _abonnement_depuis_licence();

-- Mise à jour immédiate des abonnements existants
do $$
declare a uuid;
begin
  for a in select account_id from licenses where account_id is not null loop
    perform _licence_vers_abonnements(a);
  end loop;
end $$;

-- Prolonge une date : à la suite de la fin actuelle (si on est encore dans les 7 jours de grâce),
-- sinon à partir d'aujourd'hui.
create or replace function _licence_prolonger(p_fin timestamptz, p_mois integer, p_jours integer) returns timestamptz
language sql stable as $$
  select (case when p_fin is null or p_fin < now() - nacrea_grace() then now() else p_fin end)
         + make_interval(months => coalesce(p_mois, 0), days => coalesce(p_jours, 0));
$$;

-- ---------- Vérification de la licence (date d'expiration ajoutée) ----------

create or replace function _licence_etat(p_account uuid, p_device text, p_kind text, p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  lic licenses;
  v_patronne boolean := is_account_owner(p_account);
  v_max int;
  v_nb int;
begin
  select * into lic from licenses where account_id = p_account for update;
  if lic.id is null then
    return jsonb_build_object('etat', 'aucune', 'patronne', v_patronne);
  end if;
  if not lic.active then
    return jsonb_build_object('etat', 'desactivee', 'patronne', v_patronne, 'cle', lic.key);
  end if;
  if lic.expires_at is not null and lic.expires_at < now() - nacrea_grace() then
    return jsonb_build_object('etat', 'expiree', 'patronne', v_patronne, 'cle', lic.key,
                              'expire_le', lic.expires_at);
  end if;

  update license_devices
     set last_seen = now(), user_id = auth.uid(), name = coalesce(nullif(trim(p_name), ''), name)
   where license_id = lic.id and device_id = p_device;

  if not found then
    v_max := case p_kind when 'pc' then lic.max_pc else lic.max_mobile end;
    select count(*) into v_nb from license_devices where license_id = lic.id and kind = p_kind;
    if v_nb >= v_max then
      return jsonb_build_object(
        'etat', 'limite',
        'patronne', v_patronne,
        'cle', lic.key,
        'type', p_kind,
        'max_pc', lic.max_pc,
        'max_mobile', lic.max_mobile,
        'expire_le', lic.expires_at,
        'peut_remplacer', v_patronne and (lic.last_replaced_at is null
                                          or lic.last_replaced_at < now() - interval '30 days'),
        'remplacement_le', lic.last_replaced_at + interval '30 days',
        'appareils', _licence_appareils(lic.id, p_device));
    end if;
    insert into license_devices (license_id, device_id, kind, name, user_id)
    values (lic.id, p_device, p_kind, nullif(trim(p_name), ''), auth.uid());
  end if;

  return jsonb_build_object(
    'etat', 'ok',
    'patronne', v_patronne,
    'cle', lic.key,
    'max_pc', lic.max_pc,
    'max_mobile', lic.max_mobile,
    'expire_le', lic.expires_at,
    'grace_jours', extract(day from nacrea_grace())::int,
    'appareils', _licence_appareils(lic.id, p_device));
end $$;

-- Activation : la durée en attente démarre maintenant.
create or replace function license_activate(p_key text, p_device_id text, p_kind text, p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_acc uuid;
  v_cle text := _licence_normaliser(p_key);
  lic licenses;
  autre licenses;
begin
  if auth.uid() is null then raise exception 'Utilisateur non connecté'; end if;
  perform _licence_verifier_appareil(p_device_id, p_kind, p_name);
  select account_id into v_acc from members
   where user_id = auth.uid() and active and role = 'owner' limit 1;
  if v_acc is null then
    raise exception 'Seule la patronne peut activer la licence.';
  end if;
  if (select count(*) from license_attempts
       where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 10 then
    raise exception 'Trop d''essais. Réessayez dans une heure.';
  end if;

  select * into lic from licenses where key = v_cle for update;

  if lic.id is null then
    insert into license_attempts (user_id) values (auth.uid());
    return jsonb_build_object('etat', 'cle_incorrecte');
  end if;
  if lic.account_id is not null and lic.account_id <> v_acc then
    insert into license_attempts (user_id) values (auth.uid());
    return jsonb_build_object('etat', 'cle_deja_utilisee');
  end if;
  if not lic.active then
    return jsonb_build_object('etat', 'desactivee', 'patronne', true, 'cle', lic.key);
  end if;

  if lic.account_id is null then
    select * into autre from licenses where account_id = v_acc for update;
    if autre.id is not null then
      if autre.active and (autre.expires_at is null or autre.expires_at >= now() - nacrea_grace()) then
        raise exception 'Votre entreprise a déjà une licence active (%).', autre.key;
      end if;
      -- L'ancienne licence est désactivée ou expirée : la nouvelle la remplace.
      update licenses set account_id = null where id = autre.id;
    end if;
    update licenses
       set account_id = v_acc,
           activated_at = now(),
           expires_at = coalesce(expires_at,
             case when pending_months is not null or pending_days is not null
                  then now() + make_interval(months => coalesce(pending_months, 0), days => coalesce(pending_days, 0))
             end),
           pending_months = null,
           pending_days = null
     where id = lic.id;
  end if;

  return _licence_etat(v_acc, p_device_id, p_kind, p_name);
end $$;

-- ---------- Espace Admin ----------

create or replace function admin_licenses(p_account_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  perform refresh_subscription_statuses();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', l.id,
             'cle', l.key,
             'note', l.note,
             'active', l.active,
             'max_pc', l.max_pc,
             'max_mobile', l.max_mobile,
             'cree_le', l.created_at,
             'activee_le', l.activated_at,
             'remplace_le', l.last_replaced_at,
             'expire_le', l.expires_at,
             'attente_mois', l.pending_months,
             'attente_jours', l.pending_days,
             'grace_jours', extract(day from nacrea_grace())::int,
             'compte_id', l.account_id,
             'compte', a.name,
             'patronne', (select m.display_name from members m where m.account_id = a.id and m.role = 'owner' limit 1),
             'telephone', coalesce(a.phone, (select s.phone from shops s where s.account_id = a.id and s.phone is not null limit 1)),
             'mensuel', (select coalesce(sum(su.monthly_price), 0) from subscriptions su where su.account_id = a.id),
             'appareils', _licence_appareils(l.id, null)
           ) order by l.created_at desc)
    from licenses l
    left join accounts a on a.id = l.account_id
    where p_account_id is null or l.account_id = p_account_id
  ), '[]'::jsonb);
end $$;

-- Nouvelle clé, avec une durée (p_months / p_days), une date précise (p_expires_at), ou illimitée (rien).
drop function if exists admin_create_license(text, integer, integer, uuid);
create or replace function admin_create_license(
  p_note text default null,
  p_max_pc integer default 1,
  p_max_mobile integer default 1,
  p_account_id uuid default null,
  p_months integer default null,
  p_days integer default null,
  p_expires_at timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_cle text;
  v_duree boolean := coalesce(p_months, 0) > 0 or coalesce(p_days, 0) > 0;
  v_fin timestamptz;
begin
  perform _exiger_admin();
  if p_account_id is not null and exists (select 1 from licenses where account_id = p_account_id) then
    raise exception 'Cette cliente a déjà une licence.';
  end if;
  v_fin := case
    when p_expires_at is not null then p_expires_at
    when v_duree and p_account_id is not null
      then now() + make_interval(months => coalesce(p_months, 0), days => coalesce(p_days, 0))
  end;
  loop
    v_cle := _licence_nouvelle_cle();
    begin
      insert into licenses (key, note, max_pc, max_mobile, account_id, activated_at,
                            expires_at, pending_months, pending_days)
      values (v_cle, nullif(trim(p_note), ''), coalesce(p_max_pc, 1), coalesce(p_max_mobile, 1),
              p_account_id, case when p_account_id is not null then now() end,
              v_fin,
              case when v_fin is null and v_duree then coalesce(p_months, 0) end,
              case when v_fin is null and v_duree then coalesce(p_days, 0) end)
      returning id into v_id;
      exit;
    exception when unique_violation then
      if exists (select 1 from licenses where key = v_cle) then
        continue;
      end if;
      raise;
    end;
  end loop;
  return jsonb_build_object('id', v_id, 'cle', v_cle, 'expire_le', v_fin);
end $$;

-- Prolonger une licence de N mois / N jours.
create or replace function admin_extend_license(p_id uuid, p_months integer default 0, p_days integer default 0)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  lic licenses;
begin
  perform _exiger_admin();
  if coalesce(p_months, 0) < 0 or coalesce(p_days, 0) < 0 or coalesce(p_months, 0) + coalesce(p_days, 0) = 0
     or p_months > 60 or p_days > 1000 then
    raise exception 'Durée invalide';
  end if;
  select * into lic from licenses where id = p_id for update;
  if lic.id is null then raise exception 'Licence introuvable.'; end if;

  if lic.expires_at is null and lic.account_id is null then
    -- Pas encore activée : on allonge la durée qui démarrera à l'activation.
    update licenses
       set pending_months = coalesce(pending_months, 0) + coalesce(p_months, 0),
           pending_days = coalesce(pending_days, 0) + coalesce(p_days, 0)
     where id = p_id;
  elsif lic.expires_at is null then
    raise exception 'Cette licence est illimitée : changez d''abord sa date d''expiration.';
  else
    update licenses set expires_at = _licence_prolonger(lic.expires_at, p_months, p_days) where id = p_id;
  end if;
  select * into lic from licenses where id = p_id;
  return jsonb_build_object('expire_le', lic.expires_at,
                            'attente_mois', lic.pending_months, 'attente_jours', lic.pending_days);
end $$;

-- Date d'expiration précise (null = illimitée).
create or replace function admin_set_license_expiry(p_id uuid, p_expires_at timestamptz) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  update licenses set expires_at = p_expires_at, pending_months = null, pending_days = null where id = p_id;
  if not found then raise exception 'Licence introuvable.'; end if;
end $$;

-- Paiement reçu : prolonge la licence de N mois et garde une trace du paiement.
create or replace function admin_record_license_payment(
  p_id uuid, p_amount integer, p_months integer, p_method text, p_note text default null
) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  lic licenses;
  v_fin timestamptz;
  v_boutique uuid;
begin
  perform _exiger_admin();
  if coalesce(p_amount, 0) <= 0 then raise exception 'Indiquez le montant reçu'; end if;
  if coalesce(p_months, 0) not between 1 and 36 then raise exception 'Nombre de mois invalide'; end if;
  select * into lic from licenses where id = p_id for update;
  if lic.id is null then raise exception 'Licence introuvable.'; end if;
  if lic.account_id is null then
    raise exception 'Cette clé n''est pas encore activée par une cliente.';
  end if;
  select id into v_boutique from shops where account_id = lic.account_id order by created_at limit 1;
  if v_boutique is null then raise exception 'Cette cliente n''a pas encore de boutique.'; end if;

  -- Le paiement est noté d'abord : la boutique passe de « essai » à « payé ».
  v_fin := case when lic.expires_at is null then null else _licence_prolonger(lic.expires_at, p_months, 0) end;
  insert into subscription_payments (shop_id, amount, months, method, note, period_end)
  values (v_boutique, p_amount, p_months, p_method, nullif(trim(p_note), ''),
          coalesce(v_fin, '2999-12-31'::timestamptz));
  if v_fin is not null then
    update licenses set expires_at = v_fin, active = true where id = p_id;
  else
    perform _licence_vers_abonnements(lic.account_id);
  end if;
  return v_fin;
end $$;

-- ---------- Anciens boutons (par boutique) : ils agissent maintenant sur la licence ----------

create or replace function _licence_de_boutique(p_shop_id uuid) returns licenses
language plpgsql security definer set search_path = public as $$
declare
  lic licenses;
  v_acc uuid;
begin
  select account_id into v_acc from shops where id = p_shop_id;
  if v_acc is null then raise exception 'Boutique introuvable'; end if;
  select * into lic from licenses where account_id = v_acc;
  if lic.id is null then
    -- Pas encore de licence : on la crée, liée, à partir de la date actuelle de l'abonnement.
    insert into licenses (key, note, account_id, activated_at, expires_at)
    values (_licence_nouvelle_cle(), (select name from accounts where id = v_acc), v_acc, now(),
            (select max(current_period_end) from subscriptions where account_id = v_acc))
    returning * into lic;
  end if;
  return lic;
end $$;

create or replace function admin_record_payment(
  p_shop_id uuid, p_amount integer, p_months integer, p_method text, p_note text default null
) returns timestamptz
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  return admin_record_license_payment((_licence_de_boutique(p_shop_id)).id, p_amount, p_months, p_method, p_note);
end $$;

create or replace function admin_extend(p_shop_id uuid, p_days integer) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  perform _exiger_admin();
  v_id := (_licence_de_boutique(p_shop_id)).id;
  perform admin_extend_license(v_id, 0, p_days);
  return (select expires_at from licenses where id = v_id);
end $$;

create or replace function admin_set_suspended(p_shop_id uuid, p_suspendre boolean) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  perform _exiger_admin();
  v_id := (_licence_de_boutique(p_shop_id)).id;
  update licenses set active = not p_suspendre where id = v_id;
  return (select status::text from subscriptions where shop_id = p_shop_id);
end $$;

-- ---------- Droits ----------
revoke execute on function _licence_statut_abonnement(licenses), _licence_vers_abonnements(uuid),
  _licence_prolonger(timestamptz, integer, integer), _licence_de_boutique(uuid)
  from public, anon, authenticated;

revoke execute on function admin_create_license(text, integer, integer, uuid, integer, integer, timestamptz),
  admin_extend_license(uuid, integer, integer),
  admin_set_license_expiry(uuid, timestamptz),
  admin_record_license_payment(uuid, integer, integer, text, text)
  from public, anon;
grant execute on function admin_create_license(text, integer, integer, uuid, integer, integer, timestamptz),
  admin_extend_license(uuid, integer, integer),
  admin_set_license_expiry(uuid, timestamptz),
  admin_record_license_payment(uuid, integer, integer, text, text)
  to authenticated;

notify pgrst, 'reload schema';
