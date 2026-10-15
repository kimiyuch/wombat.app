// Draws the Wombat icon: a wombat peeking over a Mac drive with the kimiyu bear
// debossed on its front, like the Apple logo on the macOS drive icon, on a dusky indigo square.
// Writes the SVGs to artwork/ and renders the PNGs with headless Chrome (no npm packages needed).
// Usage: node scripts/make-icon.mjs
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = new URL("../", import.meta.url).pathname;
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// The kimiyu studio bear (copied from kimiyu.web), recoloured in greys like the logo on an aluminium drive.
const greys = {
  "#9d6b45": "#98989f", // ears, head
  "#e3bb92": "#a9a9b0", // inside the ears
  "#ddb487": "#a6a6ad", // snout
  "#292929": "#7a7a81", // eyes, nose, mouth
  "#fcfbfc": "#98989f", // eye highlights blend into the head
};
const bearSource = readFileSync(root + "artwork/kimiyu-bear.svg", "utf8");
const bear = bearSource
  .replace(/^[\s\S]*?<svg[^>]*>|<\/svg>\s*$/g, "")
  .replace(/<!--.*?-->/g, "")
  .replace(/fill="(#[0-9a-f]{6})"/gi, (match, hex) => `fill="${greys[hex.toLowerCase()] ?? "#9c9ca2"}"`);

const defs = `
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#6d66a8"/><stop offset="1" stop-color="#1d1b31"/></linearGradient>
    <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".2"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <linearGradient id="fur" gradientUnits="userSpaceOnUse" x1="0" y1="200" x2="0" y2="620"><stop offset="0" stop-color="#a88d78"/><stop offset="1" stop-color="#76604f"/></linearGradient>
    <linearGradient id="muzzle" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#c8b29d"/><stop offset="1" stop-color="#a68c76"/></linearGradient>
    <linearGradient id="nose" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4a3b34"/><stop offset="1" stop-color="#231b18"/></linearGradient>
    <linearGradient id="case" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#85858c"/><stop offset=".025" stop-color="#a9a9b0"/><stop offset=".06" stop-color="#eeeef2"/><stop offset=".1" stop-color="#d8d8dd"/><stop offset=".5" stop-color="#d2d2d7"/><stop offset=".9" stop-color="#d8d8dd"/><stop offset=".94" stop-color="#eeeef2"/><stop offset=".975" stop-color="#a9a9b0"/><stop offset="1" stop-color="#85858c"/></linearGradient>
    <linearGradient id="caseShade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".35"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#5a5a66" stop-opacity=".18"/></linearGradient>
    <linearGradient id="foot" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9c9ca3"/><stop offset=".45" stop-color="#7d7d85"/><stop offset="1" stop-color="#5f5f68"/></linearGradient>
    <linearGradient id="footSides" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#3c3c44" stop-opacity=".55"/><stop offset=".06" stop-color="#3c3c44" stop-opacity="0"/><stop offset=".1" stop-color="#fff" stop-opacity=".12"/><stop offset=".9" stop-color="#fff" stop-opacity=".12"/><stop offset=".94" stop-color="#3c3c44" stop-opacity="0"/><stop offset="1" stop-color="#3c3c44" stop-opacity=".55"/></linearGradient>
    <filter id="deboss" x="-10%" y="-10%" width="120%" height="120%"><feDropShadow dx="0" dy="3" stdDeviation="1.5" flood-color="#fff" flood-opacity=".7"/></filter>
    <filter id="drop" x="-20%" y="-20%" width="140%" height="160%"><feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#0b0a1a" flood-opacity=".35"/></filter>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#0b0a1a" flood-opacity=".3"/></filter>
    <filter id="icon" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity=".3"/></filter>
    <clipPath id="squircle"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>`;

const background = `
  <rect width="1024" height="1024" fill="url(#bg)"/>
  <rect width="1024" height="560" fill="url(#sheen)"/>`;

