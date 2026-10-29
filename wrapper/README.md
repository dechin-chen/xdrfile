# xdrfile-python

Cython 绑定，用于读写 GROMACS **XTC** 轨迹，坐标以 **numpy `float32` 数组**直接暴露（零拷贝），无需 DLPack。

底层是 [libxdrfile](https://github.com/chemfiles/xdrfile)（BSD-3-Clause），本包只编译 XTC 读写路径（`xdrfile.c` + `xdrfile_xtc.c`），不包含 TRR。

## 快速开始

```python
import _xdrfile as xtc

# 读单个文件的原子数、帧数
n = xtc.natoms("traj.xtc")
natoms, nframes = xtc.frame_info("traj.xtc")

# 一次性读整条轨迹（预分配，最高效）
xyz, box, time, step = xtc.read_all("traj.xtc")
# xyz    : (nframes, natoms, 3)  float32
# box    : (nframes, 3, 3)       float32（完整三斜矩阵）
# time   : (nframes,)            float32
# step   : (nframes,)            int32

# 读某一帧（0 起始）
x, b, t, s = xtc.read_frame("traj.xtc", i)   # x:(natoms,3) b:(3,3)

# 写一帧
xtc.write_frame("out.xtc", xyz_i, box_i, time=t, step=s, prec=1000.0)
# append=True 时追加而非覆盖
```

## 构建

### 依赖

- Python ≥ 3.9
- C 编译器（MSVC / GCC / Clang）
- `pip install cython numpy setuptools`

兼容性说明：本包产物 C API 需要 numpy 头文件在构建期可见（`setup.py` 已通过 `numpy.get_include()` 处理），运行期可用任意 ≥2.0 的 numpy。

### Linux / macOS

```sh
cd wrapper
pip install .
```

### Windows（BuildTools 环境）

先用 `vcvars64.bat` 初始化 MSVC 环境，再编译：

```bat
cd wrapper
pip install .
```

> 若在沙箱环境中 `vcvars64.bat` 因 `reg.exe` 被拦截而无法注入
> `INCLUDE`/`LIB`，需手动设置 MSVC 与 Windows SDK 的 `INCLUDE`/`LIB`/`PATH`
> 环境变量后再执行 `pip install .`。

## 数据语义与精度

| 项 | 说明 |
|---|---|
| 坐标 dtype | 始终 `float32`，形状 `(natoms, 3)` 或 `(nframes, natoms, 3)` |
| box | 三斜盒子完整 `3×3` 矩阵，**勿丢弃非对角项** |
| 单位 | 沿用 GROMACS 惯例（nm）；`prec` 是量化因子 |
| 精度 | XTC 是有损压缩，`prec=1000.0` 对应约 3 位小数（1e-3 nm）；往返校验用 `np.allclose(atol=1e-3)` 而非 `==` |

## 已知边界（来自 libxdrfile 内部）

1. **`read_xtc` 会忽略调用方传入的 `natoms`**，改用文件头里的值。因此本包总先用 `read_xtc_natoms()` 取得权威值再分配缓冲区；缓冲偏小在上游会堆溢出，本包已规避。
2. **`read_xtc_header` 的 `offsets` 由库内 `malloc` 且无配套 free**，跨 CRT 释放是未定义行为（Windows 大概率崩）。本包**不暴露**该路径，帧数通过公开的 `xdr_seek`/`xdr_tell` 扫描得到。
3. **越界帧**读取出错误码 `exdrENDOFFILE` 时抛 `IndexError`；坏魔数抛 `XtcError`。
4. XTC **无 trailer / 无帧索引**，文件只要在帧边界结束即可读；被截断不会报错，只会静默少帧。

## ctypes 保底方案

`xdrfile_ctypes.py` 是构建 Cython 扩展之前的兜底，使用独立 SHARED 库（`libxdrfile_shared`，由 `CMakeLists.txt` 产出）。**不推荐生产使用**：多一次拷贝、且 C 侧 malloc 的跨 CRT 释放存在风险。

```sh
cmake -S . -B build -G Ninja   # 需先建 WINDOWS_EXPORT_ALL_SYMBOLS 等
```

## 目录结构

```
wrapper/
├── _xdrfile.pyx         # Cython 绑定（生产路径）
├── xdrfile_ctypes.py    # ctypes 兜底
├── setup.py             # 编译 4 个 C 源文件进单 .pyd
├── pyproject.toml
├── CMakeLists.txt       # 独立 SHARED 库（供 ctypes/其他语言）
└── README.md
```

上游源码位于 `../src`、`../include`，编译时以绝对路径引用，**不改动上游任何文件**。