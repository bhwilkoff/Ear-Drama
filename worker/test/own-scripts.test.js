// Own scripts on the server (Decision 088.3 and 088.4; R4 §3.3, §3.4, §3.5, §7.7). Owner, 2026-11-24: "Yes, a
// shared script can be kept on our server." Made once, sent once, read only by the production's own people, gone on
// every path the production goes, removable by the owner, and never published.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { call, env, githubToken, installProviderKeys, ownerOp, signIn } from "./helpers.js";
import { claimByInvite, consent, createProduction, invite, newTakeId, record, upload } from "./plays-helpers.js";
import { runArchive } from "../src/plays-archive.js";
import { isPublishable, madeFrom } from "../src/plays-castable.js";
import { nameRefusal, wordsRefusal } from "../src/plays-names.js";
import { sweepPlays } from "../src/plays.js";
import { ACCOUNT_IDLE_MS, NOTICE_MS, sweepRetention } from "../src/plays-retention.js";
import * as own from "../src/plays-own.js";
import golden from "../../catalog/tests/golden/own_script_ops.json";
import coreSource from "../../js/own-core.js?raw";

const KEYS = { IA_S3_ACCESS_KEY: "TESTIAACCESSown", IA_S3_SECRET_KEY: "TESTIASECRETown" };
const NO_LIMIT = { USER_LIMITER: undefined, PLAY_JOIN_LIMITER: undefined, READ_CREATE_LIMITER: undefined };
const NO_DO = { ...NO_LIMIT, READ_ROOMS: undefined };
const NEVER = { limit: async () => ({ success: false }) };

let fetched;
beforeEach(() => {
  fetched = [];
  installProviderKeys({
    extra: async (url) => {
      if (url.includes("eardrama.org") || url.includes("archive.org")) {
        fetched.push(url);
        return new Response(null, { status: 404 });
      }
      return null;
    },
  });
  vi.spyOn(console, "log").mockImplementation(() => {});
});
afterEach(() => vi.restoreAllMocks());

let n = 0;
const person = (label) => signIn(`own-${label}-${n++}`);

const encoder = new TextEncoder();
/** js/own-core.js canonical(), for the values a line holds: sorted keys, no spaces. */
const canonical = (v) =>
  Array.isArray(v) ? `[${v.map(canonical).join(",")}]` : v && typeof v === "object" ? `{${Object.keys(v).sort().map((k) => `${JSON.stringify(k)}:${canonical(v[k])}`).join(",")}}` : JSON.stringify(v);
const hex12 = async (bytes) => [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 12);

const LINES = (word) => [
  { id: "L0001", kind: "direction", source: "A kitchen." },
  { id: "L0002", kind: "speech", role: "ANNA", parts: [{ say: `Is it ${word}? — “Yes.”` }] },
  { id: "L0003", kind: "speech", role: "BEN", parts: [{ say: "Only the pipes." }] },
  { id: "L0003a", kind: "sound", source: "SOUND: A door." },
];

/** A script nobody else has: `bytes` is what a client hashes and sends. */
async function scriptOf(lines = LINES(`word ${n++}`), over = {}) {
  const bytes = encoder.encode(canonical(lines));
  return {
    id: `own-${crypto.randomUUID()}`,
    revision: await hex12(bytes),
    title: "The Pipes",
    bytes,
    cast: lines.map((l) => ({ id: l.id, part: l.kind === "speech" ? `role:${l.role}` : l.kind === "direction" ? "directions" : "sound" })),
    ...over,
  };
}
const bodyOf = (s, over = {}) => ({ own: true, title: s.title, script_id: s.id, script_revision: s.revision, cast: s.cast, ...over });
const post = (who, body, opts = {}) => call("POST", "/v1/plays/productions", { token: who.access_token, body, envOverride: NO_LIMIT, ...opts });
const put = (who, pid, bytes, { headers = {}, envOverride = NO_LIMIT } = {}) =>
  call("PUT", `/v1/plays/productions/${pid}/script`, { token: who.access_token, body: bytes, envOverride, headers: { "content-length": String(bytes.length), ...headers } });
const get = (who, pid, opts = {}) => call("GET", `/v1/plays/productions/${pid}/script`, { token: who.access_token, envOverride: NO_LIMIT, ...opts });
const errorOf = async (r) => [r.status, (await r.json()).error];
const made = async (r) => {
  expect(r.status, await r.clone().text()).toBe(201);
  return r.json();
};

/** Pat's own script, its text here. */
async function shared(label, over = {}, lines) {
  const pat = await person(`${label}-pat`);
  const s = await scriptOf(lines);
  const p = await made(await post(pat, bodyOf(s, { display_name: "Pat", ...over })));
  expect((await put(pat, p.id, s.bytes)).status).toBe(204);
  return { pat, s, p };
}

/** And Zoë in it, by an invite that is still live. */
async function sharedWithZoe(label, over = {}) {
  const x = await shared(label, over);
  const inv = await invite(x.pat, x.p.id);
  const zoe = await person(`${label}-zoe`);
  expect((await claimByInvite(zoe, inv.token, "role:ANNA", { display_name: "Zoë" })).status).toBe(200);
  return { ...x, inv, zoe };
}

async function klass(label, { under13 = false } = {}) {
  const teacher = await person(`${label}-teacher`);
  const c = await (await call("POST", "/v1/plays/classes", { token: teacher.access_token, body: { name: "Room 9", under13 } })).json();
  const seats = (await (await call("POST", `/v1/plays/classes/${c.id}/seats`, { token: teacher.access_token, body: { labels: ["Lucy", "Tom"] } })).json()).seats;
  const seat = await made(await call("POST", "/v1/plays/seat/claim", { body: { code: c.code, seat: seats[0].id } }));
  return { teacher, c, seats, key: seat.seat_key };
}
async function classScript(label, opts = {}) {
  const k = await klass(label, opts);
  const s = await scriptOf();
  const p = await made(await call("POST", `/v1/plays/classes/${k.c.id}/productions`, { token: k.teacher.access_token, body: bodyOf(s, { display_name: "Ms. Ortiz" }) }));
  expect((await put(k.teacher, p.id, s.bytes)).status).toBe(204);
  return { ...k, s, p };
}
const seatCall = (method, path, key, extra = {}) => call(method, `/v1/plays/seat${path}`, { headers: { "x-seat-key": key, ...extra.headers }, body: extra.body });
const room = (body, { token, envOverride = NO_LIMIT } = {}) => call("POST", "/v1/read", { body, token, envOverride });
const roomScript = (code, key, envOverride = NO_LIMIT) => call("GET", `/v1/read/${code}/script`, { envOverride, headers: key ? { "x-read-key": key } : {} });
const openView = (token, path = "") => call("GET", `/v1/plays/open/invite${path}`, { headers: { "x-invite": token } });

const rowOf = (pid) => env.DB.prepare("SELECT * FROM play_scripts WHERE production_id = ?1").bind(pid).first();
const expectTotal = async () => {
  const { n: sum } = await env.DB.prepare("SELECT COALESCE(SUM(bytes), 0) AS n FROM play_scripts").first();
  expect((await env.DB.prepare("SELECT bytes FROM play_script_total").first()).bytes).toBe(sum);
  return sum;
};
const operator = async (path, method = "DELETE") => call(method, `/v1/operator/scripts${path}`, { token: await githubToken("operator.yml") });

