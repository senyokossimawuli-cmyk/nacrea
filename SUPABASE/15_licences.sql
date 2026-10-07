-- =====================================================================
-- NACRÉA · Script 15 : licences
-- À coller dans Supabase > SQL Editor > New query, puis « Run ».
--
-- - Vous générez une clé (NAC-XXXX-XXXX-XXXX) depuis l'espace Admin.
-- - La patronne la tape une seule fois : la clé est liée à son entreprise.
-- - Chaque licence accepte un nombre limité d'appareils
--   (par défaut 1 PC + 1 téléphone), réglable par vous.
-- - Vous pouvez désactiver une licence ou libérer un appareil à tout moment.
-- - La patronne peut elle-même remplacer un appareil (téléphone perdu…),
--   une fois tous les 30 jours.
-- - L'abonnement mensuel continue de fonctionner comme avant.
-- =====================================================================

create table licenses (
  id               uuid primary key default gen_random_uuid(),
  key              text not null unique,
  account_id       uuid unique references accounts(id) on delete set null,
  note             text,                       -- pour vous : nom, téléphone de la cliente…
  active           boolean not null default true,
  max_pc           integer not null default 1 check (max_pc between 0 and 50),
  max_mobile       integer not null default 1 check (max_mobile between 0 and 50),
  created_at       timestamptz not null default now(),
  activated_at     timestamptz,
  last_replaced_at timestamptz
);

create table license_devices (
  id          uuid primary key default gen_random_uuid(),
  license_id  uuid not null references licenses(id) on delete cascade,
  device_id   text not null,
  kind        text not null check (kind in ('pc', 'mobile')),
  name        text,
  user_id     uuid references auth.users(id) on delete set null,
  first_seen  timestamptz not null default now(),
  last_seen   timestamptz not null default now(),
  unique (license_id, device_id)
);

create table license_attempts (
  user_id    uuid not null,
  created_at timestamptz not null default now()
);
create index license_attempts_user on license_attempts (user_id, created_at);

-- Aucune règle d'accès : tout passe par les fonctions ci-dessous.
alter table licenses enable row level security;
alter table license_devices enable row level security;
alter table license_attempts enable row level security;

-- ---------- Outils internes ----------

-- Nouvelle clé : NAC-XXXX-XXXX-XXXX (sans 0, O, 1, I pour éviter les confusions).
create function _licence_nouvelle_cle() returns text
language plpgsql volatile as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  octets bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  positions constant int[] := array[0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14];
  cle text := 'NAC';
  i int;
begin
  for i in 1..12 loop
    if (i - 1) % 4 = 0 then cle := cle || '-'; end if;
    cle := cle || substr(alphabet, (get_byte(octets, positions[i]) % 32) + 1, 1);
  end loop;
  return cle;
end $$;

-- « nac 7k2m-..  » → « NAC-7K2M-…» (ou null si ce n'est pas une clé)
create function _licence_normaliser(p text) returns text
language sql immutable as $$
  select case when length(v) = 15 and left(v, 3) = 'NAC'
              then 'NAC-' || substr(v, 4, 4) || '-' || substr(v, 8, 4) || '-' || substr(v, 12, 4)
         end
  from (select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')) as v) x;
$$;

create function _licence_appareils(p_license uuid, p_device text) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', d.id,
           'type', d.kind,
           'nom', d.name,
           'email', u.email,
           'premier', d.first_seen,
           'vu_le', d.last_seen,
           'ce_appareil', p_device is not null and d.device_id = p_device
         ) order by d.kind, d.first_seen), '[]'::jsonb)
  from license_devices d
  left join auth.users u on u.id = d.user_id
  where d.license_id = p_license;
$$;

-- Vérifie la licence d'une entreprise pour un appareil, et l'enregistre s'il reste de la place.
create function _licence_etat(p_account uuid, p_device text, p_kind text, p_name text) returns jsonb
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
    'appareils', _licence_appareils(lic.id, p_device));
end $$;

create function _licence_verifier_appareil(p_device text, p_kind text, p_name text) returns void
language plpgsql immutable as $$
begin
  if p_device is null or length(p_device) not between 8 and 100 then
    raise exception 'Appareil non reconnu';
  end if;
  if p_kind not in ('pc', 'mobile') then
    raise exception 'Type d''appareil inconnu';
  end if;
  if length(coalesce(p_name, '')) > 80 then
    raise exception 'Nom d''appareil trop long';
  end if;
end $$;

-- ---------- Fonctions appelées par l'application ----------

-- À chaque ouverture de Nacréa.
create function license_check(p_device_id text, p_kind text, p_name text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_acc uuid;
begin
  if auth.uid() is null then raise exception 'Utilisateur non connecté'; end if;
  perform _licence_verifier_appareil(p_device_id, p_kind, p_name);
  if is_platform_admin() then
    return jsonb_build_object('etat', 'ok', 'admin', true, 'patronne', true);
  end if;
  select account_id into v_acc from members
   where user_id = auth.uid() and active
   order by (role = 'owner') desc limit 1;
  if v_acc is null then
    return jsonb_build_object('etat', 'sans_entreprise');
  end if;
  return _licence_etat(v_acc, p_device_id, p_kind, p_name);
end $$;

-- La patronne tape sa clé.
create function license_activate(p_key text, p_device_id text, p_kind text, p_name text) returns jsonb
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

  -- Clé inconnue, ou déjà utilisée ailleurs : l'essai est noté (pas d'erreur levée, sinon la note serait annulée).
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
      if autre.active then
        raise exception 'Votre entreprise a déjà une licence active (%).', autre.key;
      end if;
      -- L'ancienne licence était désactivée : la nouvelle la remplace.
      update licenses set account_id = null where id = autre.id;
    end if;
    update licenses set account_id = v_acc, activated_at = now() where id = lic.id;
  end if;

  return _licence_etat(v_acc, p_device_id, p_kind, p_name);
