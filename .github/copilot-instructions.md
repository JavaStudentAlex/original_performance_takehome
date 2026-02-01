# Copilot Instructions

## Purpose

This repo is a performance-optimization take-home for a simulated **VLIW SIMD** machine. Use these instructions to stay grounded in the repo's constraints, keep changes minimal and correct, and avoid long/verbose outputs during extended work.

---

## How to use this file

- Treat this file as the **top-level contract** for how you work in this repo.
- Treat **VLIW.md** as the **theory / optimization playbook** and reference it instead of duplicating it.
- Treat **tests/** as **immutable** ground truth for correctness.

---

<instructions>
- ALWAYS follow <answering_rules> and <self_reflection>.
- Before answering, internally rewrite the user request into sections: Task, Expected Outcome, Constraints, Context.
  - Use this rewrite to plan your answer.
  - Do NOT output the rewritten prompt unless the user explicitly asks for it.
</instructions>

<self_reflection>
1. Create a 5-7 item internal rubric (correctness, grounding in repo constraints, minimal diffs, performance impact, clarity, safety).
2. Iterate privately until the solution would score >=98/100 on that rubric.
3. Never reveal the rubric or internal iteration notes unless explicitly requested.
</self_reflection>

<role>AI Assistant</role>
<detailed_topic>VLIW SIMD kernel optimization and static scheduling</detailed_topic>

<answering_rules>
1. Use the language of the user's message.
2. Internally adopt an expert role appropriate to <detailed_topic>; do not announce it in the response.
3. Be precise: answer only what was asked, and keep outputs short by default.
4. No tables unless explicitly requested.
5. No action items unless explicitly requested.
6. Prefer repo-specific contracts and constraints over generic best practices.
7. When proposing code changes, prefer small, reviewable diffs and preserve existing style.
8. If you are uncertain about repo behavior, consult: README.md, problem.py, tests/submission_tests.py, and VLIW.md.
</answering_rules>

---

## Repo ground truth

**Files and what to do with them**

| File | Purpose | Editable |
|------|---------|----------|
| `perf_takehome.py` | Main file to edit (KernelBuilder implementation / optimized kernel) | Yes |
| `problem.py` | Simulator + reference kernel; treat as ground truth | No (unless user asks) |
| `tests/frozen_problem.py` | Frozen test infrastructure | No |
| `tests/submission_tests.py` | Submission validation tests | No |
| `VLIW.md` | Optimization theory and tactics (memory bottleneck, predication, pipelining, vectorization) | Reference only |
| `watch_trace.py` / `watch_trace.html` | Trace visualization tooling | Read-only |

---

## Environment

- Python **3.13+**
- Dependencies: `numpy>=2.4.1`
- No build system; pure Python simulation.

---

## Architecture constraints (high level)

| Resource | Limit per cycle | Notes |
|----------|-----------------|-------|
| ALU slots | 12 | Abundant compute capacity |
| VALU slots | 6 | 6 ops x 8 lanes = 48 element-ops/cycle |
| LOAD slots | 2 | **Critical bottleneck** |
| STORE slots | 2 | Secondary bottleneck |
| FLOW slots | 1 | Single branch per cycle |

**Key constraints:**

- **2 loads/cycle is the bottleneck** - optimize memory traffic and hide latency.
- **No branch prediction** - avoid unpredictable branches; use `select` / `vselect` or arithmetic if-conversion where possible.
- **End-of-cycle writes** - reads happen before writes within a cycle (enables aggressive scheduling patterns).
- **Scratchpad size: 1536 words** - manage scratch allocation carefully for unrolling/pipelining.
- **VLEN = 8 elements** - 8-wide SIMD vectors.

For detailed optimization tactics (software pipelining, unroll-and-jam, if-conversion, gather patterns, scratchpad allocation heuristics), see **VLIW.md**.

---

## Correctness contracts

- The kernel must match the reference behavior in `problem.py` / `reference_kernel2`.
- Treat the memory header layout (rounds, n_nodes, batch_size, pointers, etc.) as authoritative.
- All arithmetic is **mod 2^32** (per ISA rules).

---

## Development workflow

- **Correctness check**: run `python tests/submission_tests.py`
- **Performance measurement**: use the repo's benchmark commands from README.md / tests.
- **Debugging**: prefer trace-based debugging (`test_kernel_trace` + `watch_trace.py`) over printing per-cycle logs.

---

## Output and logging discipline

This is important for maintaining context in long sessions:

- Avoid dumping large traces or per-cycle instruction logs into the terminal/chat.
- If you must capture verbose output, write it to a file and summarize in chat.
- Keep responses focused on the smallest change that moves correctness/perf forward.

---

## Optimization priorities (summary)

1. **Memory bandwidth first** (LOAD slots are the bottleneck)
2. **Then vectorization** (VALU utilization)
3. **Then scheduling** (instruction-level parallelism)

**Key tactics:**

- Prefer branchless/predicated control flow for traversal decisions.
- Use scratchpad strategically for reused values / caching; avoid unnecessary spills.
- Software pipeline to hide memory latency.
- Batch operations to maximize load slot utilization.

Refer to **VLIW.md** for proven tactics and theoretical foundations.
