import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, installProviderKeys, signIn } from "./helpers.js";

beforeEach(() => {
  installProviderKeys();
});
afterEach(() => vi.restoreAllMocks());

const EP = "suspense|1948-03-11";
const EP2 = "gunsmoke|1952-04-26";

async function put(s, body, path = "/v1/sync", method = "PUT") {
  const r = await call(method, path, { token: s.access_token, body });
  expect(r.status, await r.clone().text()).toBe(200);
  return r.json();
}

async function read(s, since = 0) {
  const r = await call("GET", `/v1/sync?since=${since}`, { token: s.access_token });
  expect(r.status).toBe(200);
  return r.json();
}

describe("last write wins", () => {
  it("a newer position replaces an older one, and an older one does not", async () => {
    const s = await signIn("lww-1");
    const t = Date.now() - 10_000;
    await put(s, { device: "iphone", history: [{ episode_id: EP, position: 100, updated_at: t }] });
    const later = await put(s, { device: "pixel", history: [{ episode_id: EP, position: 250, updated_at: t + 5000 }] });
    expect(later.applied.history).toBe(1);
    const stale = await put(s, { device: "mac", history: [{ episode_id: EP, position: 5, updated_at: t + 1000 }] });
    expect(stale.applied.history).toBe(0);
    const { history } = await read(s);
    expect(history).toHaveLength(1);
    expect(history[0]).toMatchObject({ episode_id: EP, position: 250, device: "pixel", updated_at: t + 5000 });
  });

  it("CONTROL: the stale write is refused because it is older, not because writes fail", async () => {
    const s = await signIn("lww-control");
    const t = Date.now() - 10_000;
    await put(s, { history: [{ episode_id: EP, position: 1, updated_at: t }] });
    const r = await put(s, { history: [{ episode_id: EP, position: 2, updated_at: t + 1 }] });
    expect(r.applied.history).toBe(1);
  });

  it("equal stamps settle the same way whichever arrives first", async () => {
    const t = Date.now() - 10_000;
    const a = await signIn("tie-a");
    await put(a, { device: "aaa", history: [{ episode_id: EP, position: 1, updated_at: t }] });
    await put(a, { device: "zzz", history: [{ episode_id: EP, position: 2, updated_at: t }] });
    const b = await signIn("tie-b");
    await put(b, { device: "zzz", history: [{ episode_id: EP, position: 2, updated_at: t }] });
    await put(b, { device: "aaa", history: [{ episode_id: EP, position: 1, updated_at: t }] });
    expect((await read(a)).history[0].position).toBe((await read(b)).history[0].position);
  });

  it("a clock in the future is clamped, so it cannot win forever", async () => {
    const s = await signIn("future-1");
    await put(s, { history: [{ episode_id: EP, position: 1, updated_at: Date.now() + 10 * 365 * 86400_000 }] });
    const { history } = await read(s);
    expect(history[0].updated_at).toBeLessThanOrEqual(Date.now());
    const r = await put(s, { history: [{ episode_id: EP, position: 9, updated_at: Date.now() + 5 }] });
    expect(r.applied.history).toBe(1);
  });

  it("a removal is a tombstone that syncs, and unfollow likewise", async () => {
    const s = await signIn("tomb-1");
    const t = Date.now() - 10_000;
    await put(s, {
      history: [{ episode_id: EP, position: 30, updated_at: t }],
      follows: [{ series_id: "suspense", updated_at: t }],
    });
    await put(s, {
      history: [{ episode_id: EP, deleted: true, updated_at: t + 1 }],
      follows: [{ series_id: "suspense", following: false, updated_at: t + 1 }],
    });
    const out = await read(s);
    expect(out.history[0].deleted).toBe(true);
    expect(out.follows[0].following).toBe(false);
  });

  it("the queue wins or loses whole", async () => {
    const s = await signIn("queue-1");
    const t = Date.now() - 10_000;
    await put(s, { device: "web", queue: { items: [EP, EP2], updated_at: t } });
    const older = await put(s, { device: "tv", queue: { items: [EP2], updated_at: t - 1 } });
    expect(older.applied.queue).toBe(false);
    await put(s, { device: "tv", queue: { items: [EP2, EP], updated_at: t + 1 } });
    expect((await read(s)).queue).toMatchObject({ items: [EP2, EP], device: "tv" });
  });

  it("since= returns only what changed after the last read, even with an old stamp", async () => {
    const s = await signIn("since-1");
    const old = Date.now() - 86400_000;
    await put(s, { history: [{ episode_id: EP, position: 1, updated_at: old }] });
    const first = await read(s);
    await new Promise((r) => setTimeout(r, 5));
    // Another device uploads late, carrying a stamp older than the last read.
    await put(s, { history: [{ episode_id: EP2, position: 7, updated_at: old + 1 }] });
    const next = await read(s, first.server_time + 1);
    expect(next.history.map((h) => h.episode_id)).toEqual([EP2]);
    expect(next.queue).toBeNull();
  });

  it("one account cannot read another's rows", async () => {
    const a = await signIn("iso-a");
    const b = await signIn("iso-b");
    await put(a, { history: [{ episode_id: EP, position: 1, updated_at: Date.now() - 5 }] });
    expect((await read(b)).history).toHaveLength(0);
  });

  it("malformed uploads are refused whole", async () => {
    const s = await signIn("bad-1");
    for (const body of [
      { history: [{ episode_id: EP }] },
      { history: [{ episode_id: "", updated_at: 5 }] },
      { history: [{ episode_id: EP, updated_at: 5, position: -1 }] },
      { history: [{ episode_id: EP, updated_at: 5, position: "NaN" }] },
      { history: "nope" },
      { follows: [{ updated_at: 5 }] },
      { queue: { items: [EP] } },
      { queue: { items: "x", updated_at: 5 } },
      { history: Array.from({ length: 501 }, (_, i) => ({ episode_id: `e${i}`, updated_at: 5 })) },
    ]) {
      const r = await call("PUT", "/v1/sync", { token: s.access_token, body });
      expect(r.status, JSON.stringify(body).slice(0, 60)).toBe(400);
    }
    expect((await call("PUT", "/v1/sync", { token: s.access_token, body: "not json" })).status).toBe(400);
    expect((await read(s)).history).toHaveLength(0);
  });

  it("sync needs a session", async () => {
    expect((await call("GET", "/v1/sync")).status).toBe(401);
    expect((await call("PUT", "/v1/sync", { body: {} })).status).toBe(401);
  });
});

