// Affichage du questionnaire. Tout texte est inséré par textContent ou createElement ; les largeurs de
// barres passent par le CSSOM ; aucun gestionnaire d'événement en attribut (CSP : script-src 'self').
import * as L from './logique.js';

const racine = document.getElementById('app');
const progression = document.getElementById('progression');
const etape = document.getElementById('etape');
const piege = document.getElementById('site_web');

const TITRES = {
  profil: 'Votre profil',
  ouverture: "La suite de l'app",
  irritants: 'Au quotidien',
  theme1: "La lecture d'un sujet",
  'theme2-a': 'iPad et iPhone Duo',
  'theme2-b': 'iPad et iPhone Duo',
  cartes: 'Quelques idées',
  idee: 'Une idée ?',
  mp: 'Messages privés',
  libre: 'Un dernier mot',
  pseudo: 'Pseudo',
};
const PISTES = "Ce sont des pistes à l'étude, pas des engagements.";

let contenu;
let etat;
let brouillon;
let jeton;
let envoyeesSession = {};
const memoire = new Map(); // repli si localStorage est indisponible (navigation privée)

// ---- stockage local, jamais bloquant ----
function lire(cle) {
  try {
    return localStorage.getItem(cle);
  } catch {
    return memoire.get(cle) ?? null;
  }
}
function ecrire(cle, valeur) {
  try {
    localStorage.setItem(cle, valeur);
  } catch {
    memoire.set(cle, valeur);
  }
}
function retirer(cle) {
  memoire.delete(cle);
  try {
    localStorage.removeItem(cle);
  } catch {
    /* sans effet */
  }
}
function sauver() {
  ecrire(L.cleBrouillon(contenu.version), JSON.stringify(brouillon));
}

// ---- construction du DOM ----
function h(balise, attrs = {}, ...enfants) {
  const el = document.createElement(balise);
  for (const [k, v] of Object.entries(attrs)) {
    if (v === false || v === null || v === undefined) continue;
    el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const e of enfants) el.append(e);
  return el;
}
const t = (texte) => document.createTextNode(texte);

async function json(url, options) {
  const r = await fetch(url, options);
  return { statut: r.status, donnees: await r.json().catch(() => ({})) };
}

// ---- démarrage ----
async function demarrer() {
  try {
    const [c, e] = await Promise.all([json('/static/questionnaire.json'), json('/api/etat')]);
    if (c.statut !== 200 || e.statut !== 200) throw new Error('chargement');
    contenu = c.donnees;
    etat = e.donnees;
  } catch {
    racine.replaceChildren(h('h1', { tabindex: '-1' }, 'Chargement impossible'), h('p', {}, 'Rechargez la page dans un instant.'));
    return;
  }
  if (!etat.ouvert) {
    await ecranFerme();
    return;
  }
  jeton = lire(L.CLE_JETON);
  if (!/^[0-9a-f]{32}$/.test(jeton ?? '')) {
    jeton = L.genererJeton();
    ecrire(L.CLE_JETON, jeton);
  }
  brouillon = L.lireBrouillon(lire(L.cleBrouillon(contenu.version)), contenu) ?? L.brouillonVide(contenu);
  sauver();
  rendreEcran(false);
}

function ecransVisibles() {
  return L.ecransVisibles(contenu, brouillon.reponses);
}

function majProgression() {
  const n = ecransVisibles().length;
  const i = Math.min(brouillon.ecran, n - 1);
  progression.max = n;
  progression.value = i + 1;
  etape.textContent = `Étape ${i + 1} sur ${n}`;
}

function aller(i) {
  brouillon = { ...brouillon, ecran: i };
  sauver();
  rendreEcran(true);
}

// ---- écrans ----
function rendreEcran(deplacerFocus) {
  const ecrans = ecransVisibles();
  const i = Math.max(0, Math.min(brouillon.ecran, ecrans.length - 1));
  brouillon = { ...brouillon, ecran: i };
  const ecran = ecrans[i];
  const titre = ecran.id === 'accueil' ? contenu.questions.E0.libelle : TITRES[ecran.id] ?? '';
  const h1 = h('h1', { tabindex: '-1', id: 'titre-ecran' }, titre);
  const corps = h('div', { class: 'corps' });
  if (ecran.id === 'accueil') corps.append(...accueil());
  else if (ecran.id === 'cartes') corps.append(h('p', { class: 'pistes' }, PISTES), ...brouillon.ordreCartes.map((id) => champ(id)));
  else if (ecran.id === 'pseudo') corps.append(...pseudo());
  else corps.append(...ecran.questions.map((id) => champ(id)));

  const dernier = i === ecrans.length - 1;
  const message = h('p', { id: 'message', role: 'status', class: 'message' });
  const precedent = h('button', { type: 'button', class: 'secondaire' }, 'Précédent');
  precedent.hidden = i === 0;
  precedent.addEventListener('click', () => aller(i - 1));
  const suivant = h('button', { type: 'button', class: 'principal' }, dernier ? 'Envoyer' : 'Suivant');
  suivant.addEventListener('click', () => (dernier ? envoyer(suivant, message) : aller(i + 1)));
  racine.replaceChildren(h('section', { 'aria-labelledby': 'titre-ecran' }, h1, corps, message, h('div', { class: 'navigation' }, precedent, suivant)));
  majProgression();
  if (deplacerFocus) {
    window.scrollTo(0, 0);
    h1.focus();
  }
}

