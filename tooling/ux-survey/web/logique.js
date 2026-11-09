// Logique du formulaire sans DOM : écrans, conditions, mélange, tri D1, construction de l'envoi, comparaison.
// Testée par `node --test` ; app.js ne fait que l'affichage.

export const ETATS_GARDES = ['garder', 'deplier'];

/** Une condition d'écran est remplie si chaque réponse attendue a l'un des codes autorisés. */
export function conditionOk(ecran, reponses) {
  if (!ecran.condition) return true;
  return Object.entries(ecran.condition).every(([q, codes]) => codes.includes(reponses[q]));
}

/** Écrans à parcourir (sans l'écran de fin), selon les réponses : D1 et D2 seulement si P1 le permet. */
export function ecransVisibles(contenu, reponses) {
  return contenu.ecrans.filter((e) => !e.fin && conditionOk(e, reponses));
}

/** Tirage entier uniforme dans [0, n) sur crypto.getRandomValues, sans biais (rejet). */
export function tirageCrypto(n, crypto = globalThis.crypto) {
  const limite = Math.floor(0x100000000 / n) * n;
  const t = new Uint32Array(1);
  do {
    crypto.getRandomValues(t);
  } while (t[0] >= limite);
  return t[0] % n;
}

/** Mélange de Fisher-Yates ; renvoie une nouvelle liste. */
export function melanger(liste, tirage = tirageCrypto) {
  const l = [...liste];
  for (let i = l.length - 1; i > 0; i--) {
    const j = tirage(i + 1);
    [l[i], l[j]] = [l[j], l[i]];
  }
  return l;
}

/** Jeton aléatoire de 128 bits en hexadécimal (32 caractères). */
export function genererJeton(crypto = globalThis.crypto) {
  const o = new Uint8Array(16);
  crypto.getRandomValues(o);
  return Array.from(o, (x) => x.toString(16).padStart(2, '0')).join('');
}

/** État initial du tri D1 : aucune section choisie, ordre de questions.md. */
export function d1Vide(contenu) {
  return { comme: false, etats: {}, ordre: contenu.questions.D1.sections.map((s) => s.code) };
}

/** Brouillon vide : réponses, écran courant, ordre des cartes (mélangé une fois), heure de début. */
export function brouillonVide(contenu, maintenant = Date.now(), tirage = tirageCrypto) {
  return {
    version: contenu.version,
    reponses: {},
    d1: d1Vide(contenu),
    ecran: 0,
    ordreCartes: melanger(contenu.cartes, tirage),
    debut: maintenant,
  };
}

/** Enregistre (ou efface, si valeur vide) une réponse, puis efface celles dont la condition n'est plus remplie. */
export function changerReponse(contenu, brouillon, id, valeur) {
  const reponses = { ...brouillon.reponses };
  if (valeur === undefined || valeur === null || valeur === '') delete reponses[id];
  else reponses[id] = valeur;
  let d1 = brouillon.d1;
  for (const e of contenu.ecrans) {
    if (conditionOk(e, reponses)) continue;
    for (const q of e.questions) {
      delete reponses[q];
      if (q === 'D1') d1 = d1Vide(contenu);
    }
  }
  const nb = ecransVisibles(contenu, reponses).length;
  return { ...brouillon, reponses, d1, ecran: Math.min(brouillon.ecran, nb - 1) };
}

// ---- tri D1 ----

/** Sections réparties : gardées (dans l'ordre choisi), sans choix, écartées. */
export function d1Groupes(d1) {
  const gardees = d1.ordre.filter((c) => ETATS_GARDES.includes(d1.etats[c]));
  const indecises = d1.ordre.filter((c) => !d1.etats[c]);
  const ecartees = d1.ordre.filter((c) => d1.etats[c] === 'ecarter');
  return { gardees, indecises, ecartees };
}

/** Ordre d'affichage : les gardées d'abord, une section écartée descend sous elles. */
export function d1Affichage(d1) {
  const g = d1Groupes(d1);
  return [...g.gardees, ...g.indecises, ...g.ecartees];
}

/** Choisit l'état d'une section (ou l'efface avec etat vide). */
export function d1ChoisirEtat(d1, code, etat) {
  const etats = { ...d1.etats };
  if (etat) etats[code] = etat;
  else delete etats[code];
  return { ...d1, etats };
}

/** Rang (à partir de 1) d'une section gardée, parmi les sections gardées. */
export function d1Rang(d1, code) {
  return d1Groupes(d1).gardees.indexOf(code) + 1;
}

/** Monte (-1) ou descend (+1) une section gardée d'un cran parmi les gardées ; renvoie le nouveau tri et sa position. */
export function d1Deplacer(d1, code, sens) {
  const { gardees } = d1Groupes(d1);
  const i = gardees.indexOf(code);
  const j = i + sens;
  if (i < 0 || j < 0 || j >= gardees.length) return { d1, position: i + 1, total: gardees.length };
  const ordre = [...d1.ordre];
  const a = ordre.indexOf(gardees[i]);
  const b = ordre.indexOf(gardees[j]);
  [ordre[a], ordre[b]] = [ordre[b], ordre[a]];
  return { d1: { ...d1, ordre }, position: j + 1, total: gardees.length };
}

