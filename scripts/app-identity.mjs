/**
 * app-identity — the ONE source of the app's identity: APP_ID, APP_SLUG,
 * APP_PRODUCT_NAME, APP_ANDROID_APP_NAME and APP_ANDROID_ACTIVITY_TITLE from the root .env (process env overrides). Every build
 * script, the stamper and Gradle read these; nothing hardcodes them.
 *
 *   node scripts/app-identity.mjs slug|product|id   → prints that value
 *   import { appIdentity } from './app-identity.mjs'
 *
 * Fails closed when a value is missing — an unlabeled build is worse than none.
 */
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

function readDotEnv() {
  const envPath = resolve(ROOT, '.env');
  if (!existsSync(envPath)) return {};
  const out = {};
  for (const line of readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !line.trim().startsWith('#')) out[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
  return out;
}

export function appIdentity() {
  const env = { ...readDotEnv(), ...process.env };
  const pick = (key) => {
    const v = env[key];
    if (!v) throw new Error(`app-identity: ${key} is not set in .env (see .env.example)`);
    return v;
  };
  return {
    id: pick('APP_ID'),
    slug: pick('APP_SLUG'),
    product: pick('APP_PRODUCT_NAME'),
    androidAppName: pick('APP_ANDROID_APP_NAME'),
    activityTitle: pick('APP_ANDROID_ACTIVITY_TITLE'),
  };
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const key = process.argv[2];
  const ident = appIdentity();
  if (!(key in ident)) {
    console.error('usage: app-identity.mjs slug|product|id|androidAppName|activityTitle');
    process.exit(2);
  }
  process.stdout.write(ident[key]);
}
