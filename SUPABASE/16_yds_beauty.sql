-- =====================================================================
-- YDS BEAUTY · Script 16 : nouveau nom
-- À coller dans Supabase > SQL Editor > New query, puis « Run ».
--
-- - Les nouvelles clés de licence commencent par YDS- (au lieu de NAC-).
-- - Les anciennes clés NAC- restent valables.
-- - Messages du serveur au nouveau nom.
-- =====================================================================

create or replace function _licence_nouvelle_cle() returns text
language plpgsql volatile as $$
declare
  alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  octets bytea := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');
  positions constant int[] := array[0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 13, 14];
  cle text := 'YDS';
  i int;
begin
  for i in 1..12 loop
    if (i - 1) % 4 = 0 then cle := cle || '-'; end if;
    cle := cle || substr(alphabet, (get_byte(octets, positions[i]) % 32) + 1, 1);
  end loop;
  return cle;
end $$;

-- « yds 7k2m… » → « YDS-7K2M-… » ; les anciennes clés NAC- sont toujours reconnues.
create or replace function _licence_normaliser(p text) returns text
language sql immutable as $$
  select case when length(v) = 15 and left(v, 3) in ('YDS', 'NAC')
              then left(v, 3) || '-' || substr(v, 4, 4) || '-' || substr(v, 8, 4) || '-' || substr(v, 12, 4)
         end
  from (select upper(regexp_replace(coalesce(p, ''), '[^A-Za-z0-9]', '', 'g')) as v) x;
$$;

create or replace function _exiger_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_platform_admin() then
    raise exception 'Réservé à l''administrateur de YDS Beauty';
  end if;
end $$;

revoke execute on function _licence_nouvelle_cle(), _licence_normaliser(text) from public, anon, authenticated;
