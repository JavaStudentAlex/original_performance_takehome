"""Tree traversal logic for VLIW SIMD kernel.

Extracted from perf_takehome.py to modularize the kernel building phases:
- Initialization: memory header loading and scratch setup
- Round generation: special rounds (0/1/11/12) vs general rounds
- Finalization: storing results back to memory

This module preserves the exact traversal logic including software pipelining
structure (PIPE_DEPTH, ADDR_RING) and round-specific optimizations.
"""

from typing import Any, cast

from problem import VLEN

# Software pipelining constants
PIPE_DEPTH = 2
ADDR_RING = PIPE_DEPTH + 1


class TraversalBuilder:
    """
    Builds tree traversal operations for the VLIW SIMD kernel.

    Handles the three phases of kernel execution:
    1. Initialization: Load memory header, set up scratch variables
    2. Round generation: Process each round with appropriate strategy
    3. Finalization: Store computed results back to memory
    """

    def __init__(self, scratch_allocator, hash_builder, scheduler):
        """
        Initialize traversal builder with dependencies.

        Parameters
        ----------
        scratch_allocator : object
            Provides alloc_scratch(), scratch[], and scratch_const() methods
        hash_builder : object
            Provides build_vhash_interleaved() method
        scheduler : object
            Provides build() method for operation scheduling
        """
        self.allocator = scratch_allocator
        self.hasher = hash_builder
        self.scheduler = scheduler

    def build_kernel_ops(
        self, forest_height: int, n_nodes: int, batch_size: int, rounds: int
    ) -> tuple[list[dict], list[dict], list[dict]]:
        """
        Build operation lists for all three kernel phases.

        Parameters
        ----------
        forest_height : int
            Height of the tree forest
        n_nodes : int
            Number of nodes in each tree
        batch_size : int
            Total number of items (must be multiple of VLEN)
        rounds : int
            Number of traversal rounds

        Returns
        -------
        init_instrs : list[dict]
            Initialization phase instructions
        round_instrs : list[dict]
            All round processing instructions
        final_instrs : list[dict]
            Finalization phase instructions
        """
        num_batches = batch_size // VLEN

        # Phase 1: Initialization
        init_instrs = self._build_initialization(num_batches)

        # Phase 2: Round generation
        round_instrs = self._build_rounds(rounds, num_batches)

        # Phase 3: Finalization
        final_instrs = self._build_finalization(num_batches)

        return init_instrs, round_instrs, final_instrs

    def _build_initialization(self, num_batches: int) -> list[dict]:
        """
        Build initialization phase operations.

        Loads memory header (rounds, n_nodes, batch_size, forest_height, pointers),
        sets up vector constants and scratch variables, and loads initial indices
        and values for all batches.

        Parameters
        ----------
        num_batches : int
            Number of VLEN-sized batches

        Returns
        -------
        list[dict]
            Instruction bundles for initialization
        """
        tmp1 = self.allocator.alloc_scratch("tmp1")

        # Load memory header
        init_vars = [
            "rounds",
            "n_nodes",
            "batch_size",
            "forest_height",
            "forest_values_p",
            "inp_indices_p",
            "inp_values_p",
        ]
        for v in init_vars:
            self.allocator.alloc_scratch(v, 1)
        for i, v in enumerate(init_vars):
            self.scheduler.add("load", ("const", tmp1, i))
            self.scheduler.add("load", ("load", self.allocator.scratch[v], tmp1))

        self.scheduler.add("flow", ("pause",))

        # Allocate vector scratch for batches
        v_idx = [self.allocator.alloc_scratch(f"v_idx_{b}", VLEN) for b in range(num_batches)]
        v_val = [self.allocator.alloc_scratch(f"v_val_{b}", VLEN) for b in range(num_batches)]
        v_node_val = [self.allocator.alloc_scratch(f"v_node_val_{b}", VLEN) for b in range(num_batches)]
        # Use a pool of rotating temporaries to avoid false dependencies
        # More pools = more parallelism, limited by scratch space
        N_TMP_POOLS = 6
        v_tmp1 = [self.allocator.alloc_scratch(f"v_tmp1_{p}", VLEN) for p in range(N_TMP_POOLS)]

        # Vector constants
        v_zero = self.allocator.vec_const(0)
        v_one = self.allocator.vec_const(1)
        v_two = self.allocator.vec_const(2)
        v_n_nodes = self.allocator.alloc_scratch("v_n_nodes", VLEN)
        self.scheduler.add_bundle({"valu": [("vbroadcast", v_n_nodes, self.allocator.scratch["n_nodes"])]})

        tmp_addr = self.allocator.alloc_scratch("tmp_addr")

        batch_offsets = [self.allocator.scratch_const(b * VLEN) for b in range(num_batches)]

        # Load initial indices and values for all batches
        init_ops: list[tuple[str, tuple[Any, ...]]] = []
        for b in range(num_batches):
            init_ops.append(
                (
                    "alu",
                    (
                        "+",
                        tmp_addr,
                        self.allocator.scratch["inp_indices_p"],
                        batch_offsets[b],
                    ),
                )
            )
            init_ops.append(("load", ("vload", v_idx[b], tmp_addr)))
            keys = tuple((0, b * VLEN + lane, "idx") for lane in range(VLEN))
            init_ops.append(("debug", ("vcompare", v_idx[b], keys)))
            init_ops.append(
                (
                    "alu",
                    ("+", tmp_addr, self.allocator.scratch["inp_values_p"], batch_offsets[b]),
                )
            )
            init_ops.append(("load", ("vload", v_val[b], tmp_addr)))
            keys = tuple((0, b * VLEN + lane, "val") for lane in range(VLEN))
            init_ops.append(("debug", ("vcompare", v_val[b], keys)))

        init_instrs = self.scheduler.build(init_ops, vliw=True)

        # Store state for round processing
        self._state = {
            "v_idx": v_idx,
            "v_val": v_val,
            "v_node_val": v_node_val,
            "v_tmp1": v_tmp1,
            "v_zero": v_zero,
            "v_one": v_one,
            "v_two": v_two,
            "v_n_nodes": v_n_nodes,
            "tmp_addr": tmp_addr,
            "batch_offsets": batch_offsets,
            "N_TMP_POOLS": N_TMP_POOLS,
        }

        return cast(list[dict[Any, Any]], init_instrs)

    def _build_rounds(self, rounds: int, num_batches: int) -> list[dict]:
        """
        Build operations for all rounds.

        Handles three cases:
        - Rounds 0, 11: Single tree (tree_0), broadcast node value
        - Rounds 1, 12: Two trees (tree_1, tree_2), select based on index LSB
        - Other rounds: General gather load from forest using per-lane addressing

        Parameters
        ----------
        rounds : int
            Number of rounds to process
        num_batches : int
            Number of VLEN-sized batches

        Returns
        -------
        list[dict]
            Instruction bundles for all rounds
        """
        # Unpack state
        v_idx = self._state["v_idx"]
        v_val = self._state["v_val"]
        v_node_val = self._state["v_node_val"]
        v_tmp1 = self._state["v_tmp1"]
        v_zero = self._state["v_zero"]
        v_one = self._state["v_one"]
        v_two = self._state["v_two"]
        v_n_nodes = self._state["v_n_nodes"]
        tmp_addr = self._state["tmp_addr"]
        N_TMP_POOLS = self._state["N_TMP_POOLS"]

        # Additional scratch for general rounds
        tree_0 = self.allocator.alloc_scratch("tree_0")
        tree_1 = self.allocator.alloc_scratch("tree_1")
        tree_2 = self.allocator.alloc_scratch("tree_2")
        v_tmp3 = self.allocator.alloc_scratch("v_tmp3", VLEN)

        idx_addr = [
            [self.allocator.alloc_scratch(f"idx_addr_{s}_{lane}") for lane in range(VLEN)] for s in range(ADDR_RING)
        ]

        all_round_instrs = []

        for round_num in range(rounds):
            round_ops: list[tuple[str, tuple[Any, ...]]] = []

            if round_num in (0, 11):
                # Special round: single tree, broadcast
                round_ops.extend(
                    self._build_single_tree_round(
                        round_num,
                        num_batches,
                        tree_0,
                        v_idx,
                        v_val,
                        v_node_val,
                        v_tmp1,
                        v_one,
                        v_two,
                        v_n_nodes,
                        v_zero,
                        tmp_addr,
                        N_TMP_POOLS,
                    )
                )
            elif round_num in (1, 12):
                # Special round: two trees, select based on LSB
                round_ops.extend(
                    self._build_dual_tree_round(
                        round_num,
                        num_batches,
                        tree_1,
                        tree_2,
                        v_tmp3,
                        v_idx,
                        v_val,
                        v_node_val,
                        v_tmp1,
                        v_one,
                        v_two,
                        v_n_nodes,
                        v_zero,
                        tmp_addr,
                        N_TMP_POOLS,
                    )
                )
            else:
                # General round: gather load
                round_ops.extend(
                    self._build_general_round(
                        round_num,
                        num_batches,
                        idx_addr,
                        v_idx,
                        v_val,
                        v_node_val,
                        v_tmp1,
                        v_one,
                        v_two,
                        v_n_nodes,
                        v_zero,
                        N_TMP_POOLS,
                    )
                )

            all_round_instrs.extend(self.scheduler.build(round_ops, vliw=True))

        return all_round_instrs

    def _build_single_tree_round(
        self,
        round_num,
        num_batches,
        tree_0,
        v_idx,
        v_val,
        v_node_val,
        v_tmp1,
        v_one,
        v_two,
        v_n_nodes,
        v_zero,
        tmp_addr,
        N_TMP_POOLS,
    ) -> list[tuple[str, tuple[Any, ...]]]:
        """Build operations for single-tree rounds (0, 11)."""
        round_ops: list[tuple[str, tuple[Any, ...]]] = []

        # Load tree value
        round_ops.append(
            (
                "alu",
                ("+", tmp_addr, self.allocator.scratch["forest_values_p"], self.allocator.scratch_const(0)),
            )
        )
        round_ops.append(("load", ("load", tree_0, tmp_addr)))

        # Broadcast and XOR for all batches first
        for b in range(num_batches):
            batch_start = b * VLEN
            round_ops.append(("valu", ("vbroadcast", v_node_val[b], tree_0)))
            keys = tuple((round_num, batch_start + lane, "node_val") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_node_val[b], keys)))
            round_ops.append(("valu", ("^", v_val[b], v_val[b], v_node_val[b])))

        # Interleaved hash across all batches
        batches_info = [(v_val[b], v_node_val[b], v_val[b], b * VLEN) for b in range(num_batches)]
        round_ops.extend(self.hasher.build_vhash_interleaved(batches_info, round_num))

        # Index updates for all batches
        for b in range(num_batches):
            batch_start = b * VLEN
            tp = b % N_TMP_POOLS
            keys = tuple((round_num, batch_start + lane, "hashed_val") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_val[b], keys)))
            # Index update: idx = idx * 2 + ((val & 1) + 1) using multiply_add (3 ops vs 4)
            round_ops.append(("valu", ("&", v_tmp1[tp], v_val[b], v_one)))
            round_ops.append(("valu", ("+", v_tmp1[tp], v_tmp1[tp], v_one)))
            round_ops.append(("valu", ("multiply_add", v_idx[b], v_idx[b], v_two, v_tmp1[tp])))
            keys = tuple((round_num, batch_start + lane, "next_idx") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_idx[b], keys)))
            round_ops.append(("valu", ("<", v_tmp1[tp], v_idx[b], v_n_nodes)))
            round_ops.append(("flow", ("vselect", v_idx[b], v_tmp1[tp], v_idx[b], v_zero)))
            keys = tuple((round_num, batch_start + lane, "wrapped_idx") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_idx[b], keys)))

        return round_ops

    def _build_dual_tree_round(
        self,
        round_num,
        num_batches,
        tree_1,
        tree_2,
        v_tmp3,
        v_idx,
        v_val,
        v_node_val,
        v_tmp1,
        v_one,
        v_two,
        v_n_nodes,
        v_zero,
        tmp_addr,
        N_TMP_POOLS,
    ) -> list[tuple[str, tuple[Any, ...]]]:
        """Build operations for dual-tree rounds (1, 12)."""
        round_ops: list[tuple[str, tuple[Any, ...]]] = []

        # Load both tree values
        round_ops.append(
            (
                "alu",
                ("+", tmp_addr, self.allocator.scratch["forest_values_p"], self.allocator.scratch_const(1)),
            )
        )
        round_ops.append(("load", ("load", tree_1, tmp_addr)))
        round_ops.append(
            (
                "alu",
                ("+", tmp_addr, self.allocator.scratch["forest_values_p"], self.allocator.scratch_const(2)),
            )
        )
        round_ops.append(("load", ("load", tree_2, tmp_addr)))

        # Select node value and XOR for all batches first
        for b in range(num_batches):
            batch_start = b * VLEN
            tp = b % N_TMP_POOLS  # Rotate through temp pool
            round_ops.append(("valu", ("&", v_tmp1[tp], v_idx[b], v_one)))
            round_ops.append(("valu", ("vbroadcast", v_tmp3, tree_1)))
            round_ops.append(("valu", ("vbroadcast", v_node_val[b], tree_2)))
            round_ops.append(("flow", ("vselect", v_node_val[b], v_tmp1[tp], v_tmp3, v_node_val[b])))
            keys = tuple((round_num, batch_start + lane, "node_val") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_node_val[b], keys)))
            round_ops.append(("valu", ("^", v_val[b], v_val[b], v_node_val[b])))

        batches_info = [(v_val[b], v_node_val[b], v_val[b], b * VLEN) for b in range(num_batches)]
        round_ops.extend(self.hasher.build_vhash_interleaved(batches_info, round_num))

        # Index updates for all batches
        for b in range(num_batches):
            batch_start = b * VLEN
            tp = b % N_TMP_POOLS
            keys = tuple((round_num, batch_start + lane, "hashed_val") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_val[b], keys)))
            # Index update: idx = idx * 2 + ((val & 1) + 1) using multiply_add (3 ops vs 4)
            round_ops.append(("valu", ("&", v_tmp1[tp], v_val[b], v_one)))
            round_ops.append(("valu", ("+", v_tmp1[tp], v_tmp1[tp], v_one)))
            round_ops.append(("valu", ("multiply_add", v_idx[b], v_idx[b], v_two, v_tmp1[tp])))
            keys = tuple((round_num, batch_start + lane, "next_idx") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_idx[b], keys)))
            round_ops.append(("valu", ("<", v_tmp1[tp], v_idx[b], v_n_nodes)))
            round_ops.append(("flow", ("vselect", v_idx[b], v_tmp1[tp], v_idx[b], v_zero)))
            keys = tuple((round_num, batch_start + lane, "wrapped_idx") for lane in range(VLEN))
            round_ops.append(("debug", ("vcompare", v_idx[b], keys)))

        return round_ops

    def _build_general_round(
        self,
        round_num,
        num_batches,
        idx_addr,
        v_idx,
        v_val,
        v_node_val,
        v_tmp1,
        v_one,
        v_two,
        v_n_nodes,
        v_zero,
        N_TMP_POOLS,
    ) -> list[tuple[str, tuple[Any, ...]]]:
        """Build operations for general gather rounds."""
        round_ops: list[tuple[str, tuple[Any, ...]]] = []

        # General rounds: single gather load of current node value per lane (8 loads/batch)
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
                                self.allocator.scratch["forest_values_p"],
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
                            tuple((round_num, b * VLEN + lane, "node_val") for lane in range(VLEN)),
                        ),
                    )
                )

            if 0 <= compute_batch < num_batches:
                b = compute_batch
                round_ops.append(("valu", ("^", v_val[b], v_val[b], v_node_val[b])))

        batches_info = [(v_val[b], v_node_val[b], v_val[b], b * VLEN) for b in range(num_batches)]
        round_ops.extend(self.hasher.build_vhash_interleaved(batches_info, round_num))

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
            # Index update: idx = idx * 2 + ((val & 1) + 1) using multiply_add
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

        return round_ops

    def _build_finalization(self, num_batches: int) -> list[dict]:
        """
        Build finalization phase operations.

        Stores computed indices and values back to memory for all batches.

        Parameters
        ----------
        num_batches : int
            Number of VLEN-sized batches

        Returns
        -------
        list[dict]
            Instruction bundles for finalization
        """
        v_idx = self._state["v_idx"]
        v_val = self._state["v_val"]
        tmp_addr = self._state["tmp_addr"]
        batch_offsets = self._state["batch_offsets"]

        final_ops: list[tuple[str, tuple[Any, ...]]] = []
        for b in range(num_batches):
            final_ops.append(
                (
                    "alu",
                    (
                        "+",
                        tmp_addr,
                        self.allocator.scratch["inp_indices_p"],
                        batch_offsets[b],
                    ),
                )
            )
            final_ops.append(("store", ("vstore", tmp_addr, v_idx[b])))
            final_ops.append(
                (
                    "alu",
                    ("+", tmp_addr, self.allocator.scratch["inp_values_p"], batch_offsets[b]),
                )
            )
            final_ops.append(("store", ("vstore", tmp_addr, v_val[b])))

        return cast(list[dict[Any, Any]], self.scheduler.build(final_ops, vliw=True))