function accueil() {
  const q = contenu.questions.E0;
  return [h('p', {}, q.textes[0]), h('p', {}, h('a', { href: '/donnees', target: '_blank', rel: 'noopener' }, q.textes[1]))];
}

function pseudo() {
  const mention = document.getElementById('mention-pseudo').content.cloneNode(true);
  const q = contenu.questions.I1;
  return [mention, h('p', {}, h('a', { href: '/donnees', target: '_blank', rel: 'noopener' }, q.lien)), champ('I1')];
}

function champ(id) {
  const q = contenu.questions[id];
  switch (q.type) {
    case 'choix':
    case 'reaction':
      return champChoix(id, q);
    case 'texte':
    case 'pseudo':
      return champTexte(id, q);
    case 'tri':
      return champTri(id, q);
    default:
      return h('p', {}, q.libelle);
  }
}

function boutonEffacer(visible, action) {
  const b = h('button', { type: 'button', class: 'lien' }, 'Effacer ma réponse');
  b.hidden = !visible;
  b.addEventListener('click', action);
  return b;
}

// ---- choix et réactions ----
function visuel(v) {
  const base = '/static/visuels/';
  if (v.fichier.endsWith('.mp4')) {
    const video = h('video', { controls: true, preload: 'none', muted: true, playsinline: true, poster: base + v.image_attente, 'aria-label': v.alt });
    video.muted = true;
    video.append(h('source', { src: base + v.fichier, type: 'video/mp4' }));
    return h('figure', { class: 'visuel' }, video);
  }
  return h('figure', { class: 'visuel' }, h('img', { src: base + v.fichier, alt: v.alt, loading: 'lazy' }));
}

function champChoix(id, q) {
  const carte = q.type === 'reaction';
  const fs = h('fieldset', { class: carte ? 'question carte' : 'question' }, h('legend', {}, q.libelle));
  if (q.aide) fs.append(h('p', { class: 'aide', id: `${id}-aide` }, q.aide));
  const groupe = h('div', { class: carte ? 'reponses boutons' : 'reponses' });
  const efface = boutonEffacer(Boolean(brouillon.reponses[id]), () => {
    brouillon = L.changerReponse(contenu, brouillon, id, '');
    for (const r of groupe.querySelectorAll('input')) r.checked = false;
    efface.hidden = true;
    sauver();
    majProgression();
  });
  for (const r of q.reponses) {
    const rid = `${id}-${r.code}`;
    const input = h('input', { type: 'radio', name: id, id: rid, value: r.code });
    input.checked = brouillon.reponses[id] === r.code;
    input.addEventListener('change', () => {
      brouillon = L.changerReponse(contenu, brouillon, id, r.code);
      efface.hidden = false;
      sauver();
      majProgression();
    });
    const option = h('div', { class: 'option' }, input, h('label', { for: rid }, r.libelle));
    if (r.details?.length) {
      const ul = h('ul', { class: 'details', id: `${rid}-details` }, ...r.details.map((d) => h('li', {}, d)));
      input.setAttribute('aria-describedby', ul.id);
      option.append(ul);
    }
    for (const v of r.visuels ?? []) option.append(visuel(v));
    groupe.append(option);
  }
  fs.append(groupe, efface);
  return fs;
}

