// YDS Beauty : garde l'application sur l'appareil pour l'ouvrir sans internet.
// Le numéro de version du cache est remplacé à chaque mise en ligne.
// - Fichiers de l'application : internet d'abord (toujours la dernière version),
//   sinon la copie gardée sur l'appareil.
// - Polices d'écriture : copie gardée d'abord.
// - Données (Supabase, PowerSync) : jamais gardées ici, l'application s'en occupe.
const CACHE = 'yds-beauty-v1';
const POLICES = ['fonts.googleapis.com', 'fonts.gstatic.com'];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const nom of await caches.keys()) if (nom !== CACHE) await caches.delete(nom);
    await self.clients.claim();
  })());
});

async function reseauDabord(requete) {
  const cache = await caches.open(CACHE);
  try {
    const reponse = await fetch(requete);
    if (reponse.ok) cache.put(requete, reponse.clone());
    return reponse;
  } catch (err) {
    const copie = await cache.match(requete, { ignoreSearch: requete.mode === 'navigate' });
    if (copie) return copie;
    if (requete.mode === 'navigate') {
      const accueil = await cache.match(self.registration.scope);
      if (accueil) return accueil;
    }
    throw err;
  }
}

async function cacheDabord(requete) {
  const cache = await caches.open(CACHE);
  const copie = await cache.match(requete);
  if (copie) return copie;
  const reponse = await fetch(requete);
  if (reponse.ok || reponse.type === 'opaque') cache.put(requete, reponse.clone());
  return reponse;
}

self.addEventListener('fetch', (e) => {
  const requete = e.request;
  if (requete.method !== 'GET') return;
  const url = new URL(requete.url);
  if (url.origin === self.location.origin) {
    e.respondWith(reseauDabord(requete));
  } else if (POLICES.includes(url.hostname)) {
    e.respondWith(cacheDabord(requete));
  }
});
