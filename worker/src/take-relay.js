/**
 * Takes pass through (Decision 082, PLAYS-DESIGN §12.5). Owner, 2026-11-19:
 * "We are using archive.org for storage, not cloudflare." A take crosses the
 * Worker from the device that recorded it to the director's (the teacher's)
 * device while both are there, and nothing keeps it: no R2, no D1, no KV, and
 * no Durable Object storage. This object never calls `ctx.storage`.
 *
 * ONE OBJECT PER PRODUCTION, IN MEMORY ONLY. The director's device asks for
 * the next take (`pickup`, a long poll). A sender's request is matched to a
 * waiting pickup and its body is piped straight into the pickup's response.
 * Neither side is ever read whole: the pipe moves one chunk at a time and
 * waits for the receiver to read it (stream backpressure), so a slow receiver
 * slows the sender rather than filling memory.
 *
 * MEMORY. A Durable Object's isolate has 128 MB. Each transfer holds at most
 * the replayed head (HEAD_BYTES, 64 KiB, in the Worker that checked it) and
 * the chunk in the pipe (one network read, tens of KiB). At most MAX_PICKUPS
 * transfers run at once per production and each sender has one take in
 * flight, so a production's object holds well under 1 MB of audio at any
 * moment, never a whole take. A waiting sender's body is not read at all.
 *
 * NOBODY RECEIVING. With no pickup waiting and no director's device seen in
 * the last RECEIVER_GRACE_MS (the gap between two long polls), a take is
 * refused with 409 `nobody_receiving`; it stays on the recording device,
 * which sends it again when both are present. A sender waits at most
 * SEND_WAIT_MS for the next pickup. An evicted object forgets everything,
 * which only means the next take is refused until the director polls again.
 */

import { DurableObject } from "cloudflare:workers";
import { json, problem } from "./http.js";

export const PICKUP_WAIT_MS = 25 * 1000;
export const RECEIVER_GRACE_MS = 10 * 1000;
export const SEND_WAIT_MS = 10 * 1000;
export const MAX_PICKUPS = 4;
export const MAX_WAITING_SENDERS = 40;
export const SENDER_HEADER = "x-relay-sender";
export const TAKE_HEADER = "x-take";
export const LENGTH_HEADER = "x-relay-length";

export class TakeRelay extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.pickups = [];
    this.senders = [];
    this.inFlight = new Set();
    this.seenAt = 0;
  }

  present(now) {
    return this.pickups.length > 0 || now - this.seenAt <= RECEIVER_GRACE_MS;
  }

  async fetch(request) {
    const op = new URL(request.url).pathname.slice(1);
    const now = Date.now();
    if (op === "status") return json({ receiving: this.present(now), waiting: this.pickups.length });
    if (op === "pickup") return this.pickup(now);
    if (op === "send") return this.send(request, now);
    return problem(404, "not_found");
  }

  pickup(now) {
    this.seenAt = now;
    const waiting = this.senders.shift();
    if (waiting) {
      clearTimeout(waiting.timer);
      return new Promise((resolve) => waiting.match(resolve));
    }
    if (this.pickups.length >= MAX_PICKUPS) return problem(409, "too_many_pickups", MAX_PICKUPS);
    return new Promise((resolve) => {
      const p = { resolve };
      p.timer = setTimeout(() => {
        this.pickups = this.pickups.filter((x) => x !== p);
        this.seenAt = Date.now();
        resolve(new Response(null, { status: 204 }));
      }, PICKUP_WAIT_MS);
      this.pickups.push(p);
    });
  }

  async send(request, now) {
    const sender = request.headers.get(SENDER_HEADER) || "";
    if (this.inFlight.has(sender)) return problem(409, "one_take_at_a_time");
    let deliver;
    const p = this.pickups.shift();
    if (p) {
      clearTimeout(p.timer);
      deliver = p.resolve;
    } else {
      if (!this.present(now) || this.senders.length >= MAX_WAITING_SENDERS) return problem(409, "nobody_receiving");
      deliver = await new Promise((resolve) => {
        const s = { match: resolve };
        s.timer = setTimeout(() => {
          this.senders = this.senders.filter((x) => x !== s);
          resolve(null);
        }, SEND_WAIT_MS);
        this.senders.push(s);
      });
      if (!deliver) return problem(409, "nobody_receiving");
    }
    this.inFlight.add(sender);
    // One chunk in the pipe at a time: the receiver's reads pull the sender's bytes (highWaterMark 0).
    // A body shorter or longer than declared errors the receiver's stream, so a cut take is never a take.
    const expected = Number(request.headers.get(LENGTH_HEADER));
    const reader = request.body.getReader();
    let seen = 0;
    let settle;
    const done = new Promise((resolve) => (settle = resolve));
    const fail = (controller) => {
      controller.error(new Error("take_length_mismatch"));
      reader.cancel().catch(() => {});
      settle(false);
    };
    const readable = new ReadableStream(
      {
        async pull(controller) {
          let r;
          try {
            r = await reader.read();
          } catch {
            return fail(controller);
          }
          if (r.done) {
            if (seen !== expected) return fail(controller);
            controller.close();
            return settle(true);
          }
          seen += r.value.byteLength;
          if (seen > expected) return fail(controller);
          controller.enqueue(r.value);
        },
        cancel() {
          reader.cancel().catch(() => {});
          settle(false);
        },
      },
      { highWaterMark: 0 },
    );
    deliver(
      new Response(readable, {
        headers: { "content-type": "application/octet-stream", [TAKE_HEADER]: request.headers.get(TAKE_HEADER) || "{}", "cache-control": "no-store" },
      }),
    );
    const ok = await done;
    this.inFlight.delete(sender);
    return ok ? json({ delivered: true }) : problem(502, "not_delivered");
  }
}

const stub = (env, pid) => env.TAKE_RELAY.get(env.TAKE_RELAY.idFromName(pid));

/** Whether the director's device is there to receive a take now. */
export async function receiving(env, pid) {
  if (!env.TAKE_RELAY) return false;
  const r = await stub(env, pid).fetch("https://take-relay/status");
  return (await r.json()).receiving === true;
}

/** The director's device asks for the next take: the take's bytes with its fields in `x-take`, or 204 after a quiet wait. */
export function pickup(env, pid) {
  if (!env.TAKE_RELAY) return problem(503, "pass_through_unavailable");
  return stub(env, pid).fetch("https://take-relay/pickup");
}

/** Pipes a checked take stream to the waiting director's device; resolves to the relay's answer. */
export function relay(env, pid, sender, meta, stream, length) {
  return stub(env, pid).fetch("https://take-relay/send", {
    method: "POST",
    headers: { [SENDER_HEADER]: sender, [TAKE_HEADER]: JSON.stringify(meta), [LENGTH_HEADER]: String(length) },
    body: stream,
    duplex: "half",
  });
}
