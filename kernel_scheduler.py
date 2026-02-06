"""VLIW instruction scheduler with dependency analysis and bundle formation.

Extracted from perf_takehome.py to separate scheduling concerns from kernel building.
"""

from collections import defaultdict
from typing import Any

from problem import SLOT_LIMITS, VLEN


class VLIWScheduler:
    """Static scheduler for VLIW instruction bundles with dependency analysis."""

    @staticmethod
    def build(slots: list[tuple[str, tuple[Any, ...]]], vliw: bool = False):
        """
        Pack operations into VLIW bundles respecting slot limits and dependencies.

        Parameters
        ----------
        slots : list of (engine, slot) tuples
            Operations to pack into instruction bundles.
        vliw : bool
            If True, use VLIW packing; otherwise one op per bundle.

        Returns
        -------
        list of dict
            Instruction bundles mapping engine names to slot lists.
        """
        if not vliw:
            instrs = []
            for engine, slot in slots:
                instrs.append({engine: [slot]})
            return instrs

        def get_writes(engine, slot):
            """Get scratch addresses written by this operation."""
            if engine == "debug":
                return set()
            if engine == "alu":
                return {slot[1]}
            if engine == "valu":
                if slot[0] == "vbroadcast":
                    return set(range(slot[1], slot[1] + VLEN))
                return set(range(slot[1], slot[1] + VLEN))
            if engine == "load":
                if slot[0] == "const":
                    return {slot[1]}
                elif slot[0] == "load":
                    return {slot[1]}
                elif slot[0] == "vload":
                    return set(range(slot[1], slot[1] + VLEN))
                elif slot[0] == "load_offset":
                    return {slot[1] + slot[3]}
            if engine == "store":
                return set()
            if engine == "flow":
                if slot[0] == "select":
                    return {slot[1]}
                elif slot[0] == "vselect":
                    return set(range(slot[1], slot[1] + VLEN))
                elif slot[0] == "add_imm":
                    return {slot[1]}
            return set()

        def get_reads(engine, slot):
            """Get scratch addresses read by this operation."""
            if engine == "debug":
                return set()
            if engine == "alu":
                return {slot[2], slot[3]}
            if engine == "valu":
                if slot[0] == "vbroadcast":
                    return {slot[2]}
                if slot[0] == "multiply_add":
                    reads: set[int] = set()
                    for base in [slot[2], slot[3], slot[4]]:
                        reads.update(range(base, base + VLEN))
                    return reads
                return set(range(slot[2], slot[2] + VLEN)) | set(range(slot[3], slot[3] + VLEN))
            if engine == "load":
                if slot[0] == "const":
                    return set()
                elif slot[0] in ("load", "vload"):
                    return {slot[2]}
                elif slot[0] == "load_offset":
                    return {slot[2] + slot[3]}
            if engine == "store":
                if slot[0] == "store":
                    return {slot[1], slot[2]}
                elif slot[0] == "vstore":
                    return {slot[1]} | set(range(slot[2], slot[2] + VLEN))
            if engine == "flow":
                if slot[0] == "select":
                    return {slot[2], slot[3], slot[4]}
                elif slot[0] == "vselect":
                    reads = {slot[2]}
                    reads.update(range(slot[3], slot[3] + VLEN))
                    reads.update(range(slot[4], slot[4] + VLEN))
                    return reads
                elif slot[0] == "add_imm":
                    return {slot[2]}
                elif slot[0] in ("cond_jump", "cond_jump_rel"):
                    return {slot[1]}
            return set()

        # List scheduling with lookahead
        instrs = []
        n = len(slots)
        scheduled = [False] * n

        # Precompute reads/writes for all ops
        op_reads = [get_reads(slots[i][0], slots[i][1]) for i in range(n)]
        op_writes = [get_writes(slots[i][0], slots[i][1]) for i in range(n)]

        # Build dependency graph: pred[i] = set of ops that must complete before i
        pred: list[set[int]] = [set() for _ in range(n)]
        last_write: dict[int, int] = {}  # addr -> op index that last wrote it

        for i in range(n):
            engine, slot = slots[i]
            if engine == "debug":
                continue
            # RAW: read after write - B reads what A wrote, so B depends on A
            for addr in op_reads[i]:
                if addr in last_write:
                    pred[i].add(last_write[addr])
            # WAW: write after write - B writes what A wrote, so B depends on A (to preserve order)
            for addr in op_writes[i]:
                if addr in last_write:
                    pred[i].add(last_write[addr])
            # Update last_write
            for addr in op_writes[i]:
                last_write[addr] = i

        # WAR (write-after-read): allow same-cycle, forbid earlier-cycle.
        # If op A reads X and later op B writes X, sequential semantics require
        # cycle(B) >= cycle(A). We model this with a separate dependency set that
        # can be satisfied within the same cycle (reads happen before writes).
        war_pred: list[set[int]] = [set() for _ in range(n)]
        last_read: dict[int, set[int]] = {}  # addr -> set of op indices that read it
        for i in range(n):
            engine, slot = slots[i]
            if engine == "debug":
                continue
            for addr in op_writes[i]:
                if addr in last_read:
                    for reader in last_read[addr]:
                        if reader < i:
                            war_pred[i].add(reader)
            for addr in op_reads[i]:
                last_read.setdefault(addr, set()).add(i)

        # Compute remaining dependencies count
        dep_count = [len(pred[i]) for i in range(n)]

        # Build successor list for critical path
        succ: list[set[int]] = [set() for _ in range(n)]
        for i in range(n):
            for p in pred[i]:
                succ[p].add(i)

        # Latency weights for critical path computation.
        # Scarcity-weight by per-engine slot limits, but cap against the load
        # roofline so FLOW/STORE scarcity doesn't dominate load throughput.
        base_limit = max(v for k, v in SLOT_LIMITS.items() if k != "debug")
        load_limit = SLOT_LIMITS.get("load", 1)
        load_weight = (base_limit + load_limit - 1) // load_limit
        load_bias = load_weight * 2

        def get_latency_weight(engine):
            if engine == "debug":
                return 0
            if engine == "load":
                return load_bias
            limit = SLOT_LIMITS.get(engine, 1)
            weight = (base_limit + limit - 1) // limit
            if engine in ("flow", "store"):
                # FLOW/STORE are scarce, but load throughput is the roofline.
                return min(weight, load_weight)
            return weight

        # Compute height (longest latency-weighted path to any leaf) for critical path priority
        height = [0] * n
        for i in range(n - 1, -1, -1):
            weight = get_latency_weight(slots[i][0])
            if succ[i]:
                height[i] = weight + max(height[s] for s in succ[i])
            else:
                height[i] = weight

        # Ready queue: ops with all dependencies satisfied
        ready = [i for i in range(n) if dep_count[i] == 0]

        while ready:
            bundle: dict[str, list[Any]] = defaultdict(list)
            slot_counts: dict[str, int] = defaultdict(int)
            bundle_writes: set[int] = set()
            bundle_reads = set()
            scheduled_this_cycle = []

            # Try to fill the bundle from ready ops
            # Prioritize by: 1) critical path height, 2) engine type, 3) original order
            # Default heuristic: get LOADs out early, then arithmetic/VALU, then stores/flow.
            engine_priority = {"load": 0, "store": 1, "valu": 2, "alu": 3, "flow": 4, "debug": 5}
            ready.sort(key=lambda i: (-height[i], engine_priority.get(slots[i][0], 10), i))

            # Iteratively fill the bundle so same-cycle WAR constraints can be satisfied.
            ready_set = ready
            ready = []
            progress = True
            scheduled_this_cycle_set = set()
            while progress and ready_set:
                progress = False
                new_ready = []
                for i in ready_set:
                    engine, slot = slots[i]
                    if engine == "debug":
                        bundle[engine].append(slot)
                        scheduled[i] = True
                        scheduled_this_cycle.append(i)
                        scheduled_this_cycle_set.add(i)
                        progress = True
                        continue

                    # Same-cycle WAR: require all earlier readers to be in a previous cycle or this cycle.
                    if any((not scheduled[p]) and (p not in scheduled_this_cycle_set) for p in war_pred[i]):
                        new_ready.append(i)
                        continue

                    limit = SLOT_LIMITS.get(engine, 1)
                    if slot_counts[engine] >= limit:
                        new_ready.append(i)
                        continue

                    writes = op_writes[i]
                    reads = op_reads[i]

                    # In VLIW, all reads happen before all writes within a cycle.
                    # - RAW (reads & bundle_writes): forbidden (would read stale)
                    # - WAR (writes & bundle_reads): allowed (reads see old value)
                    # - WAW (writes & bundle_writes): forbidden
                    if reads & bundle_writes:
                        new_ready.append(i)
                        continue
                    if writes & bundle_writes:
                        new_ready.append(i)
                        continue

                    bundle[engine].append(slot)
                    slot_counts[engine] += 1
                    bundle_writes.update(writes)
                    bundle_reads.update(reads)
                    scheduled[i] = True
                    scheduled_this_cycle.append(i)
                    scheduled_this_cycle_set.add(i)
                    progress = True
                ready_set = new_ready

            ready = ready_set

            if bundle:
                instrs.append(dict(bundle))

            # Update ready queue with newly enabled ops
            for i in scheduled_this_cycle:
                for j in range(n):
                    if not scheduled[j] and i in pred[j]:
                        pred[j].remove(i)
                        if len(pred[j]) == 0 and j not in ready:
                            ready.append(j)

        return instrs