describe("making a production of an own script", () => {
  it("takes the director's title and cast sheet, asks nothing of the library, and can never publish", async () => {
    const pat = await person("make");
    const s = await scriptOf();
    const p = await made(await post(pat, bodyOf(s, { title: "  The Pipes  ", episode_id: "suspense|1949-01-06", rights: { bucket: "script_source_cleared" }, publishable: true })));
    expect(p).toMatchObject({ scriptID: s.id, scriptRevision: s.revision, title: "The Pipes", publishable: false, own_script: { state: "owed", by: pat.user_id, episode_id: "suspense|1949-01-06" } });
    expect(fetched).toEqual([]);
    expect((await env.DB.prepare("SELECT script_row FROM play_productions WHERE id = ?1").bind(p.id).first()).script_row).toBeNull();
  });

  it("CONTROL: a catalog play's record says it may publish, and carries no own script", async () => {
    const p = await createProduction(await person("catalog"));
    expect(p.publishable).toBe(true);
    expect(p.own_script).toBeUndefined();
  });

  it("an own id without own, and a catalog id with it, make nothing", async () => {
    const pat = await person("ids");
    const s = await scriptOf();
    expect(await errorOf(await post(pat, bodyOf(s, { own: undefined })))).toEqual([422, "not_castable"]);
    expect(await errorOf(await post(pat, bodyOf(s, { own: "true" })))).toEqual([422, "not_castable"]);
    for (const id of ["gut-3012", "own-x", `own-${"A".repeat(8)}-5a7d-4e90-8b21-0c9d7e6f5a43`, `${s.id}/..`, 7, undefined]) {
      expect(await errorOf(await post(pat, bodyOf(s, { script_id: id }))), String(id)).toEqual([422, "bad_script_id"]);
    }
    for (const r of ["0BEA09F62D19", "0bea09f62d1", `${s.revision}0`, undefined]) {
      expect(await errorOf(await post(pat, bodyOf(s, { script_revision: r }))), String(r)).toEqual([422, "bad_script_id"]);
    }
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM play_productions WHERE user_id = ?1").bind(pat.user_id).first()).n).toBe(0);
  });

  it("refuses a title or a part that a stranger should not meet in an invite, and names which", async () => {
    const pat = await person("words");
    const s = await scriptOf();
    for (const title of ["", "   ", undefined, 7, "x".repeat(301), "The FUCKING Pipes", "f u c k it", "Come to www.example.com", "Pipes\u202e"]) {
      const r = await post(pat, bodyOf(s, { title }));
      expect(r.status, String(title)).toBe(422);
      expect(await r.json()).toEqual({ error: "bad_name", detail: "title" });
    }
    for (const role of ["SHIT", "x".repeat(41), " ", "ANNA\u200b"]) {
      const cast = s.cast.map((c) => (c.part === "role:BEN" ? { ...c, part: `role:${role}` } : c));
      const r = await post(pat, bodyOf(s, { cast }));
      expect(r.status, role).toBe(422);
      expect(await r.json()).toEqual({ error: "bad_name", detail: `role:${role}` });
    }
    const ok = await post(pat, bodyOf(s, { title: `The Grapes of Wrath ${"x".repeat(279)}`.slice(0, 300), cast: s.cast.map((c) => (c.part === "role:BEN" ? { ...c, part: "role:STAFF OFFICER" } : c)) }));
    expect(ok.status, await ok.clone().text()).toBe(201);
  });

  it("the gate for titles judges whole words; the gate for people is unchanged", () => {
    for (const t of ["The Grapes of Wrath", "Was Hitched", "The Rape of Lucrece", "Who Killed Cock Robin?", "The Ass and the Lapdog", "The Official Story", "Othello, the Moor of Venice", "An Ear Drama", "Essex", "A B C", "Scunthorpe", "The Nazi Spy"]) {
      expect(wordsRefusal(t, 300), t).toBeNull();
    }
    for (const t of ["Shits", "sh1t", "$hit", "Bitchy", "B I T C H", "Sexing", "go kill yourself", "Fück", "porn", "don't fuck"]) expect(wordsRefusal(t, 300), t).toBe("name_not_allowed");
    expect(wordsRefusal("eardrama.org", 300)).toBe("name_has_link");
    expect(nameRefusal("Staff")).toBe("name_reserved");
    expect(nameRefusal("Grape")).toBe("name_not_allowed");
  });

  it("refuses a cast sheet no own script has: 6,001 lines, other line ids, no part, 201 parts, a bad episode", async () => {
    const pat = await person("sheet");
    const s = await scriptOf();
    const ids = (k) => Array.from({ length: k }, (_, i) => `L${String(Math.floor(i / 2) + 1).padStart(4, "0")}${i % 2 ? "a" : ""}`);
    const many = (k) => ids(k).map((id) => ({ id, part: "role:ANNA" }));
    expect(await errorOf(await post(pat, bodyOf(s, { cast: many(6001) })))).toEqual([413, "script_too_long"]);
    expect((await post(pat, bodyOf(s, { cast: many(6000) }))).status).toBe(201);
    expect(await errorOf(await post(pat, bodyOf(s, { cast: [{ id: "come-to-my-site", part: "role:ANNA" }] })))).toEqual([400, "bad_request"]);
    expect(await errorOf(await post(pat, bodyOf(s, { cast: [{ id: "L0001", part: "directions" }] })))).toEqual([422, "bad_request"]);
    const parts = (k) => ids(k).map((id, i) => ({ id, part: `role:V${i}` }));
    expect(await errorOf(await post(pat, bodyOf(s, { cast: parts(201) })))).toEqual([422, "bad_request"]);
    expect((await post(pat, bodyOf(s, { cast: parts(200) }))).status).toBe(201);
    for (const episode_id of ["", 7, "a\nb", "x".repeat(201)]) expect(await errorOf(await post(pat, bodyOf(s, { episode_id }))), String(episode_id)).toEqual([400, "bad_request"]);
  });

  it("20 an account, a class's counted to its teacher; another account's are its own", async () => {
    const { teacher, c, p, s } = await classScript("cap");
    for (let i = 0; i < 18; i++) expect((await post(teacher, bodyOf(s))).status, String(i)).toBe(201);
    expect((await post(teacher, bodyOf(s))).status).toBe(201);
    const twentyFirst = await post(teacher, bodyOf(s));
    expect(await errorOf(twentyFirst)).toEqual([409, "too_many_scripts"]);
    expect(await errorOf(await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: teacher.access_token, body: bodyOf(s) }))).toEqual([409, "too_many_scripts"]);
    expect((await post(await person("cap-other"), bodyOf(s))).status).toBe(201);
    // A catalog play is not counted, and a deleted one makes room.
    await createProduction(teacher);
    expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: teacher.access_token })).status).toBe(204);
    expect((await post(teacher, bodyOf(s))).status).toBe(201);
  });

  it("the caps and id shapes are js/own-core.js's", () => {
    const of = (name) => new RegExp(`const ${name} = (.+);`).exec(coreSource)[1];
    expect(Number(of("MAX_BYTES"))).toBe(own.MAX_SCRIPT_BYTES);
    expect(Number(of("MAX_LINES"))).toBe(own.MAX_OWN_LINES);
    expect(Number(of("MAX_TITLE"))).toBe(own.MAX_TITLE);
    expect(Number(of("MAX_PART_NAME"))).toBe(own.MAX_PART_NAME);
    expect(of("OWN_ID")).toBe(String(own.OWN_ID));
    expect(of("LINE_ID")).toBe(String(own.LINE_ID));
  });

  it("needs an account", async () => {
    expect((await call("POST", "/v1/plays/productions", { body: bodyOf(await scriptOf()) })).status).toBe(401);
  });
});

