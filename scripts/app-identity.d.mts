/**
 * TypeScript declarations for app-identity.mjs.
 *
 * Hand-authored declaration companion (precedent: release-state.d.mts) so
 * tsc -b — which includes vite.config.ts — can import the identity source
 * without allowJs.
 */
export interface AppIdentity {
  /** Play package identifier, e.g. mba.robin.helloword. */
  id: string;
  /** Artifact-naming slug. */
  slug: string;
  /** Display product name (must satisfy Tauri's productName charset). */
  product: string;
  /** Android launcher label. */
  androidAppName: string;
  /** Android main-activity title. */
  activityTitle: string;
}
export declare function appIdentity(): AppIdentity;
