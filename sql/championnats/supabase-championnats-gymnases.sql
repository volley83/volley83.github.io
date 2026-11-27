-- Championnats : liste de référence des gymnases (nom affiché, ville, adresse) pour l'affichage
-- et le bouton « Itinéraire ». Clé = nom FFvolley normalisé (majuscules, sans accents, sans « GYMNASE DE », sans la ville entre parenthèses).
-- À lancer une fois : Supabase › SQL Editor › coller › Run. Peut être relancé sans risque.
create table if not exists chp_gymnases (
  cle        text primary key,
  nom        text not null default '',
  ville      text not null default '',
  adresse    text not null default '',
  updated_at timestamptz not null default now()
);
alter table chp_gymnases enable row level security;

create or replace function chp_gymnases_public() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(cle, jsonb_build_object('nom', nom, 'ville', ville, 'adresse', adresse)), '{}'::jsonb) from chp_gymnases;
$$;

create or replace function chp_admin_gymnase(pwd text, k text, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if p is null then delete from chp_gymnases where cle = k; return; end if;
  insert into chp_gymnases (cle, nom, ville, adresse) values (k, coalesce(p->>'nom', ''), coalesce(p->>'ville', ''), coalesce(p->>'adresse', ''))
  on conflict (cle) do update set nom = excluded.nom, ville = excluded.ville, adresse = excluded.adresse, updated_at = now();
end $$;

grant execute on function chp_gymnases_public() to anon, authenticated;
grant execute on function chp_admin_gymnase(text, text, jsonb) to anon, authenticated;

-- La liste se remplit depuis Admin › Gymnases (propositions reprises des fiches clubs FFvolley).