describe("sending the text", () => {
  it("the golden scripts every client stack hashes arrive whole", async () => {
    const pat = await person("golden");
    expect(golden.scripts.length).toBeGreaterThan(0);
    for (const { want } of golden.scripts) {
      const s = await scriptOf(want.lines, { id: want.id, title: want.title });
      expect(s.revision).toBe(want.revision);
      const p = await made(await post(pat, bodyOf(s)));
      expect((await put(pat, p.id, s.bytes)).status).toBe(204);
      expect(new Uint8Array(await (await get(pat, p.id)).arrayBuffer())).toEqual(s.bytes);
    }
  });

  it("once, by the director, and only the text of the production's revision", async () => {
    const { zoe, s, p, pat } = await sharedWithZoe("once");
    const owed = await made(await post(pat, bodyOf(s)));
    const other = await scriptOf();
    expect(await errorOf(await put(pat, owed.id, other.bytes))).toEqual([422, "revision_mismatch"]);
    expect((await rowOf(owed.id)).body).toBeNull();
    expect(await errorOf(await put(zoe, p.id, s.bytes))).toEqual([403, "director_only"]);
    expect(await errorOf(await put(await person("once-out"), p.id, s.bytes))).toEqual([404, "not_found"]);
    expect(await errorOf(await put(pat, p.id, s.bytes))).toEqual([409, "already_there"]);
    expect(await errorOf(await put(pat, p.id, other.bytes))).toEqual([409, "already_there"]);
    expect((await record(pat, p.id)).own_script).toEqual({ state: "kept", by: pat.user_id, episode_id: null });
    const cat = await createProduction(pat);
    expect(await errorOf(await put(pat, cat.id, s.bytes))).toEqual([404, "no_script"]);
    await expectTotal();
  });

  it("two at once keep one, and count it once", async () => {
    const pat = await person("race");
    const s = await scriptOf();
    const p = await made(await post(pat, bodyOf(s)));
    const before = await expectTotal();
    const both = (await Promise.all([put(pat, p.id, s.bytes), put(pat, p.id, s.bytes)])).map((r) => r.status).sort();
    expect(both).toEqual([204, 409]);
    expect(await expectTotal()).toBe(before + s.bytes.length);
  });

  it("at most 400 KB: judged by its declared length, before a byte is read", async () => {
    const pat = await person("long");
    const pad = (k) => [{ id: "L0001", kind: "speech", role: "ANNA", parts: [{ say: "x".repeat(k) }] }];
    const empty = canonical(pad(0)).length;
    const full = await scriptOf(pad(own.MAX_SCRIPT_BYTES - empty));
    expect(full.bytes.length).toBe(400000);
    const p = await made(await post(pat, bodyOf(full)));
    expect((await put(pat, p.id, full.bytes)).status).toBe(204);
    const over = await scriptOf(pad(own.MAX_SCRIPT_BYTES - empty + 1));
    const q = await made(await post(pat, bodyOf(over)));
    expect(await errorOf(await put(pat, q.id, over.bytes))).toEqual([413, "script_too_long"]);
    expect(await errorOf(await put(pat, q.id, encoder.encode("[]"), { headers: { "content-length": "400001" } }))).toEqual([413, "script_too_long"]);
  });

  it("needs a Content-Length that is the body's", async () => {
    const pat = await person("length");
    const s = await scriptOf();
    const p = await made(await post(pat, bodyOf(s)));
    const bare = await call("PUT", `/v1/plays/productions/${p.id}/script`, { token: pat.access_token, body: s.bytes });
    expect(await errorOf(bare)).toEqual([411, "length_required"]);
    for (const bad of ["-5", "1e3", "ten", ""]) expect(await errorOf(await put(pat, p.id, s.bytes, { headers: { "content-length": bad } })), bad).toEqual([411, "length_required"]);
    for (const d of [-1, 1]) expect(await errorOf(await put(pat, p.id, s.bytes, { headers: { "content-length": String(s.bytes.length + d) } }))).toEqual([400, "bad_request"]);
    expect((await rowOf(p.id)).bytes).toBe(0);
  });

  it("is kept byte for byte or not at all: not UTF-8, or with a raw control, is refused though its digest matches", async () => {
    const pat = await person("bytes");
    const base = await scriptOf();
    const bom = new Uint8Array([0xef, 0xbb, 0xbf, ...base.bytes]);
    const withBom = { ...base, id: `own-${crypto.randomUUID()}`, bytes: bom, revision: await hex12(bom) };
    const b = await made(await post(pat, bodyOf(withBom)));
    expect((await put(pat, b.id, bom)).status).toBe(204);
    expect(new Uint8Array(await (await get(pat, b.id)).arrayBuffer())).toEqual(bom);
    for (const raw of [new Uint8Array([0x5b, 0xff, 0x5d]), encoder.encode('["a\u0000b"]'), encoder.encode('["a\nb"]')]) {
      const s = { ...base, revision: await hex12(raw) };
      const p = await made(await post(pat, bodyOf(s)));
      expect(await errorOf(await put(pat, p.id, raw))).toEqual([400, "bad_request"]);
      expect((await rowOf(p.id)).body).toBeNull();
    }
  });

  it("stops at 250 MB of everyone's text, and opens again when some goes", async () => {
    const pat = await person("full");
    const s = await scriptOf();
    const p = await made(await post(pat, bodyOf(s)));
    const kept = await expectTotal();
    const room = (left) => env.DB.prepare("UPDATE play_script_total SET bytes = ?1").bind(own.SCRIPTS_CAP_BYTES - left).run();
    try {
      await room(s.bytes.length - 1);
      expect(await errorOf(await put(pat, p.id, s.bytes))).toEqual([503, "scripts_full"]);
      expect((await rowOf(p.id)).bytes).toBe(0);
      // Said before a byte is read: a body that is not its length is not even looked at.
      expect(await errorOf(await put(pat, p.id, s.bytes.slice(1), { headers: { "content-length": String(s.bytes.length) } }))).toEqual([503, "scripts_full"]);
      // Filled between the look and the write: the write itself is the arbiter.
      await room(s.bytes.length);
      const full = { prepare: (sql) => (sql.startsWith("UPDATE play_scripts") ? { bind: (...v) => ({ run: async () => { await room(0); return env.DB.prepare(sql).bind(...v).run(); } }) } : env.DB.prepare(sql)), batch: (x) => env.DB.batch(x) };
      expect(await errorOf(await put(pat, p.id, s.bytes, { envOverride: { ...NO_LIMIT, DB: full } }))).toEqual([503, "scripts_full"]);
      await room(s.bytes.length);
      expect((await put(pat, p.id, s.bytes)).status).toBe(204);
    } finally {
      await env.DB.prepare("UPDATE play_script_total SET bytes = ?1").bind(kept + (await rowOf(p.id)).bytes).run();
    }
    await expectTotal();
  });

  it("costs a handful of rows, and reading it writes none", async () => {
    const meter = { read: 0, written: 0, queries: 0 };
    const note = (r) => ((meter.read += r.meta.rows_read), (meter.written += r.meta.rows_written), (meter.queries += 1), r);
    const raw = new Map();
    const wrap = (st) => {
      const w = {
        bind: (...v) => wrap(st.bind(...v)),
        run: async () => note(await st.run()),
        all: async () => note(await st.all()),
        first: async () => note(await st.all()).results[0] ?? null,
      };
      raw.set(w, st);
      return w;
    };
    const DB = { prepare: (sql) => wrap(env.DB.prepare(sql)), batch: async (list) => (await env.DB.batch(list.map((w) => raw.get(w)))).map(note) };
    const opts = { envOverride: { ...NO_LIMIT, DB } };
    const took = async (fn) => {
      Object.assign(meter, { read: 0, written: 0, queries: 0 });
      const out = await fn();
      return [out, { ...meter }];
    };
    const pat = await person("rows");
    const s = await scriptOf();
    const [r, a] = await took(() => post(pat, bodyOf(s), opts));
    const p = await made(r);
    const [w, b] = await took(() => put(pat, p.id, s.bytes, opts));
    expect(w.status).toBe(204);
    const [g, c] = await took(() => get(pat, p.id, opts));
    expect(g.status).toBe(200);
    await g.text();
    // 7 are any shared production's and its member row's; the script's own row is 3 (with its two indexes).
    expect(a.written).toBe(10);
    // The text and the total.
    expect(b.written).toBe(2);
    expect(c.written).toBe(0);
    // The total is one row, however many scripts are kept.
    expect(b.read).toBeLessThanOrEqual(12);
    expect(c.read).toBeLessThanOrEqual(8);
  });
});

