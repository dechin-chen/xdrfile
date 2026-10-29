# cython: language_level=3
# cython: boundscheck=False
# cython: wraparound=False
# cython: cdivision=True
# cython: initializedcheck=False
# distutils: language = c

# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026 Dechin CHEN
# Python bindings for GROMACS libxdrfile (upstream: Erik Lindahl &
# David van der Spoel, BSD 3-Clause). See COPYING in the repository root.

"""Cython binding for libxdrfile XTC read/write.

Reads and writes GROMACS XTC trajectories. Coordinates are exposed as
zero-copy numpy arrays of dtype float32 and shape (natoms, 3) or
(nframes, natoms, 3).

Key correctness notes (mirrored from libxdrfile internals):
  * read_xtc() ignores the caller's ``natoms`` argument and uses the value in
    the file header, so the output buffer must be sized from read_xtc_natoms()
    to avoid heap overflow.
  * read_xtc_header()'s ``offsets`` pointer is malloc'd inside the library with
    no matching free entry point, so it is never exposed here. Frame offsets
    are recomputed internally via the public xdr_seek/xdr_tell when needed.
  * The box is stored as a full triclinic 3x3 matrix (float32); do not drop the
    off-diagonal terms.
"""

import numpy as np
cimport numpy as cnp
from libc.stdint cimport int64_t

cnp.import_array()

cdef extern from "xdrfile.h":
    ctypedef struct XDRFILE:
        pass

    ctypedef float matrix[3][3]
    ctypedef float rvec[3]

    int exdrOK
    int exdrENDOFFILE
    int exdrFILENOTFOUND
    int exdrMAGIC
    int exdr3DX
    int exdrINT
    int exdrFLOAT
    int exdrNOMEM
    int exdrNR

    XDRFILE* xdrfile_open(const char* path, const char* mode)
    int xdrfile_close(XDRFILE* xfp)

    int64_t xdr_tell(XDRFILE* xd)
    int xdr_seek(XDRFILE* xd, int64_t pos, int whence)

cdef extern from "xdrfile_xtc.h":
    int read_xtc_natoms(const char* fn, int* natoms)
    int read_xtc_header(const char* fn, int* natoms, unsigned long* nframes,
                        int64_t** offsets)
    int read_xtc(XDRFILE* xd, int natoms, int* step, float* time,
                 matrix box, rvec* x, float* prec)
    int write_xtc(XDRFILE* xd, int natoms, int step, float time,
                  matrix box, rvec* x, float prec)


class XtcError(Exception):
    """Raised when libxdrfile returns an error code."""


cdef inline void _check(int code) except *:
    if code != exdrOK:
        raise XtcError(_message(code))


cdef str _message(int code):
    if code == exdrENDOFFILE:
        return "end of file reached"
    elif code == exdrFILENOTFOUND:
        return "file not found"
    elif code == exdrMAGIC:
        return "bad magic number (not an XTC file)"
    elif code == exdr3DX:
        return "error decompressing 3D coordinates"
    elif code == exdrINT:
        return "error reading/writing integer"
    elif code == exdrFLOAT:
        return "error reading/writing float"
    elif code == exdrNOMEM:
        return "out of memory"
    else:
        return "xdrfile error code %d" % code


cdef inline int _natoms(const char* path) except -1:
    cdef int n = 0
    _check(read_xtc_natoms(path, &n))
    return n


def natoms(path):
    """Return the number of atoms declared in the XTC file header."""
    cdef bytes p = _fsencode(path)
    cdef int n = _natoms(p)
    return int(n)


def frame_info(path):
    """Return ``(natoms, nframes)`` for an XTC file.

    The frame count is computed by scanning the file with the public
    xdr_seek/xdr_tell entry points, never via read_xtc_header whose ``offsets``
    buffer has no matching free() in the library.
    """
    cdef bytes p = _fsencode(path)
    cdef int n = 0
    _check(read_xtc_natoms(p, &n))

    cdef XDRFILE* xd = xdrfile_open(p, b"r")
    if xd == NULL:
        raise XtcError("could not open file: %r" % (path,))
    cdef int step = 0
    cdef float t = 0.0
    cdef float prec = 0.0
    cdef matrix box
    cdef cnp.ndarray[cnp.float32_t, ndim=2, mode="c"] x = \
        np.empty((n, 3), dtype=np.float32)
    cdef rvec* xp = <rvec*>&x[0, 0]
    cdef int count = 0
    cdef int code
    try:
        while True:
            code = read_xtc(xd, n, &step, &t, box, xp, &prec)
            if code == exdrENDOFFILE:
                break
            _check(code)
            count += 1
    finally:
        xdrfile_close(xd)
    return int(n), int(count)


