#!/usr/bin/env python3
"""Récupère les calendriers, résultats et classements des championnats du Comité du Var
sur le site de la FFvolley et les enregistre dans championnats/data/ffvb.json.

Lancé automatiquement par GitHub Actions (.github/workflows/ffvb.yml).
Usage local : python3 scripts/ffvb.py [dossier_de_pages_html]  (sinon téléchargement en ligne)
"""
import json, re, sys, os, time, hashlib, urllib.request
from datetime import datetime, timezone
from html.parser import HTMLParser

CODENT = 'PTCA83'
SAISON = '2026/2027'
BASE = 'https://www.ffvbbeach.org/ffvbapp/resu/'
# Poules gérées autrement sur le site du Comité (Compétitions OPEN, Pitchoun')
EXCLUES = {'M4M', 'MFM', 'C4M', 'CFM', 'O11', 'O13', 'PIT'}
SORTIE = os.path.join(os.path.dirname(__file__), '..', 'championnats', 'data', 'ffvb.json')
DOSSIER_ICS = os.path.join(os.path.dirname(__file__), '..', 'championnats', 'data', 'ics')
SUPABASE_URL = 'https://nssdhgpvkdbgdewsnlgl.supabase.co'
SUPABASE_KEY = 'sb_publishable_GeMMc45mQbDOq-ZkU5vXZw_lYJe9KXf'   # clé publique (lecture des compétitions OPEN)
CLUBS = {   # code : nom affiché (même liste que l'admin des compétitions OPEN)
    'CSB': 'Club Sportif Brignolais', 'DVVB': 'Draguignan Union Club Var VB', 'FVV': 'Fréjus Var Volley',
    'LLVB': 'Le Luc Volley-Ball', 'SMCV': 'Sainte-Maxime Cogolin Volley', '2SBVC': 'Sud Sainte-Baume Volley Club',
    'UAV': 'Union Athlétique Valettoise', 'VVB': 'Vidauban Volley-Ball', 'VBO': 'Volley-Ball Ollioulais',
    'VCHPL': 'Volley Club Hyères / Pierrefeu La Londe', 'VCM': 'Volley Club Méditerranée', 'VCS': 'Volley Club Seynois',
    'VPG': 'Volley Pradétan Gardéen',
    # clubs qui ne jouent qu'en Compet'Lib
    'RCVB': 'Rocbaron Club Volley-Ball', 'SFBV': 'Six-Fours Beach Volley', 'VCSM': 'Volley Club de Saint-Maximin',
}
NOM_FFVB = {'RCVB': 'ROCBARON CLUB VOLLEY-BALL - RCVB'}   # quand la FFvolley écrit le nom autrement
UA = 'Mozilla/5.0 (compatible; Comite-Var-Volley/1.0; +https://volley83.github.io/championnats/)'


def lire(url, local=None):
    if local:
        return open(local, encoding='latin-1').read()
    for essai in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode('latin-1')
        except Exception as e:
            if essai == 2:
                raise
            time.sleep(5)


class Lignes(HTMLParser):
    """Extrait les lignes de tableau (texte des cellules)."""
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], None, None
        self.classes, self.rcls = [], None
    def handle_starttag(self, t, a):
        if t == 'tr':
            self.row, self.rcls = [], []
        elif t in ('td', 'th'):
            self.cell = ''
            if self.rcls is not None:
                self.rcls.append(dict(a).get('class') or '')
        elif t == 'br' and self.cell is not None:
            self.cell += ' '
    def handle_endtag(self, t):
        if t in ('td', 'th') and self.cell is not None and self.row is not None:
            self.row.append(re.sub(r'\s+', ' ', self.cell).strip())
            self.cell = None
        elif t == 'tr' and self.row is not None:
            if any(self.row):
                self.rows.append(self.row)
                self.classes.append(self.rcls or [])
            self.row = None
    def handle_data(self, d):
        if self.cell is not None:
            self.cell += d


