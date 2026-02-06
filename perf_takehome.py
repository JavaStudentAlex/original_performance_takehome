"""Anthropic's Original Performance Engineering Take-home (Release version).

Copyright Anthropic PBC 2026. Permission is granted to modify and use, but not
to publish or redistribute your solutions so it's hard to find spoilers.

Task
----
- Optimize the kernel (in KernelBuilder.build_kernel) as much as possible in the
  available time, as measured by test_kernel_cycles on a frozen separate copy
  of the simulator.

Validate your results using `python tests/submission_tests.py` without modifying
anything in the tests/ folder.

We recommend you look through problem.py next.
"""

import random
import unittest
from typing import Any

from kernel_hash import HashBuilder
from kernel_memory import ScratchAllocator
from kernel_scheduler import VLIWScheduler
from kernel_traversal import TraversalBuilder
from problem import (
    N_CORES,
    SCRATCH_SIZE,
    VLEN,
    Input,
    Machine,
    Tree,
    build_mem_image,
    reference_kernel,
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
        self.allocator = ScratchAllocator(VLEN, SCRATCH_SIZE)
        self.hasher = HashBuilder(self)
        # Expose allocator attributes for backward compatibility
        self.scratch = self.allocator.scratch
        self.scratch_debug = self.allocator.scratch_debug

    @property
    def scratch_ptr(self):
        """Scratch pointer property for backward compatibility."""
        return self.allocator.scratch_ptr

    @property
    def const_map(self):
        """Constant map property for backward compatibility."""
        return self.allocator.const_map

    @property
    def vec_const_map(self):
        """Vector constant map property for backward compatibility."""
        return self.allocator.vec_const_map

    def debug_info(self):
        """Return debug information for scratch memory mapping."""
        return self.allocator.debug_info()

    def build(self, slots: list[tuple[str, tuple[Any, ...]]], vliw: bool = False):
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
        return VLIWScheduler.build(slots, vliw)

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
        return self.allocator.alloc_scratch(name, length)

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
        addr, instrs = self.allocator.scratch_const(val, name)
        for instr in instrs:
            self.add_bundle(instr)
        return addr

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
        addr, instrs = self.allocator.vec_const(val)
        for instr in instrs:
            self.add_bundle(instr)
        return addr

    def build_valu_select(self, dest, cond, a, b, tmp):
        """
        Build VALU-based conditional select: dest = cond ? a : b.

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
            ("valu", ("-", tmp, a, b)),  # tmp = a - b
            ("valu", ("*", tmp, cond, tmp)),  # tmp = cond * (a - b)
            ("valu", ("+", dest, tmp, b)),  # dest = cond * (a - b) + b
        ]

    def build_hash(self, val_hash_addr, tmp1, tmp2, round, i):
        """Build scalar hash function slots (deprecated, use build_vhash)."""
        return self.hasher.build_hash(val_hash_addr, tmp1, tmp2, round, i)

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
        return self.hasher.build_vhash(v_val, v_tmp1, v_tmp2, round_num, batch_start)

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
        return self.hasher.build_vhash_interleaved(batches_info, round_num)

    def build_kernel(self, forest_height: int, n_nodes: int, batch_size: int, rounds: int):
        """Build optimized VLIW SIMD kernel with software pipelining."""
        traversal = TraversalBuilder(self, self.hasher, self)
        init_instrs, round_instrs, final_instrs = traversal.build_kernel_ops(forest_height, n_nodes, batch_size, rounds)
        self.instrs.extend(init_instrs)
        self.instrs.extend(round_instrs)
        self.instrs.extend(final_instrs)


BASELINE = 147734


def do_kernel_test(
    forest_height: int,
    rounds: int,
    batch_size: int,
    seed: int = 123,
    trace: bool = False,
    prints: bool = False,
):
    """Run the kernel test and return cycle count."""
    print(f"{forest_height=}, {rounds=}, {batch_size=}")
    random.seed(seed)
    forest = Tree.generate(forest_height)
    inp = Input.generate(forest, batch_size, rounds)
    mem = build_mem_image(forest, inp)

    kb = KernelBuilder()
    kb.build_kernel(forest.height, len(forest.values), len(inp.indices), rounds)
    # print(kb.instrs)

    value_trace: dict[Any, Any] = {}
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
        # assert (
        #     machine.mem[inp_indices_p:inp_indices_p+len(inp.indices)]
        #     == ref_mem[inp_indices_p:inp_indices_p+len(inp.indices)]
        # )

    print("CYCLES: ", machine.cycle)
    print("Speedup over baseline: ", BASELINE / machine.cycle)
    return machine.cycle


class Tests(unittest.TestCase):
    """Unit tests for kernel correctness and performance."""

    def test_ref_kernels(self):
        """Test the reference kernels against each other."""
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
        """Test kernel with trace enabled for performance profiling."""
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
        """Test kernel cycle count for performance benchmarking."""
        do_kernel_test(10, 16, 256)


# To run all the tests:
#    python perf_takehome.py
# To run a specific test:
#    python perf_takehome.py Tests.test_kernel_cycles
# To view a hot-reloading trace of all the instructions:  **Recommended debug loop**
# NOTE: The trace hot-reloading only works in Chrome. In the worst case if things
# aren't working, drag trace.json onto https://ui.perfetto.dev/
#    python perf_takehome.py Tests.test_kernel_trace
# Then run `python watch_trace.py` in another tab, it'll open a browser tab, then click "Open Perfetto"
# You can then keep that open and re-run the test to see a new trace.

# To run the proper checks to see which thresholds you pass:
#    python tests/submission_tests.py

if __name__ == "__main__":
    unittest.main()
