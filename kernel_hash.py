"""Hash computation methods for VLIW SIMD kernel.

This module provides hash building functions extracted from KernelBuilder.
"""

from typing import Any

from problem import HASH_STAGES, VLEN


class HashBuilder:
    """Builds hash computation operations for tree traversal kernel.

    Parameters
    ----------
    scratch_allocator : object
        Object with vec_const(val) and scratch_const(val) methods for
        getting/creating constants in scratch memory.
    """

    def __init__(self, scratch_allocator):
        self.scratch_allocator = scratch_allocator

    def scratch_const(self, val, name=None):
        """Get or create a scalar constant in scratch memory."""
        return self.scratch_allocator.scratch_const(val, name)

    def vec_const(self, val):
        """Get or create a vector constant (broadcast to VLEN words)."""
        return self.scratch_allocator.vec_const(val)

    def build_hash(self, val_hash_addr, tmp1, tmp2, round, i):
        """Build scalar hash function slots (deprecated, use build_vhash)."""
        slots: list[tuple[str, tuple[Any, ...]]] = []
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
        slots: list[tuple[str, tuple[Any, ...]]] = []
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
        slots: list[tuple[str, tuple[Any, ...]]] = []
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
