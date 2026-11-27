/* Factures des clubs : calcul (paiements, avoirs) et dessin du PDF.
   Fichier COMMUN à la Facturation (facturation/index.html) et à l'Espace club (espace-club/index.html),
   pour que le club télécharge exactement la même facture que celle du Comité.
   Les fonctions lisent la variable globale D de la page : { clubs, bordereaux, lignes, paiements, reglages }.
   À charger avant le script de la page :  <script src="/facturation/facture-commun.js"></script>  */
const r2 = n => Math.round((+n || 0) * 100) / 100;
const num = v => { const n = parseFloat(String(v == null ? '' : v).replace(/\s/g, '').replace(',', '.')); return isNaN(n) ? 0 : n; };
const fmtN = n => r2(n).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const euros = n => fmtN(n) + ' €';
const qte = n => r2(n).toLocaleString('fr-FR', { maximumFractionDigits: 2 });
function parseD(s) { if (!s) return null; const [y, m, d] = String(s).slice(0, 10).split('-').map(Number); return new Date(y, m - 1, d); }
function fmtD(s) { const d = parseD(s); return d ? String(d.getDate()).padStart(2,'0') + '/' + String(d.getMonth()+1).padStart(2,'0') + '/' + d.getFullYear() : ''; }

const club = code => (D.clubs.find(c => c.code === code) || { code, nom: code });

const montant = l => r2(num(l.quantite) * num(l.prix));
const lignesDe = (bid, code) => D.lignes.filter(l => String(l.bordereau_id) === String(bid) && (!code || l.club === code));
const totalDe = (bid, code) => r2(lignesDe(bid, code).reduce((s, l) => s + montant(l), 0));

const facNum = (b, code) => `${b.saison.slice(2, 4)}${b.saison.slice(7, 9)}-${String(b.numero).padStart(2, '0')}-${code}`;
const reglage = (k, d) => (D.reglages && D.reglages[k] != null) ? D.reglages[k] : d;
const bordsTries = () => [...D.bordereaux].sort((a, b) => a.numero - b.numero);

// Paiements d'un club : d'abord imputés au bordereau indiqué, puis le reste sur les bordereaux les plus anciens
function etatClub(code) {
  const bs = bordsTries(), du = {}, regle = {}, avoir = {};
  bs.forEach(b => { du[b.id] = totalDe(b.id, code); regle[b.id] = 0; avoir[b.id] = 0; });
  // un bordereau négatif (avoir, trop-perçu) est soldé et crée un crédit, déduit des bordereaux suivants
  let credit = 0; const sources = [];
  bs.forEach(b => { if (du[b.id] < -0.005) { credit += -du[b.id]; regle[b.id] = du[b.id]; sources.push(b.numero); } });
  const creditTotal = r2(credit);
  const pays = D.paiements.filter(p => p.club === code);
  let libre = 0;
  pays.forEach(p => { if (p.bordereau_id && regle[p.bordereau_id] != null) regle[p.bordereau_id] += num(p.montant); else libre += num(p.montant); });
  bs.forEach(b => { const reste = du[b.id] - regle[b.id]; if (reste > 0 && credit > 0) { const x = Math.min(reste, credit); regle[b.id] += x; avoir[b.id] = r2(x); credit -= x; } });
  bs.forEach(b => { const reste = du[b.id] - regle[b.id]; if (reste > 0 && libre > 0) { const x = Math.min(reste, libre); regle[b.id] += x; libre -= x; } });
  const totDu = r2(Object.values(du).reduce((s, x) => s + x, 0)), totRegle = r2(pays.reduce((s, p) => s + num(p.montant), 0));
  return { du, regle, avoir, creditTotal, creditRestant: r2(credit), sourcesAvoir: sources, totDu, totRegle, reste: r2(totDu - totRegle) };
}

