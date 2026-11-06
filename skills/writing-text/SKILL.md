---
name: writing-text
description: Rules that make any text easy to scan and easy to read, whatever it is - a chat message, a commit message, a PR description, a ticket, a doc, a blog post or article, a Claude artifact. Gives the shape of the text (conclusion first, short paragraphs, lists and tables where the content has that shape), the limits per channel, the extra rules for long articles, and a script that audits a markdown file. Use before writing or rewriting prose that another person will read, and when a text is called hard to read.
---

# Writing text

Readers scan first and read second. In Nielsen Norman Group's study of web reading, 79% of test users scanned a page and 16% read word by word. A scannable layout measured +47% usability, concise text +58%, objective tone +27%, and all three together +124%. So shape the text for scanning, then make each sentence easy to read.

Next action: name the reader and the channel, take the rules for that channel from "By channel", write the conclusion first, then run the checklist at the end. For a markdown file longer than a screen, run the audit script too.

## Rules for every text

1. **Conclusion first.** The first one or two sentences say what happened, what you need or what the result is. Background comes after.
2. **One idea per paragraph,** one to three sentences. A new idea is a new paragraph.
3. **One idea per sentence,** under about 25 words. Split at "and", "which", a semicolon or a long parenthesis.
4. **Three or more parallel items are a list.** Steps in an order are a numbered list. Never string three or more items together with commas inside a sentence.
5. **Data with three or more attributes per row is a table,** introduced by one sentence. A table with one column is a list.
6. **Start a point with its key phrase.** In a document, bold it when the reader will scan.
7. **Name a thing once and keep the name.** Spell out an abbreviation on first use.
8. **Concrete over abstract.** A number, a path, a command or a name instead of "some" and "various".
9. **No filler.** Cut an opening that repeats the question, a closing that repeats the text, and hedges stacked on one claim.
10. **Say what you know and what you do not.** A guess is labelled as a guess.

## By channel

| Channel | Shape |
|---|---|
| Chat message (Slack, Telegram, e-mail) | What is going on, then what is asked, then what is already done. A link or reference alone on the last line. No headings. A list only for truly parallel items. |
| Commit message | Subject in the imperative, up to about 70 characters. A body that says why, not what the diff already shows. |
| PR description or ticket | Summary of what and why in one to three sentences. Changes as a list. How it was verified. Links. |
| Doc, README, runbook | Title, then a summary. A contents list once it passes about 1,000 words. H2 sections, numbered steps, code blocks that name the language. |
| Article or blog post | The long-form rules below. |
| Claude artifact or HTML page | The doc rules. The conclusion sits in the first screen. Real headings and tables, not styled text. A chart has a title that states the takeaway and labelled axes. |

Do not hard-wrap prose in files, PR bodies and commit bodies. A paragraph is one physical line, and the renderer reflows it.

## Long-form rules (articles, and docs over about 1,000 words)

Structure:

- The title is H1 and states the result, not only the topic. Headings start at H2, skip no level, and say what the section contains.
- A summary block of three to five bullets follows the intro.
- A contents list with anchor links follows the summary once the text passes about 1,000 to 1,500 words.
- Sections stay short. A section over about 400 words is split or its raw data is collapsed.

Content:

- Start list items with a bold lead-in, such as "**Result:** ...", so a scan shows the structure.
- Long raw data (a full table, a log) goes into a collapsible block or a linked file. The body carries the summary.
- Code is fenced and names its language. Do not use a screenshot of code. When it is longer than about 15 lines, describe it in a sentence and link or collapse it.
- Alt text says what the image shows and what to take from it, not "image of". When the platform shrinks images, link the full-size file.

Platform notes:

- dev.to: headings start at H2. Raw `<details>` is stripped, so use the liquid tag `{% details Title %}` ... `{% enddetails %}`, with blank lines around a table inside it. Heading anchors are `#lowercase-with-dashes`. The cover image is 1000 by 420 pixels. Inline images are capped at 800 pixels wide and are copied to the platform's own storage on save. Up to four tags. AI assistance must be disclosed: the toggle plus a closing line. Preview before you publish.
- GitHub markdown: `<details><summary>` works, and so do task lists and tables.

## Sentence level

Aim for ARI grade 7 or lower, the formula behind the Hemingway app:

`ARI = 4.71 * (characters / words) + 0.5 * (words / sentences) - 21.43`

Short words and short sentences lower it. Keep the technical terms, simplify everything around them. Prefer the active voice. Do not bend a sentence out of shape to hit the number: meaning wins.

## The audit script

`node scripts/readability.mjs <file.md>` (path relative to this skill's folder; Node 18 or newer, no dependencies) prints the word count, reading time, ARI grade, heading levels, paragraphs over three sentences, sentences of 25 words or more, list items over 35 words, single-item lists, tables without an intro sentence, image alt text and the size of every H2 section. Under "Flags", `none` is a pass. Fix the flags, run it again, and stop when it passes.

## Checklist before you send

- The first sentence holds the point.
- No paragraph over three sentences, no sentence over about 25 words.
- Every run of three or more items is a list, and every table has an intro sentence.
- Every abbreviation is spelled out once, and every number has its unit.
- Every image has alt text that says what it shows.
- Long raw data is collapsed or linked.
- Every claim that is a guess says so.
- For a published article: AI disclosure set, preview checked, no personal data in the text.

## Sources

- DEV, "Best practices for writing on DEV: formatting", and "Guidelines for AI-assisted articles on DEV".
- Google developer documentation style guide, lists and tables.
- Nielsen Norman Group, "How users read on the web".
