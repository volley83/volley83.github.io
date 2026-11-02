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
    def handle_starttag(self, t, a):
        if t == 'tr':
            self.row = []
        elif t in ('td', 'th'):
            self.cell = ''
        elif t == 'br' and self.cell is not None:
            self.cell += ' '
    def handle_endtag(self, t):
        if t in ('td', 'th') and self.cell is not None and self.row is not None:
            self.row.append(re.sub(r'\s+', ' ', self.cell).strip())
            self.cell = None
        elif t == 'tr' and self.row is not None:
            if any(self.row):
                self.rows.append(self.row)
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
    for r in p.rows:
        if len(r) >= 19 and re.fullmatch(r'\d+\.', r[0]):
            classement.append({
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


def main():
    local = sys.argv[1] if len(sys.argv) > 1 else None
    home = lire(f'{BASE}vbspo_home.php?codent={CODENT}', local and os.path.join(local, 'home.html'))
    s = Sommaire()
    s.feed(home)
    cats, vues = [], set()
    for c in s.cats:
        if 'OPEN' in c['titre'].upper() or 'PITCHOUN' in c['titre'].upper():
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
