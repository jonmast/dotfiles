#!/usr/bin/env node
/**
 * Render a template from ../templates/ to stdout.
 *
 *   render.ts <template> [key=value | key=@file]...
 *   render.ts --keys <template>      list the template's keys and what each holds
 *
 * Template syntax, one construct per line:
 *   {{key}}             replaced by the key's value; key=@file reads the value from a file
 *   {{?key}} text       the line is kept, without the marker, only when key has a value
 *   {{>name}}           the line is replaced by templates/name.md, rendered with the same keys
 *   {{! key: doc }}     documents a key for --keys; dropped from the output
 *   {{! one-of: a b }}  exactly one of the keys must have a value
 *   {{! text }}         a note for maintainers; dropped from the output
 *
 * Fails, printing what is wrong, on an unknown key or a {{key}} left without a value,
 * so the orchestrator never has to read a rendered prompt to check it.
 *
 * Needs Node 22.18 or later, which runs TypeScript by stripping types.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const TEMPLATES = join(dirname(fileURLToPath(import.meta.url)), "..", "templates");
const ONE_OF = /^\{\{!\s*one-of:\s*(.*?)\s*\}\}$/;
const DOC = /^\{\{!\s*(\w+):\s*(.*?)\s*\}\}$/;
const COMMENT = /^\{\{!.*\}\}$/;
const COND = /^\{\{\?(\w+)\}\}\s?/;
const INCLUDE = /^\{\{>(\w[\w-]*)\}\}$/;
const VAR = /\{\{(\w+)\}\}/g;

function fail(message: string): never {
  process.stderr.write(`render.ts: ${message}\n`);
  process.exit(1);
}

function load(name: string): string[] {
  const path = join(TEMPLATES, `${name}.md`);
  if (!existsSync(path)) fail(`no template ${name} in ${TEMPLATES}`);
  return readFileSync(path, "utf8").split("\n");
}

function varsIn(line: string): string[] {
  return [...line.matchAll(VAR)].map((m) => m[1]);
}

/** Key -> doc, gathered from the template and its includes. */
function keys(name: string, seen = new Set<string>()): Map<string, string> {
  const found = new Map<string, string>();
  const add = (k: string, doc = "") => {
    if (!found.has(k) || (!found.get(k) && doc)) found.set(k, doc);
  };
  for (const raw of load(name)) {
    const line = raw.trim();
    let m: RegExpMatchArray | null;
    if ((m = line.match(DOC))) {
      add(m[1], m[2]);
    } else if ((m = line.match(INCLUDE))) {
      if (seen.has(m[1])) continue;
      seen.add(m[1]);
      for (const [k, doc] of keys(m[1], seen)) add(k, doc);
    } else if (!COMMENT.test(line)) {
      const cond = line.match(COND);
      for (const k of [...varsIn(line), ...(cond ? [cond[1]] : [])]) add(k);
    }
  }
  return found;
}

function render(name: string, values: Map<string, string>, missing: Set<string>): string[] {
  const out: string[] = [];
  for (let line of load(name)) {
    const stripped = line.trim();
    let m: RegExpMatchArray | null;
    if ((m = stripped.match(ONE_OF))) {
      const group = m[1].split(/\s+/);
      if (group.filter((k) => values.get(k)).length !== 1) {
        fail(`${name} needs exactly one of: ${group.join(", ")}`);
      }
      continue;
    }
    if (COMMENT.test(stripped)) continue;
    if ((m = stripped.match(INCLUDE))) {
      out.push(...render(m[1], values, missing));
      continue;
    }
    if ((m = line.match(COND))) {
      if (!values.get(m[1])) continue;
      line = line.slice(m[0].length);
    }
    for (const k of varsIn(line)) if (!values.get(k)) missing.add(k);
    out.push(line.replace(VAR, (whole, k: string) => values.get(k) || whole));
  }
  return out;
}

function main(argv: string[]): void {
  if (argv.length === 2 && argv[0] === "--keys") {
    for (const [k, doc] of keys(argv[1])) console.log(doc ? `${k}: ${doc}` : k);
    return;
  }
  if (argv.length === 0 || argv[0].startsWith("-")) {
    fail("usage: render.ts <template> [key=value | key=@file]...  |  render.ts --keys <template>");
  }
  const [name, ...pairs] = argv;
  const known = keys(name);
  const values = new Map<string, string>();
  for (const pair of pairs) {
    const eq = pair.indexOf("=");
    if (eq < 0) fail(`expected key=value, got ${JSON.stringify(pair)}`);
    const k = pair.slice(0, eq);
    let v = pair.slice(eq + 1);
    if (!known.has(k)) fail(`${name} has no key ${JSON.stringify(k)}; keys: ${[...known.keys()].join(", ")}`);
    if (v.startsWith("@")) {
      const path = v.slice(1).replace(/^~(?=\/|$)/, homedir());
      if (!existsSync(path)) fail(`${k}: no file ${path}`);
      v = readFileSync(path, "utf8").replace(/\n+$/, "");
    }
    values.set(k, v);
  }
  const missing = new Set<string>();
  const lines = render(name, values, missing);
  if (missing.size) fail(`${name} needs values for: ${[...missing].sort().join(", ")}`);
  console.log(lines.join("\n").replace(/\n{3,}/g, "\n\n").replace(/^\n+|\n+$/g, ""));
}

main(process.argv.slice(2));
