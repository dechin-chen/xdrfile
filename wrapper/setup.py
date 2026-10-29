# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026 Dechin CHEN
# Python bindings for GROMACS libxdrfile (upstream: Erik Lindahl &
# David van der Spoel, BSD 3-Clause). See COPYING in the repository root.

import os
import sys

import numpy

from Cython.Build import cythonize
from setuptools import Extension, setup

# 上游 xdrfile 源码：相对本文件 ../src 与 ../include
_XDRFILE_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

SOURCES = [
    "src/xdrfile.c",
    "src/xdrfile_xtc.c",
    # trr 不编译，XTC 路径即可
]

_sources = ["_xdrfile.pyx"] + [os.path.join(_XDRFILE_ROOT, s) for s in SOURCES]

extra_compile_args = []
extra_link_args = []
define_macros = [("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")]

if sys.platform == "win32":
    # 强制链接到 CPython 的 release CRT（/MD），避免与 Debug（/MDd）混用
    # 导致的 LNK2038 或加载后崩溃。
    extra_compile_args += ["/O2", "/MD"]
else:
    # Linux/macOS 下默认即可；显式优化级别，方便 CI 复现。
    extra_compile_args += ["-O2", "-fPIC"]

ext = Extension(
    "_xdrfile",
    sources=_sources,
    include_dirs=[numpy.get_include(), os.path.join(_XDRFILE_ROOT, "include")],
    define_macros=define_macros,
    extra_compile_args=extra_compile_args,
    extra_link_args=extra_link_args,
)

setup(
    name="xdrfile-python",
    version="0.1.0",
    description="Cython binding for libxdrfile: read/write GROMACS XTC into numpy arrays",
    ext_modules=cythonize([ext], compiler_directives={"language_level": "3"}),
)