end $$;

-- La patronne remplace un ancien appareil par celui-ci (une fois tous les 30 jours).
create function license_replace_device(p_old_device uuid, p_device_id text, p_kind text, p_name text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_acc uuid;
  lic licenses;
begin
  if auth.uid() is null then raise exception 'Utilisateur non connecté'; end if;
  perform _licence_verifier_appareil(p_device_id, p_kind, p_name);
  select account_id into v_acc from members
   where user_id = auth.uid() and active and role = 'owner' limit 1;
  if v_acc is null then
    raise exception 'Seule la patronne peut remplacer un appareil.';
  end if;
  select * into lic from licenses where account_id = v_acc for update;
  if lic.id is null or not lic.active then
    raise exception 'Licence introuvable ou désactivée.';
  end if;
  if lic.last_replaced_at is not null and lic.last_replaced_at > now() - interval '30 days' then
    raise exception 'Un appareil a déjà été remplacé le %. Prochain remplacement possible le %, ou contactez Nacréa.',
      to_char(lic.last_replaced_at, 'DD/MM/YYYY'), to_char(lic.last_replaced_at + interval '30 days', 'DD/MM/YYYY');
  end if;
  delete from license_devices where id = p_old_device and license_id = lic.id;
  if not found then
    raise exception 'Appareil introuvable.';
  end if;
  update licenses set last_replaced_at = now() where id = lic.id;
  return _licence_etat(v_acc, p_device_id, p_kind, p_name);
end $$;

-- ---------- Espace Admin ----------

create function admin_licenses(p_account_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
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
             'compte_id', l.account_id,
             'compte', a.name,
             'appareils', _licence_appareils(l.id, null)
           ) order by l.created_at desc)
    from licenses l
    left join accounts a on a.id = l.account_id
    where p_account_id is null or l.account_id = p_account_id
  ), '[]'::jsonb);
end $$;

-- Nouvelle clé. Avec p_account_id : directement liée à cette cliente (elle n'a rien à taper).
create function admin_create_license(
  p_note text default null,
  p_max_pc integer default 1,
  p_max_mobile integer default 1,
  p_account_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_cle text;
begin
  perform _exiger_admin();
  if p_account_id is not null and exists (select 1 from licenses where account_id = p_account_id) then
    raise exception 'Cette cliente a déjà une licence.';
  end if;
  loop
    v_cle := _licence_nouvelle_cle();
    begin
      insert into licenses (key, note, max_pc, max_mobile, account_id, activated_at)
      values (v_cle, nullif(trim(p_note), ''), coalesce(p_max_pc, 1), coalesce(p_max_mobile, 1),
              p_account_id, case when p_account_id is not null then now() end)
      returning id into v_id;
      exit;
    exception when unique_violation then
      if exists (select 1 from licenses where key = v_cle) then
        continue;  -- clé déjà prise (très rare) : on en tire une autre
      end if;
      raise;
    end;
  end loop;
  return jsonb_build_object('id', v_id, 'cle', v_cle);
end $$;

create function admin_update_license(p_id uuid, p_note text, p_max_pc integer, p_max_mobile integer)
returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  update licenses
     set note = nullif(trim(p_note), ''), max_pc = p_max_pc, max_mobile = p_max_mobile
   where id = p_id;
  if not found then raise exception 'Licence introuvable.'; end if;
end $$;

create function admin_set_license_active(p_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  update licenses set active = p_active where id = p_id;
  if not found then raise exception 'Licence introuvable.'; end if;
end $$;

-- Libère un appareil : la place peut être prise par un autre.
create function admin_remove_license_device(p_device uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  delete from license_devices where id = p_device;
  if not found then raise exception 'Appareil introuvable.'; end if;
end $$;

create function admin_delete_license(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform _exiger_admin();
  delete from licenses where id = p_id;
  if not found then raise exception 'Licence introuvable.'; end if;
end $$;

-- ---------- Droits ----------
revoke execute on function _licence_nouvelle_cle(), _licence_normaliser(text),
  _licence_appareils(uuid, text), _licence_etat(uuid, text, text, text),
  _licence_verifier_appareil(text, text, text)
  from public, anon, authenticated;

revoke execute on function license_check(text, text, text),
  license_activate(text, text, text, text),
  license_replace_device(uuid, text, text, text),
  admin_licenses(uuid),
  admin_create_license(text, integer, integer, uuid),
  admin_update_license(uuid, text, integer, integer),
  admin_set_license_active(uuid, boolean),
  admin_remove_license_device(uuid),
  admin_delete_license(uuid)
  from public, anon;

grant execute on function license_check(text, text, text),
  license_activate(text, text, text, text),
  license_replace_device(uuid, text, text, text),
  admin_licenses(uuid),
  admin_create_license(text, integer, integer, uuid),
  admin_update_license(uuid, text, integer, integer),
  admin_set_license_active(uuid, boolean),
  admin_remove_license_device(uuid),
  admin_delete_license(uuid)
  to authenticated;