describe("the anonymous merge on first sign-in", () => {
  it("a new account takes the device's history, follows, and queue", async () => {
    const s = await signIn("merge-new");
    const t = Date.now() - 60_000;
    await put(
      s,
      {
        device: "iphone",
        history: [
          { episode_id: EP, position: 600, duration: 1800, updated_at: t },
          { episode_id: EP2, position: 1700, finished: true, updated_at: t + 1 },
        ],
        follows: [{ series_id: "suspense", updated_at: t }],
        queue: { items: [EP2], updated_at: t },
      },
      "/v1/sync/merge",
      "POST",
    );
    const out = await read(s);
    expect(out.history).toHaveLength(2);
    expect(out.follows).toHaveLength(1);
    expect(out.queue.items).toEqual([EP2]);
  });

  it("into an existing account: newer rows win per episode, and queues are joined, not replaced", async () => {
    const s = await signIn("merge-existing");
    const t = Date.now() - 60_000;
    await put(s, {
      device: "web",
      history: [
        { episode_id: EP, position: 900, updated_at: t + 10 },
        { episode_id: EP2, position: 100, updated_at: t },
      ],
      queue: { items: ["a|1", "b|2"], updated_at: t + 50 },
    });
    // The phone listened signed-out: EP older than the account's, EP2 newer.
    const merged = await put(
      s,
      {
        device: "iphone",
        history: [
          { episode_id: EP, position: 30, updated_at: t + 1 },
          { episode_id: EP2, position: 1200, updated_at: t + 20 },
          { episode_id: "new|3", position: 5, updated_at: t + 2 },
        ],
        queue: { items: ["b|2", "c|3"], updated_at: t },
      },
      "/v1/sync/merge",
      "POST",
    );
    expect(merged.applied.history).toBe(2);
    const out = await read(s);
    const by = Object.fromEntries(out.history.map((h) => [h.episode_id, h.position]));
    expect(by).toEqual({ [EP]: 900, [EP2]: 1200, "new|3": 5 });
    expect(out.queue.items).toEqual(["a|1", "b|2", "c|3"]);
  });

  it("CONTROL: a plain PUT with the same older queue would have lost it", async () => {
    const s = await signIn("merge-control");
    const t = Date.now() - 60_000;
    await put(s, { queue: { items: ["a|1"], updated_at: t + 50 } });
    const r = await put(s, { queue: { items: ["c|3"], updated_at: t } });
    expect(r.applied.queue).toBe(false);
    expect((await read(s)).queue.items).toEqual(["a|1"]);
  });
});
