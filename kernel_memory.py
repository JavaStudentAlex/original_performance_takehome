"""Memory and scratch management for VLIW SIMD kernel building.

This module provides the ScratchAllocator class for managing scratch memory
allocation and constant caching in the kernel builder.
"""

from problem import SCRATCH_SIZE, VLEN, DebugInfo


class ScratchAllocator:
    """
    Manages scratch memory allocation and constant caching for kernel building.

    Parameters
    ----------
    vlen : int, optional
        Vector length for SIMD operations (default: VLEN from problem.py).
    scratch_size : int, optional
        Total scratch memory size in words (default: SCRATCH_SIZE from problem.py).

    Attributes
    ----------
    scratch : dict
        Maps symbolic names to scratch addresses.
    scratch_debug : dict
        Maps scratch addresses to (name, length) tuples for debugging.
    scratch_ptr : int
        Next available scratch address.
    const_map : dict
        Maps scalar constant values to their scratch addresses.
    vec_const_map : dict
        Maps vector constant values to their scratch addresses.
    """

    def __init__(self, vlen=VLEN, scratch_size=SCRATCH_SIZE):
        self.vlen = vlen
        self.scratch_size = scratch_size
        self.scratch = {}
        self.scratch_debug = {}
        self.scratch_ptr = 0
        self.const_map = {}
        self.vec_const_map = {}

    def debug_info(self):
        """Return debug information for scratch memory mapping."""
        return DebugInfo(scratch_map=self.scratch_debug)

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
        assert self.scratch_ptr <= self.scratch_size, "Out of scratch space"
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
        tuple of (int, list)
            Tuple containing:
            - Scratch address containing the constant
            - List of instructions needed to initialize (empty if already exists)
        """
        if val not in self.const_map:
            addr = self.alloc_scratch(name)
            instrs = [{"load": [("const", addr, val)]}]
            self.const_map[val] = addr
            return addr, instrs
        return self.const_map[val], []

    def vec_const(self, val):
        """
        Get or create a vector constant (broadcast to VLEN words).

        Parameters
        ----------
        val : int
            Constant value to broadcast.

        Returns
        -------
        tuple of (int, list)
            Tuple containing:
            - Scratch address of vector constant (VLEN words)
            - List of instructions needed to initialize (empty if already exists)
        """
        if val not in self.vec_const_map:
            scalar, scalar_instrs = self.scratch_const(val)
            vec = self.alloc_scratch(f"vc_{val}", self.vlen)
            vec_instrs = scalar_instrs + [{"valu": [("vbroadcast", vec, scalar)]}]
            self.vec_const_map[val] = vec
            return vec, vec_instrs
        return self.vec_const_map[val], []
