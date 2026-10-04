-- =====================================================================
-- NACRÉA · Script 07 : équipe (invitation des employées par code)
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- =====================================================================

create table invitations (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid not null references accounts(id) on delete cascade,
  shop_id       uuid not null references shops(id) on delete cascade,
  display_name  text not null,
  can_see_costs boolean not null default false,
  code          text not null unique,
  created_by    uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '7 days',
  used_by       uuid references auth.users(id),
  used_at       timestamptz
);

alter table invitations enable row level security;
create policy invitations_read   on invitations for select using (is_account_owner(account_id));
create policy invitations_delete on invitations for delete using (is_account_owner(account_id) and used_at is null);
-- La création passe par create_invitation (code généré par le serveur).

-- ---------- La patronne crée une invitation : renvoie le code ----------
create function create_invitation(p_shop_id uuid, p_name text, p_can_see_costs boolean default false)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_account uuid;
  v_code    text;
  -- Lettres et chiffres sans confusion possible (pas de O/0, I/1)
  alphabet  constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  select account_id into v_account from shops where id = p_shop_id;
  if v_account is null or not is_account_owner(v_account) then
    raise exception 'Seule la patronne peut inviter une employée';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Indiquez le nom de l''employée';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from invitations where code = v_code);
  end loop;

  insert into invitations (account_id, shop_id, display_name, can_see_costs, code, created_by)
  values (v_account, p_shop_id, trim(p_name), coalesce(p_can_see_costs, false), v_code, auth.uid());
  return v_code;
end $$;

-- ---------- L'employée rejoint la boutique avec son code ----------
create function join_with_invitation(p_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  inv invitations;
begin
  if auth.uid() is null then
    raise exception 'Utilisateur non connecté';
  end if;

  select * into inv from invitations
   where code = upper(trim(p_code)) for update;

  if inv.id is null then
    raise exception 'Code d''invitation inconnu. Vérifiez les lettres et les chiffres.';
  end if;
  if inv.used_at is not null then
    raise exception 'Ce code a déjà été utilisé.';
  end if;
  if inv.expires_at < now() then
    raise exception 'Ce code a expiré. Demandez-en un nouveau à la patronne.';
  end if;
  if exists (select 1 from members where user_id = auth.uid()) then
    raise exception 'Ce compte est déjà rattaché à une entreprise.';
  end if;

  insert into members (user_id, account_id, shop_id, role, display_name, can_see_costs)
  values (auth.uid(), inv.account_id, inv.shop_id, 'employee', inv.display_name, inv.can_see_costs);

  update invitations set used_by = auth.uid(), used_at = now() where id = inv.id;
  return inv.account_id;
end $$;

revoke execute on function create_invitation(uuid, text, boolean) from public, anon;
grant execute on function create_invitation(uuid, text, boolean) to authenticated;
revoke execute on function join_with_invitation(text) from public, anon;
grant execute on function join_with_invitation(text) to authenticated;

notify pgrst, 'reload schema';
