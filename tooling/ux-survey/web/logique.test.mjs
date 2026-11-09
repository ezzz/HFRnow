// Tests de la logique du formulaire : `node --test web/logique.test.mjs` (exécuteur intégré à Node).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import * as L from './logique.js';

const contenu = JSON.parse(readFileSync(new URL('../contenu/questionnaire.json', import.meta.url), 'utf8'));
const ids = (ecrans) => ecrans.map((e) => e.id);
const base = () => L.brouillonVide(contenu, 1_000_000, (n) => n - 1); // tirage déterministe

// Test 4 : conditions côté front.
test('écrans selon P1, G1 toujours entre O1 et L1', () => {
  for (const p1 of ['ipad', 'duo', 'plusieurs']) {
    const e = ids(L.ecransVisibles(contenu, { P1: p1 }));
    assert.ok(e.includes('theme2-a') && e.includes('theme2-b'), p1);
  }
  for (const r of [{ P1: 'iphone' }, {}]) {
    const e = ids(L.ecransVisibles(contenu, r));
    assert.ok(!e.includes('theme2-a') && !e.includes('theme2-b'));
  }
  for (const r of [{}, { P1: 'ipad' }]) {
    const e = ids(L.ecransVisibles(contenu, r));
    assert.equal(e.indexOf('irritants'), e.indexOf('ouverture') + 1);
    assert.equal(e.indexOf('theme1'), e.indexOf('irritants') + 1);
  }
  assert.ok(!ids(L.ecransVisibles(contenu, {})).includes('fin'));
});

test('changer P1 efface D1 et D2 du brouillon', () => {
  let b = L.changerReponse(contenu, base(), 'P1', 'ipad');
  b = L.changerReponse(contenu, b, 'D2', 'cote_a_cote');
  b = { ...b, d1: L.d1ChoisirEtat(b.d1, 'favoris', 'garder') };
  assert.equal(b.reponses.D2, 'cote_a_cote');
  b = L.changerReponse(contenu, b, 'P1', 'iphone');
  assert.equal(b.reponses.D2, undefined);
  assert.deepEqual(b.d1, L.d1Vide(contenu));
  const envoi = L.construireEnvoi(contenu, b, 'a'.repeat(32));
  assert.equal(envoi.reponses.D1, undefined);
  assert.equal(envoi.reponses.D2, undefined);
});

test('L2 reste actif sans réponse à L1', () => {
  const b = L.changerReponse(contenu, base(), 'L2', 'ce qui compte');
  const envoi = L.construireEnvoi(contenu, b, 'a'.repeat(32));
  assert.equal(envoi.reponses.L2, 'ce qui compte');
  assert.equal(envoi.reponses.L1, undefined);
});

// Test 5 : mélange et D1.
test('ordre des cartes : permutation des neuf cartes, stable au rechargement du brouillon', () => {
  const b = L.brouillonVide(contenu, 0);
  assert.deepEqual([...b.ordreCartes].sort(), [...contenu.cartes].sort());
  assert.equal(b.ordreCartes.length, 9);
  assert.ok(!b.ordreCartes.includes('C08'));
  const relu = L.lireBrouillon(JSON.stringify(b), contenu);
  assert.deepEqual(relu.ordreCartes, b.ordreCartes);
  assert.equal(L.lireBrouillon(JSON.stringify({ ...b, version: 'autre' }), contenu), null);
  assert.equal(L.lireBrouillon(JSON.stringify({ ...b, ordreCartes: ['C01'] }), contenu), null);
  assert.equal(L.lireBrouillon('pas du json', contenu), null);
  // le mélange n'est pas toujours l'identité
  const ordres = new Set(Array.from({ length: 20 }, () => L.melanger(contenu.cartes).join()));
  assert.ok(ordres.size > 1);
});

