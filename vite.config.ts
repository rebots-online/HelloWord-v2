import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';
import { appIdentity } from './scripts/app-identity.mjs';

// Identity (product name) comes ONLY from .env (scripts/app-identity.mjs) —
// the PWA manifest and the document title are naming surfaces like any other.
const ident = appIdentity();

export default defineConfig(({ mode }) => {
  // Storage namespace/scope, frozen into the bundle via define — the
  // decision-22 contract in DOCS/STORAGE-NAMESPACE.md: build-time choice,
  // no runtime discretion. Parity with generate-storage-config.mjs (Rust side).
  const env = loadEnv(mode, process.cwd(), 'VITE_');
  const namespace = env.VITE_APP_NAMESPACE || 'mba.robin.helloword';
  if (!/^[a-z0-9][a-z0-9_.-]{2,63}$/.test(namespace)) {
    throw new Error(`Invalid VITE_APP_NAMESPACE: ${namespace}`);
  }
  const scope = env.VITE_STORAGE_SCOPE === 'app' ? 'app' : 'common';

  return {
    plugins: [
      react(),
      {
        name: 'html-title-from-env',
        transformIndexHtml(html) {
          return html.replace(/<title>[^<]*<\/title>/, `<title>${ident.product}</title>`);
        },
      },
      VitePWA({
        registerType: 'autoUpdate',
        includeAssets: ['icon.png', 'icon-192.png'],
        manifest: {
          name: ident.product,
          short_name: ident.product,
          description: 'Traditional Latin Mass and Divine Office reader',
          theme_color: '#7b1e2b',
          background_color: '#f7f3eb',
          display: 'standalone',
          start_url: '/',
          scope: '/',
          icons: [
            { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
            { src: '/icon.png', sizes: '512x512', type: 'image/png' },
            { src: '/icon.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
          ],
        },
        workbox: {
          globPatterns: ['**/*.{html,js,css,png,wasm}'],
          cleanupOutdatedCaches: true,
          runtimeCaching: [{
            urlPattern: /\/missal\.db$/,
            // The corpus URL is stable across releases, so the CACHE must be the
            // thing that notices a new one. It previously used CacheFirst under a
            // cache name hardcoded to v1.24.37311: CacheFirst never revalidates,
            // the name never changed, so `cleanupOutdatedCaches` never evicted it
            // — a returning user would have kept the v1.24 corpus forever, taking
            // the new UI with the OLD text. That would have silently defeated the
            // English-Ordinary fix, which lives in the corpus and not in the JS.
            //
            // StaleWhileRevalidate serves the cached copy immediately (so the app
            // still opens instantly and works offline) and revalidates in the
            // background against the ETag nginx already sets for this URL — a 304
            // costs nothing, and a changed corpus lands on the next load. The
            // cache name is deliberately version-free: stamping it per release
            // would force every user to re-download 194 MB on every MINOR bump.
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'standroid-missal-corpus',
              expiration: { maxEntries: 1 },
            },
          }],
        },
      }),
    ],
    clearScreen: false,
    server: {
      port: 5173,
      strictPort: true,
      watch: {
        // The vendored corpus snapshot is ~90k flat-text files; watching it
        // exhausts the OS inotify limit (ENOSPC) and it is never a dev input —
        // the app only ever reads the ingested missal.db.
        ignored: ['**/VENDORED/**', '**/src-tauri/**', '**/assets/**'],
      },
    },
    envPrefix: ['VITE_', 'TAURI_'],
    define: {
      __SAM_BUILD_STORAGE__: JSON.stringify({ namespace, scope }),
    },
    build: {
      // Web output lives in a clean, disposable `dist/web/` (gitignored via the
      // `dist-*/` rule) so Tauri's `frontendDist` embeds ONLY the web surface and
      // Vite's outDir-emptying never touches release artifacts.  `dist/` is the
      // durable, versioned, append-only archive (I-0/CC12); `dist/web/` is
      // cleared each build.
      outDir: 'dist/web',
      emptyOutDir: true,
      target: 'es2022',
      sourcemap: false,
      chunkSizeWarningLimit: 1600,
    },
  };
});
