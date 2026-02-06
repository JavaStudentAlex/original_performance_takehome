"""
# Anthropic's Original Performance Engineering Take-home (Release version)

Copyright Anthropic PBC 2026. Permission is granted to modify and use, but not
to publish or redistribute your solutions so it's hard to find spoilers.

# Task

- Optimize the kernel (in KernelBuilder.build_kernel) as much as possible in the
  available time, as measured by test_kernel_cycles on a frozen separate copy
  of the simulator.

Validate your results using `python tests/submission_tests.py` without modifying
anything in the tests/ folder.

We recommend you look through problem.py next.
"""

from collections import defaultdict
import random
import unittest

from problem import (
    Engine,
    DebugInfo,
    SLOT_LIMITS,
    VLEN,
    N_CORES,
    SCRATCH_SIZE,
    Machine,
    Tree,
    Input,
    HASH_STAGES,
    reference_kernel,
    build_mem_image,
    reference_kernel2,
)


class KernelBuilder:
    """
    Builds optimized VLIW SIMD instructions for the tree traversal kernel.
    
    Optimization strategy:
    1. VLIW bundling: Pack multiple independent operations per cycle
    2. SIMD vectorization: Process VLEN=8 items simultaneously with VALU
    3. Software gather: Scalar loads for divergent tree indices into vector scratch
    4. Branchless computation: Arithmetic-based index updates, no cond_jump
    """

    def __init__(self):
        self.instrs = []
        self.scratch = {}
        self.scratch_debug = {}
        self.scratch_ptr = 0
        self.const_map = {}
        self.vec_const_map = {}

    def debug_info(self):
        """Return debug information for scratch memory mapping."""
        return DebugInfo(scratch_map=self.scratch_debug)

    def build(self, slots: list[tuple[Engine, tuple]], vliw: bool = False):
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
                    reads = set()
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
        pred = [set() for _ in range(n)]
        last_write = {}  # addr -> op index that last wrote it
        
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
        war_pred = [set() for _ in range(n)]
        last_read = {}  # addr -> set of op indices that read it
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
        succ = [set() for _ in range(n)]
        for i in range(n):
            for p in pred[i]:
                succ[p].add(i)
        
        # Latency weights for critical path computation
        # LOADs/STOREs are the bottleneck (2 slots/cycle), so weight them higher
        # FLOW ops (branches) also critical for control flow
        # ALU/VALU abundant, so lower weight
        def get_latency_weight(engine):
            if engine == "load":
                return 3  # Highest: memory bottleneck
            elif engine == "store":
                return 3  # High: limited slots
            elif engine == "flow":
                return 2  # Medium: control critical
            elif engine == "valu":
                return 1  # Low: abundant
            elif engine == "alu":
                return 1  # Low: abundant
            else:
                return 0
        
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
            bundle = defaultdict(list)
            slot_counts = defaultdict(int)
            bundle_writes = set()
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

    def add(self, engine, slot):
        """Add a single-slot instruction bundle."""
        self.instrs.append({engine: [slot]})

    def add_bundle(self, bundle):
        """Add a pre-formed instruction bundle directly."""
        self.instrs.append(bundle)

    def alloc_scratch(self, name=None, length=1):
        """
        Allocate scratch memory.
        
        Parameters
        ----------
        name : str, optional
            Name for debugging; if provided, registers in scratch map.
        length : int
            Number of words to allocate.
            
        Returns
        -------
        int
            Starting address of allocated region.
        """
        addr = self.scratch_ptr
        if name is not None:
            self.scratch[name] = addr
            self.scratch_debug[addr] = (name, length)
        self.scratch_ptr += length
        assert self.scratch_ptr <= SCRATCH_SIZE, "Out of scratch space"
        return addr

    def scratch_const(self, val, name=None):
        """
        Get or create a scalar constant in scratch memory.
        
        Parameters
        ----------
        val : int
            Constant value to store.
        name : str, optional
            Name for debugging.
            
        Returns
        -------
        int
            Scratch address containing the constant.
        """
        if val not in self.const_map:
            addr = self.alloc_scratch(name)
            self.add("load", ("const", addr, val))
            self.const_map[val] = addr
        return self.const_map[val]

    def vec_const(self, val):
        """
        Get or create a vector constant (broadcast to VLEN words).
        
        Parameters
        ----------
        val : int
            Constant value to broadcast.
            
        Returns
        -------
        int
            Scratch address of vector constant (VLEN words).
        """
        if val not in self.vec_const_map:
            scalar = self.scratch_const(val)
            vec = self.alloc_scratch(f"vc_{val}", VLEN)
            self.add_bundle({"valu": [("vbroadcast", vec, scalar)]})
            self.vec_const_map[val] = vec
        return self.vec_const_map[val]

    def build_valu_select(self, dest, cond, a, b, tmp):
        """
        Build VALU-based conditional select: dest = cond ? a : b
        
        Assumes cond contains 0 or 1 values (not arbitrary non-zero).
        Uses formula: result = cond * (a - b) + b
        
        Parameters
        ----------
        dest : int
            Destination vector address
        cond : int
            Condition vector (must be 0 or 1 values)
        a : int  
            Value to select when cond=1
        b : int
            Value to select when cond=0
        tmp : int
            Temporary vector for computation
            
        Returns
        -------
        list of (engine, slot) tuples
        """
        return [
            ("valu", ("-", tmp, a, b)),       # tmp = a - b
            ("valu", ("*", tmp, cond, tmp)),   # tmp = cond * (a - b)
            ("valu", ("+", dest, tmp, b)),     # dest = cond * (a - b) + b
        ]

    def build_hash(self, val_hash_addr, tmp1, tmp2, round, i):
        """Build scalar hash function slots (deprecated, use build_vhash)."""
        slots = []
        for hi, (op1, val1, op2, op3, val3) in enumerate(HASH_STAGES):
            slots.append(("alu", (op1, tmp1, val_hash_addr, self.scratch_const(val1))))
            slots.append(("alu", (op3, tmp2, val_hash_addr, self.scratch_const(val3))))
            slots.append(("alu", (op2, val_hash_addr, tmp1, tmp2)))
            slots.append(("debug", ("compare", val_hash_addr, (round, i, "hash_stage", hi))))
        return slots

    def build_vhash(self, v_val, v_tmp1, v_tmp2, round_num, batch_start):
        """
        Build vectorized hash function using VALU operations.
        
        Parameters
        ----------
        v_val : int
            Vector scratch address for values (in/out, VLEN words).
        v_tmp1 : int
            Vector scratch address for temp1 (VLEN words).
        v_tmp2 : int
            Vector scratch address for temp2 (VLEN words).
        round_num : int
            Current round number for debug tracing.
        batch_start : int
            Starting item index for debug tracing.
            
        Returns
        -------
        list of (engine, slot) tuples
            Vector hash operations.
        """
        slots = []
        for hi, (op1, val1, op2, op3, val3) in enumerate(HASH_STAGES):
            # Optimization: For stages with pattern a = (a + const1) + (a << shift),
            # use multiply_add: a = a * (1 + 2^shift) + const1 = 1 op instead of 3
            if op1 == "+" and op2 == "+" and op3 == "<<":
                # a = (a + val1) + (a << val3) = a * (1 + 2^val3) + val1
                multiplier = 1 + (1 << val3)
                vc_mult = self.vec_const(multiplier)
                vc1 = self.vec_const(val1)
                slots.append(("valu", ("multiply_add", v_val, v_val, vc_mult, vc1)))
            else:
                # Standard 3-op pattern
                vc1 = self.vec_const(val1)
                vc3 = self.vec_const(val3)
                slots.append(("valu", (op1, v_tmp1, v_val, vc1)))
                slots.append(("valu", (op3, v_tmp2, v_val, vc3)))
                slots.append(("valu", (op2, v_val, v_tmp1, v_tmp2)))
            keys = tuple((round_num, batch_start + lane, "hash_stage", hi) for lane in range(VLEN))
            slots.append(("debug", ("vcompare", v_val, keys)))
        return slots

    def build_vhash_interleaved(self, batches_info, round_num):
        """
        Build hash operations for multiple batches with interleaved stages.
        
        This generates operations stage-by-stage across all batches, which
        allows better VALU slot utilization by enabling parallelism between
        independent hash operations.
        
        Parameters
        ----------
        batches_info : list of (v_val, v_tmp1, v_tmp2, batch_start) tuples
        round_num : int
        
        Returns
        -------
        list of (engine, slot) tuples
        """
        slots = []
        for hi, (op1, val1, op2, op3, val3) in enumerate(HASH_STAGES):
            # Optimization: For stages with pattern a = (a + const1) + (a << shift),
            # use multiply_add: a = a * (1 + 2^shift) + const1 = 1 op instead of 3
            if op1 == "+" and op2 == "+" and op3 == "<<":
                # a = (a + val1) + (a << val3) = a * (1 + 2^val3) + val1
                multiplier = 1 + (1 << val3)
                vc_mult = self.vec_const(multiplier)
                vc1 = self.vec_const(val1)
                for v_val, v_tmp1, v_tmp2, batch_start in batches_info:
                    slots.append(("valu", ("multiply_add", v_val, v_val, vc_mult, vc1)))
                    keys = tuple((round_num, batch_start + lane, "hash_stage", hi) for lane in range(VLEN))
                    slots.append(("debug", ("vcompare", v_val, keys)))
            else:
                # Standard 3-op pattern
                vc1 = self.vec_const(val1)
                vc3 = self.vec_const(val3)
                # First pass: op1 and op3 for all batches (independent)
                for v_val, v_tmp1, v_tmp2, batch_start in batches_info:
                    slots.append(("valu", (op1, v_tmp1, v_val, vc1)))
                    slots.append(("valu", (op3, v_tmp2, v_val, vc3)))
                # Second pass: op2 for all batches (depends on op1, op3)
                for v_val, v_tmp1, v_tmp2, batch_start in batches_info:
                    slots.append(("valu", (op2, v_val, v_tmp1, v_tmp2)))
                    keys = tuple((round_num, batch_start + lane, "hash_stage", hi) for lane in range(VLEN))
                    slots.append(("debug", ("vcompare", v_val, keys)))
        return slots

    def build_kernel(
        self, forest_height: int, n_nodes: int, batch_size: int, rounds: int
    ):
        """
        Build optimized VLIW SIMD kernel with software pipelining.
        """
        tmp1 = self.alloc_scratch("tmp1")
        
        init_vars = [
            "rounds", "n_nodes", "batch_size", "forest_height",
            "forest_values_p", "inp_indices_p", "inp_values_p",
        ]
        for v in init_vars:
            self.alloc_scratch(v, 1)
        for i, v in enumerate(init_vars):
            self.add("load", ("const", tmp1, i))
            self.add("load", ("load", self.scratch[v], tmp1))

        self.add("flow", ("pause",))

        num_batches = batch_size // VLEN
        
        v_idx = [self.alloc_scratch(f"v_idx_{b}", VLEN) for b in range(num_batches)]
        v_val = [self.alloc_scratch(f"v_val_{b}", VLEN) for b in range(num_batches)]
        v_node_val = [self.alloc_scratch(f"v_node_val_{b}", VLEN) for b in range(num_batches)]
        # Use a pool of rotating temporaries to avoid false dependencies
        # More pools = more parallelism, limited by scratch space
        N_TMP_POOLS = 6
        v_tmp1 = [self.alloc_scratch(f"v_tmp1_{p}", VLEN) for p in range(N_TMP_POOLS)]
        v_tmp2 = [self.alloc_scratch(f"v_tmp2_{p}", VLEN) for p in range(N_TMP_POOLS)]
        
        v_zero = self.vec_const(0)
        v_one = self.vec_const(1)
        v_two = self.vec_const(2)
        v_n_nodes = self.alloc_scratch("v_n_nodes", VLEN)
        self.add_bundle({"valu": [("vbroadcast", v_n_nodes, self.scratch["n_nodes"])]})

        tmp_addr = self.alloc_scratch("tmp_addr")
        
        batch_offsets = [self.scratch_const(b * VLEN) for b in range(num_batches)]

        init_ops = []
        for b in range(num_batches):
            init_ops.append(("alu", ("+", tmp_addr, self.scratch["inp_indices_p"], batch_offsets[b])))
            init_ops.append(("load", ("vload", v_idx[b], tmp_addr)))
            init_ops.append(("debug", ("vcompare", v_idx[b], tuple((0, b * VLEN + lane, "idx") for lane in range(VLEN)))))
            init_ops.append(("alu", ("+", tmp_addr, self.scratch["inp_values_p"], batch_offsets[b])))
            init_ops.append(("load", ("vload", v_val[b], tmp_addr)))
            init_ops.append(("debug", ("vcompare", v_val[b], tuple((0, b * VLEN + lane, "val") for lane in range(VLEN)))))
        self.instrs.extend(self.build(init_ops, vliw=True))

        PIPE_DEPTH = 2
        ADDR_RING = PIPE_DEPTH + 1
        
        tree_0 = self.alloc_scratch("tree_0")
        tree_1 = self.alloc_scratch("tree_1")
        tree_2 = self.alloc_scratch("tree_2")
        v_tmp3 = self.alloc_scratch("v_tmp3", VLEN)

        idx_addr = [
            [self.alloc_scratch(f"idx_addr_{s}_{lane}") for lane in range(VLEN)]
            for s in range(ADDR_RING)
        ]

        for round_num in range(rounds):
            round_ops = []
            
            level_size = 1 << (round_num % 11)
            level_start = level_size - 1
            
            if round_num in (0, 11):
                round_ops.append(("alu", ("+", tmp_addr, self.scratch["forest_values_p"], self.scratch_const(0))))
                round_ops.append(("load", ("load", tree_0, tmp_addr)))
                
                # Broadcast and XOR for all batches first
                for b in range(num_batches):
                    batch_start = b * VLEN
                    round_ops.append(("valu", ("vbroadcast", v_node_val[b], tree_0)))
                    round_ops.append(("debug", ("vcompare", v_node_val[b], tuple((round_num, batch_start + lane, "node_val") for lane in range(VLEN)))))
                    round_ops.append(("valu", ("^", v_val[b], v_val[b], v_node_val[b])))
                
                # Interleaved hash across all batches
                batches_info = [(v_val[b], v_node_val[b], v_val[b], b * VLEN) for b in range(num_batches)]
                round_ops.extend(self.build_vhash_interleaved(batches_info, round_num))
                
                # Index updates for all batches
                for b in range(num_batches):
                    batch_start = b * VLEN
                    tp = b % N_TMP_POOLS
                    round_ops.append(("debug", ("vcompare", v_val[b], tuple((round_num, batch_start + lane, "hashed_val") for lane in range(VLEN)))))
                    # Index update: idx = idx * 2 + ((val & 1) + 1) using multiply_add (3 ops vs 4)
                    round_ops.append(("valu", ("&", v_tmp1[tp], v_val[b], v_one)))
                    round_ops.append(("valu", ("+", v_tmp1[tp], v_tmp1[tp], v_one)))
                    round_ops.append(("valu", ("multiply_add", v_idx[b], v_idx[b], v_two, v_tmp1[tp])))
                    round_ops.append(("debug", ("vcompare", v_idx[b], tuple((round_num, batch_start + lane, "next_idx") for lane in range(VLEN)))))
                    round_ops.append(("valu", ("<", v_tmp1[tp], v_idx[b], v_n_nodes)))
                    round_ops.append(("flow", ("vselect", v_idx[b], v_tmp1[tp], v_idx[b], v_zero)))
                    round_ops.append(("debug", ("vcompare", v_idx[b], tuple((round_num, batch_start + lane, "wrapped_idx") for lane in range(VLEN)))))
            elif round_num in (1, 12):
                round_ops.append(("alu", ("+", tmp_addr, self.scratch["forest_values_p"], self.scratch_const(1))))
                round_ops.append(("load", ("load", tree_1, tmp_addr)))
                round_ops.append(("alu", ("+", tmp_addr, self.scratch["forest_values_p"], self.scratch_const(2))))
                round_ops.append(("load", ("load", tree_2, tmp_addr)))
                
                # Select node value and XOR for all batches first.
                for b in range(num_batches):
                    batch_start = b * VLEN
                    tp = b % N_TMP_POOLS  # Rotate through temp pool
                    round_ops.append(("valu", ("&", v_tmp1[tp], v_idx[b], v_one)))
                    round_ops.append(("valu", ("vbroadcast", v_tmp3, tree_1)))
                    round_ops.append(("valu", ("vbroadcast", v_node_val[b], tree_2)))
                    round_ops.append(("flow", ("vselect", v_node_val[b], v_tmp1[tp], v_tmp3, v_node_val[b])))
                    round_ops.append(("debug", ("vcompare", v_node_val[b], tuple((round_num, batch_start + lane, "node_val") for lane in range(VLEN)))))
                    round_ops.append(("valu", ("^", v_val[b], v_val[b], v_node_val[b])))

                batches_info = [(v_val[b], v_node_val[b], v_val[b], b * VLEN) for b in range(num_batches)]
                round_ops.extend(self.build_vhash_interleaved(batches_info, round_num))

                # Index updates for all batches.
                for b in range(num_batches):
                    batch_start = b * VLEN
                    tp = b % N_TMP_POOLS
                    round_ops.append(("debug", ("vcompare", v_val[b], tuple((round_num, batch_start + lane, "hashed_val") for lane in range(VLEN)))))
                    # Index update: idx = idx * 2 + ((val & 1) + 1) using multiply_add (3 ops vs 4)
                    round_ops.append(("valu", ("&", v_tmp1[tp], v_val[b], v_one)))
                    round_ops.append(("valu", ("+", v_tmp1[tp], v_tmp1[tp], v_one)))
                    round_ops.append(("valu", ("multiply_add", v_idx[b], v_idx[b], v_two, v_tmp1[tp])))
                    round_ops.append(("debug", ("vcompare", v_idx[b], tuple((round_num, batch_start + lane, "next_idx") for lane in range(VLEN)))))
                    round_ops.append(("valu", ("<", v_tmp1[tp], v_idx[b], v_n_nodes)))
                    round_ops.append(("flow", ("vselect", v_idx[b], v_tmp1[tp], v_idx[b], v_zero)))
                    round_ops.append(("debug", ("vcompare", v_idx[b], tuple((round_num, batch_start + lane, "wrapped_idx") for lane in range(VLEN)))))
            else:
                # General rounds: single gather load of current node value per lane (8 loads/batch).
                total_steps = num_batches + PIPE_DEPTH
                for step in range(total_steps):
                    addr_batch = step
                    load_batch = step - 1
                    compute_batch = step - PIPE_DEPTH

                    if addr_batch < num_batches:
                        b = addr_batch
                        s = b % ADDR_RING
                        for lane in range(VLEN):
                            round_ops.append(
                                (
                                    "alu",
                                    (
                                        "+",
                                        idx_addr[s][lane],
                                        self.scratch["forest_values_p"],
                                        v_idx[b] + lane,
                                    ),
                                )
                            )

                    if 0 <= load_batch < num_batches:
                        b = load_batch
                        s = b % ADDR_RING
                        for lane in range(VLEN):
                            round_ops.append(("load", ("load", v_node_val[b] + lane, idx_addr[s][lane])))
                        round_ops.append(
                            (
                                "debug",
                                (
                                    "vcompare",
                                    v_node_val[b],
                                    tuple(
                                        (round_num, b * VLEN + lane, "node_val")
                                        for lane in range(VLEN)
                                    ),
                                ),
                            )
                        )

                    if 0 <= compute_batch < num_batches:
                        b = compute_batch
                        round_ops.append(("valu", ("^", v_val[b], v_val[b], v_node_val[b])))

                batches_info = [(v_val[b], v_node_val[b], v_val[b], b * VLEN) for b in range(num_batches)]
                round_ops.extend(self.build_vhash_interleaved(batches_info, round_num))

                for b in range(num_batches):
                    batch_start = b * VLEN
                    tp = b % N_TMP_POOLS  # Rotate through temp pool
                    round_ops.append(
                        (
                            "debug",
                            (
                                "vcompare",
                                v_val[b],
                                tuple((round_num, batch_start + lane, "hashed_val") for lane in range(VLEN)),
                            ),
                        )
                    )
                    # Index update: idx = idx * 2 + ((val & 1) + 1) using multiply_add.
                    round_ops.append(("valu", ("&", v_tmp1[tp], v_val[b], v_one)))
                    round_ops.append(("valu", ("+", v_tmp1[tp], v_tmp1[tp], v_one)))
                    round_ops.append(("valu", ("multiply_add", v_idx[b], v_idx[b], v_two, v_tmp1[tp])))
                    round_ops.append(
                        (
                            "debug",
                            (
                                "vcompare",
                                v_idx[b],
                                tuple((round_num, batch_start + lane, "next_idx") for lane in range(VLEN)),
                            ),
                        )
                    )
                    round_ops.append(("valu", ("<", v_tmp1[tp], v_idx[b], v_n_nodes)))
                    round_ops.append(("flow", ("vselect", v_idx[b], v_tmp1[tp], v_idx[b], v_zero)))
                    round_ops.append(
                        (
                            "debug",
                            (
                                "vcompare",
                                v_idx[b],
                                tuple((round_num, batch_start + lane, "wrapped_idx") for lane in range(VLEN)),
                            ),
                        )
                    )
            
            self.instrs.extend(self.build(round_ops, vliw=True))

        final_ops = []
        for b in range(num_batches):
            final_ops.append(("alu", ("+", tmp_addr, self.scratch["inp_indices_p"], batch_offsets[b])))
            final_ops.append(("store", ("vstore", tmp_addr, v_idx[b])))
            final_ops.append(("alu", ("+", tmp_addr, self.scratch["inp_values_p"], batch_offsets[b])))
            final_ops.append(("store", ("vstore", tmp_addr, v_val[b])))
        self.instrs.extend(self.build(final_ops, vliw=True))