test('D1 : comme aujourd’hui produit la réponse seule, le décocher rend le tri', () => {
  let d = L.d1Vide(contenu);
  d = L.d1ChoisirEtat(d, 'mp', 'garder');
  d = L.d1ChoisirEtat(d, 'favoris', 'deplier');
  d = L.d1ChoisirEtat(d, 'reglages', 'ecarter');
  const tri = L.d1Envoi(d);
  assert.equal(tri.comme_aujourdhui, false);
  assert.deepEqual(tri.sections.map((s) => [s.code, s.etat, s.rang]), [
    ['favoris', 'deplier', 1], ['mp', 'garder', 2], ['reglages', 'ecarter', undefined],
  ]);
  d = L.d1Comme(d, true);
  assert.deepEqual(L.d1Envoi(d), { comme_aujourdhui: true });
  d = L.d1Comme(d, false);
  assert.deepEqual(L.d1Envoi(d), tri);
  assert.equal(L.d1Envoi(L.d1Vide(contenu)), undefined);
});

test('D1 : déplacements, rangs contigus, écartées sous les gardées', () => {
  let d = L.d1Vide(contenu);
  for (const c of ['favoris', 'categories', 'mp']) d = L.d1ChoisirEtat(d, c, 'garder');
  d = L.d1ChoisirEtat(d, 'drapeaux', 'ecarter');
  assert.deepEqual(L.d1Affichage(d).slice(0, 3), ['favoris', 'categories', 'mp']);
  assert.equal(L.d1Affichage(d).at(-1), 'drapeaux');
  let r = L.d1Deplacer(d, 'mp', -1);
  assert.deepEqual([r.position, r.total], [2, 3]);
  assert.deepEqual(L.d1Groupes(r.d1).gardees, ['favoris', 'mp', 'categories']);
  r = L.d1Deplacer(r.d1, 'favoris', -1); // déjà premier
  assert.equal(r.position, 1);
  assert.deepEqual(L.d1Groupes(r.d1).gardees, ['favoris', 'mp', 'categories']);
  assert.equal(L.d1Rang(r.d1, 'categories'), 3);
  const envoi = L.d1Envoi(r.d1);
  assert.deepEqual(envoi.sections.filter((s) => s.rang).map((s) => s.rang), [1, 2, 3]);
});

test('envoi : réponses vides absentes, ordre des cartes, durée bornée', () => {
  let b = base();
  b = L.changerReponse(contenu, b, 'G1', '   ');
  b = L.changerReponse(contenu, b, 'P2', 'lit_surtout');
  const e = L.construireEnvoi(contenu, b, 'b'.repeat(32), 1_000_000 + 312_000, '');
  assert.equal(e.duree_s, 312);
  assert.equal(e.site_web, '');
  assert.equal(e.version, contenu.version);
  assert.equal(e.reponses.G1, undefined);
  assert.equal(e.reponses.P2, 'lit_surtout');
  assert.equal(e.reponses.ordre_cartes.length, 9);
  assert.equal(L.construireEnvoi(contenu, b, 'b'.repeat(32), 1_000_000 + 99_999_000).duree_s, 7200);
});

test('jeton : 128 bits en hexadécimal', () => {
  const j = L.genererJeton();
  assert.match(j, /^[0-9a-f]{32}$/);
  assert.notEqual(j, L.genererJeton());
});

test('comparaison vous / la communauté', () => {
  const stats = {
    disponible: true, total: 12, seuil: 10,
    questions: {
      P1: { effectif: 12, codes: { iphone: 50, ipad: 25, duo: 25, plusieurs: 0 } },
      D1: { effectif: 10, comme_aujourdhui: 20, sections: { favoris: { effectif: 8, garder: 50, deplier: 25, ecarter: 25, rang_median: 1.5 } } },
    },
  };
  const l = L.comparer(contenu, stats, { P1: 'ipad', D1: { comme_aujourdhui: false, sections: [{ code: 'favoris', etat: 'deplier', rang: 1 }] } });
  assert.deepEqual(l.map((x) => x.id), ['P1', 'D1']);
  assert.deepEqual(l[0].barres.filter((b) => b.vous).map((b) => b.code), ['ipad']);
  assert.equal(l[1].comme.pct, 20);
  assert.equal(l[1].sections[0].vousEtat, 'deplier');
  assert.equal(l[1].sections[0].rangMedian, 1.5);
  assert.deepEqual(L.comparer(contenu, { disponible: false, seuil: 10 }, {}), []);
});
