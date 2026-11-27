/* Connexion unique de l'Espace Comité — volley83.github.io
   À inclure dans le <head> de chaque partie, AVANT son script :  <script src="/comite/session.js"></script>

   Chaque partie garde son propre mot de passe en mémoire (stg_admin, chp_admin, fac_admin…).
   Ce petit script les relie :
   - quand le mot de passe du Comité est connu (connexion sur n'importe quelle partie ou sur l'Espace Comité),
     il est recopié pour toutes les autres parties → plus besoin de le retaper ;
   - « Se déconnecter » sur une partie déconnecte partout ;
   - « Rester connecté sur cet ordinateur » (Espace Comité) garde le mot de passe après la fermeture du navigateur. */
(function () {
  var KEYS = ['stg_admin', 'chp_admin', 'fac_admin', 'doc_admin', 'clb_admin', 'ecl_admin', 'tip_admin', 'pit_admin'];
  var NO_COPY = ['tip_admin'];        // le TIP accepte aussi un mot de passe « saisie des résultats » : on ne le propage pas
  var SHARED = 'v83_admin';
  var proto = window.Storage && Storage.prototype;
  if (!proto) return;
  var set = proto.setItem, get = proto.getItem, rem = proto.removeItem;
  var ss, ls;
  try { ss = window.sessionStorage; ls = window.localStorage; } catch (e) { return; }

  function forgetAll() {
    try {
      rem.call(ss, SHARED); rem.call(ls, SHARED);
      KEYS.forEach(function (k) { rem.call(ss, k); });
      // session Supabase du Pitchoun' Volley
      for (var i = ls.length - 1; i >= 0; i--) { var k = ls.key(i); if (/^sb-.*-auth-token$/.test(k)) rem.call(ls, k); }
    } catch (e) {}
    var b = document.getElementById('v83-espace'); if (b) b.remove();
  }

  // 1) Au chargement : le mot de passe commun est recopié pour toutes les parties
  try {
    var p = get.call(ss, SHARED) || get.call(ls, SHARED);
    if (p) { set.call(ss, SHARED, p); KEYS.forEach(function (k) { set.call(ss, k, p); }); }
  } catch (e) {}

  // 2) Connexion sur une partie → mot de passe commun ; déconnexion → partout
  proto.setItem = function (k, v) {
    set.call(this, k, v);
    if (this === ss && KEYS.indexOf(k) >= 0 && NO_COPY.indexOf(k) < 0) {
      try { set.call(ss, SHARED, v); if (get.call(ls, SHARED)) set.call(ls, SHARED, v); } catch (e) {}
    }
  };
  proto.removeItem = function (k) {
    rem.call(this, k);
    if (this === ss && KEYS.indexOf(k) >= 0) forgetAll();
  };

  // 3) Petit bouton « Espace Comité » en bas à gauche, visible seulement quand on est connecté
  function bouton() {
    if (/\/comite\/?$/.test(location.pathname) || !window.V83Session.get() || document.getElementById('v83-espace')) return;
    var a = document.createElement('a');
    a.id = 'v83-espace'; a.href = '/comite/'; a.textContent = '◂ Espace Comité';
    a.setAttribute('style', 'position:fixed;left:12px;bottom:12px;z-index:9999;background:#0B2149;color:#fff;font:600 13px/1 Inter,system-ui,sans-serif;' +
      'padding:9px 13px;border-radius:999px;text-decoration:none;box-shadow:0 2px 8px rgba(0,0,0,.25);border:2px solid #F6C21B;opacity:.92');
    document.body.appendChild(a);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bouton); else setTimeout(bouton, 0);

  window.V83Session = {
    get: function () { try { return get.call(ss, SHARED) || get.call(ls, SHARED) || ''; } catch (e) { return ''; } },
    save: function (pwd, remember) {
      try { set.call(ss, SHARED, pwd); KEYS.forEach(function (k) { set.call(ss, k, pwd); });
        if (remember) set.call(ls, SHARED, pwd); else rem.call(ls, SHARED); } catch (e) {}
    },
    remembered: function () { try { return !!get.call(ls, SHARED); } catch (e) { return false; } },
    logout: forgetAll
  };
})();
