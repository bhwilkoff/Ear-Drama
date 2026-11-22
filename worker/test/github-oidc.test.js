// The owner's routes by GitHub Actions OIDC, with no stored token (docs/research/SECRETS-PLAN.md; owner 2026-11-22:
// "I do not want to set or keep track of keys and passwords for this repo."). A token must be GitHub's, for this
// Worker's origin, from this repository on main, from exactly the one workflow the route names, on its events.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, githubClaims, githubToken, installProviderKeys, keys, mint } from "./helpers.js";

const GITHUB_JWKS = "https://token.actions.githubusercontent.com/.well-known/jwks";
let spy;
beforeEach(() => {
  spy = installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

const operator = async (token, extra = {}) => (await call("GET", "/v1/operator/classes?reference=no-such-school", { token, ...extra })).status;
const takedown = async (token, extra = {}) => (await call("GET", "/v1/takedown/cases", { token, ...extra })).status;
const nowS = () => Math.floor(Date.now() / 1000);

describe("GitHub OIDC on the operator route", () => {
  it("operator.yml's token, dispatched on main, is let in", async () => {
    expect(await operator(await githubToken("operator.yml"))).toBe(200);
  });

  const refused = {
    "another repository": { repository: "someone/Ear-Drama" },
    "a recreated namesake (another repository id)": { repository_id: "999" },
    "another branch": { ref: "refs/heads/feature", job_workflow_ref: "bhwilkoff/Ear-Drama/.github/workflows/operator.yml@refs/heads/feature" },
    "a pull request ref": { ref: "refs/pull/7/merge" },
    "another workflow": { job_workflow_ref: "bhwilkoff/Ear-Drama/.github/workflows/pulse.yml@refs/heads/main" },
    "the operator workflow at another ref": { job_workflow_ref: "bhwilkoff/Ear-Drama/.github/workflows/operator.yml@refs/heads/feature" },
    "another repository's reusable workflow": { job_workflow_ref: "someone/tools/.github/workflows/operator.yml@refs/heads/main" },
    "no job_workflow_ref": { job_workflow_ref: undefined },
    "a push event": { event_name: "push" },
    "a pull_request event": { event_name: "pull_request" },
    "a scheduled run (the operator is dispatched by a person)": { event_name: "schedule" },
    "another audience": { aud: "https://eardrama-api.example.workers.dev" },
    "the plan's fixed audience name": { aud: "eardrama-operator" },
    "GitHub's default audience": { aud: "https://github.com/bhwilkoff" },
    "another issuer": { iss: "https://token.actions.example.com" },
    "an expired token": { iat: nowS() - 3600, exp: nowS() - 600 },
  };
  for (const [name, over] of Object.entries(refused)) {
    it(`refuses ${name}`, async () => {
      expect(await operator(await githubToken("operator.yml", over))).toBe(403);
    });
  }

  it("refuses a token signed by any key GitHub did not publish, even with GitHub's key id", async () => {
    expect(await operator(await mint(githubClaims("operator.yml"), { key: keys.forger, header: { kid: "github-test-1" } }))).toBe(403);
  });

  it("refuses an unsigned token and a token with the signature of another", async () => {
    const good = await githubToken("operator.yml");
    const [h, , s] = good.split(".");
    const forged = btoa(JSON.stringify(githubClaims("operator.yml", { repository: "x/y" }))).replace(/=+$/, "");
    expect(await operator(`${h}.${forged}.${s}`)).toBe(403);
    const none = btoa(JSON.stringify({ alg: "none", typ: "JWT" })).replace(/=+$/, "");
    expect(await operator(`${none}.${good.split(".")[1]}.`)).toBe(403);
  });

  it("refuses the take-down workflow's token: one workflow per route", async () => {
    expect(await operator(await githubToken("takedown-check.yml"))).toBe(403);
  });

  it("fetches GitHub's published keys once and caches them", async () => {
    expect(await operator(await githubToken("operator.yml"))).toBe(200);
    expect(await operator(await githubToken("operator.yml"))).toBe(200);
    expect(spy.mock.calls.filter(([u]) => String(u) === GITHUB_JWKS).length).toBe(1);
  });
});

describe("GitHub OIDC on the take-down check's routes", () => {
  it("takedown-check.yml's scheduled and dispatched runs are let in", async () => {
    expect(await takedown(await githubToken("takedown-check.yml", { event_name: "schedule" }))).toBe(200);
    expect(await takedown(await githubToken("takedown-check.yml", { event_name: "workflow_dispatch" }))).toBe(200);
  });

  it("refuses another event, branch, or workflow", async () => {
    expect(await takedown(await githubToken("takedown-check.yml", { event_name: "push" }))).toBe(403);
    expect(await takedown(await githubToken("takedown-check.yml", { ref: "refs/heads/x" }))).toBe(403);
    expect(await takedown(await githubToken("operator.yml"))).toBe(403);
  });

  it("an old stored TAKEDOWN_TOKEN is no longer a key", async () => {
    const old = "an-old-takedown-token-value";
    expect(await takedown(old, { envOverride: { TAKEDOWN_TOKEN: old } })).toBe(403);
    expect(await operator(old, { envOverride: { OPERATOR_TOKEN: old } })).toBe(403);
  });
});

describe("the bench's test keys (the only test seam)", () => {
  const bench = { LOCAL_TEST_JWKS: JSON.stringify({ keys: [keys.forger.publicJwk] }) };
  const benchToken = (aud) => mint(githubClaims("operator.yml", { aud }), { key: keys.forger });

  it("on this machine, a token signed by the bench's key is let in, and GitHub is never asked", async () => {
    vi.restoreAllMocks();
    const none = vi.spyOn(globalThis, "fetch").mockImplementation(async (u) => { throw new Error(`fetched ${u}`); });
    const base = "http://127.0.0.1:8787";
    expect(await operator(await benchToken(base), { envOverride: bench, base })).toBe(200);
    expect(none).not.toHaveBeenCalled();
  });

  it("a Worker carrying them answers no public host: production refuses the test key set", async () => {
    const r = await call("GET", "/v1/operator/classes?reference=x", { token: await benchToken("https://api.eardrama.test"), envOverride: bench });
    expect(r.status).toBe(503);
    expect((await r.json()).error).toBe("test_auth_refused");
  });
});