class Sommaire(HTMLParser):
    """Lit le menu de la page d'accueil : catégories et poules."""
    def __init__(self):
        super().__init__()
        self.cats, self.href, self.txt, self.ina = [], None, '', False
    def handle_starttag(self, t, a):
        if t == 'a':
            self.href, self.txt, self.ina = dict(a).get('href', ''), '', True
    def handle_endtag(self, t):
        if t == 'a' and self.ina:
            self.ina = False
            txt = re.sub(r'\s+', ' ', self.txt).strip()
            m = re.search(r'poule=([A-Z0-9]+)', self.href or '')
            if m and self.cats:
                code = m.group(1)
                titre = txt[len(code):].strip() if txt.startswith(code) else txt
                self.cats[-1]['poules'].append({'code': code, 'titre': titre})
            elif self.href == '#' and txt and txt not in ('Compétitions', 'Competitions'):
                self.cats.append({'titre': txt, 'poules': []})
    def handle_data(self, d):
        if self.ina:
            self.txt += d


def groupe(cat):
    t = cat.upper()
    if 'COMPETLIB' in t:
        return 'competlib'
    if 'DÉPARTEMENTAL' in t or 'DEPARTEMENTAL' in t or 'SENIOR' in t:
        return 'seniors'
    return 'jeunes'


def num(s):
    s = (s or '').strip()
    if s == 'MAX':
        return 'MAX'
    try:
        return int(s) if re.fullmatch(r'-?\d+', s) else float(s) if re.fullmatch(r'-?\d+\.\d+', s) else (0 if s == '' else s)
    except ValueError:
        return s


def date_iso(s):
    m = re.fullmatch(r'(\d\d)/(\d\d)/(\d\d)', s or '')
    return f'20{m.group(3)}-{m.group(2)}-{m.group(1)}' if m else None


def poule(code, html):
    p = Lignes()
    p.feed(html)
    classement, journees, equipes = [], [], []
    for r, cls in zip(p.rows, p.classes):
        if len(r) >= 19 and re.fullmatch(r'\d+\.', r[0]):
            classement.append({
                'mis_en_avant': len(cls) > 1 and cls[1] == 'lienquestion_pt',   # nom en gras sur le site FFvolley (qualification)
                'rang': int(r[0][:-1]), 'equipe': r[1], 'pts': num(r[2]), 'j': num(r[3]), 'g': num(r[4]), 'p': num(r[5]),
                'f': num(r[6]), 'sp': num(r[13]), 'sc': num(r[14]), 'cs': num(r[15]), 'pp': num(r[16]), 'pc': num(r[17]), 'cp': num(r[18]),
            })
        elif len(r) == 1 and re.match(r'^(Tournoi|Journée|Journee|Tour|Plateau)\b', r[0]):
            journees.append({'titre': r[0], 'matchs': []})
        elif len(r) >= 9 and re.fullmatch(code + r'\d+', r[0]):
            joue = len(r) > 7 and re.fullmatch(r'\d+', r[6] or '') and re.fullmatch(r'\d+', r[7] or '')
            m = {'code': r[0], 'date': date_iso(r[1]), 'heure': r[2] or None, 'dom': r[3], 'ext': r[5]}
            if joue:
                m.update({'sd': int(r[6]), 'se': int(r[7]), 'sets': r[8] if len(r) > 8 else '', 'points': r[9] if len(r) > 9 else '',
                          'arbitre': r[10] if len(r) > 10 and r[10] else None})
            else:
                m.update({'lieu': r[7] if len(r) > 7 and r[7] else None, 'arbitre': r[9] if len(r) > 9 and r[9] else None})
            if not journees:
                journees.append({'titre': '', 'matchs': []})
            journees[-1]['matchs'].append(m)
        elif r and r[0].startswith('Composition de la Poule'):
            continue
    # Poules sans classement (M11) : composition = équipes à partir des matchs
    if not classement:
        vus = []
        for j in journees:
            for m in j['matchs']:
                for e in (m['dom'], m['ext']):
                    if e and e not in vus:
                        vus.append(e)
        equipes = sorted(vus)
    journees = [j for j in journees if j['matchs']]
    return {'classement': classement, 'journees': journees, 'equipes': equipes}


