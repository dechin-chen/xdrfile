# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026 Dechin CHEN
# Python bindings for GROMACS libxdrfile (upstream: Erik Lindahl &
# David van der Spoel, BSD 3-Clause). See COPYING in the repository root.
"""ctypes 保底绑定 —— 不作为生产路径。

正常使用请走编译好的 ``_xdrfile`` Cython 扩展（零拷贝 numpy）。
本模块仅用于：没有编译环境、或需要直接调用 SHARED 库（wrapper/CMakeLists.txt
产出的 libxdrfile_shared）时的兜底。

注意：ctypes 路径会多一次 C buffer -> numpy 的拷贝，且 C 侧的 malloc 释放
由 Python 侧的 ``ctypes`` 处理时，跨 CRT 在 Windows 上存在风险，故不推荐生产使用。
"""

import ctypes
import os
import sys

import numpy as np


def _load_shared():
    name = {
        "win32": "xdrfile_shared.dll",
        "darwin": "libxdrfile_shared.dylib",
    }.get(sys.platform, "libxdrfile_shared.so")
    here = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(here, name),
        os.path.join(here, "build", name),
        name,
    ]
    for c in candidates:
        if os.path.exists(c):
            return ctypes.CDLL(c)
    raise OSError("找不到 SHARED 库，请先用 wrapper/CMakeLists.txt 构建；"
                  "或使用编译好的 _xdrfile 扩展。")


class XDRFILE(ctypes.Structure):
    pass


_lib = None


def _lib_once():
    global _lib
    if _lib is None:
        _lib = _load_shared()
        _lib.xdrfile_open.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        _lib.xdrfile_open.restype = ctypes.POINTER(XDRFILE)
        _lib.xdrfile_close.argtypes = [ctypes.POINTER(XDRFILE)]
        _lib.xdrfile_close.restype = ctypes.c_int
        _lib.read_xtc_natoms.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_int)]
        _lib.read_xtc_natoms.restype = ctypes.c_int
        _lib.read_xtc.argtypes = [
            ctypes.POINTER(XDRFILE), ctypes.c_int,
            ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_float),
            (ctypes.c_float * 3) * 3, ctypes.POINTER(ctypes.c_float),
            ctypes.POINTER(ctypes.c_float),
        ]
        _lib.read_xtc.restype = ctypes.c_int
        _lib.write_xtc.argtypes = [
            ctypes.POINTER(XDRFILE), ctypes.c_int, ctypes.c_int, ctypes.c_float,
            (ctypes.c_float * 3) * 3, ctypes.POINTER(ctypes.c_float),
            ctypes.c_float,
        ]
        _lib.write_xtc.restype = ctypes.c_int
    return _lib


def natoms(path):
    _l = _lib_once()
    n = ctypes.c_int()
    code = _l.read_xtc_natoms(path.encode(), ctypes.byref(n))
    if code != 0:
        raise RuntimeError("read_xtc_natoms failed: %d" % code)
    return n.value


def read_all(path):
    n = natoms(path)
    _l = _lib_once()
    xd = _l.xdrfile_open(path.encode(), b"r")
    if not xd:
        raise RuntimeError("打开失败")
    step = ctypes.c_int()
    t = ctypes.c_float()
    prec = ctypes.c_float()
    box = ((ctypes.c_float * 3) * 3)()
    frames = []
    boxes = []
    times = []
    steps = []
    try:
        while True:
            buf = np.empty((n, 3), dtype=np.float32)
            code = _l.read_xtc(
                xd, n, ctypes.byref(step), ctypes.byref(t), box,
                buf.ctypes.data_as(ctypes.POINTER(ctypes.c_float)),
                ctypes.byref(prec),
            )
            if code == 11:  # exdrENDOFFILE
                break
            if code != 0:
                raise RuntimeError("read_xtc failed: %d" % code)
            frames.append(buf.copy())
            boxes.append(np.array(box, dtype=np.float32).copy())
            times.append(t.value)
            steps.append(step.value)
    finally:
        _l.xdrfile_close(xd)
    return (np.stack(frames), np.stack(boxes),
            np.array(times, np.float32), np.array(steps, np.int32))


def write_frame(path, xyz, box, time=0.0, step=0, prec=1000.0):
    x = np.ascontiguousarray(xyz, np.float32)
    b = np.ascontiguousarray(box, np.float32)
    n = x.shape[0]
    _l = _lib_once()
    xd = _l.xdrfile_open(path.encode(), b"w")
    if not xd:
        raise RuntimeError("打开失败")
    m = ((ctypes.c_float * 3) * 3)()
    for i in range(3):
        for j in range(3):
            m[i][j] = b[i, j]
    code = _l.write_xtc(
        xd, n, int(step), float(time), m,
        x.ctypes.data_as(ctypes.POINTER(ctypes.c_float)), float(prec),
    )
    _l.xdrfile_close(xd)
    if code != 0:
        raise RuntimeError("write_xtc failed: %d" % code)