BASELINE = 147734

def do_kernel_test(
    forest_height: int,
    rounds: int,
    batch_size: int,
    seed: int = 123,
    trace: bool = False,
    prints: bool = False,
):
    print(f"{forest_height=}, {rounds=}, {batch_size=}")
    random.seed(seed)
    forest = Tree.generate(forest_height)
    inp = Input.generate(forest, batch_size, rounds)
    mem = build_mem_image(forest, inp)

    kb = KernelBuilder()
    kb.build_kernel(forest.height, len(forest.values), len(inp.indices), rounds)
    # print(kb.instrs)

    value_trace = {}
    machine = Machine(
        mem,
        kb.instrs,
        kb.debug_info(),
        n_cores=N_CORES,
        value_trace=value_trace,
        trace=trace,
    )
    machine.prints = prints
    for i, ref_mem in enumerate(reference_kernel2(mem, value_trace)):
        machine.run()
        inp_values_p = ref_mem[6]
        if prints:
            print(machine.mem[inp_values_p : inp_values_p + len(inp.values)])
            print(ref_mem[inp_values_p : inp_values_p + len(inp.values)])
        assert (
            machine.mem[inp_values_p : inp_values_p + len(inp.values)]
            == ref_mem[inp_values_p : inp_values_p + len(inp.values)]
        ), f"Incorrect result on round {i}"
        inp_indices_p = ref_mem[5]
        if prints:
            print(machine.mem[inp_indices_p : inp_indices_p + len(inp.indices)])
            print(ref_mem[inp_indices_p : inp_indices_p + len(inp.indices)])
        # Updating these in memory isn't required, but you can enable this check for debugging
        # assert machine.mem[inp_indices_p:inp_indices_p+len(inp.indices)] == ref_mem[inp_indices_p:inp_indices_p+len(inp.indices)]

    print("CYCLES: ", machine.cycle)
    print("Speedup over baseline: ", BASELINE / machine.cycle)
    return machine.cycle