# ---------------------------------------------------------------------------
# Agendas .ics (abonnement Google Agenda, iPhone, Outlook) : une par poule, une par club
# ---------------------------------------------------------------------------
def normn(s):
    import unicodedata
    s = unicodedata.normalize('NFD', s or '')
    return re.sub(r'[^A-Z0-9]', '', ''.join(c for c in s if not unicodedata.combining(c)).upper())


def club_de(nom):
    n = normn(nom)
    for code, cnom in sorted(CLUBS.items(), key=lambda kv: -len(normn(NOM_FFVB.get(kv[0], kv[1])))):
        if n.startswith(normn(NOM_FFVB.get(code, cnom))):
            return code
    return None


def equipe_jolie(nom):
    if re.fullmatch(r'X{3,}', (nom or '').strip(), re.I):
        return 'Exempt'
    code = club_de(nom)
    if not code:
        return (nom or '').title()
    besoin, i = len(normn(NOM_FFVB.get(code, CLUBS[code]))), 0
    while i < len(nom) and besoin > 0:
        if re.match(r'[A-Za-z0-9À-ÿ]', nom[i]):
            besoin -= 1
        i += 1
    reste = nom[i:].strip()
    return CLUBS[code] + (' ' + reste if reste else '')


def lieu_joli(s):
    petits = {'de', 'du', 'des', 'la', 'le', 'les', 'et', 'à', 'au', 'aux', 'sur', 'en'}
    out = []
    for i, w in enumerate(re.split(r'(\W+)', (s or '').lower())):
        out.append(w[:1].upper() + w[1:] if w and w[0].isalpha() and (i == 0 or w not in petits or (out and out[-1].endswith(('(', '-'))) ) else w)
    return ''.join(out)


def ics_txt(s):
    return (s or '').replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\n', '\\n')


def ics_plier(ligne):
    b = ligne.encode('utf-8')
    if len(b) <= 74:
        return ligne
    res, cur = [], ''
    for ch in ligne:
        if len((cur + ch).encode('utf-8')) > 73:
            res.append(cur)
            cur = ' ' + ch
        else:
            cur += ch
    res.append(cur)
    return '\r\n'.join(res)


def evenement(uid, date, heure, titre, lieu, desc, duree_h=2):
    l = ['BEGIN:VEVENT', f'UID:{uid}@volley83.github.io', 'DTSTAMP:20260901T000000Z']
    d = date.replace('-', '')
    if heure and re.fullmatch(r'\d\d:\d\d', heure):
        h, m = int(heure[:2]), int(heure[3:])
        fh, fm = (h + duree_h) % 24, m
        l += [f'DTSTART;TZID=Europe/Paris:{d}T{h:02d}{m:02d}00', f'DTEND;TZID=Europe/Paris:{d}T{fh:02d}{fm:02d}00']
    else:
        from datetime import date as dt, timedelta
        y, mo, da = map(int, date.split('-'))
        l += [f'DTSTART;VALUE=DATE:{d}', 'DTEND;VALUE=DATE:' + (dt(y, mo, da) + timedelta(days=1)).strftime('%Y%m%d')]
    l.append('SUMMARY:' + ics_txt(titre))
    if lieu:
        l.append('LOCATION:' + ics_txt(lieu))
    if desc:
        l.append('DESCRIPTION:' + ics_txt(desc))
    l.append('END:VEVENT')
    return l


