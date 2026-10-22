#!/usr/bin/env node
// Writes every platform's design-token file from design-tokens.json, so the
// look is chosen once and reaches web, Apple, Android, Windows, and the TV
// targets together.
//
//   node tools/design_tokens.mjs           rewrite every target
//   node tools/design_tokens.mjs --check   change nothing; exit 1 and name each
//                                          target that differs from a fresh run
//
// Three kinds of target: whole files (each opens with a "generated" header),
// marked blocks inside hand-written files (between BEGIN/END design-tokens
// lines), and single fields in JSON or XML manifests that cannot carry a
// comment. No dependencies beyond Node itself.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const NOTE = 'generated from design-tokens.json by tools/design_tokens.mjs. Do not edit by hand';

// ---- helpers -------------------------------------------------------------

const hex6 = (h) => {
  const m = /^#([0-9a-fA-F]{6})$/.exec(h);
  if (!m) throw new Error(`design-tokens.json: "${h}" is not a #RRGGBB color`);
  return m[1].toUpperCase();
};
const rgb = (h) => { const x = hex6(h); return [0, 2, 4].map((i) => parseInt(x.slice(i, i + 2), 16)); };
const toHex = ([r, g, b]) => '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
const mixBlack = (h, t) => toHex(rgb(h).map((v) => v * (1 - t)));
const kebab = (s) => s.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
const pascal = (s) => s[0].toUpperCase() + s.slice(1);