class Tests(unittest.TestCase):
    def test_ref_kernels(self):
        """
        Test the reference kernels against each other
        """
        random.seed(123)
        for i in range(10):
            f = Tree.generate(4)
            inp = Input.generate(f, 10, 6)
            mem = build_mem_image(f, inp)
            reference_kernel(f, inp)
            for _ in reference_kernel2(mem, {}):
                pass
            assert inp.indices == mem[mem[5] : mem[5] + len(inp.indices)]
            assert inp.values == mem[mem[6] : mem[6] + len(inp.values)]

    def test_kernel_trace(self):
        # Full-scale example for performance testing
        do_kernel_test(10, 16, 256, trace=True, prints=False)

    # Passing this test is not required for submission, see submission_tests.py for the actual correctness test
    # You can uncomment this if you think it might help you debug
    # def test_kernel_correctness(self):
    #     for batch in range(1, 3):
    #         for forest_height in range(3):
    #             do_kernel_test(
    #                 forest_height + 2, forest_height + 4, batch * 16 * VLEN * N_CORES
    #             )

    def test_kernel_cycles(self):
        do_kernel_test(10, 16, 256)


# To run all the tests:
#    python perf_takehome.py
# To run a specific test:
#    python perf_takehome.py Tests.test_kernel_cycles
# To view a hot-reloading trace of all the instructions:  **Recommended debug loop**
# NOTE: The trace hot-reloading only works in Chrome. In the worst case if things aren't working, drag trace.json onto https://ui.perfetto.dev/
#    python perf_takehome.py Tests.test_kernel_trace
# Then run `python watch_trace.py` in another tab, it'll open a browser tab, then click "Open Perfetto"
# You can then keep that open and re-run the test to see a new trace.

# To run the proper checks to see which thresholds you pass:
#    python tests/submission_tests.py

if __name__ == "__main__":
    unittest.main()
