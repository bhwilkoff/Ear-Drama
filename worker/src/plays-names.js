/**
 * Display names on shared plays: the server's gate (zero-cost-hosted-backend,
 * the two-layer banned-words gate; this is the authoritative layer, so an old
 * client cannot get around a newly denied term).
 *
 * A name is folded before it is checked: accents dropped, case folded, the
 * usual look-alike digits and symbols read as letters, and everything that is
 * not a letter removed. A STRONG term is refused anywhere in the folded name;
 * a WORD term only as a whole word, so "Cassandra" and "Hancock" pass (and
 * "Dick" is a name, not a WORD term).
 *
 * OWNER: this list is a seed, not a vetted list. Replace or extend it from a
 * maintained list the owner approves (PLAYS-DESIGN §11, open items).
 */

export const MAX_NAME = 40;

const STRONG = [
  "fuck", "shit", "cunt", "nigger", "nigga", "faggot", "retard", "whore", "slut",
  "bitch", "dickhead", "motherfucker", "wanker", "twat", "rape", "nazi", "hitler",
];
const WORD = ["ass", "asshole", "cock", "fag", "piss", "tits", "porn", "sex", "kys", "kill yourself"];
/** Names that would pass as the service speaking. */
const RESERVED = ["eardrama", "ear drama", "admin", "moderator", "official", "staff", "support"];

const LOOK_ALIKE = { 0: "o", 1: "i", 3: "e", 4: "a", 5: "s", 7: "t", 8: "b", "@": "a", $: "s", "!": "i", "|": "i", "+": "t" };

function fold(name) {
  const plain = name.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  return [...plain].map((c) => LOOK_ALIKE[c] || c).join("");
}

const UNSEEN = /[\u0000-\u001f\u007f\u200b-\u200f\u2028-\u202e]/;
const LINK = /https?:|www\.|\.(com|net|org|io|ly|gg)\b/i;

/** null when the name may be shown, or the refusal's code. */
export function nameRefusal(raw) {
  if (raw === undefined || raw === null || raw === "") return null;
  if (typeof raw !== "string") return "bad_name";
  const name = raw.trim();
  if (name.length > MAX_NAME) return "name_too_long";
  if (UNSEEN.test(name)) return "bad_name";
  if (LINK.test(name)) return "name_has_link";
  const folded = fold(name);
  const squashed = folded.replace(/[^a-z]/g, "");
  const words = ` ${folded.replace(/[^a-z]+/g, " ").trim()} `;
  if (STRONG.some((t) => squashed.includes(t))) return "name_not_allowed";
  if (WORD.some((t) => words.includes(` ${t} `) || squashed === t.replace(/ /g, ""))) return "name_not_allowed";
  if (RESERVED.some((t) => squashed.includes(t.replace(/ /g, "")))) return "name_reserved";
  return null;
}

/** Words a name may not hold that titles and characters do: The Rape of Lucrece, Who Killed Cock Robin, The Nazi Spy. */
const IN_TITLES = ["ass", "cock", "rape", "nazi", "hitler"];
const TITLE_WORDS = [...STRONG, ...WORD].filter((t) => !IN_TITLES.includes(t) && !t.includes(" "));
const ENDING = /^(s|es|ed|er|ers|ing|in|y)?$/;

/**
 * The same gate for the title or a part of an own script (Decision 088.4): null, or the refusal's
 * code. Words are judged whole, never inside another or across two, or "The Grapes of Wrath" and
 * "Was Hitched" would be refused; a word spelled out in single letters is read as one. The reserved
 * names are for people, so a part may be STAFF or MODERATOR.
 */
export function wordsRefusal(raw, max) {
  const text = raw.trim();
  if (text.length > max) return "name_too_long";
  if (UNSEEN.test(text)) return "bad_name";
  if (LINK.test(text)) return "name_has_link";
  const words = [];
  let spelled = "";
  for (const w of [...fold(text).replace(/['’]/g, "").split(/[^a-z]+/).filter(Boolean), ""]) {
    if (w.length === 1) {
      spelled += w;
      continue;
    }
    if (spelled) words.push(spelled);
    spelled = "";
    if (w) words.push(w);
  }
  const denied = words.some((w) => TITLE_WORDS.some((t) => w.startsWith(t) && ENDING.test(w.slice(t.length))));
  return denied || ` ${words.join(" ")} `.includes(" kill yourself ") ? "name_not_allowed" : null;
}

export const cleanName = (raw) => (typeof raw === "string" ? raw.trim() : "");
