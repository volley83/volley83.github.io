-- Coupe de France : calendrier des tours (saisi dans l'admin des championnats)
-- À lancer une fois dans Supabase › SQL Editor. Relançable, aucune donnée supprimée.
create table if not exists chp_coupe (
  id         bigint generated always as identity primary key,
  categorie  text not null,          -- ex. « M15 féminin », « Seniors masculins »
  tour       text not null,          -- ex. « 1er tour », « 1/8e de finale », « Finale »
  date       date,
  date_fin   date,
  lieu       text,
  lien       text,                   -- page FFvolley des résultats (poule ou tableau)
  remarque   text,
  ordre      int default 0
);
alter table chp_coupe enable row level security;
revoke all on chp_coupe from anon, authenticated;

create or replace function chp_coupe_public() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(c) order by c.categorie, c.date nulls last, c.ordre), '[]'::jsonb) from chp_coupe c;
$$;

-- p = la ligne (sans id : création) ; p = null : suppression
create or replace function chp_admin_coupe(pwd text, cid bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare nid bigint := cid;
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if p is null then delete from chp_coupe where id = cid; return null; end if;
  if nid is null then
    insert into chp_coupe (categorie, tour) values (coalesce(nullif(trim(p->>'categorie'), ''), 'Catégorie'), coalesce(nullif(trim(p->>'tour'), ''), 'Tour'))
    returning id into nid;
  end if;
  update chp_coupe set
    categorie = case when p ? 'categorie' then coalesce(nullif(trim(p->>'categorie'), ''), categorie) else categorie end,
    tour      = case when p ? 'tour' then coalesce(nullif(trim(p->>'tour'), ''), tour) else tour end,
    date      = case when p ? 'date' then nullif(p->>'date', '')::date else date end,
    date_fin  = case when p ? 'date_fin' then nullif(p->>'date_fin', '')::date else date_fin end,
    lieu      = case when p ? 'lieu' then nullif(trim(p->>'lieu'), '') else lieu end,
    lien      = case when p ? 'lien' then nullif(trim(p->>'lien'), '') else lien end,
    remarque  = case when p ? 'remarque' then nullif(trim(p->>'remarque'), '') else remarque end
  where id = nid;
  return nid;
end $$;

grant execute on function chp_coupe_public(), chp_admin_coupe(text, bigint, jsonb) to anon;

-- Message attendu : « Success. No rows returned »

-- Calendrier 2026-2027 des Coupes de France Jeunes (document de déroulement FFvolley : M13, M18, M21)
-- Inséré seulement si la table est vide ; à compléter ou corriger ensuite dans l'admin (onglet Coupe de France).
insert into chp_coupe (categorie, tour, date, date_fin, lien, remarque, ordre)
select cat, tour, d::date, f::date, 'https://www.ffvbbeach.org/ffvbapp/resu/jeunes/2026-2027/', rq, o
from (values ('M13'), ('M18'), ('M21')) c(cat)
cross join (values
  ('1er tour', '2026-10-18', null, null, 1),
  ('2e tour',  '2026-11-15', null, null, 2),
  ('3e tour',  '2026-12-13', null, null, 3),
  ('4e tour',  '2027-01-24', null, 'Tour supprimé pour les filles', 4),
  ('5e tour',  '2027-02-07', null, null, 5),
  ('6e tour',  '2027-03-14', null, null, 6),
  ('7e tour',  '2027-04-11', null, null, 7),
  ('Finales',  '2027-05-28', '2027-05-30', null, 8)
) t(tour, d, f, rq, o)
where not exists (select 1 from chp_coupe);
