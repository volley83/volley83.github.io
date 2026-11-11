#!/usr/bin/env python3
"""Récupère les dernières publications des pages Facebook du Comité
et écrit accueil/data/actus.json (+ les images dans accueil/data/img/).

Les clés d'accès (jetons de Page) viennent des secrets GitHub :
  FB_TOKEN_COMITE  -> page facebook.com/varvolley
  FB_TOKEN_BEACH   -> page facebook.com/beachvolley83
Elles ne doivent JAMAIS figurer dans le dépôt. Sans clé, le script ne fait rien.
"""
import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOSSIER = os.path.join(RACINE, 'accueil', 'data')
IMG = os.path.join(DOSSIER, 'img')
SORTIE = os.path.join(DOSSIER, 'actus.json')

PAGES = [
    ('comite', 'FB_TOKEN_COMITE'),
    ('beach', 'FB_TOKEN_BEACH'),
]
PAR_PAGE = 8          # publications demandées par page
GARDEES = 12          # publications gardées au total
CHAMPS = 'id,message,created_time,permalink_url,full_picture'


def lire(url, binaire=False):
    req = urllib.request.Request(url, headers={'User-Agent': 'volley83-site'})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
    return data if binaire else json.loads(data.decode('utf-8'))


def publications(cle, jeton):
    """Publications d'une page. N'affiche jamais l'adresse appelée (elle contient le jeton)."""
    url = 'https://graph.facebook.com/me/posts?' + urllib.parse.urlencode(
        {'fields': CHAMPS, 'limit': PAR_PAGE, 'access_token': jeton})
    try:
        rep = lire(url)
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode('utf-8')).get('error', {}).get('message', '')
        except Exception:
            msg = ''
        print(f'[{cle}] erreur Facebook {e.code} : {msg}')
        return None
    except Exception as e:
        print(f'[{cle}] erreur : {type(e).__name__}')
        return None
    res = []
    for p in rep.get('data', []):
        if not p.get('permalink_url'):
            continue
        if not (p.get('message') or p.get('full_picture')):
            continue
        res.append({
            'page': cle,
            'id': p['id'],
            'date': p.get('created_time', ''),
            'texte': (p.get('message') or '').strip(),
            'lien': p['permalink_url'],
            '_img': p.get('full_picture') or '',
        })
    print(f'[{cle}] {len(res)} publication(s)')
    return res


def image(post):
    """Copie l'image de la publication dans le dépôt (les adresses Facebook expirent)."""
    src = post.pop('_img', '')
    post['image'] = ''
    if not src:
        return
    nom = hashlib.sha1(post['id'].encode()).hexdigest()[:16] + '.jpg'
    chemin = os.path.join(IMG, nom)
    if not os.path.exists(chemin):
        try:
            data = lire(src, binaire=True)
            if len(data) > 3_000_000:
                return
            with open(chemin, 'wb') as f:
                f.write(data)
        except Exception as e:
            print(f"  image non récupérée ({type(e).__name__})")
            return
    post['image'] = 'data/img/' + nom


def main():
    anciennes = []
    if os.path.exists(SORTIE):
        try:
            with open(SORTIE, encoding='utf-8') as f:
                anciennes = json.load(f).get('posts', [])
        except Exception:
            anciennes = []

    posts, vues = [], 0
    for cle, var in PAGES:
        jeton = os.environ.get(var, '').strip()
        if not jeton:
            print(f'[{cle}] pas de clé ({var}) : page ignorée')
            posts += [p for p in anciennes if p.get('page') == cle]
            continue
        res = publications(cle, jeton)
        if res is None:      # erreur : on garde ce qu'on avait pour cette page
            posts += [p for p in anciennes if p.get('page') == cle]
            continue
        vues += 1
        posts += res

    if not vues:
        print('Aucune page lue : rien à mettre à jour.')
        return 0

    os.makedirs(IMG, exist_ok=True)
    posts.sort(key=lambda p: p.get('date', ''), reverse=True)
    posts = posts[:GARDEES]
    for p in posts:
        if '_img' in p:
            image(p)

    gardees = {os.path.basename(p['image']) for p in posts if p.get('image')}
    for nom in os.listdir(IMG):
        if nom not in gardees:
            os.remove(os.path.join(IMG, nom))

    with open(SORTIE, 'w', encoding='utf-8') as f:
        json.dump({'posts': posts}, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print(f'{len(posts)} publication(s) écrites')
    return 0


if __name__ == '__main__':
    sys.exit(main())