// ---- textes ----
function champTexte(id, q) {
  const unique = q.type === 'pseudo';
  const zone = unique
    ? h('input', { type: 'text', id, name: id, maxlength: q.max, autocomplete: 'off', autocapitalize: 'off', spellcheck: 'false' })
    : h('textarea', { id, name: id, rows: 4, maxlength: q.max });
  zone.value = brouillon.reponses[id] ?? '';
  const restant = h('span', { class: 'compteur', 'aria-hidden': 'true' });
  const annonce = h('span', { class: 'sr-only', 'aria-live': 'polite' });
  const decrire = [];
  const bloc = h('div', { class: 'question texte' }, h('label', { for: id }, q.libelle));
  if (q.aide) {
    bloc.append(h('p', { class: 'aide', id: `${id}-aide` }, q.aide));
    decrire.push(`${id}-aide`);
  }
  decrire.push(`${id}-reste`);
  zone.setAttribute('aria-describedby', decrire.join(' '));
  let minuteur;
  const maj = (annoncer) => {
    const n = q.max - [...zone.value].length;
    const phrase = `Il reste ${Math.max(0, n)} caractère${n > 1 ? 's' : ''}`;
    restant.textContent = phrase;
    if (annoncer) annonce.textContent = phrase;
  };
  maj(false);
  zone.addEventListener('input', () => {
    brouillon = L.changerReponse(contenu, brouillon, id, zone.value);
    sauver();
    maj(false);
    clearTimeout(minuteur);
    minuteur = setTimeout(() => maj(true), 800);
  });
  bloc.append(zone, h('p', { class: 'reste', id: `${id}-reste` }, restant, annonce));
  return bloc;
}

// ---- tri de la barre latérale (D1) ----
function champTri(id, q) {
  const fs = h('fieldset', { class: 'question tri' }, h('legend', {}, q.libelle));
  if (q.aide) fs.append(h('p', { class: 'aide' }, q.aide));
  const comme = h('input', { type: 'checkbox', id: 'D1-comme' });
  comme.checked = brouillon.d1.comme;
  const liste = h('ol', { class: 'sections' });
  const zone = h('fieldset', { class: 'zone-tri' }, h('legend', { class: 'sr-only' }, 'Sections de la barre latérale'), liste);
  const annonce = h('p', { class: 'sr-only', 'aria-live': 'polite' });
  const efface = boutonEffacer(false, () => {
    brouillon = { ...brouillon, d1: L.d1Vide(contenu) };
    comme.checked = false;
    sauver();
    dessiner();
  });

  function mettre(d1, focus) {
    brouillon = { ...brouillon, d1 };
    sauver();
    dessiner();
    if (focus) document.getElementById(focus)?.focus();
  }

  function dessiner() {
    const d1 = brouillon.d1;
    zone.disabled = d1.comme;
    efface.hidden = !L.d1Repondu(d1);
    liste.replaceChildren();
    for (const code of L.d1Affichage(d1)) {
      const s = q.sections.find((x) => x.code === code);
      const etatActuel = d1.etats[code];
      const li = h('li', { class: 'section' });
      const nom = h('span', { class: 'nom' }, s.libelle);
      li.append(nom);
      const groupeEtat = h('div', { class: 'etats', role: 'radiogroup', 'aria-label': `État de ${s.libelle}` });
      for (const e of q.etats) {
        const rid = `D1-${code}-${e.code}`;
        const r = h('input', { type: 'radio', name: `D1-${code}`, id: rid, value: e.code });
        r.checked = etatActuel === e.code;
        r.addEventListener('change', () => mettre(L.d1ChoisirEtat(brouillon.d1, code, e.code), rid));
        groupeEtat.append(h('div', { class: 'option' }, r, h('label', { for: rid }, e.libelle)));
      }
      li.append(groupeEtat);
      if (etatActuel === 'garder' || etatActuel === 'deplier') {
        nom.append(t(` (position ${L.d1Rang(d1, code)})`));
        const bouger = (sens, bid) => () => {
          const res = L.d1Deplacer(brouillon.d1, code, sens);
          annonce.textContent = `${s.libelle}, position ${res.position} sur ${res.total}`;
          mettre(res.d1, bid);
        };
        const mid = `D1-${code}-monter`;
        const did = `D1-${code}-descendre`;
        const monter = h('button', { type: 'button', id: mid, class: 'secondaire' }, 'Monter', h('span', { class: 'sr-only' }, ` ${s.libelle}`));
        const descendre = h('button', { type: 'button', id: did, class: 'secondaire' }, 'Descendre', h('span', { class: 'sr-only' }, ` ${s.libelle}`));
        monter.addEventListener('click', bouger(-1, mid));
        descendre.addEventListener('click', bouger(1, did));
        li.append(h('div', { class: 'deplacer' }, monter, descendre));
      }
      liste.append(li);
    }
  }

  comme.addEventListener('change', () => {
    brouillon = { ...brouillon, d1: L.d1Comme(brouillon.d1, comme.checked) };
    sauver();
    dessiner();
  });
  fs.append(h('div', { class: 'option' }, comme, h('label', { for: 'D1-comme' }, q.reponse_seule.libelle)), zone, annonce, efface);
  dessiner();
  return fs;
}