export function contrast(a, b) {
  const lum = (h) => {
    const [r, g, bl] = rgb(h).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * bl;
  };
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

function hue(h) {
  const [r, g, b] = rgb(h).map((v) => v / 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  if (d === 0) return 0;
  let x = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return Math.round((x * 60 + 360) % 360);
}

// Every color, flattened: [{ name, light, dark, kind }]
export function colors(t) {
  const out = [];
  for (const kind of ['brand', 'semantic']) {
    for (const [name, v] of Object.entries(t.color[kind])) out.push({ name, light: v.light, dark: v.dark, kind });
  }
  return out;
}

const WEIGHT = {
  css: (w) => String(w),
  swift: (w) => ({ 400: 'regular', 500: 'medium', 600: 'semibold', 700: 'bold', 800: 'heavy', 900: 'black' })[w],
  kotlin: (w) => ({ 400: 'Normal', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black' })[w],
  axaml: (w) => ({ 400: 'Normal', 500: 'Medium', 600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black' })[w],
};

// ---- block and field replacement ----------------------------------------

function replaceBlock(text, file, id, body, open, close) {
  const tag = `design-tokens${id ? ':' + id : ''}`;
  const lines = text.split('\n');
  const begin = new RegExp(`BEGIN ${tag}[ .]`), end = new RegExp(`END ${tag} `);
  const b = lines.findIndex((l) => begin.test(l));
  const e = lines.findIndex((l, i) => i > b && end.test(l));
  if (b < 0 || e < 0) throw new Error(`${file}: missing the "BEGIN ${tag}" / "END ${tag}" lines`);
  const indent = lines[b].match(/^\s*/)[0];
  const block = [
    `${indent}${open} BEGIN ${tag}. ${pascal(NOTE)}. ${close}`,
    ...body.map((l) => (l ? indent + l : l)),
    `${indent}${open} END ${tag} ${close}`,
  ];
  return [...lines.slice(0, b), ...block, ...lines.slice(e + 1)].join('\n');
}
const cssBlock = (text, file, id, body) => replaceBlock(text, file, id, body, '/*', '*/');
const xmlBlock = (text, file, id, body) => replaceBlock(text, file, id, body, '<!--', '-->');

function setJsonFields(text, fields) {
  const j = JSON.parse(text);
  Object.assign(j, fields);
  return JSON.stringify(j, null, 2) + '\n';
}

function setPattern(text, file, re, value) {
  if (!re.test(text)) throw new Error(`${file}: nothing matches ${re}`);
  return text.replace(re, (_, pre, _old, post) => pre + value + post);
}

// ---- web -----------------------------------------------------------------

function webVars(t, mode) {
  return colors(t).map((c) => `--color-${kebab(c.name)}: ${c[mode].toUpperCase()};`);
}

function webStyles(t) {
  const out = [':root {', '  color-scheme: light;', ...webVars(t, 'light').map((l) => '  ' + l)];
  out.push(`  --font-body: ${t.font.body.web};`, `  --font-mono: ${t.font.mono.web};`);
  for (const l of t.type) {
    out.push(`  --type-${kebab(l.id)}-size: ${l.size / 16}rem;`, `  --type-${kebab(l.id)}-weight: ${WEIGHT.css(l.weight)};`);
  }
  for (const [k, v] of Object.entries(t.space)) out.push(`  --space-${k}: ${v}px;`);
  for (const [k, v] of Object.entries(t.radius)) out.push(`  --radius-${kebab(k)}: ${v}px;`);
  out.push('}');
  const dark = ['  color-scheme: dark;', ...webVars(t, 'dark').map((l) => '  ' + l)];
  out.push('html[data-theme="dark"] {', ...dark, '}');
  out.push('@media (prefers-color-scheme: dark) {', '  html:not([data-theme="light"]) {', ...dark.map((l) => '  ' + l), '  }', '}');
  return out;
}

function themeColorMeta(t) {
  const b = t.color.brand.background;
  return [
    `<meta name="theme-color" content="${b.light.toUpperCase()}" media="(prefers-color-scheme: light)">`,
    `<meta name="theme-color" content="${b.dark.toUpperCase()}" media="(prefers-color-scheme: dark)">`,
  ];
}

// ---- TV (smart-TV web, Cast receiver, webOS) ----------------------------

function tvCss(t) {
  const c = t.color.brand;
  return [
    'html.tv {',
    `  --tv-bg: ${c.background.dark.toUpperCase()};`,
    `  --tv-text: ${c.text.dark.toUpperCase()};`,
    `  --tv-text-muted: ${c.textMuted.dark.toUpperCase()};`,
    `  --tv-accent: ${c.primary.dark.toUpperCase()};`,
    `  --tv-focus-ring: ${c.text.dark.toUpperCase()};`,
    '}',
  ];
}

function castCss(t) {
  const p = t.color.brand.primary.dark.toUpperCase();
  return [
    ':root {',
    `  --brand-primary: ${p};`,
    `  --brand-text-muted: ${t.color.brand.textMuted.dark.toUpperCase()};`,
    '}',
    'cast-media-player {',
    `  --theme-hue: ${hue(p)};`,
    `  --progress-color: ${p};`,
    '}',
  ];
}

// ---- Apple ---------------------------------------------------------------

function appleDesign(t) {
  const L = [];
  L.push(`// Design tokens, ${NOTE}:`);
  L.push('// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.');
  L.push('// Every Apple platform reads this one file (it lives in Core/).');
  L.push('');
  L.push('import SwiftUI');
  L.push('#if canImport(UIKit)');
  L.push('import UIKit');
  L.push('#elseif canImport(AppKit)');
  L.push('import AppKit');
  L.push('#endif');
  L.push('');
  L.push('extension Color {');
  let kind = '';
  for (const c of colors(t)) {
    if (c.kind !== kind) {
      if (kind) L.push('');
      L.push(c.kind === 'brand' ? '    // Brand: UI chrome only, never content meaning.' : '    // Semantic: content meaning only, never chrome.');
      kind = c.kind;
    }
    L.push(`    nonisolated static let ${c.kind}${pascal(c.name)} = Color.tokenPair(light: 0x${hex6(c.light)}, dark: 0x${hex6(c.dark)})`);
  }
  L.push('');
  L.push('    nonisolated private static func tokenPair(light: UInt32, dark: UInt32) -> Color {');
  L.push('        #if canImport(UIKit)');
  L.push('        Color(uiColor: UIColor { traits in');
  L.push('            platformColor(traits.userInterfaceStyle == .dark ? dark : light)');
  L.push('        })');
  L.push('        #else');
  L.push('        Color(nsColor: NSColor(name: nil) { appearance in');
  L.push('            platformColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)');
  L.push('        })');
  L.push('        #endif');
  L.push('    }');
  L.push('');
  L.push('    #if canImport(UIKit)');
  L.push('    nonisolated private static func platformColor(_ v: UInt32) -> UIColor {');
  L.push('        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,');
  L.push('                blue: CGFloat(v & 0xFF) / 255, alpha: 1)');
  L.push('    }');
  L.push('    #else');
  L.push('    nonisolated private static func platformColor(_ v: UInt32) -> NSColor {');
  L.push('        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,');
  L.push('                blue: CGFloat(v & 0xFF) / 255, alpha: 1)');
  L.push('    }');
  L.push('    #endif');
  L.push('}');
  L.push('');
  L.push('/// The six-level type ramp. Apple platforms use the system text styles, so');
  L.push('/// Dynamic Type keeps working; tvOS maps to its own larger ten-foot styles.');
  L.push('enum TypeRamp {');
  for (const l of t.type) {
    const f = (style) => `Font.${style}${l.mono ? '.monospacedDigit()' : ''}.weight(.${WEIGHT.swift(l.weight)})`;
    L.push('    #if os(tvOS)');
    L.push(`    nonisolated static let ${l.id} = ${f(l.tvos)}  // ${l.level}`);
    L.push('    #else');
    L.push(`    nonisolated static let ${l.id} = ${f(l.apple)}  // ${l.level}`);
    L.push('    #endif');
  }
  L.push('}');
  L.push('');
  L.push('enum Spacing {');
  for (const [k, v] of Object.entries(t.space)) L.push(`    nonisolated static let s${k}: CGFloat = ${v}`);
  L.push('}');
  L.push('');
  L.push('enum Radius {');
  for (const [k, v] of Object.entries(t.radius)) L.push(`    nonisolated static let ${k}: CGFloat = ${v}`);
  L.push('}');
  return L.join('\n') + '\n';
}

function appleAccent(t) {
  const comp = (h) => {
    const [r, g, b] = rgb(h).map((v) => (v / 255).toFixed(3));
    return { 'color-space': 'srgb', components: { alpha: '1.000', blue: b, green: g, red: r } };
  };
  const p = t.color.brand.primary;
  const j = {
    colors: [
      { color: comp(p.light), idiom: 'universal' },
      { appearances: [{ appearance: 'luminosity', value: 'dark' }], color: comp(p.dark), idiom: 'universal' },
    ],
    info: { author: `design-tokens (${NOTE})`, version: 1 },
  };
  return JSON.stringify(j, null, 2) + '\n';
}

// ---- Android -------------------------------------------------------------

const argb = (h) => `0xFF${hex6(h)}`;

function androidColor(t, pkg) {
  const L = [`// Design tokens, ${NOTE}:`, '// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.', `package ${pkg}`, '', 'import androidx.compose.ui.graphics.Color', ''];
  L.push('// --- BRAND tokens (UI chrome only, never content meaning) ---');
  for (const c of colors(t).filter((c) => c.kind === 'brand')) {
    L.push(`val Brand${pascal(c.name)}Light = Color(${argb(c.light)})`);
    L.push(`val Brand${pascal(c.name)}Dark = Color(${argb(c.dark)})`);
  }
  L.push('');
  L.push('// --- SEMANTIC tokens (content only, never chrome) ---');
  L.push('// Read them through AppSemantics (Theme.kt), never through colorScheme, so');
  L.push('// Material You dynamic color can never change what they mean.');
  const sem = colors(t).filter((c) => c.kind === 'semantic');
  L.push('data class SemanticColors(');
  for (const c of sem) L.push(`    val ${c.name}: Color,`);
  L.push(')');
  for (const mode of ['light', 'dark']) {
    L.push('');
    L.push(`val ${pascal(mode)}SemanticColors = SemanticColors(`);
    for (const c of sem) L.push(`    ${c.name} = Color(${argb(c[mode])}),`);
    L.push(')');
  }
  L.push('');
  L.push('object Spacing {');
  for (const [k, v] of Object.entries(t.space)) L.push(`    const val S${k} = ${v} // dp`);
  L.push('}');
  L.push('');
  L.push('object Radius {');
  for (const [k, v] of Object.entries(t.radius)) L.push(`    const val ${pascal(k)} = ${v} // dp`);
  L.push('}');
  return L.join('\n') + '\n';
}

function androidType(t, pkg) {
  const L = [`// Design tokens, ${NOTE}:`, '// change design-tokens.json at the repository root and run `node tools/design_tokens.mjs`.', `package ${pkg}`, ''];
  L.push('import androidx.compose.material3.Typography');
  L.push('import androidx.compose.ui.text.TextStyle');
  L.push('import androidx.compose.ui.text.font.FontFamily');
  L.push('import androidx.compose.ui.text.font.FontWeight');
  L.push('import androidx.compose.ui.unit.sp');
  L.push('');
  L.push('// The system face. A custom face goes in res/font/ and replaces this line by');
  L.push('// hand only if the chosen look truly needs one; keep fonts out of the splash path.');
  L.push('private val BrandFontFamily = FontFamily.Default');
  L.push('');
  L.push('/** The six-level ramp: refuse a seventh level; refactor instead. */');
  L.push('val AppTypography = Typography(');
  for (const l of t.type) {
    const extra = l.mono ? ', fontFeatureSettings = "tnum"' : '';
    L.push(`    ${l.android} = TextStyle(fontFamily = BrandFontFamily, fontWeight = FontWeight.${WEIGHT.kotlin(l.weight)}, fontSize = ${l.size}.sp${extra}), // ${l.level} ${l.id}`);
  }
  L.push(')');
  return L.join('\n') + '\n';
}

function androidColorsXml(t, mode) {
  const b = t.color.brand;
  return [
    '<?xml version="1.0" encoding="utf-8"?>',
    `<!-- Design tokens (${mode}), ${NOTE}. -->`,
    '<!-- Compose reads Color.kt; these serve themes.xml (the splash) and the launcher icon. -->',
    '<resources>',
    `    <color name="brand_primary">#FF${hex6(b.primary[mode])}</color>`,
    `    <color name="brand_background">#FF${hex6(b.background[mode])}</color>`,
    `    <color name="brand_surface">#FF${hex6(b.surface[mode])}</color>`,
    '</resources>',
    '',
  ].join('\n');
}

// ---- Windows -------------------------------------------------------------

function windowsResources(t) {
  const L = ['<ResourceDictionary.ThemeDictionaries>'];
  for (const [mode, key] of [['light', 'Light'], ['dark', 'Dark']]) {
    L.push(`    <ResourceDictionary x:Key="${key}">`);
    for (const c of colors(t)) {
      const n = (c.kind === 'brand' ? 'Brand' : 'Semantic') + pascal(c.name);
      L.push(`        <Color x:Key="${n}">#${hex6(c[mode])}</Color>`);
      L.push(`        <SolidColorBrush x:Key="${n}Brush" Color="#${hex6(c[mode])}"/>`);
    }
    const p = t.color.brand.primary[mode];
    L.push(`        <SolidColorBrush x:Key="BrandPrimaryHoverBrush" Color="${mixBlack(p, 0.1)}"/>`);
    L.push(`        <SolidColorBrush x:Key="BrandPrimaryPressedBrush" Color="${mixBlack(p, 0.2)}"/>`);
    L.push(`        <SolidColorBrush x:Key="BrandPrimaryDisabledBrush" Color="#66${hex6(p)}"/>`);
    L.push('    </ResourceDictionary>');
  }
  L.push('</ResourceDictionary.ThemeDictionaries>');
  for (const [k, v] of Object.entries(t.space)) L.push(`<x:Double x:Key="Space${k}">${v}</x:Double>`);
  for (const [k, v] of Object.entries(t.radius)) L.push(`<CornerRadius x:Key="Radius${pascal(k)}">${v}</CornerRadius>`);
  return L;
}

function windowsStyles(t) {
  const L = [`<sty:FluentAvaloniaTheme CustomAccentColor="#${hex6(t.color.brand.primary.light)}" />`, ''];
  L.push('<!-- The six-level type ramp, adopted via Classes. Refuse a seventh level. -->');
  for (const l of t.type) {
    L.push(`<Style Selector="TextBlock.${l.windows}"> <!-- ${l.level} ${l.id} -->`);
    L.push(`    <Setter Property="FontSize" Value="${l.size}"/>`);
    L.push(`    <Setter Property="FontWeight" Value="${WEIGHT.axaml(l.weight)}"/>`);
    if (l.mono) L.push(`    <Setter Property="FontFamily" Value="${t.font.mono.windows}"/>`);
    if (l.id === 'caption') L.push('    <Setter Property="Foreground" Value="{DynamicResource BrandTextMutedBrush}"/>');
    L.push('</Style>');
  }
  return L;
}

// ---- the target list ------------------------------------------------------

// The Android theme folder follows the app's package, which each app renames,
// so find it: the one folder under java/ that ends in ui/theme and holds Theme.kt.
function androidTheme(root) {
  const base = 'android/app/src/main/java';
  const walk = (rel) => {
    let entries;
    try { entries = readdirSync(join(root, rel), { withFileTypes: true }); } catch { return null; }
    if (rel.endsWith('/ui/theme') && entries.some((e) => e.name === 'Theme.kt')) return rel;
    for (const e of entries) if (e.isDirectory()) { const f = walk(`${rel}/${e.name}`); if (f) return f; }
    return null;
  };
  const dir = walk(base);
  if (!dir) throw new Error(`${base}: no ui/theme folder with a Theme.kt in it`);
  return { dir, pkg: dir.slice(base.length + 1).replaceAll('/', '.') };
}

// The Windows app folder is renamed with the app too (AppName.App).
function windowsApp(root) {
  let entries = [];
  try { entries = readdirSync(join(root, 'windows'), { withFileTypes: true }); } catch { return null; }
  const app = entries.find((e) => e.isDirectory() && e.name.endsWith('.App'));
  return app ? `windows/${app.name}` : null;
}

// A platform the app does not ship (a deleted android/, windows/, or tv/
// folder) is skipped rather than recreated: `platform` names the folder whose
// absence means "not adopted".
export function targets(t, root = ROOT) {
  const has = (dir) => existsSync(join(root, dir));
  const android = has('android') ? androidTheme(root) : null;
  const win = windowsApp(root);
  const list = [
    { path: 'css/styles.css', edit: (s, f) => cssBlock(s, f, '', webStyles(t)) },
    { path: 'index.html', edit: (s, f) => xmlBlock(s, f, '', themeColorMeta(t)) },
    { path: 'manifest.json', edit: (s) => setJsonFields(s, { background_color: t.color.brand.background.light.toUpperCase(), theme_color: t.color.brand.background.light.toUpperCase() }) },
    { path: 'tv.css', edit: (s, f) => cssBlock(s, f, '', tvCss(t)) },
    { path: 'cast/index.html', edit: (s, f) => cssBlock(s, f, '', castCss(t)) },
    { path: 'tv/webos/appinfo.json', edit: (s) => setJsonFields(s, { bgColor: t.color.brand.background.dark.toUpperCase(), iconColor: t.color.brand.primary.dark.toUpperCase() }) },
    { path: 'apple/Core/Design.swift', whole: () => appleDesign(t) },
    { path: 'apple/Assets.xcassets/AccentColor.colorset/Contents.json', whole: () => appleAccent(t) },
    ...(android ? [
      { path: `${android.dir}/Color.kt`, whole: () => androidColor(t, android.pkg) },
      { path: `${android.dir}/Type.kt`, whole: () => androidType(t, android.pkg) },
    ] : []),
    { path: 'android/app/src/main/res/values/colors.xml', whole: () => androidColorsXml(t, 'light') },
    { path: 'android/app/src/main/res/values-night/colors.xml', whole: () => androidColorsXml(t, 'dark') },
    ...(win ? [
      { path: `${win}/App.axaml`, edit: (s, f) => xmlBlock(xmlBlock(s, f, 'resources', windowsResources(t)), f, 'styles', windowsStyles(t)) },
      { path: `${win}/AppxManifest.xml`, edit: (s, f) => setPattern(s, f, /(<uap:SplashScreen [^>]*BackgroundColor=")(#[0-9A-Fa-f]{6})(")/, '#' + hex6(t.color.brand.primary.light)) },
    ] : []),
  ];
  return list.filter((tg) => has(tg.path.split('/')[0]));
}

export function loadTokens(root = ROOT) {
  return JSON.parse(readFileSync(join(root, 'design-tokens.json'), 'utf8'));
}

const read = (p) => { try { return readFileSync(p, 'utf8'); } catch { return null; } };

/** [{ path, current, expected }] for every target, written nowhere. */
export function plan(root = ROOT, tokens = loadTokens(root)) {
  return targets(tokens, root).map((tg) => {
    const full = join(root, tg.path);
    const current = read(full);
    let expected;
    if (tg.whole) expected = tg.whole();
    else if (current === null) throw new Error(`${tg.path}: file is missing`);
    else expected = tg.edit(current, tg.path);
    return { path: tg.path, current, expected };
  });
}

function main() {
  const check = process.argv.includes('--check');
  const results = plan();
  const stale = results.filter((r) => r.current !== r.expected);
  if (check) {
    for (const r of results) console.log(`  ${stale.includes(r) ? 'FAIL' : 'ok  '}  ${r.path}`);
    if (stale.length) {
      console.log(`\n${stale.length} file(s) differ from design-tokens.json. Change design-tokens.json, then run: node tools/design_tokens.mjs`);
      process.exit(1);
    }
    return;
  }
  for (const r of stale) {
    mkdirSync(dirname(join(ROOT, r.path)), { recursive: true });
    writeFileSync(join(ROOT, r.path), r.expected);
    console.log(`  wrote  ${r.path}`);
  }
  console.log(stale.length ? `${stale.length} file(s) written.` : 'Every platform already matches design-tokens.json.');
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