def calendrier(nom, evts):
    l = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Comite du Var de Volley-Ball//Championnats//FR', 'CALSCALE:GREGORIAN',
         'METHOD:PUBLISH', 'X-WR-CALNAME:' + ics_txt(nom), 'X-WR-TIMEZONE:Europe/Paris', 'REFRESH-INTERVAL;VALUE=DURATION:PT6H',
         'X-PUBLISHED-TTL:PT6H',
         'BEGIN:VTIMEZONE', 'TZID:Europe/Paris',
         'BEGIN:DAYLIGHT', 'TZOFFSETFROM:+0100', 'TZOFFSETTO:+0200', 'TZNAME:CEST', 'DTSTART:19700329T020000', 'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU', 'END:DAYLIGHT',
         'BEGIN:STANDARD', 'TZOFFSETFROM:+0200', 'TZOFFSETTO:+0100', 'TZNAME:CET', 'DTSTART:19701025T030000', 'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU', 'END:STANDARD',
         'END:VTIMEZONE']
    for e in evts:
        l += e
    l.append('END:VCALENDAR')
    return '\r\n'.join(ics_plier(x) for x in l) + '\r\n'


def cat_courte(titre):
    t = titre.upper()
    t = t.replace('DÉPARTEMENTAL ACCESSION ', 'SENIORS ').replace('DEPARTEMENTAL ACCESSION ', 'SENIORS ')
    t = re.sub(r' QUALIFICATION AU CHAMPIONNAT R[EÉ]GIONAL', ' QUALIF.', t)
    return t.replace('FÉMININ', 'F').replace('FEMININ', 'F').replace('MASCULIN', 'M').replace('COMPETLIB', "COMPET'LIB").replace('MIXTE', 'MIXTE')


def match_evt(cat, p, m):
    titre = f"{cat_courte(cat)} · {equipe_jolie(m['dom'])} – {equipe_jolie(m['ext'])}"
    if m.get('sd') is not None:
        titre += f" ({m['sd']}-{m['se']})"
        desc = f"Résultat : {m['sd']}-{m['se']} ({m.get('sets', '')})"
    else:
        desc = ''
    desc = (desc + '\n' if desc else '') + f"Poule {p['code']} – classement et résultats : https://volley83.github.io/championnats/#championnats/{p.get('groupe', 'jeunes')}/{p['code']}"
    return evenement(m['code'], m['date'], m.get('heure'), titre, lieu_joli(m.get('lieu') or ''), desc)


def open_evts():
    """Tournois des compétitions OPEN (base Supabase du Comité)."""
    try:
        req = urllib.request.Request(SUPABASE_URL + '/rest/v1/rpc/chp_public', data=b'{}', method='POST',
                                     headers={'apikey': SUPABASE_KEY, 'Authorization': 'Bearer ' + SUPABASE_KEY, 'Content-Type': 'application/json'})
        d = json.load(urllib.request.urlopen(req, timeout=30))
    except Exception as e:
        print('Compétitions OPEN indisponibles :', e, file=sys.stderr)
        return {}, {}
    comps = {c['code']: c for c in d.get('competitions', [])}
    par_comp = {}
    for t in d.get('tournois', []):
        if t.get('statut') == 'annule' or not t.get('date'):
            continue
        c = comps.get(t['competition'], {})
        dernier = max(x['numero'] for x in d['tournois'] if x['competition'] == t['competition'])
        nom = 'Tournoi final' if c.get('famille') == 'open' and t['numero'] == dernier else f"Tournoi {t['numero']}"
        lieu = ', '.join(x for x in (t.get('lieu'), t.get('ville')) if x)
        rub = 'open' if c.get('famille') == 'open' else '4x4'
        desc = f"https://volley83.github.io/championnats/#{rub}/{t['competition']}"
        if t.get('date_limite'):
            desc = f"Inscriptions jusqu'au {t['date_limite'][8:10]}/{t['date_limite'][5:7]} à {t.get('heure_limite') or '12:00'}\n" + desc
        par_comp.setdefault(t['competition'], []).append(evenement(f"chp-{t['id']}", t['date'], t.get('heure'), f"{c.get('nom', '')} · {nom}", lieu, desc, 4))
    return par_comp, comps