describe("reading it: the production's people, and nobody else", () => {
  it("a member reads the lines as they were sent, with what a device needs beside them, and no cache keeps them", async () => {
    const { zoe, s, p } = await sharedWithZoe("member", { title: "Café — “Noir”", episode_id: "suspense|1949-01-06" });
    const r = await get(zoe, p.id, { origin: "https://eardrama.org" });
    expect(r.status).toBe(200);
    expect(new Uint8Array(await r.clone().arrayBuffer())).toEqual(s.bytes);
    expect(r.headers.get("cache-control")).toBe("private, no-store");
    expect(r.headers.get("etag")).toBe(`"${s.revision}"`);
    expect(r.headers.get("content-type")).toBe("application/json; charset=utf-8");
    expect(r.headers.get("x-content-type-options")).toBe("nosniff");
    expect(r.headers.get("x-script")).toMatch(/^[\x20-\x7e]+$/);
    expect(JSON.parse(r.headers.get("x-script"))).toEqual({ id: s.id, revision: s.revision, title: "Café — “Noir”", episode_id: "suspense|1949-01-06" });
    for (const h of ["x-script", "etag"]) expect(r.headers.get("access-control-expose-headers")).toContain(h);
  });

  it("a device that has this revision is told so, after the same checks", async () => {
    const { pat, s, p } = await shared("etag");
    for (const tag of [`"${s.revision}"`, `W/"${s.revision}"`, `"x", "${s.revision}"`]) {
      const r = await get(pat, p.id, { headers: { "if-none-match": tag } });
      expect([r.status, await r.text()]).toEqual([304, ""]);
    }
    expect((await get(pat, p.id, { headers: { "if-none-match": '"000000000000"' } })).status).toBe(200);
    expect((await get(await person("etag-out"), p.id, { headers: { "if-none-match": `"${s.revision}"` } })).status).toBe(404);
    expect((await operator(`/${p.id}`)).status).toBe(204);
    expect((await get(pat, p.id, { headers: { "if-none-match": `"${s.revision}"` } })).status).toBe(410);
  });

  it("404 no_script while it is owed, and for a catalog play", async () => {
    const pat = await person("owed");
    const p = await made(await post(pat, bodyOf(await scriptOf())));
    expect(await errorOf(await get(pat, p.id))).toEqual([404, "no_script"]);
    expect(await errorOf(await get(pat, (await createProduction(pat)).id))).toEqual([404, "no_script"]);
  });

  it("a stranger, a signed-out device, and a wrong, revoked or expired token get nothing", async () => {
    const { pat, s, p } = await shared("stranger");
    expect(await errorOf(await get(await person("stranger-out"), p.id))).toEqual([404, "not_found"]);
    expect((await call("GET", `/v1/plays/productions/${p.id}/script`)).status).toBe(401);
    expect(await errorOf(await openView("A".repeat(43), "/script"))).toEqual([404, "invite_not_found"]);
    expect((await call("GET", "/v1/plays/open/invite/script")).status).toBe(404);
    const a = await invite(pat, p.id);
    const r = await openView(a.token, "/script");
    expect(r.status).toBe(200);
    expect(r.headers.get("cache-control")).toBe("private, no-store");
    expect(new Uint8Array(await r.arrayBuffer())).toEqual(s.bytes);
    expect((await openView(a.token, "/script/x")).status).toBe(404);
    expect((await call("DELETE", `/v1/plays/productions/${p.id}/invites/${a.id}`, { token: pat.access_token })).status).toBe(204);
    expect(await errorOf(await openView(a.token, "/script"))).toEqual([410, "invite_gone"]);
    const b = await invite(pat, p.id);
    await env.DB.prepare("UPDATE play_invites SET expires_at = 1 WHERE id = ?1").bind(b.id).run();
    expect(await errorOf(await openView(b.token, "/script"))).toEqual([410, "invite_gone"]);
    expect((await call("GET", "/v1/plays/open/invite/script", { headers: { "x-invite": a.token }, envOverride: { OPEN_READ_LIMITER: NEVER } })).status).toBe(429);
  });

  it("a class's seats read it by seat key; another class's, a released key, and no key do not", async () => {
    const { teacher, c, seats, key, s, p } = await classScript("seat");
    const r = await seatCall("GET", `/productions/${p.id}/script`, key);
    expect(new Uint8Array(await r.arrayBuffer())).toEqual(s.bytes);
    expect((await (await seatCall("GET", "", key)).json()).productions[0].own_script).toEqual({ state: "kept", episode_id: null });
    const other = await klass("seat-other");
    expect((await seatCall("GET", `/productions/${p.id}/script`, other.key)).status).toBe(404);
    expect((await call("GET", `/v1/plays/seat/productions/${p.id}/script`)).status).toBe(401);
    // An account that joined the class is not in its production.
    const joined = await person("seat-joined");
    expect((await call("POST", "/v1/plays/classes/join", { token: joined.access_token, body: { code: c.code } })).status).toBe(200);
    expect((await get(joined, p.id)).status).toBe(404);
    expect((await call("POST", `/v1/plays/classes/${c.id}/seats/${seats[0].id}/release`, { token: teacher.access_token })).status).toBe(204);
    expect((await seatCall("GET", `/productions/${p.id}/script`, key)).status).toBe(401);
  });

  it("the open invite says the play is somebody's own, with no account id", async () => {
    const { p, inv, pat, zoe } = await sharedWithZoe("openview", { episode_id: "escape|1950-02-03" });
    const r = await openView(inv.token);
    const v = await r.json();
    expect(v).toMatchObject({ title: "The Pipes", source: null, own_script: { state: "kept", episode_id: "escape|1950-02-03" } });
    expect(JSON.stringify(v)).not.toContain(pat.user_id);
    expect(JSON.stringify(v)).not.toContain(zoe.user_id);
    expect(v.id).toBe(p.id);
  });

  it("no route lists, searches, or finds one by its script id, and only these four read one", async () => {
    const { s, p } = await shared("list");
    const out = await person("list-out");
    expect((await (await call("GET", "/v1/plays/productions", { token: out.access_token })).json()).productions).toEqual([]);
    for (const path of ["/v1/plays/scripts", `/v1/plays/scripts/${s.id}`, `/v1/plays/productions/${s.id}/script`, `/v1/plays/scripts?q=Pipes`]) {
      expect((await call("GET", path, { token: out.access_token })).status, path).toBe(404);
    }
    for (const path of [`/v1/plays/open/${s.id}`, `/v1/plays/finished/${p.id}`]) expect((await call("GET", path)).status, path).toBe(404);
    expect((await (await call("GET", "/v1/plays/finished?limit=50")).json()).productions.map((x) => x.id)).not.toContain(p.id);
    // The same id claimed by someone else resolves to their production, never to this text.
    const theirs = await made(await post(out, bodyOf(s)));
    expect(await errorOf(await get(out, theirs.id))).toEqual([404, "no_script"]);
  });
});

