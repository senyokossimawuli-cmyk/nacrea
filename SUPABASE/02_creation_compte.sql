-- =====================================================================
-- NACRÉA · Script 02 : création d'un compte patronne + sa première boutique
-- À coller dans Supabase > SQL Editor > New query, puis "Run".
-- =====================================================================

create function create_account_with_shop(
  p_owner_name   text,
  p_account_name text,
  p_shop_name    text,
  p_phone        text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  acc uuid;
begin
  if auth.uid() is null then
    raise exception 'Utilisateur non connecté';
  end if;
  if exists (select 1 from members where user_id = auth.uid()) then
    raise exception 'Ce compte possède déjà une entreprise';
  end if;
  if coalesce(trim(p_account_name), '') = '' or coalesce(trim(p_shop_name), '') = '' then
    raise exception 'Nom de l''entreprise et de la boutique obligatoires';
  end if;

  insert into accounts (name, owner_user_id, phone)
  values (trim(p_account_name), auth.uid(), p_phone)
  returning id into acc;

  -- Le membre "owner" est créé automatiquement : on lui donne le nom de la patronne.
  update members set display_name = coalesce(nullif(trim(p_owner_name), ''), trim(p_account_name))
  where account_id = acc and user_id = auth.uid();

  insert into shops (account_id, name, phone)
  values (acc, trim(p_shop_name), p_phone);

  return acc;
end $$;

revoke execute on function create_account_with_shop(text, text, text, text) from public, anon;
grant execute on function create_account_with_shop(text, text, text, text) to authenticated;
