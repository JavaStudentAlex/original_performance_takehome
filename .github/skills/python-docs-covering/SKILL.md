---
name: python-docs-covering
description: Ensures Python documentation coverage by adding or improving docstrings (and related docs) to meet the repo’s doc-coverage requirements, while preserving code behavior.
---
# Python Docstrings Guidance (VLIW SIMD take-home)

## Overview

This repository is a performance-optimization take-home for a simulated **VLIW SIMD** machine.

- `.github/copilot-instructions.md` is the **top-level contract** for repo work.
- `VLIW.md` is the **optimization playbook** (reference it instead of duplicating it).
- `tests/` and `problem.py` are the **ground truth** for correctness.

This document exists to keep docstrings **consistent, small, and useful** when modifying Python code (typically `perf_takehome.py`). It does **not** introduce new repo requirements.

## When to add or edit docstrings

Add (or update) a docstring when you:

- Introduce a new public function/class that will be called from multiple places.
- Add non-obvious logic (e.g., scratchpad layout, bundling rules, modulo scheduling trick, or a correctness subtlety around end-of-cycle semantics).
- Change a function signature (keep parameters/returns accurate).

Skip docstrings for:

- One-off local helpers that are obvious from the name and a few lines of code.
- Tight inner-loop code where long docstrings would drown the actual logic.

## Style

Keep docstrings:

- **Short first line**: one sentence describing what the function does.
- **Optional Notes**: only if there's a subtle invariant or assumption.
- **Avoid repetition**: don't restate architecture theory - point to `VLIW.md`.

Prefer plain PEP 257 style unless a function genuinely benefits from structured sections.

### Examples

Module docstring (only if it adds value beyond the filename):

```python
"""Optimized kernel builder for the VLIW SIMD simulator.

Notes
-----
- Correctness is validated against the reference behavior in `problem.py`.
- Performance work should follow `VLIW.md` and repo constraints in `.github/copilot-instructions.md`.
"""
```

Function docstring with a key invariant:

```python
def emit_kernel(...):
    """Emit a scheduled kernel for the simulator.

    Notes
    -----
    - All arithmetic is mod 2**32 per ISA rules.
    - Scheduling assumes end-of-cycle write semantics (reads happen before writes).
    """
    ...
```

A minimal test docstring (only if your tooling checks tests too):

```python
def test_kernel_matches_reference():
    """Kernel output matches reference for the fixed test vectors."""
    ...
```

## Optional: docstring coverage checks

This repo's contract does **not** currently define a documentation-coverage gate.

If you *choose* to enforce docstring presence in your own workflow (locally or in CI), `interrogate` is a reasonable tool. Use paths that match this repo (e.g., `perf_takehome.py` and `tests/`). Example:

```bash
interrogate -v perf_takehome.py tests
```

If you later decide on a threshold, configure it explicitly (e.g., in `.interrogate.ini` or `pyproject.toml`) so the rule is visible and stable.

## Consistency rules

- Don't contradict `.github/copilot-instructions.md` (minimal diffs, keep outputs small, tests are ground truth).
- Don't duplicate optimization guidance that belongs in `VLIW.md` - link to it instead.
- Keep docstrings accurate; stale docstrings are worse than none.