// ---- envoi ----
async function envoyer(bouton, message) {
  bouton.disabled = true;
  message.textContent = 'Envoi en cours…';
  const corps = L.construireEnvoi(contenu, brouillon, jeton, Date.now(), piege.value);
  try {
    const { statut, donnees } = await json('/api/reponses', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(corps),
    });
    if (statut === 201 || (statut === 409 && donnees.deja_recu)) {
      envoyeesSession = corps.reponses;
      ecranFin(corps.reponses, donnees.stats);
      retirer(L.cleBrouillon(contenu.version)); // R3 : brouillon effacé après l'écran de fin rendu
      return;
    }
    message.textContent =
      {
        409: 'Le questionnaire a été mis à jour : rechargez la page. Vos réponses sont gardées.',
        410: 'Le questionnaire est fermé.',
        429: "Trop d'envois depuis cette adresse. Réessayez plus tard.",
        413: 'Vos réponses sont trop longues.',
      }[statut] ?? "L'envoi a échoué. Vos réponses sont gardées : vous pouvez réessayer.";
  } catch {
    message.textContent = 'Connexion impossible. Vos réponses sont gardées : vous pouvez réessayer.';
  }
  bouton.disabled = false;
}

// ---- écran de fin et comparaison ----
function barre(libelle, pct, vous) {
  const piste = h('div', { class: 'piste' });
  const b = h('div', { class: 'barre' });
  b.style.setProperty('--part', `${pct}%`);
  piste.append(b);
  const ligne = h('li', { class: vous ? 'vous' : '' }, h('span', { class: 'etiquette' }, libelle), piste, h('span', { class: 'valeur' }, `${pct} %`));
  if (vous) ligne.append(h('strong', { class: 'marque' }, 'Votre réponse'));
  return ligne;
}

function rendreComparaison(lignes) {
  const sortie = [];
  for (const l of lignes) {
    const bloc = h('section', { class: 'resultat' }, h('h2', {}, l.libelle));
    if (l.barres) {
      bloc.append(h('ul', { class: 'barres' }, ...l.barres.map((b) => barre(b.libelle, b.pct, b.vous))));
    } else {
      const q = contenu.questions[l.id];
      bloc.append(h('ul', { class: 'barres' }, barre(q.reponse_seule.libelle, l.comme.pct, l.comme.vous)));
      for (const s of l.sections) {
        const rang = s.rangMedian === null ? '' : `, rang médian ${s.rangMedian}`;
        bloc.append(
          h('h3', {}, `${s.libelle}${rang}`),
          h('ul', { class: 'barres' },
            ...q.etats.map((e) => barre(e.libelle, s[e.code], s.vousEtat === e.code)))
        );
      }
    }
    bloc.append(h('p', { class: 'effectif' }, `${l.effectif} réponse${l.effectif > 1 ? 's' : ''}`));
    sortie.push(bloc);
  }
  return sortie;
}

function ecranFin(envoyees, stats) {
  const q = contenu.questions.E1;
  const h1 = h('h1', { tabindex: '-1' }, q.libelle);
  const corps = h('div', { class: 'corps' }, h('p', {}, q.textes[0]));
  if (stats?.disponible) corps.append(h('div', { class: 'resultats' }, ...rendreComparaison(L.comparer(contenu, stats, envoyees))));
  else corps.append(h('p', {}, q.textes[1]));
  corps.append(h('p', { class: 'aide' }, q.textes[2]));
  racine.replaceChildren(h('section', {}, h1, corps));
  progression.hidden = true;
  etape.hidden = true;
  window.scrollTo(0, 0);
  h1.focus();
}

async function ecranFerme() {
  const q = contenu.questions.E1;
  const h1 = h('h1', { tabindex: '-1' }, 'Questionnaire fermé');
  const corps = h('div', { class: 'corps' }, h('p', {}, 'Merci à toutes les personnes qui ont répondu.'));
  progression.hidden = true;
  etape.hidden = true;
  try {
    const { donnees } = await json('/api/stats');
    if (donnees.disponible) corps.append(h('div', { class: 'resultats' }, ...rendreComparaison(L.comparer(contenu, donnees, envoyeesSession))));
    else corps.append(h('p', {}, q.textes[1]));
  } catch {
    /* les statistiques sont facultatives */
  }
  corps.append(h('p', { class: 'aide' }, q.textes[2]));
  racine.replaceChildren(h('section', {}, h1, corps));
  h1.focus();
}

demarrer();