for (const [label, envOverride] of [["the Durable Object", NO_LIMIT], ["D1 polling", NO_DO]]) {
  describe(`a read room on an own script, over ${label}`, () => {
    const roomBody = (s, over = {}) => ({ script_id: s.id, script_revision: s.revision, cast: s.cast, ...over });

    it("carries the director's production, and its members read the text by their key", async () => {
      const { pat, s, p } = await shared("room");
      const r = await room(roomBody(s, { production_id: p.id }), { token: pat.access_token, envOverride });
      expect(r.status, await r.clone().text()).toBe(200);
      const h = await r.json();
      expect(h).toMatchObject({ script_id: s.id, script_revision: s.revision, production_id: p.id });
      for (const role of ["reader", "screen"]) {
        const m = await (await call("POST", `/v1/read/${h.code}/join`, { body: { role, ...(role === "reader" ? { name: "Ann" } : {}) }, envOverride })).json();
        const t = await roomScript(h.code, m.member_key, envOverride);
        expect(t.status, await t.clone().text()).toBe(200);
        expect(t.headers.get("cache-control")).toBe("private, no-store");
        expect(new Uint8Array(await t.arrayBuffer())).toEqual(s.bytes);
        expect(JSON.parse(t.headers.get("x-script")).title).toBe("The Pipes");
      }
      expect(await errorOf(await roomScript(h.code, "A".repeat(32), envOverride))).toEqual([403, "not_a_member"]);
      expect((await roomScript(h.code, null, envOverride)).status).toBe(403);
      expect((await call("PUT", `/v1/read/${h.code}/script`, { envOverride, headers: { "x-read-key": h.member_key }, body: s.bytes })).status).toBe(405);
    });

    it("a member who left or was put out of the room reads no more", async () => {
      const { pat, s, p } = await shared("leaver");
      const h = await (await room(roomBody(s, { production_id: p.id }), { token: pat.access_token, envOverride })).json();
      const m = await (await call("POST", `/v1/read/${h.code}/join`, { body: { name: "Ann" }, envOverride })).json();
      expect((await roomScript(h.code, m.member_key, envOverride)).status).toBe(200);
      expect((await call("POST", `/v1/read/${h.code}/send`, { body: { type: "leave" }, envOverride, headers: { "x-read-key": m.member_key } })).status).toBe(200);
      expect((await roomScript(h.code, m.member_key, envOverride)).status).toBe(403);
    });

    it("has no anonymous form, none of a stranger's production, and none before the text is there", async () => {
      const { s, p } = await shared("noroom");
      const out = await person("noroom-out");
      expect(await errorOf(await room(roomBody(s), { envOverride }))).toEqual([422, "not_castable"]);
      expect(await errorOf(await room(roomBody(s, { own: true }), { envOverride }))).toEqual([422, "not_castable"]);
      expect((await room(roomBody(s, { production_id: p.id }), { envOverride })).status).toBe(401);
      expect(await errorOf(await room(roomBody(s, { production_id: p.id }), { token: out.access_token, envOverride }))).toEqual([404, "no_such_production"]);
      const owed = await made(await post(out, bodyOf(s)));
      expect(await errorOf(await room(roomBody(s, { production_id: owed.id }), { token: out.access_token, envOverride }))).toEqual([409, "no_script"]);
    });

    it("only at the production's revision, with its cast sheet", async () => {
      const { pat, s, p } = await shared("roomcast");
      const at = (over) => room(roomBody(s, { production_id: p.id, ...over }), { token: pat.access_token, envOverride });
      expect(await errorOf(await at({ script_revision: "000000000000" }))).toEqual([409, "revision_mismatch"]);
      expect(await errorOf(await at({ cast: s.cast.slice(0, 3) }))).toEqual([422, "cast_mismatch"]);
    });

    it("a class's teacher opens one for its production, and its seats read by the room", async () => {
      const { teacher, c, seats, key, s, p } = await classScript("roomclass");
      const open = (over) => room(roomBody(s, { kind: "class", class_id: c.id, ...over }), { token: teacher.access_token, envOverride });
      expect(await errorOf(await open({}))).toEqual([422, "not_castable"]);
      const h = await (await open({ production_id: p.id })).json();
      const m = await (await call("POST", `/v1/read/${h.code}/join`, { body: { seat: seats[0].id, seat_key: key }, envOverride })).json();
      expect((await roomScript(h.code, m.member_key, envOverride)).status).toBe(200);
    });

    it("a room on a catalog play has no text to read", async () => {
      const { createBody } = await import("./plays-helpers.js");
      const { script_id, script_revision, cast } = createBody();
      const h = await (await room({ script_id, script_revision, cast }, { envOverride })).json();
      expect(await errorOf(await roomScript(h.code, h.member_key, envOverride))).toEqual([404, "no_script"]);
      const pat = await person("roomcat");
      const p = await createProduction(pat);
      const q = await (await room({ script_id, script_revision, cast, production_id: p.id }, { token: pat.access_token, envOverride })).json();
      expect(await errorOf(await roomScript(q.code, q.member_key, envOverride))).toEqual([404, "no_script"]);
    });
  });
}

describe("invites wait for the text", () => {
  it("none is made until it is there", async () => {
    const pat = await person("inv");
    const s = await scriptOf();
    const p = await made(await post(pat, bodyOf(s)));
    const ask = () => call("POST", `/v1/plays/productions/${p.id}/invites`, { token: pat.access_token, body: {} });
    expect(await errorOf(await ask())).toEqual([409, "no_script"]);
    expect((await put(pat, p.id, s.bytes)).status).toBe(204);
    expect((await ask()).status).toBe(201);
    expect((await call("POST", `/v1/plays/productions/${(await createProduction(pat)).id}/invites`, { token: pat.access_token, body: {} })).status).toBe(201);
  });
});