def ecrire_ics(cats):
    os.makedirs(DOSSIER_ICS, exist_ok=True)
    fichiers = {}
    par_club = {}
    for c in cats:
        for p in c['poules']:
            p['groupe'] = c['groupe']
            evts = [match_evt(c['titre'], p, m) for j in p['journees'] for m in j['matchs'] if m.get('date')]
            fichiers[f"{p['code']}.ics"] = calendrier(f"{cat_courte(c['titre'])} – {p['titre']}".title().replace("'L", "'l"), evts)
            for j in p['journees']:
                for m in j['matchs']:
                    for code in {club_de(m['dom']), club_de(m['ext'])} - {None}:
                        if m.get('date'):
                            par_club.setdefault(code, []).append(match_evt(c['titre'], p, m))
            del p['groupe']
    for code, evts in par_club.items():
        fichiers[f'club-{code}.ics'] = calendrier(f'{CLUBS[code]} – matchs', evts)
    par_comp, comps = open_evts()
    for code, evts in par_comp.items():
        fichiers[f'{code}.ics'] = calendrier(comps[code]['nom'], evts)
    for nom, contenu in fichiers.items():
        chemin = os.path.join(DOSSIER_ICS, nom)
        try:
            if open(chemin, encoding='utf-8', newline='').read() == contenu:
                continue
        except FileNotFoundError:
            pass
        with open(chemin, 'w', encoding='utf-8', newline='') as fh:
            fh.write(contenu)
    print(f'{len(fichiers)} agendas .ics')


def main():
    local = sys.argv[1] if len(sys.argv) > 1 else None
    home = lire(f'{BASE}vbspo_home.php?codent={CODENT}', local and os.path.join(local, 'home.html'))
    s = Sommaire()
    s.feed(home)
    cats, vues = [], set()
    for c in s.cats:
        if c['titre'].strip().upper() in ('CONTACTS', 'CONTACT'):
            continue
        if 'OPEN' in c['titre'].upper() or 'PITCHOUN' in c['titre'].upper() or 'QUALIFICATION' in c['titre'].upper():
            vues.update(pl['code'] for pl in c['poules'])
            continue
        poules = []
        for pl in c['poules']:
            if pl['code'] in EXCLUES or pl['code'] in vues:   # (le menu « Contacts » répète les poules)
                continue
            vues.add(pl['code'])
            url = f"{BASE}vbspo_calendrier.php?saison={SAISON.replace('/', '%2F')}&codent={CODENT}&poule={pl['code']}"
            f = local and os.path.join(local, f"cal_{pl['code']}.html")
            if local and not os.path.exists(f):
                continue
            try:
                d = poule(pl['code'], lire(url, f))
            except Exception as e:
                print('ERREUR', pl['code'], e, file=sys.stderr)
                continue
            poules.append({'code': pl['code'], 'titre': pl['titre'], 'url': url, **d})
            if not local:
                time.sleep(1)
        if poules:
            cats.append({'titre': c['titre'], 'groupe': groupe(c['titre']), 'poules': poules})
    data = {'saison': SAISON, 'source': f'{BASE}vbspo_home.php?codent={CODENT}', 'categories': cats}
    if not local:
        ecrire_ics(cats)
    empreinte = hashlib.sha1(json.dumps(data, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    try:
        ancien = json.load(open(SORTIE, encoding='utf-8'))
        if ancien.get('empreinte') == empreinte:
            print('Aucun changement')
            return
    except Exception:
        pass
    data['maj'] = datetime.now(timezone.utc).isoformat(timespec='minutes')
    data['empreinte'] = empreinte
    os.makedirs(os.path.dirname(SORTIE), exist_ok=True)
    with open(SORTIE, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, separators=(',', ':'))
    n = sum(len(c['poules']) for c in cats)
    print(f'{n} poules enregistrées')


if __name__ == '__main__':
    main()
