-- Championnats : clôture des inscriptions le jeudi à 12 h, tournoi annulé
-- À lancer une fois dans Supabase › SQL Editor (après supabase-championnats.sql). Relançable.

create or replace function chp_admin_save_tournoi(pwd text, t jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare tid bigint := nullif(t->>'id','')::bigint;
begin
  if not chp_is_admin(pwd) then raise exception 'Accès refusé'; end if;
  if tid is null then
    insert into chp_tournois (competition, numero, date) values (t->>'competition', (t->>'numero')::int, (t->>'date')::date)
    returning id into tid;
  end if;
  update chp_tournois set
    numero       = coalesce(nullif(t->>'numero','')::int, numero),
    date         = coalesce(nullif(t->>'date','')::date, date),
    heure        = case when t ? 'heure' then nullif(trim(t->>'heure'), '') else heure end,
    lieu         = case when t ? 'lieu' then nullif(trim(t->>'lieu'), '') else lieu end,
    ville        = case when t ? 'ville' then nullif(trim(t->>'ville'), '') else ville end,
    organisateur = case when t ? 'organisateur' then nullif(trim(t->>'organisateur'), '') else organisateur end,
    email_orga   = case when t ? 'email_orga' then nullif(trim(t->>'email_orga'), '') else email_orga end,
    date_limite  = case when t ? 'date_limite' then nullif(t->>'date_limite','')::date else date_limite end,
    heure_limite = case when t ? 'heure_limite' then nullif(trim(t->>'heure_limite'), '') else heure_limite end,
    inscriptions = case when t->>'inscriptions' in ('auto','ouvertes','fermees') then t->>'inscriptions' else inscriptions end,
    statut       = case when t->>'statut' in ('ouvert','saisi','valide','annule') then t->>'statut' else statut end,
    code_orga    = case when t ? 'code_orga' then nullif(upper(trim(t->>'code_orga')), '') else code_orga end,
    remarque     = case when t ? 'remarque' then nullif(trim(t->>'remarque'), '') else remarque end
  where id = tid;
  return tid;
end $$;

-- ---------- Règles de la saison ----------
-- Clôture des inscriptions : le jeudi précédant le tournoi à 12 h
alter table chp_tournois alter column heure_limite set default '12:00';
alter table chp_tournois drop constraint if exists chp_tournois_statut_check;
alter table chp_tournois add constraint chp_tournois_statut_check check (statut in ('ouvert','saisi','valide','annule'));
update chp_tournois set heure_limite = '12:00' where heure_limite is null or heure_limite = '20:00';
update chp_tournois set date_limite = date - case when (extract(dow from date)::int + 3) % 7 = 0 then 7 else (extract(dow from date)::int + 3) % 7 end
 where date_limite is null or date_limite <> date - case when (extract(dow from date)::int + 3) % 7 = 0 then 7 else (extract(dow from date)::int + 3) % 7 end;
-- M18 masculin du 10 octobre : tournoi non joué
update chp_tournois set statut = 'annule' where competition = 'C4M' and numero = 1 and statut = 'ouvert';

select competition, numero, date, date_limite, heure_limite, statut from chp_tournois order by competition, numero;

-- Message attendu : la liste des tournois avec leurs dates limites