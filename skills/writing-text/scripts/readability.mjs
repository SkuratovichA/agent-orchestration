// usage: node readability.mjs <file.md>   (Node 18 or newer, no dependencies; prints the metrics and a "Flags" list, "none" means a pass)
// Audits a markdown text against common readability criteria (the DEV formatting guide, the Google developer style guide, Nielsen Norman):
// heading levels, paragraph length in sentences, sentence length in words, ARI grade (the formula the Hemingway app uses), list items, tables introduced by a sentence, images with alt text, section sizes.
import { readFileSync } from 'node:fs'
const md = readFileSync(process.argv[2], 'utf8').replace(/\r/g, '')
const lines = md.split('\n')
const strip = (s) => s.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/[`*_]/g, '').replace(/<[^>]+>/g, '').trim()
const words = (s) => (strip(s).match(/[A-Za-z0-9$%][A-Za-z0-9$%'.,\-+/:<>=]*/g) || [])
const sentences = (s) => strip(s).split(/(?<=[.!?])\s+(?=[A-Z"(\[])/).filter((x) => x.trim())
const ari = (text) => { const w = words(text), s = sentences(text); if (!w.length || !s.length) return 0; const ch = w.join('').length; return 4.71 * (ch / w.length) + 0.5 * (w.length / s.length) - 21.43 }
const blocks = []
let cur = [], inCode = false, kind = null
const flush = () => { if (cur.length) blocks.push({ kind, text: cur.join('\n'), start: cur.start }); cur = []; kind = null }
lines.forEach((l, i) => {
  if (/^```/.test(l)) { flush(); inCode = !inCode; return }
  if (inCode) return
  if (!l.trim()) { flush(); return }
  const k = /^#{1,6}\s/.test(l) ? 'heading' : /^\s*[-*]\s/.test(l) ? 'ul' : /^\s*\d+\.\s/.test(l) ? 'ol' : /^\|/.test(l) ? 'table' : /^!\[/.test(l) ? 'image' : /^>/.test(l) ? 'quote' : /^</.test(l) ? 'html' : 'p'
  if (kind && kind !== k && !(kind === 'p' && k === 'p')) flush()
  if (!cur.length) { cur.start = i + 1; kind = k }
  cur.push(l)
})
flush()
const out = []
const flag = (m) => out.push(m)
const prose = blocks.filter((b) => b.kind === 'p')
const allProse = prose.map((b) => b.text).join(' ') + ' ' + blocks.filter((b) => b.kind === 'ul' || b.kind === 'ol').map((b) => b.text.replace(/^\s*([-*]|\d+\.)\s+/gm, '')).join('. ')
const nWords = words(allProse).length
console.log(`words in prose and lists: ${nWords}, reading time about ${Math.round(nWords / 230)} min, ARI grade ${ari(allProse).toFixed(1)} (Hemingway advice: 7 or below)`)
// headings
let last = 1
const heads = blocks.filter((b) => b.kind === 'heading').map((b) => ({ level: b.text.match(/^#+/)[0].length, text: b.text.replace(/^#+\s*/, ''), line: b.start }))
for (const h of heads) { if (h.level === 1) flag(`line ${h.line}: H1 in body (title is H1): ${h.text}`); if (h.level > last + 1) flag(`line ${h.line}: heading level jumps ${last} to ${h.level}: ${h.text}`); last = h.level }
console.log(`headings: ${heads.length} (H2 ${heads.filter((h) => h.level === 2).length}, H3 ${heads.filter((h) => h.level === 3).length}, deeper ${heads.filter((h) => h.level > 3).length})`)
// paragraphs and sentences
let longP = 0, longS = 0
for (const b of prose) {
  const ss = sentences(b.text)
  if (ss.length > 3) { longP++; flag(`line ${b.start}: paragraph of ${ss.length} sentences`) }
  for (const s of ss) { const n = words(s).length; if (n >= 25) { longS++; flag(`line ${b.start}: sentence of ${n} words: ${strip(s).slice(0, 90)}...`) } }
}
console.log(`paragraphs ${prose.length}, over 3 sentences ${longP}, sentences of 25 words or more ${longS}`)
// lists
const lists = blocks.filter((b) => b.kind === 'ul' || b.kind === 'ol')
let longItems = 0, singles = 0
for (const b of lists) {
  const items = b.text.split('\n').filter((l) => /^\s*([-*]|\d+\.)\s/.test(l))
  if (items.length < 2) { singles++; flag(`line ${b.start}: list with a single item`) }
  for (const it of items) { if (words(it).length > 35) { longItems++; flag(`line ${b.start}: list item of ${words(it).length} words: ${strip(it).slice(0, 80)}...`) } }
}
console.log(`lists ${lists.length}, single-item lists ${singles}, list items over 35 words ${longItems}`)
// tables introduced by a sentence
const idx = (b) => blocks.indexOf(b)
let bareTables = 0
for (const b of blocks.filter((x) => x.kind === 'table')) {
  const prev = blocks[idx(b) - 1]
  if (!prev || prev.kind === 'heading' || !/[.:]$/.test(prev.text.trim())) { bareTables++; flag(`line ${b.start}: table without an introducing sentence`) }
}
console.log(`tables ${blocks.filter((x) => x.kind === 'table').length}, without an intro sentence ${bareTables}`)
// images
for (const b of blocks.filter((x) => x.kind === 'image')) { const alt = b.text.match(/!\[([^\]]*)\]/)?.[1] || ''; if (alt.length < 20) flag(`line ${b.start}: image alt text too short`); if (/^(image|picture|screenshot) of/i.test(alt)) flag(`line ${b.start}: alt starts with "image of"`) }
// section sizes
let sec = null; const secs = []
for (const b of blocks) { if (b.kind === 'heading' && /^##\s/.test(b.text)) { sec = { title: b.text.replace(/^##\s*/, ''), words: 0 }; secs.push(sec) } else if (sec && b.kind !== 'table') sec.words += words(b.text).length }
console.log('H2 sections by size (words, tables excluded): ' + secs.map((s) => `${s.title} ${s.words}`).join(' | '))
for (const s of secs) if (s.words > 450) flag(`section "${s.title}" has ${s.words} words, consider splitting or collapsing`)
console.log(`has contents list after the intro: ${/^##\s+(Contents|Table of contents)/im.test(md)}; has summary block: ${/^##\s+(The short version|TL;DR|Summary)/im.test(md)}`)
console.log('\nFlags:\n' + (out.length ? out.join('\n') : 'none'))