/** Coche ou décoche « comme aujourd'hui » ; le tri est gardé dans le brouillon. */
export function d1Comme(d1, comme) {
  return { ...d1, comme: Boolean(comme) };
}

/** Réponse D1 à envoyer : `{comme_aujourdhui: true}` seul si la case est cochée, sinon le tri, ou rien. */
export function d1Envoi(d1) {
  if (d1.comme) return { comme_aujourdhui: true };
  const { gardees, ecartees } = d1Groupes(d1);
  const sections = [
    ...gardees.map((code, i) => ({ code, etat: d1.etats[code], rang: i + 1 })),
    ...ecartees.map((code) => ({ code, etat: 'ecarter' })),
  ];
  return sections.length ? { comme_aujourdhui: false, sections } : undefined;
}

/** Vrai si D1 a une réponse (case cochée ou au moins une section choisie). */
export function d1Repondu(d1) {
  return d1.comme || Object.keys(d1.etats).length > 0;
}

// ---- envoi ----

/** Construit le corps de POST /api/reponses : seules les réponses des écrans visibles, les questions vides sont absentes. */
export function construireEnvoi(contenu, brouillon, jeton, maintenant = Date.now(), siteWeb = '') {
  const visibles = new Set(ecransVisibles(contenu, brouillon.reponses).flatMap((e) => e.questions));
  const reponses = {};
  for (const [id, v] of Object.entries(brouillon.reponses)) {
    if (!visibles.has(id) || id === 'D1') continue;
    if (typeof v === 'string' && v.trim() === '') continue;
    reponses[id] = v;
  }
  if (visibles.has('D1')) {
    const d = d1Envoi(brouillon.d1);
    if (d) reponses.D1 = d;
  }
  reponses.ordre_cartes = brouillon.ordreCartes;
  const duree = Math.round((maintenant - brouillon.debut) / 1000);
  return {
    version: contenu.version,
    jeton,
    site_web: siteWeb,
    duree_s: Math.max(0, Math.min(7200, duree)),
    reponses,
  };
}

// ---- brouillon ----

export function cleBrouillon(version) {
  return `ux-survey:${version}:brouillon`;
}

export const CLE_JETON = 'ux-survey:jeton';

/** Relit un brouillon sérialisé ; renvoie null s'il est absent, invalide ou d'une autre version. */
export function lireBrouillon(texte, contenu) {
  if (!texte) return null;
  try {
    const b = JSON.parse(texte);
    const ok =
      b && b.version === contenu.version && typeof b.reponses === 'object' && b.reponses !== null &&
      b.d1 && typeof b.d1.etats === 'object' && Array.isArray(b.d1.ordre) && Number.isInteger(b.ecran) &&
      Array.isArray(b.ordreCartes) && Number.isFinite(b.debut);
    if (!ok) return null;
    const cartes = [...contenu.cartes].sort().join();
    if ([...b.ordreCartes].sort().join() !== cartes) return null;
    const sections = contenu.questions.D1.sections.map((s) => s.code).sort().join();
    if ([...b.d1.ordre].sort().join() !== sections) return null;
    return b;
  } catch {
    return null;
  }
}

// ---- comparaison « vous / la communauté » ----

/** Met les réponses du répondant en regard des pourcentages publiés, dans l'ordre des écrans. */
export function comparer(contenu, stats, envoyees = {}) {
  if (!stats || !stats.disponible) return [];
  const lignes = [];
  for (const e of contenu.ecrans) {
    for (const id of e.questions) {
      const q = contenu.questions[id];
      const s = stats.questions[id];
      if (!s) continue;
      if (q.type === 'choix' || q.type === 'reaction') {
        lignes.push({
          id, libelle: q.libelle, effectif: s.effectif,
          barres: q.reponses.map((r) => ({ code: r.code, libelle: r.libelle, pct: s.codes[r.code] ?? 0, vous: envoyees[id] === r.code })),
        });
      } else if (q.type === 'tri') {
        const mien = envoyees.D1;
        const sections = [];
        for (const sec of q.sections) {
          const x = s.sections?.[sec.code];
          if (!x) continue;
          const m = mien?.sections?.find((y) => y.code === sec.code);
          sections.push({
            code: sec.code, libelle: sec.libelle, effectif: x.effectif,
            garder: x.garder, deplier: x.deplier, ecarter: x.ecarter, rangMedian: x.rang_median ?? null,
            vousEtat: m?.etat ?? null, vousRang: m?.rang ?? null,
          });
        }
        lignes.push({
          id, libelle: q.libelle, effectif: s.effectif,
          comme: { pct: s.comme_aujourdhui ?? 0, vous: mien?.comme_aujourdhui === true },
          sections,
        });
      }
    }
  }
  return lignes;
}