def read_frame(path, int frame):
    """Read a single 0-indexed frame.

    Returns ``(xyz, box, time, step)`` where ``xyz`` is ``(natoms, 3)`` float32
    and ``box`` is ``(3, 3)`` float32.
    """
    cdef bytes p = _fsencode(path)
    cdef int n = 0
    _check(read_xtc_natoms(p, &n))

    cdef XDRFILE* xd = xdrfile_open(p, b"r")
    if xd == NULL:
        raise XtcError("could not open file: %r" % (path,))

    cdef int step = 0
    cdef float time = 0.0
    cdef float prec = 0.0
    cdef matrix box
    cdef cnp.ndarray[cnp.float32_t, ndim=2, mode="c"] x = \
        np.empty((n, 3), dtype=np.float32)
    cdef rvec* xp = <rvec*>&x[0, 0]
    cdef int i = 0
    cdef int code
    try:
        while i <= frame:
            code = read_xtc(xd, n, &step, &time, box, xp, &prec)
            if code == exdrENDOFFILE:
                raise IndexError("frame %d out of range" % frame)
            _check(code)
            i += 1
    finally:
        xdrfile_close(xd)

    cdef cnp.ndarray[cnp.float32_t, ndim=2, mode="c"] b = \
        np.empty((3, 3), dtype=np.float32)
    b[...] = _box_to_array(box)
    return x, b, float(time), int(step)


def read_all(path):
    """Read an entire trajectory into a single preallocated array.

    Returns ``(xyz, box, time, step)`` with shapes (nframes, natoms, 3),
    (nframes, 3, 3), (nframes,), (nframes,).
    """
    cdef int n, nf
    n, nf = frame_info(path)
    cdef bytes p = _fsencode(path)

    cdef cnp.ndarray[cnp.float32_t, ndim=3, mode="c"] xyz = \
        np.empty((nf, n, 3), dtype=np.float32)
    cdef cnp.ndarray[cnp.float32_t, ndim=3, mode="c"] box = \
        np.empty((nf, 3, 3), dtype=np.float32)
    cdef cnp.ndarray[cnp.float32_t, ndim=1, mode="c"] times = \
        np.empty(nf, dtype=np.float32)
    cdef cnp.ndarray[cnp.int32_t, ndim=1, mode="c"] steps = \
        np.empty(nf, dtype=np.int32)

    cdef XDRFILE* xd = xdrfile_open(p, b"r")
    if xd == NULL:
        raise XtcError("could not open file: %r" % (path,))

    cdef int step = 0
    cdef float t = 0.0
    cdef float prec = 0.0
    cdef matrix m
    cdef int i = 0
    cdef int code
    try:
        while i < nf:
            code = read_xtc(xd, n, &step, &t, m,
                            <rvec*>&xyz[i, 0, 0], &prec)
            _check(code)
            times[i] = t
            steps[i] = step
            box[i] = _box_to_array(m)
            i += 1
    finally:
        xdrfile_close(xd)

    return xyz, box, times, steps


def write_frame(path, xyz, box, time=0.0, step=0, prec=1000.0,
                bint append=False):
    """Write one frame to an XTC file.

    ``xyz`` must be a C-contiguous float32 array of shape (natoms, 3).
    ``box`` must be float32 of shape (3, 3). ``prec`` controls lossy
    compression (default 1000.0 == three decimal places).
    """
    cdef cnp.ndarray[cnp.float32_t, ndim=2, mode="c"] x = \
        np.ascontiguousarray(xyz, dtype=np.float32)
    cdef cnp.ndarray[cnp.float32_t, ndim=2, mode="c"] b = \
        np.ascontiguousarray(box, dtype=np.float32)
    if x.shape[1] != 3:
        raise ValueError("xyz must have shape (natoms, 3)")
    if b.shape[0] != 3 or b.shape[1] != 3:
        raise ValueError("box must have shape (3, 3)")

    cdef int n = x.shape[0]
    cdef bytes p = _fsencode(path)
    cdef bytes mode = b"a" if append else b"w"
    cdef XDRFILE* xd = xdrfile_open(p, mode)
    if xd == NULL:
        raise XtcError("could not open file: %r" % (path,))

    cdef matrix m
    m[0][0] = b[0, 0]; m[0][1] = b[0, 1]; m[0][2] = b[0, 2]
    m[1][0] = b[1, 0]; m[1][1] = b[1, 1]; m[1][2] = b[1, 2]
    m[2][0] = b[2, 0]; m[2][1] = b[2, 1]; m[2][2] = b[2, 2]

    cdef int s = int(step)
    cdef float t = float(time)
    cdef float pr = float(prec)
    cdef rvec* xp = <rvec*>&x[0, 0]
    cdef int code
    try:
        code = write_xtc(xd, n, s, t, m, xp, pr)
    finally:
        xdrfile_close(xd)
    _check(code)


cdef inline cnp.float32_t[:, ::1] _box_to_array(matrix box):
    cdef cnp.ndarray[cnp.float32_t, ndim=2, mode="c"] b = \
        np.empty((3, 3), dtype=np.float32)
    b[0, 0] = box[0][0]; b[0, 1] = box[0][1]; b[0, 2] = box[0][2]
    b[1, 0] = box[1][0]; b[1, 1] = box[1][1]; b[1, 2] = box[1][2]
    b[2, 0] = box[2][0]; b[2, 1] = box[2][1]; b[2, 2] = box[2][2]
    return b


cdef inline bytes _fsencode(path):
    """Encode a path (str or bytes) to the filesystem encoding."""
    if isinstance(path, bytes):
        return path
    return (<str>path).encode('utf-8')