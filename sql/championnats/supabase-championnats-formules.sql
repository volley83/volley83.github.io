-- Championnats : bibliothèque des formules sportives (mail « formule sportive » aux inscrits).
-- Une formule = un nombre d'équipes, la taille des poules de la 1re phase et le texte du mail,
-- où {POULES} est remplacé par la composition des poules faite automatiquement (serpentin).
-- À lancer une fois : Supabase › SQL Editor › coller › Run. Peut être relancé sans risque.
create table if not exists chp_formules (
  id          bigserial primary key,
  famille     text not null default '4x4',          -- '4x4' (M15/M18) ou 'open'
  nb_equipes  int  not null,
  nom         text not null default '',
  poules      text not null default '',             -- ex. « 4 (joue sur 2 terrains), 3 »
  texte       text not null default '',
  updated_at  timestamptz not null default now()
);
alter table chp_formules enable row level security;   -- aucun accès direct : seulement par les fonctions ci-dessous

create or replace function chp_admin_formules(pwd text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  return coalesce((select jsonb_agg(to_jsonb(f) order by f.famille, f.nb_equipes, f.nom) from chp_formules f), '[]'::jsonb);
end $$;

-- fid null = nouvelle formule ; p null = suppression
create or replace function chp_admin_formule(pwd text, fid bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare nid bigint;
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if p is null then delete from chp_formules where id = fid; return fid; end if;
  if fid is null then
    insert into chp_formules (famille, nb_equipes, nom, poules, texte)
    values (coalesce(nullif(p->>'famille', ''), '4x4'), (p->>'nb_equipes')::int, coalesce(p->>'nom', ''), coalesce(p->>'poules', ''), coalesce(p->>'texte', ''))
    returning id into nid;
    return nid;
  end if;
  update chp_formules set
    famille    = coalesce(nullif(p->>'famille', ''), famille),
    nb_equipes = coalesce(nullif(p->>'nb_equipes', '')::int, nb_equipes),
    nom        = coalesce(p->>'nom', nom),
    poules     = coalesce(p->>'poules', poules),
    texte      = coalesce(p->>'texte', texte),
    updated_at = now()
  where id = fid;
  return fid;
end $$;

grant execute on function chp_admin_formules(text) to anon, authenticated;
grant execute on function chp_admin_formule(text, bigint, jsonb) to anon, authenticated;

-- Première formule : 7 équipes (M15 / M18 4x4)
insert into chp_formules (famille, nb_equipes, nom, poules, texte)
select '4x4', 7, '1 poule de 4 + 1 poule de 3', '4 (joue sur 2 terrains), 3',
$t$1ERE PHASE

1 poule de 4 et 1 poule de 3.
Matchs en 1 set de 21 points.

Composition des poules :

{POULES}

3 rotations de matchs.
Ne pas perdre de temps entre les rencontres avec de longs échauffements au filet, mais privilégier le jeu.

2EME PHASE

Places 1 à 4 - Poule D : Matchs en 2 sets de 15 - Tie Break en 11 (joue sur 2 terrains)
1 - 1er poule A
2 - 1er poule B
3 - 2ème poule A
4 - 2ème poule B

Places 5 à 7 - Poule E : Matchs en 2 sets de 15 - Tie Break en 11
1 - 3ème poule A
2 - 3ème poule B
3 - 4ème poule A$t$
where not exists (select 1 from chp_formules where famille = '4x4' and nb_equipes = 7);

-- 4 équipes (M15 / M18 4x4)
insert into chp_formules (famille, nb_equipes, nom, poules, texte)
select '4x4', 4, '1 poule de 4', '4',
$t$4 équipes engagées. 1 poule de 4.
Matchs en 2 sets de 25 points - Tie-Break en 15 points.

Composition de la poule :

{POULES}

3 rotations de matchs.$t$
where not exists (select 1 from chp_formules where famille = '4x4' and nb_equipes = 4);
