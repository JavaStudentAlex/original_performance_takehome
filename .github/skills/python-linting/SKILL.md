---
name: python-linting
description: Runs Python linters/formatters and applies minimal code changes to satisfy the project’s lint rules without altering behavior.
---
# Python Linting Skill

## Overview

This skill explains how to run and pass the repo's Python lint / type-check / docstring-style tooling (typically via **pre-commit**), while staying consistent with the repo's top-level contract in `.github/copilot-instructions.md`.

Key alignment points:
- **Correctness is validated by tests** (see `tests/submission_tests.py`). Linting helps keep changes clean and reviewable, but it does not replace `python tests/submission_tests.py`.
- Keep outputs small: if a lint run is verbose, redirect it to a file and summarize.

## When to use this skill

Use this skill when you:
- Modify `perf_takehome.py` (the main editable file)
- Add or change tests under `tests/`
- Touch any other Python module in the repo

## The five tools

The linting stack:

1. **isort** — import sorting  
2. **black** — formatting  
3. **flake8** — lint rules  
4. **mypy** — static typing  
5. **pydocstyle** — docstring style

The exact rules come from repo configuration (commonly `pyproject.toml`, `setup.cfg`, `.flake8`, `mypy.ini`, and/or `.pre-commit-config.yaml`). If no config is present, tools fall back to defaults.

## Command patterns

Run all commands from the repo root.

Incremental (fast, during development):

```bash
pre-commit run --files perf_takehome.py
pre-commit run --files perf_takehome.py tests/submission_tests.py
```

Comprehensive (before commit / handoff):

```bash
pre-commit run --all-files
```

If `pre-commit` is not available, run tools directly:

```bash
isort perf_takehome.py
black perf_takehome.py
flake8 perf_takehome.py
mypy perf_takehome.py
pydocstyle perf_takehome.py
```

Capture verbose output (recommended when logs are long):

```bash
pre-commit run --all-files > .lint.log 2>&1
```

## Pass criteria

All configured hooks/checks must exit with code **0**.

## Common fixes

### isort

Imports should be grouped as: **stdlib → third-party → first-party**.

If isort modifies files, rerun pre-commit (or commit the changes) and retry.

Example ordering:

```python
# stdlib
from typing import Optional

# third-party
import numpy as np

# first-party
from problem import reference_kernel2
```

### black

If black fails, run:

```bash
black <file>
```

### flake8

Common codes:
- `F401` unused import
- `F841` assigned-but-unused local
- `E501` line too long (wrap/extract)

### mypy

Common fixes:
- Add missing annotations (especially for public helpers)
- Handle `Optional[...]` explicitly (guard or raise)

### pydocstyle

Add short docstrings where required; keep them accurate and concise.

## Tool conflict resolution

If isort and black disagree, run **isort first**, then **black**:

```bash
isort <file> && black <file>
```

## Related resources

- `.github/copilot-instructions.md` — repo contract and correctness workflow
- `tests/submission_tests.py` — correctness validation entrypoint
