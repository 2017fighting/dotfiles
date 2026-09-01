---
name: pdf2md
description: Convert PDF files to clean Markdown via the pdf2md CLI. Use whenever a task needs the contents of a PDF — reading, quoting, or answering questions about it — or converting a PDF to Markdown.
---

# pdf2md

Fast PDF → Markdown extraction built for agents: tables become Markdown tables, output is token-efficient.

## Standard extraction

```bash
pdf2md input.pdf output.md --compact
```

Name the output `<pdf-stem>.md` next to the source. The file contains pure Markdown; diagnostics (PDF type, page count, per-page tables/columns, timing) go to stderr.

Done when the `.md` exists — then read it with pagination (`offset`/`limit`) instead of dumping the whole file into context.

Small PDFs (< 20 pages or < 100 KB) can skip the file and read stdout directly:

```bash
pdf2md input.pdf --raw --compact
```

## Empty or garbled output

Check the PDF type first:

```bash
pdf2md input.pdf --detect-only
```

- **text_based / mixed** → extraction works; re-run with `--pages` to see per-page output if something looks off.
- **scanned** → dead end: this build ships without OCR (`--ocr` exits with an error). Report that the PDF needs OCR and stop — re-extracting produces nothing.

## Flags

| flag | effect |
|---|---|
| `--compact` | collapse token-heavy formatting (dot leaders) — default for agent use |
| `--raw` | markdown only on stdout; diagnostics and output file are both ignored |
| `--pages` | insert `<!-- Page N -->` markers — use when citing page numbers |
| `--select-pages 1,3-5` | extract a page subset — sample a long PDF before committing to it |
| `--json` | one JSON object with type, page count, markdown, and warnings |
| `--items-json` | positioned text items — for coordinate-level analysis only |
| `--password PW` | encrypted PDFs |

## Environment

`pdf2md` is on PATH via mise. If a shell cannot find it, use `/root/.local/share/mise/installs/cargo-pdf-inspector/latest/bin/pdf2md`.

There is no `--help` — a non-file argument is treated as a path and fails with an IO error.