// The wombat behind the drive, the drive with its foot and the bear on its front, then the paws on its top edge.
// Both scale around the drive's top edge, so the paws stay on it; the shift re-centres the pair in the square.
const wombatScale = 1.12;
const driveScale = 0.86;
const artShift = 14;
const art = `

  <g transform="translate(0 ${artShift})">
  <g transform="translate(512 470) scale(${wombatScale}) translate(-512 -470)">
  <g class="wombat">
    <g filter="url(#soft)">
      <path d="M338 262c-20-40-12-80 12-88 24-8 56 16 72 52z" fill="url(#fur)"/>
      <path d="M686 262c20-40 12-80-12-88-24-8-56 16-72 52z" fill="url(#fur)"/>
      <ellipse cx="512" cy="356" rx="226" ry="156" fill="url(#fur)"/>
      <ellipse cx="512" cy="430" rx="238" ry="104" fill="url(#fur)"/>
    </g>
    <path d="M354 246c-10-24-6-46 8-52 14-4 30 10 40 32z" fill="#c9a08c"/>
    <path d="M670 246c10-24 6-46-8-52-14-4-30 10-40 32z" fill="#c9a08c"/>
    <ellipse cx="512" cy="426" rx="150" ry="82" fill="url(#muzzle)"/>
    <g class="eyes">
      <g fill="#1d1a1c"><ellipse cx="416" cy="334" rx="20" ry="23"/><ellipse cx="608" cy="334" rx="20" ry="23"/></g>
      <g fill="#fff"><circle cx="423" cy="325" r="7"/><circle cx="615" cy="325" r="7"/></g>
    </g>
    <path d="M424 384q88-30 176 0 12 52-24 74-64 24-128 0-36-22-24-74z" fill="url(#nose)"/>
    <path d="M458 390q54-14 108 0" fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round" opacity=".28"/>
    <g fill="none" stroke="#120d0b" stroke-width="9" stroke-linecap="round" opacity=".55"><path d="M462 436q14 8 30 4M562 436q-14 8-30 4"/></g>
  </g>

  </g>
  <g transform="translate(512 470) scale(${driveScale}) translate(-512 -470)">
  <g filter="url(#drop)">
    <rect x="280" y="836" width="464" height="92" rx="42" fill="url(#foot)"/>
    <path d="M326 470h372a34 34 0 0 1 34 34v370H292V504a34 34 0 0 1 34-34z" fill="url(#case)"/>
  </g>
  <path d="M326 470h372a34 34 0 0 1 34 34v370H292V504a34 34 0 0 1 34-34z" fill="url(#caseShade)"/>
  <path d="M328 474h368a30 30 0 0 1 30 30" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" opacity=".8"/>
  <rect x="280" y="836" width="464" height="92" rx="42" fill="url(#foot)"/>
  <rect x="280" y="836" width="464" height="92" rx="42" fill="url(#footSides)"/>
  <path d="M318 840h388a38 38 0 0 1 34 22" fill="none" stroke="#d4d4da" stroke-width="4" stroke-linecap="round" opacity=".7"/>

  <g filter="url(#deboss)" transform="translate(512 668) scale(0.22) translate(-627 -632)">${bear}</g>

  </g>
  <g transform="translate(512 470) scale(${wombatScale}) translate(-512 -470)">
  <g fill="#6a5545">
    <ellipse cx="420" cy="476" rx="50" ry="32"/><ellipse cx="604" cy="476" rx="50" ry="32"/>
  </g>
  <g fill="none" stroke="#e9ddd0" stroke-width="6" stroke-linecap="round" opacity=".8">
    <path d="M400 488v13M420 490v13M440 488v13M584 488v13M604 490v13M624 488v13"/>
  </g>
  </g>
  </g>`;

const svg = (viewBox, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">\n  <defs>${defs}\n  </defs>${body}\n</svg>\n`;

// Rounded square on transparent with a shadow, on the macOS icon grid like the siblings': the app icon, favicon, README.
const rounded = svg("0 0 1024 1024", `
  <rect x="100" y="100" width="824" height="824" rx="185" fill="#2e2b4c" filter="url(#icon)"/>
  <g clip-path="url(#squircle)"><g transform="translate(100 100) scale(0.8047)">${background}${art}</g></g>`);
// Full-bleed square for the apple-touch-icon (iOS rounds the corners itself).
const square = svg("0 0 1024 1024", background + art);
// The wombat and its drive without a background.
const mascot = svg("150 120 724 800", art);

mkdirSync(root + "artwork", { recursive: true });
writeFileSync(root + "artwork/icon.svg", rounded);
writeFileSync(root + "artwork/icon-square.svg", square);
writeFileSync(root + "artwork/mascot.svg", mascot);

const renders = [
  [rounded, "artwork/icon.png", 1024],
  [square, "artwork/icon-square.png", 1024],
  [mascot, "artwork/mascot.png", 800],
];
const work = mkdtempSync(join(tmpdir(), "wombat-icon-"));
for (const [source, out, size] of renders) {
  const page = join(work, "page.html");
  writeFileSync(page, `<style>html,body{margin:0;background:transparent}svg{display:block;width:${size}px;height:${size}px}</style>${source}`);
  execFileSync(chrome, [
    "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
    `--window-size=${size},${size}`, "--default-background-color=00000000",
    `--user-data-dir=${join(work, "profile")}`, `--screenshot=${root + out}`, `file://${page}`,
  ], { stdio: "ignore" });
  console.log(out);
}
