# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2026 Dechin CHEN
# Python bindings for GROMACS libxdrfile (upstream: Erik Lindahl &
# David van der Spoel, BSD 3-Clause). See COPYING in the repository root.

# 独立的 SHARED 库构建 —— 用于 ctypes 保底方案。
#
# 与仓库根 CMakeLists.txt 分开，是为了不改动上游文件：
#   * 仓库只定义 OBJECT 库，这里单独编译一份 SHARED（.so/.dll/.dylib）。
#   * Windows 上必须 WINDOWS_EXPORT_ALL_SYMBOLS，否则 DLL 导出表为空，
#     ctypes 能加载但找不到符号。
#
# 正常 Python 使用应走 setup.py（把源码直接编进单 .pyd，无 DLL 依赖）；
# 本文件仅当你需要一份独立动态库时使用。
cmake_minimum_required(VERSION 3.16)

project(xdrfile_shared C)

get_filename_component(_XDR_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

add_library(xdrfile_shared SHARED
    ${_XDR_ROOT}/src/xdrfile.c
    ${_XDR_ROOT}/src/xdrfile_xtc.c
)
target_include_directories(xdrfile_shared PUBLIC ${_XDR_ROOT}/include)

if (WIN32)
    # WINDOWS_EXPORT_ALL_SYMBOLS 会为所有全局符号生成 .def，缺它则 DLL 导出表
    # 为空（源码无 __declspec(dllexport)），ctypes 能加载但找不到符号。
    # 若用 cl.exe 直接编译（不经 CMake），需手动 /EXPORT:xdrfile_open 等逐个导出。
    set_target_properties(xdrfile_shared PROPERTIES
        WINDOWS_EXPORT_ALL_SYMBOLS ON
        C_STANDARD 99
    )
    target_compile_options(xdrfile_shared PRIVATE /O2 /MD)
else()
    set_target_properties(xdrfile_shared PROPERTIES C_STANDARD 99)
    target_compile_options(xdrfile_shared PRIVATE -O2 -fPIC)
endif()