describe("a report of the script", () => {
  const report = (who, pid, over = {}) => call("POST", "/v1/plays/reports", { token: who.access_token, body: { production_id: pid, script: true, reason: "copyright", ...over } });

  it("hides the production from its reporter at once, and from nobody else", async () => {
    const { pat, zoe, p } = await sharedWithZoe("hide");
    const inList = async (w) => (await (await call("GET", "/v1/plays/productions", { token: w.access_token })).json()).productions.some((x) => x.id === p.id);
    expect(await inList(zoe)).toBe(true);
    const r = await report(zoe, p.id, { note: "This is mine." });
    expect(r.status, await r.clone().text()).toBe(201);
    expect(await env.DB.prepare("SELECT script, take_id, target_user_id, reason, status FROM play_reports WHERE id = ?1").bind((await r.json()).id).first()).toEqual({
      script: 1, take_id: null, target_user_id: pat.user_id, reason: "copyright", status: "open",
    });
    expect(await inList(zoe)).toBe(false);
    expect((await call("GET", `/v1/plays/productions/${p.id}`, { token: zoe.access_token })).status).toBe(404);
    expect((await get(zoe, p.id)).status).toBe(404);
    expect(await inList(pat)).toBe(true);
    expect((await get(pat, p.id)).status).toBe(200);
  });

  it("lets no new person in until the owner answers: no invite made, opened or claimed, and no room", async () => {
    const { pat, zoe, s, p, inv } = await sharedWithZoe("shut");
    const body = { script_id: s.id, script_revision: s.revision, cast: s.cast, production_id: p.id };
    const h = await (await room(body, { token: pat.access_token })).json();
    const { id } = await (await report(zoe, p.id)).json();
    const ana = await person("shut-ana");
    const doors = () => [
      call("POST", `/v1/plays/productions/${p.id}/invites`, { token: pat.access_token, body: {} }),
      call("POST", "/v1/plays/invites/view", { token: ana.access_token, body: { token: inv.token } }),
      claimByInvite(ana, inv.token, "role:BEN"),
      openView(inv.token),
      openView(inv.token, "/script"),
      room(body, { token: pat.access_token }),
      roomScript(h.code, h.member_key),
    ];
    for (const r of await Promise.all(doors())) expect(await errorOf(r)).toEqual([409, "script_reported"]);
    await ownerOp("dismiss", { id });
    for (const r of await Promise.all(doors().filter((_, i) => i !== 2))) expect(r.status, await r.clone().text()).toBeLessThan(300);
    // A dismissed report keeps the reporter's own view of it, as a reported take's does.
    expect((await get(zoe, p.id)).status).toBe(404);
  });

  it("does not hide its bringer's takes from a viewer with no account, as a report of the person would", async () => {
    const { pat, zoe, p, inv } = await sharedWithZoe("takes");
    await env.DB.prepare(
      "INSERT INTO play_takes (production_id, id, user_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, created, uploaded_at, chosen) VALUES (?1, ?2, ?3, 'L0003', 'role:BEN', 'x.wav', 'audio/wav', 10, 4800, 48000, 'direct', 0, 1, 1)",
    ).bind(p.id, newTakeId(), pat.user_id).run();
    const { id } = await (await report(zoe, p.id)).json();
    // Looked at while the report is open, past the door it shuts: the rule itself.
    await env.DB.prepare("UPDATE play_reports SET status = 'open' WHERE id = ?1").bind(id).run();
    const through = { prepare: (sql) => env.DB.prepare(sql.replace("r.script = 1 AND r.status = 'open'", "r.status = 'never'")), batch: (x) => env.DB.batch(x) };
    const v = await (await call("GET", "/v1/plays/open/invite", { headers: { "x-invite": inv.token }, envOverride: { DB: through } })).json();
    expect(v.takes.length).toBe(1);
  });

  it("only of text that is there, by someone else in it, as a script and nothing else", async () => {
    const { pat, zoe, p } = await sharedWithZoe("which");
    expect((await report(await person("which-out"), p.id)).status).toBe(404);
    expect(await errorOf(await report(pat, p.id))).toEqual([404, "no_script"]);
    expect((await report(zoe, p.id, { user_id: pat.user_id })).status).toBe(400);
    expect((await report(zoe, p.id, { take_id: "TAKE-00001" })).status).toBe(400);
    expect((await report(zoe, p.id, { reason: "dull" })).status).toBe(400);
    // Copyright is a script's reason, not a person's.
    expect((await report(zoe, p.id, { script: undefined, user_id: pat.user_id })).status).toBe(400);
    expect((await report(zoe, p.id, { script: undefined, user_id: pat.user_id, reason: "other" })).status).toBe(201);
    const cat = await createProduction(pat);
    const inv = await invite(pat, cat.id);
    const { firstPart } = await import("./plays-helpers.js");
    expect((await claimByInvite(zoe, inv.token, firstPart)).status).toBe(200);
    expect(await errorOf(await report(zoe, cat.id))).toEqual([404, "no_script"]);
    expect((await operator(`/${p.id}`)).status).toBe(204);
    expect(await errorOf(await report(zoe, p.id))).toEqual([404, "no_script"]);
  });

  it("is counted for the hourly email like any other", async () => {
    const count = async () => (await (await call("GET", "/v1/operator/reports/count", { token: await githubToken("reports.yml") })).json()).open;
    const { zoe, p } = await sharedWithZoe("email");
    const before = await count();
    await report(zoe, p.id);
    expect(await count()).toBe(before + 1);
  });

  it("list and show tell the owner what it is, and the text can be read before it is answered", async () => {
    const { pat, zoe, s, p } = await sharedWithZoe("owner", { episode_id: "suspense|1949-01-06" });
    const { id } = await (await report(zoe, p.id)).json();
    expect((await ownerOp("list")).find((x) => x.id === id)).toMatchObject({ kind: "script", reason: "copyright", title: "The Pipes" });
    expect((await ownerOp("show", { id, now: Date.now() }))[0]).toMatchObject({ script: 1, take_id: null, target_user_id: pat.user_id, names_director: 1, script_bytes: s.bytes.length, episode_id: "suspense|1949-01-06" });
    expect((await ownerOp("read-script", { production: p.id }))[0].body).toBe(new TextDecoder().decode(s.bytes));
  });
});

/** The two ways the owner removes one script do the same. */
for (const [label, remove] of [
  ["the operator route", async (p) => expect((await operator(`/${p.id}`)).status).toBe(204)],
  ["tools/reports.py remove-script", (p) => ownerOp("remove-script", { production: p.id, now: Date.now() })],
]) {
  describe(`the owner's removal, by ${label}`, () => {
    it("drops the text, answers its reports, and holds the production: nobody new, no claim, no take", async () => {
      const { pat, zoe, s, p, inv } = await sharedWithZoe("gone");
      const bodyRoom = { script_id: s.id, script_revision: s.revision, cast: s.cast, production_id: p.id };
      const h = await (await room(bodyRoom, { token: pat.access_token })).json();
      const rep = await (await call("POST", "/v1/plays/reports", { token: zoe.access_token, body: { production_id: p.id, script: true, reason: "copyright" } })).json();
      const person2 = await (await call("POST", "/v1/plays/reports", { token: zoe.access_token, body: { production_id: p.id, user_id: pat.user_id, reason: "other" } })).json();
      await remove(p);
      const row = await rowOf(p.id);
      expect([row.body, row.bytes, row.held_at > 0]).toEqual([null, 0, true]);
      await expectTotal();
      const status = async (id) => (await env.DB.prepare("SELECT status FROM play_reports WHERE id = ?1").bind(id).first()).status;
      expect([await status(rep.id), await status(person2.id)]).toEqual(["acted", "open"]);
      const ana = await person("gone-ana");
      for (const r of await Promise.all([
        get(pat, p.id),
        get(zoe, p.id),
        put(pat, p.id, s.bytes),
        call("POST", `/v1/plays/productions/${p.id}/invites`, { token: pat.access_token, body: {} }),
        call("POST", "/v1/plays/invites/view", { token: ana.access_token, body: { token: inv.token } }),
        claimByInvite(ana, inv.token, "role:BEN"),
        openView(inv.token),
        openView(inv.token, "/script"),
        room(bodyRoom, { token: pat.access_token }),
        roomScript(h.code, h.member_key),
        upload(zoe, p.id, "L0002"),
      ])) expect(await errorOf(r)).toEqual([410, "script_removed"]);
      // The people in it keep the record, and the director can delete it.
      expect((await record(zoe, p.id)).own_script.state).toBe("removed");
      expect((await call("POST", `/v1/plays/productions/${p.id}/parts/${encodeURIComponent("role:ANNA")}/release`, { token: zoe.access_token })).status).toBe(200);
      expect(await errorOf(await call("POST", `/v1/plays/productions/${p.id}/claim`, { token: zoe.access_token, body: { part: "role:ANNA" } }))).toEqual([410, "script_removed"]);
      expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: pat.access_token })).status).toBe(204);
    });

    it("refuses the same text at its next share, whoever brings it, and at a put already owed", async () => {
      const { s, p } = await shared("again");
      const other = await person("again-other");
      const owed = await made(await post(other, bodyOf(s)));
      const elsewhere = await shared("again-keeps");
      await remove(p);
      expect(await errorOf(await post(other, bodyOf({ ...s, id: `own-${crypto.randomUUID()}` })))).toEqual([410, "script_removed"]);
      expect(await errorOf(await put(other, owed.id, s.bytes))).toEqual([410, "script_removed"]);
      expect((await post(other, bodyOf(await scriptOf()))).status).toBe(201);
      // Nothing else is touched.
      expect((await get(elsewhere.pat, elsewhere.p.id)).status).toBe(200);
    });

    it("a class's: its seats read no more and send no take", async () => {
      const { teacher, seats, key, p } = await classScript("goneclass");
      expect((await call("PUT", `/v1/plays/productions/${p.id}/assignments`, { token: teacher.access_token, body: { assignments: [{ part: "role:ANNA", seat: seats[0].id }] } })).status).toBe(200);
      await remove(p);
      expect(await errorOf(await seatCall("GET", `/productions/${p.id}/script`, key))).toEqual([410, "script_removed"]);
      const { wav } = await import("./plays-helpers.js");
      const bytes = wav(4800);
      const t = await seatCall("PUT", `/productions/${p.id}/takes/${newTakeId()}`, key, { body: bytes, headers: { "content-length": String(bytes.length), "x-take": JSON.stringify({ lineID: "L0002" }) } });
      expect(await errorOf(t)).toEqual([410, "script_removed"]);
    });
  });
}

