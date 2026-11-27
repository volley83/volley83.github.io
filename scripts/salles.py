"""Salles des clubs, lues dans les fiches de match PDF de la FFvolley (rubrique « Salle principale » / « Salle de repli »).
Utilisé par ffvb.py ; peut aussi être lancé seul sur des PDF : python3 salles.py fiche1.pdf fiche2.pdf"""
import re
import subprocess
import sys


def texte_pdf(octets):
    p = subprocess.run(['pdftotext', '-layout', '-', '-'], input=octets, capture_output=True, check=True)
    return p.stdout.decode('utf-8', 'replace')


def salles_fiche(txt):
    """→ (salle du match {nom, cp, ville}, [ {club_num, club, role, nom, adresse, cp, ville} ])"""
    lignes = txt.splitlines()
    match = {}
    for i, l in enumerate(lignes):
        if l.strip() == 'Salle':
            vals = []
            for l2 in lignes[i + 1:i + 4]:
                if 'Arbitre' in l2:
                    break
                if l2.strip():
                    vals.append(l2.strip())
            if vals:
                match['nom'] = vals[0]
                for v in vals[1:]:
                    m = re.match(r'(\d{5})\s+(.*)', v)
                    if m:
                        match['cp'], match['ville'] = m.group(1), m.group(2).strip()
            break
    out = []
    club_num = club = None
    i = 0
    while i < len(lignes):
        l = lignes[i]
        m = re.match(r'\s*\d+\s+-\s+(\d{7})\s+(.+?)\s{2,}', l)
        if m:
            club_num, club = m.group(1), m.group(2).strip()
        if 'Salle principale' in l:
            cols = [('principale', l.index('Salle principale'))]
            if 'Salle de repli' in l:
                cols.append(('repli', l.index('Salle de repli')))
            blocs = {r: [] for r, _ in cols}
            for l2 in lignes[i + 1:i + 9]:
                if re.match(r'\s*\d+\s+-\s+\d{7}', l2) or not l2.strip() or l2.strip() == 'Var':
                    break
                for k, (r, x) in enumerate(cols):
                    fin = cols[k + 1][1] if k + 1 < len(cols) else None
                    # tolérance : le texte peut commencer quelques caractères avant la colonne
                    debut = max(0, x - 3)
                    morceau = l2[debut:fin - 3 if fin else None].strip()
                    if morceau:
                        blocs[r].append(re.split(r'\s{3,}', morceau)[0].strip())
            for r, v in blocs.items():
                v = [x for x in v if x and not re.match(r'(Tél|Sol|Accès|Port|Mel|Fax)\b', x)]
                if not v:
                    continue
                s = {'club_num': club_num, 'club': club, 'role': r, 'nom': v[0], 'adresse': '', 'cp': '', 'ville': ''}
                for x in v[1:]:
                    mc = re.match(r'(\d{5})\s+(.*)', x)
                    if mc:
                        s['cp'], s['ville'] = mc.group(1), mc.group(2).strip()
                        break
                    if not s['adresse']:
                        s['adresse'] = x
                out.append(s)
        i += 1
    return match, out


if __name__ == '__main__':
    for f in sys.argv[1:]:
        print(salles_fiche(texte_pdf(open(f, 'rb').read())))
