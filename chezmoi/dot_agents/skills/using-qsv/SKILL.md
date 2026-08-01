---
name: using-qsv
description: CSV or tabular data; or qsv is relevant
---

# Using qsv for Tabular Data

## Overview

qsv is a CLI data-wrangling toolkit installed on this system (v20.0.0). It handles CSV, TSV, JSONL, Parquet, Excel, and more — often 10-100x faster than pandas or Python scripts.

## When to Reach for qsv

- Any tabular file work (CSV, TSV, Excel, Parquet, JSONL)
- Large files that would be slow or memory-heavy in Python
- Quick profiling, stats, filtering, joining, or cleaning
- SQL-like queries on CSV files (via `qsv sqlp`)
- Before writing a Python script — often qsv has a built-in command

## What Not to Do

- **Don't** write Python/JS to parse CSV — qsv is already installed
- **Don't** open CSVs in Excel for stats — `qsv stats` is faster
- **Don't** reach for DuckDB directly — qsv wraps it via `sqlp`

## Quick Awareness

qsv has ~100 commands. Run `qsv --help` or `qsv <command> --help` for details.