describe("the operator routes", () => {
  it("only operator.yml's token on main; no such production, and a catalog play's, are 404", async () => {
    const { pat, p } = await shared("op");
    for (const token of [undefined, pat.access_token, await githubToken("reports.yml"), await githubToken("takedown-check.yml"), await githubToken("operator.yml", { ref: "refs/heads/x" })]) {
      expect((await call("DELETE", `/v1/operator/scripts/${p.id}`, { token })).status).toBe(403);
      expect((await call("DELETE", "/v1/operator/scripts?episode=x", { token })).status).toBe(403);
    }
    expect((await get(pat, p.id)).status).toBe(200);
    expect((await operator("/NO-SUCH-PRODUCTION")).status).toBe(404);
    expect((await operator(`/${(await createProduction(pat)).id}`)).status).toBe(404);
    for (const m of ["GET", "POST", "PUT"]) expect((await operator(`/${p.id}`, m)).status, m).toBe(404);
    expect((await operator("")).status).toBe(400);
    expect((await operator(`/${p.id}`)).status).toBe(204);
    expect((await operator(`/${p.id}`)).status).toBe(204);
  });

  it("a take-down naming an episode removes every transcript of it, refuses the next, and leaves other text", async () => {
    const episode_id = `take-down|${crypto.randomUUID()}`;
    const a = await shared("ep-a", { episode_id });
    const b = await shared("ep-b", { episode_id });
    const c = await shared("ep-c", { episode_id: `${episode_id}x` });
    const d = await shared("ep-d");
    const r = await operator(`?episode=${encodeURIComponent(episode_id)}`);
    expect(await r.json()).toEqual({ removed: 2 });
    for (const x of [a, b]) expect((await get(x.pat, x.p.id)).status).toBe(410);
    for (const x of [c, d]) expect((await get(x.pat, x.p.id)).status).toBe(200);
    const later = await scriptOf();
    expect(await errorOf(await post(a.pat, bodyOf(later, { episode_id })))).toEqual([410, "script_removed"]);
    // Nor may the same transcript come back unnamed.
    expect(await errorOf(await post(a.pat, bodyOf(a.s)))).toEqual([410, "script_removed"]);
    expect((await post(a.pat, bodyOf(later))).status).toBe(201);
    await expectTotal();
  });
});

describe("it goes with what holds it", () => {
  const gone = async (p, before, s) => {
    expect(await rowOf(p.id)).toBeNull();
    expect(await expectTotal()).toBe(before - s.bytes.length);
  };

  it("Delete production, by its director only", async () => {
    const { pat, zoe, s, p } = await sharedWithZoe("d-prod");
    const before = await expectTotal();
    expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: zoe.access_token })).status).toBe(403);
    expect(await expectTotal()).toBe(before);
    expect((await call("DELETE", `/v1/plays/productions/${p.id}`, { token: pat.access_token })).status).toBe(204);
    await gone(p, before, s);
  });

  it("Delete class, a school's request, and the class's end date", async () => {
    const ways = [
      async (k) => expect((await call("DELETE", `/v1/plays/classes/${k.c.id}`, { token: k.teacher.access_token })).status).toBe(204),
      async (k) => expect((await call("DELETE", `/v1/operator/classes/${k.c.id}`, { token: await githubToken("operator.yml") })).status).toBe(200),
      async (k) => {
        await env.DB.prepare("UPDATE play_classes SET ends_on = '2000-01-01' WHERE id = ?1").bind(k.c.id).run();
        await sweepRetention(env);
      },
      async (k) => expect((await call("DELETE", "/v1/account", { token: k.teacher.access_token })).status).toBe(200),
    ];
    for (const [i, way] of ways.entries()) {
      const k = await classScript(`d-class-${i}`);
      const before = await expectTotal();
      await way(k);
      await gone(k.p, before, k.s);
    }
  });

  it("a class idle a year, after its notice", async () => {
    const k = await classScript("d-idle");
    const before = await expectTotal();
    const YEAR = 366 * 24 * 3600 * 1000;
    const then = Date.now() - YEAR - NOTICE_MS;
    await env.DB.batch([
      env.DB.prepare("UPDATE play_classes SET created_at = ?2, touched_at = ?2, notice_at = ?3, ends_on = '2999-01-01' WHERE id = ?1").bind(k.c.id, then, Date.now() - NOTICE_MS - 1000),
      env.DB.prepare("UPDATE play_class_seats SET claimed_at = ?2 WHERE class_id = ?1").bind(k.c.id, then),
      env.DB.prepare("UPDATE play_productions SET updated_at = ?2 WHERE class_id = ?1").bind(k.c.id, then),
    ]);
    await sweepRetention(env);
    await gone(k.p, before, k.s);
  });

  it("were a class's own script ever submitted, its text would still go with the class", async () => {
    const k = await classScript("d-sub");
    const before = await expectTotal();
    await env.DB.prepare("INSERT INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at) VALUES (?1, ?2, 'failed', '[]', 1, 1)").bind(k.p.id, k.teacher.user_id).run();
    expect((await call("DELETE", `/v1/plays/classes/${k.c.id}`, { token: k.teacher.access_token })).status).toBe(204);
    await gone(k.p, before, k.s);
  });

  it("the account that brought it: the production passes on with its takes, the text is gone, and nobody new comes in", async () => {
    const { pat, zoe, s, p } = await sharedWithZoe("d-acct");
    const before = await expectTotal();
    expect((await call("DELETE", "/v1/account", { token: pat.access_token })).status).toBe(200);
    await gone(p, before, s);
    const rec = await record(zoe, p.id);
    expect(rec.director).toBe(zoe.user_id);
    expect(rec.own_script).toEqual({ state: "removed", by: null, episode_id: null });
    expect(await errorOf(await get(zoe, p.id))).toEqual([410, "script_removed"]);
    expect(await errorOf(await put(zoe, p.id, s.bytes))).toEqual([410, "script_removed"]);
    expect(await errorOf(await call("POST", `/v1/plays/productions/${p.id}/invites`, { token: zoe.access_token, body: {} }))).toEqual([410, "script_removed"]);
    expect(await errorOf(await room({ script_id: s.id, script_revision: s.revision, cast: s.cast, production_id: p.id }, { token: zoe.access_token }))).toEqual([410, "script_removed"]);
    // Not held: the people in it have the text on their devices and may go on.
    expect((await call("POST", `/v1/plays/productions/${p.id}/claim`, { token: zoe.access_token, body: { part: "role:BEN" } })).status).toBe(409);
    expect((await call("POST", `/v1/plays/productions/${p.id}/parts/${encodeURIComponent("role:ANNA")}/release`, { token: zoe.access_token })).status).toBe(200);
    expect((await call("POST", `/v1/plays/productions/${p.id}/claim`, { token: zoe.access_token, body: { part: "role:BEN" } })).status).toBe(200);
    expect((await upload(zoe, p.id, "L0003")).status).toBe(201);
  });

  it("an account idle three years goes the same way", async () => {
    const { pat, s, p } = await shared("d-acct-idle");
    const before = await expectTotal();
    const long = Date.now() - ACCOUNT_IDLE_MS - NOTICE_MS;
    await env.DB.prepare("UPDATE users SET seen_at = ?2, idle_notice_at = ?3 WHERE id = ?1").bind(pat.user_id, long, Date.now() - NOTICE_MS - 1000).run();
    await sweepRetention(env);
    expect(await env.DB.prepare("SELECT 1 FROM users WHERE id = ?1").bind(pat.user_id).first()).toBeNull();
    await gone(p, before, s);
  });

  it("another member's account, or its present director's, does not take it", async () => {
    const { pat, zoe, p } = await sharedWithZoe("d-member");
    expect((await call("DELETE", "/v1/account", { token: zoe.access_token })).status).toBe(200);
    expect((await get(pat, p.id)).status).toBe(200);
  });

  it("no sweep or owner's take-down of a person takes it by accident", async () => {
    const { pat, p } = await shared("d-sweep");
    await sweepPlays(env);
    await sweepRetention(env);
    expect((await get(pat, p.id)).status).toBe(200);
  });

  it("the class export names it and where its lines are read, and parses none of it", async () => {
    const k = await classScript("export");
    const out = await (await call("GET", `/v1/plays/classes/${k.c.id}/export`, { token: k.teacher.access_token })).json();
    expect(out.productions[0].script).toEqual({ title: "The Pipes", revision: k.s.revision, source: "Added by you", episode_id: null, state: "kept" });
    expect(JSON.stringify(out)).not.toContain("Only the pipes.");
  });
});

