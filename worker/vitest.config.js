import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// Runs inside workerd (Miniflare) against a local D1 built from migrations/.
// Nothing here reaches Cloudflare. The audiences and secret are test values.
export default defineConfig(async () => {
  const migrations = await readD1Migrations(path.join(import.meta.dirname, "migrations"));
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.toml" },
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: migrations,
            SESSION_SECRET: "test-only-session-secret-0123456789abcdef",
            APPLE_AUDIENCES: "app.eardrama.test,web.eardrama.test",
            GOOGLE_AUDIENCES: "google-client.test",
          },
        },
      }),
    ],
    // 5 s, the default, failed passing tests on a Mac under load (2026-11-15, 2026-11-24).
    test: { setupFiles: ["./test/apply-migrations.js"], testTimeout: 30_000, hookTimeout: 30_000 },
  };
});