const pdfTxt = s => String(s == null ? '' : s).replace(/[  ]/g, ' ').replace(/[’]/g, "'");
const pdfN = n => pdfTxt(fmtN(n));
function pageFacture(doc, b, code, img) {
  const c = club(code), tot = totalDe(b.id, code), e = etatClub(code), av = tot > 0 ? r2(e.avoir[b.id] || 0) : 0, rg = tot > 0 ? r2((e.regle[b.id] || 0) - av) : 0;
  const extra = [];
  if (av > 0 || rg > 0) {
    if (av > 0) extra.push({ t: `Avoir déduit${e.sourcesAvoir.length ? ' (bordereau N° ' + e.sourcesAvoir.join(', ') + ')' : ''} : ` + euros(av) });
    if (rg > 0) extra.push({ t: 'Déjà réglé : ' + euros(rg) });
    extra.push({ t: 'Reste à payer : ' + euros(Math.max(0, tot - av - rg)), b: 1 });
    if (av > 0 && e.creditRestant > 0.005) extra.push({ t: 'Avoir restant : ' + euros(e.creditRestant), s: 1 });
  }
  dessinFacture(doc, { numero: facNum(b, code), infos: [`Bordereau n° ${b.numero} du ${fmtD(b.date)}`, 'Saison ' + b.saison.replace('-', '/')],
    dest: { nom: c.nom, sous: c.numero ? 'N° d\'affiliation ' + c.numero : '', adresse: c.adresse }, titre: b.titre, lignes: lignesDe(b.id, code), tot, extra }, img);
}
// Mise en page commune des factures (clubs et hors clubs)
function dessinFacture(doc, o, img) {
  const ls = o.lignes, W = 210, M = 16, navy = [11, 33, 73];
  doc.setTextColor(20, 32, 58);
  let lw = 0;
  if (img) { try { const ip = doc.getImageProperties(img), h = 22; lw = Math.min(40, h * ip.width / ip.height); doc.addImage(img, 'JPEG', M, 12, lw, lw * ip.height / ip.width); } catch(e) { lw = 0; } }
  const X = M + (lw ? lw + 5 : 0);
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5);
  const em = pdfTxt(reglage('emetteur', 'Comité du Var de Volley-Ball')).split('\n');
  doc.text(em[0] || '', X, 17); doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  em.slice(1).forEach((t, i) => doc.text(t, X, 21.5 + i * 4.2));
  doc.setFont('helvetica', 'bold'); doc.setFontSize(24); doc.setTextColor(...navy); doc.text(o.doc || 'FACTURE', W - M, 20, { align: 'right' });
  doc.setFontSize(10); doc.setTextColor(20, 32, 58); doc.text('N° ' + o.numero, W - M, 27, { align: 'right' });
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  (o.infos || []).forEach((t, k) => doc.text(pdfTxt(t), W - M, 32 + k * 4.5, { align: 'right' }));
  // destinataire (adresse : lignes séparées par « / » ou des retours à la ligne)
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5);
  const nomL = doc.splitTextToSize(pdfTxt(o.dest.nom), 84);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  const adrL = String(o.dest.adresse || '').split(/\s*\/\s*|\n/).map(x => pdfTxt(x.trim())).filter(Boolean).slice(0, 5);
  const y0 = 46, hBox = Math.max(26, 8 + nomL.length * 4.6 + (o.dest.sous ? 4.2 : 0) + adrL.length * 4.1);
  doc.setDrawColor(201, 210, 226); doc.setFillColor(244, 246, 250); doc.roundedRect(W - M - 92, y0, 92, hBox, 2, 2, 'FD');
  doc.setFont('helvetica', 'bold'); doc.setFontSize(10.5); doc.text(nomL, W - M - 88, y0 + 6.5);
  doc.setFont('helvetica', 'normal'); doc.setFontSize(9);
  let yy = y0 + 6.5 + nomL.length * 4.6;
  if (o.dest.sous) { doc.setTextColor(86, 98, 122); doc.text(pdfTxt(o.dest.sous), W - M - 88, yy); doc.setTextColor(20, 32, 58); yy += 4.2; }
  adrL.forEach(t => { doc.text(t, W - M - 88, yy); yy += 4.1; });
  if (o.titre) { doc.setFont('helvetica', 'bold'); doc.setFontSize(10); doc.text(doc.splitTextToSize(pdfTxt(o.titre), W - 2 * M - 100), M, y0 + 8); }
  // tableau
  const cols = [{ t: 'Date', x: M, w: 19 }, { t: 'Compte', x: M + 19, w: 16 }, { t: 'Désignation', x: M + 35, w: 89 }, { t: 'Qté', x: M + 124, w: 14, r: 1 }, { t: 'P.U. €', x: M + 138, w: 20, r: 1 }, { t: 'Total €', x: M + 158, w: 20, r: 1 }];
  let y = Math.max(82, y0 + hBox + 10);
  const head = () => {
    doc.setFillColor(...navy); doc.rect(M, y - 5, W - 2 * M, 7.5, 'F'); doc.setTextColor(255, 255, 255); doc.setFont('helvetica', 'bold'); doc.setFontSize(8.5);
    cols.forEach(k => doc.text(pdfTxt(k.t), k.r ? k.x + k.w - 1.5 : k.x + 1.5, y, k.r ? { align: 'right' } : {}));
    doc.setTextColor(20, 32, 58); doc.setFont('helvetica', 'normal'); y += 7;
  };
  head();
  ls.forEach((l, i) => {
    doc.setFontSize(8.5);
    const des = doc.splitTextToSize(pdfTxt(l.designation), cols[2].w - 3);
    doc.setFontSize(7.5); const pre = l.precisions ? doc.splitTextToSize(pdfTxt(l.precisions), cols[2].w - 3) : []; doc.setFontSize(8.5);
    const h = Math.max(1, des.length) * 3.8 + pre.length * 3.3 + 2.4;
    if (y + h > 262) { doc.addPage(); y = 20; head(); }
    if (i % 2) { doc.setFillColor(248, 250, 253); doc.rect(M, y - 4, W - 2 * M, h, 'F'); }
    doc.text(fmtD(l.date_ligne), cols[0].x + 1.5, y); doc.text(pdfTxt(l.code_compta || ''), cols[1].x + 1.5, y); doc.text(des, cols[2].x + 1.5, y);
    if (pre.length) { doc.setFontSize(7.5); doc.setFont('helvetica', 'italic'); doc.setTextColor(86, 98, 122); doc.text(pre, cols[2].x + 1.5, y + des.length * 3.8 - 0.4); doc.setTextColor(20, 32, 58); doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); }
    doc.text(pdfTxt(qte(l.quantite)), cols[3].x + cols[3].w - 1.5, y, { align: 'right' }); doc.text(pdfN(l.prix), cols[4].x + cols[4].w - 1.5, y, { align: 'right' });
    doc.setFont('helvetica', 'bold'); doc.text(pdfN(montant(l)), cols[5].x + cols[5].w - 1.5, y, { align: 'right' }); doc.setFont('helvetica', 'normal');
    y += h;
  });
  doc.setDrawColor(...navy); doc.setLineWidth(0.4); doc.line(M, y - 2.5, W - M, y - 2.5);
  if (y > 240) { doc.addPage(); y = 24; }
  const tot = o.tot;
  y += 5; doc.setFillColor(...navy); doc.rect(W - M - 70, y - 5.5, 70, 10, 'F'); doc.setTextColor(255, 255, 255); doc.setFont('helvetica', 'bold'); doc.setFontSize(11);
  doc.text('TOTAL', W - M - 66, y + 1); doc.text(pdfTxt(euros(tot)), W - M - 3, y + 1, { align: 'right' }); doc.setTextColor(20, 32, 58);
  if ((o.extra || []).length) { y += 5;
    o.extra.forEach(x => { y += x.b ? 5.5 : 5; doc.setFont('helvetica', x.b ? 'bold' : 'normal'); doc.setFontSize(x.s ? 8.5 : 9.5); doc.text(pdfTxt(x.t), W - M - 3, y, { align: 'right' }); }); }
  const tva = String(reglage('mention_tva', '') || '').trim();
  if (tva) { y += (o.extra || []).length ? 6.5 : 10.5; doc.setFont('helvetica', 'italic'); doc.setFontSize(8.5); doc.setTextColor(86, 98, 122); doc.text(doc.splitTextToSize(pdfTxt(tva), 125), W - M - 3, y, { align: 'right' }); doc.setTextColor(20, 32, 58); }
  if (o.devis) {   // devis : pas de coordonnées bancaires, cadre « Bon pour accord »
    const yA = Math.max(y + 12, 222);
    if (yA + 48 > 285) doc.addPage();
    const yB = yA + 48 > 285 ? 30 : yA;
    doc.setDrawColor(201, 210, 226); doc.setFillColor(244, 246, 250); doc.roundedRect(W - M - 92, yB, 92, 38, 2, 2, 'FD');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9.5); doc.setTextColor(...navy); doc.text('Bon pour accord', W - M - 88, yB + 6);
    doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(86, 98, 122);
    doc.text('Date, signature et cachet, précédés de la mention', W - M - 88, yB + 11); doc.text('« Bon pour accord »', W - M - 88, yB + 15);
    doc.setFontSize(8.5); doc.setTextColor(86, 98, 122);
    doc.text(doc.splitTextToSize(pdfTxt(`Devis valable${o.validite ? " jusqu'au " + fmtD(o.validite) : ' 30 jours'}. Une facture sera établie à l'acceptation du devis.`), W - 2 * M - 100), M, yB + 6);
    return;
  }
  // pied : coordonnées bancaires puis mentions
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5);
  const me = doc.splitTextToSize(pdfTxt(reglage('mentions', '')), W - 2 * M), yMe = 285 - me.length * 3.8;
  const bq = pdfTxt(reglage('banque', '')).split('\n').map(x => x.trim()).filter(Boolean);
  if (bq.length) {
    const hB = 9 + bq.length * 4.4, yB = yMe - 4 - hB;
    if (y + 6 > yB) { doc.addPage(); }
    doc.setDrawColor(201, 210, 226); doc.setFillColor(244, 246, 250); doc.roundedRect(M, yB, 120, hB, 2, 2, 'FD');
    doc.setFont('helvetica', 'bold'); doc.setFontSize(9); doc.setTextColor(...navy); doc.text('Règlement par virement', M + 4, yB + 5.5);
    doc.setFont('courier', 'normal'); doc.setFontSize(8.8); doc.setTextColor(20, 32, 58);
    bq.forEach((t, i) => { if (/^(IBAN|BIC)/i.test(t)) doc.setFont('courier', 'bold'); else doc.setFont('helvetica', 'normal'); doc.text(t, M + 4, yB + 10.5 + i * 4.4); });
  }
  doc.setFont('helvetica', 'normal'); doc.setFontSize(8.5); doc.setTextColor(86, 98, 122);
  doc.text(me, M, yMe);
}