describe("an own script never publishes", () => {
  const forged = (p, s) => JSON.stringify({ format: 1, id: s.id, revision: s.revision, title: "The Pipes", cast: "a".repeat(64), lines: 4, source: null, rights: { bucket: "script_source_cleared", evidence: [] }, publishable: true });

  it("publish is refused with no job, complete and consented", async () => {
    const { pat, p } = await shared("pub");
    expect((await consent(pat, p.id)).status).toBe(204);
    const r = await call("POST", `/v1/plays/productions/${p.id}/publish`, { token: pat.access_token, envOverride: KEYS });
    expect(await errorOf(r)).toEqual([422, "script_not_publishable"]);
    expect(await env.DB.prepare("SELECT 1 FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first()).toBeNull();
  });

  it("nor for a 13-and-over class with both confirmations", async () => {
    const k = await classScript("pubclass");
    const r = await call("POST", `/v1/plays/productions/${k.p.id}/publish`, { token: k.teacher.access_token, envOverride: KEYS, body: { credit_name: "Ms. Ortiz", performers_agreed: true, media_release: true } });
    expect(await errorOf(r)).toEqual([422, "script_not_publishable"]);
  });

  for (const [label, row] of [["no row", () => null], ["a forged publishable row", forged]]) {
    it(`a job that should not exist uploads nothing, with ${label}: the cron fails it and archive/files refuses`, async () => {
      const { pat, s, p } = await shared("job");
      const job = (status) =>
        env.DB.prepare("INSERT OR REPLACE INTO play_archive_jobs (production_id, user_id, status, take_ids, created_at, updated_at) VALUES (?1, ?2, ?3, '[]', 1, 1)").bind(p.id, pat.user_id, status).run();
      const stored = row(p, s);
      await env.DB.prepare("UPDATE play_productions SET script_row = ?2 WHERE id = ?1").bind(p.id, stored).run();
      const state = () => env.DB.prepare("SELECT status, reason FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).first();
      await job("queued");
      await runArchive({ ...env, ...KEYS });
      expect(await state()).toEqual({ status: "failed", reason: "script_not_publishable" });
      await job("uploading");
      const { wav } = await import("./plays-helpers.js");
      const bytes = wav(4800);
      const r = await call("PUT", `/v1/plays/productions/${p.id}/archive/files/L0002`, { token: pat.access_token, envOverride: KEYS, body: bytes, headers: { "content-length": String(bytes.length) } });
      expect(await errorOf(r)).toEqual([422, "script_not_publishable"]);
      expect(await state()).toEqual({ status: "failed", reason: "script_not_publishable" });
      expect(fetched).toEqual([]);
      await env.DB.prepare("DELETE FROM play_archive_jobs WHERE production_id = ?1").bind(p.id).run();
    });
  }

  it("CONTROL: the row forged above would publish under a catalog id", async () => {
    const s = await scriptOf();
    const row = JSON.parse(forged(null, s));
    expect(isPublishable(row)).toBe(false);
    expect(isPublishable({ ...row, id: "gut-3012" })).toBe(true);
    expect(madeFrom({ script_id: s.id, script_revision: s.revision, script_row: null })).toBeNull();
  });
});

describe("a class: the teacher brings the script", () => {
  it("a seat has no route to send text, and a class's other people none to make or send one", async () => {
    const { c, key, p, teacher } = await classScript("u13", { under13: true });
    const s = await scriptOf();
    for (const m of ["PUT", "POST", "DELETE"]) {
      expect(await errorOf(await seatCall(m, `/productions/${p.id}/script`, key, { body: s.bytes })), m).toEqual([403, "teacher_only"]);
    }
    expect((await seatCall("POST", "/productions", key, { body: bodyOf(s) })).status).toBe(404);
    expect((await call("PUT", `/v1/plays/productions/${p.id}/script`, { headers: { "x-seat-key": key }, body: s.bytes })).status).toBe(401);
    const out = await person("u13-out");
    expect(await errorOf(await call("POST", `/v1/plays/classes/${c.id}/productions`, { token: out.access_token, body: bodyOf(s) }))).toEqual([403, "teacher_only"]);
    expect((await put(out, p.id, s.bytes)).status).toBe(404);
    // Its seats read what the teacher brought, under 13 or not; no voice leaves without the school's consent, as before.
    expect((await seatCall("GET", `/productions/${p.id}/script`, key)).status).toBe(200);
    expect((await get(teacher, p.id)).status).toBe(200);
  });
});
