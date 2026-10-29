# libxdrfile

GROMACS libxdrfile 1.1.4 的一个 fork，含 chemfiles 项目所需的补丁，采用 BSD 许可。

本库用于读取 GROMACS 的 **trr** 和 **xtc** 轨迹文件，并支持格式间的相互转换。

> 英文版说明见 [README.en.md](README.en.md)。

---

## 目录

- [构建 C 库](#构建-c-库)
- [Python 绑定（重点）](#python-绑定重点)
  - [功能概览](#功能概览)
  - [环境要求](#环境要求)
  - [Linux 编译与使用](#linux-编译与使用)
  - [Windows 编译与使用](#windows-编译与使用)
  - [API 参考](#api-参考)
  - [数据语义与精度](#数据语义与精度)
  - [已知边界](#已知边界)
  - [ctypes 保底方案](#ctypes-保底方案)
- [许可](#许可)

---

## 构建 C 库

标准 CMake 流程：

```sh
cmake -S . -B build -G Ninja
cmake --build build
ctest --test-dir build --output-on-failure
```

> 本仓库 `CMakeLists.txt` 声明的最低版本为 2.8.12，新版 CMake（≥3.5）需加
> `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`。Windows 上若缺 SDK 的 `rc.exe`，可加
> `-DCMAKE_EXE_LINKER_FLAGS="/MANIFEST:NO"` 禁用清单嵌入。

---

## Python 绑定（重点）

仓库已附带一个 **Cython 绑定**（位于 `wrapper/` 目录），用于在 Python 中读写 XTC 轨迹，
坐标直接暴露为 **numpy `float32` 数组**（零拷贝），无需 DLPack。这是 Python 场景下的
首选路径。

### 功能概览

| 能力 | 说明 |
|---|---|
| 读 | `natoms` / `frame_info` / `read_frame` / `read_all` |
| 写 | `write_frame`（支持追加） |
| 数据类型 | 坐标 `float32`，形状 `(natoms, 3)` 或 `(nframes, natoms, 3)`；box 为完整三斜 `3×3` 矩阵 |
| 零拷贝 | 解压结果直接写入预分配的 numpy 缓冲区，无中间拷贝 |
| 预分配 | `read_all` 一次读完整条轨迹，最高效 |
| 保底方案 | `xdrfile_ctypes.py`（走独立 SHARED 库，不推荐生产） |

### 环境要求

- Python ≥ 3.9
- C 编译器（Linux：gcc/clang；Windows：MSVC 或 BuildTools）
- `pip install cython numpy setuptools`

### Linux 编译与使用

Linux 下最简单，无需处理 Windows 特有的工具链问题。

```sh
# 1. 安装 C 编译器与 Python 开发头文件（多数发行版已自带）
sudo apt install gcc python3-dev          # Debian / Ubuntu
# sudo dnf install gcc python3-devel       # Fedora / CentOS

# 2. 安装 Python 构建依赖
pip install cython numpy setuptools

# 3. 进入 wrapper 目录编译安装
cd wrapper
pip install .
```

一条命令等价写法：`cd wrapper && pip install .`

`setup.py` 会自动检测平台并在 Linux 上追加 `-O2 -fPIC`，产物为
`_xdrfile.cpython-3XX-x86_64-linux-gnu.so`。

使用示例：

```python
import _xdrfile as xtc

# 读单个文件的原子数、帧数
n = xtc.natoms("traj.xtc")
natoms, nframes = xtc.frame_info("traj.xtc")

# 一次性读整条轨迹（预分配，最高效）
xyz, box, time, step = xtc.read_all("traj.xtc")
# xyz  : (nframes, natoms, 3)  float32
# box  : (nframes, 3, 3)       float32（完整三斜矩阵）
# time : (nframes,)            float32
# step : (nframes,)            int32

# 读某一帧（0 起始）
x, b, t, s = xtc.read_frame("traj.xtc", i)   # x:(natoms,3) b:(3,3)

# 写一帧
xtc.write_frame("out.xtc", xyz_i, box_i, time=t, step=s, prec=1000.0)
# append=True 时追加而非覆盖
```

构建可分发的 wheel：

```sh
cd wrapper && pip wheel . -w dist        # 产出 .whl
pip install dist/xdrfile_python-0.1.0-*.whl
```

### Windows 编译与使用

Windows 下需先设置 MSVC 工具链，其余步骤与 Linux 相同。先用
`vcvars64.bat` 初始化环境，再执行与 Linux 相同的安装步骤：

```bat
cd wrapper
pip install .
```

> 若在沙箱环境中 `vcvars64.bat` 因 `reg.exe` 被拦截而无法注入
> `INCLUDE`/`LIB`，需手动设置 MSVC / Windows SDK 的 `INCLUDE`、`LIB`、`PATH`
> 环境变量后再执行上一步。核心变量等价于：

```bat
set MSVC=<Visual Studio BuildTools 的 MSVC 路径>
set SDK=<Windows Kits 路径>
set INCLUDE=%MSVC%\include;%SDK%\Include\<版本>\ucrt;%SDK%\Include\<版本>\um;%SDK%\Include\<版本>\shared
set LIB=%MSVC%\lib\x64;%SDK%\Lib\<版本>\ucrt\x64;%SDK%\Lib\<版本>\um\x64
set PATH=%MSVC%\bin\Hostx64\x64;%SDK%\bin\<版本>\x64;%PATH%
```

> `<版本>` 请按本机实际安装的 MSVC / SDK 版本号调整。

### API 参考

| 函数 | 签名 | 返回值 |
|---|---|---|
| `natoms` | `natoms(path)` | `int` |
| `frame_info` | `frame_info(path)` | `(natoms, nframes)` |
| `read_frame` | `read_frame(path, frame)` | `(xyz, box, time, step)` |
| `read_all` | `read_all(path)` | `(xyz, box, time, step)` |
| `write_frame` | `write_frame(path, xyz, box, time=0.0, step=0, prec=1000.0, append=False)` | `None` |

其中 `xyz` 为 `(natoms, 3)`（`read_frame`）或 `(nframes, natoms, 3)`（`read_all`）的
`float32`；`box` 为 `(3, 3)`（`read_frame`）或 `(nframes, 3, 3)`（`read_all`）的
`float32`；`time`/`step` 分别为 `float32` 标量（或对应长度的一维数组）。

### 数据语义与精度

| 项 | 说明 |
|---|---|
| 坐标 dtype | 始终 `float32` |
| box | 三斜盒子完整 `3×3` 矩阵，**勿丢弃非对角项** |
| 单位 | 沿用 GROMACS 惯例（nm） |
| 精度 | XTC 是有损压缩，`prec=1000.0` 对应约 3 位小数（1e-3 nm）；往返校验用 `np.allclose(atol=1e-3)` 而非 `==` |

### 已知边界（来自 libxdrfile 内部）

1. **`read_xtc` 会忽略调用方传入的 `natoms`**，改用文件头里的值。因此本绑定总先用
   `read_xtc_natoms()` 取得权威值再分配缓冲区，规避了上游"缓冲偏小即堆溢出"的风险。
2. **`read_xtc_header` 的 `offsets` 由库内 `malloc` 且无配套 free**，跨 CRT 释放是未定义
   行为。本绑定**不暴露**该路径，帧数通过公开的 `xdr_seek`/`xdr_tell` 扫描得到。
3. **越界帧**抛出 `IndexError`；坏魔数抛出 `XtcError`。
4. XTC **无 trailer / 无帧索引**，文件只要在帧边界结束即可读；被截断不会报错，只会静默
   少帧。

### ctypes 保底方案

`wrapper/xdrfile_ctypes.py` 是构建 Cython 扩展之前的兜底，通过独立 SHARED 库
（`libxdrfile_shared`，由 `wrapper/CMakeLists.txt` 产出）来读写。**不推荐生产使用**：
多一次拷贝，且 C 侧 `malloc` 的跨 CRT 释放存在风险。

#### 自行构建 SHARED 库

由 `wrapper/CMakeLists.txt` 单独编译一份动态库（只编 `xdrfile.c` +
`xdrfile_xtc.c`，与根 `CMakeLists.txt` 的 OBJECT 库互不影响）：

```sh
cd wrapper
cmake -S . -B build -G Ninja      # 1) 配置，生成 build/ 与构建脚本
cmake --build build               # 2) 编译，真正产出生动态库
```

**产物位置与命名**：由 `add_library(xdrfile_shared SHARED ...)` 决定，默认输出到
`wrapper/build/` 目录，文件名按平台固定为：

| 平台 | 产物路径 |
|---|---|
| Linux / 其他 | `wrapper/build/libxdrfile_shared.so` |
| Windows | `wrapper/build/xdrfile_shared.dll` |
| macOS | `wrapper/build/libxdrfile_shared.dylib` |

这正是 `_load_shared()` 的第二处搜索位置（`wrapper/` 同目录下的 `build/`），因此
**编完即可被 ctypes 直接加载，无需手动搬运**。

> Windows 注意：需先初始化 MSVC 环境（见上文“Windows 编译与使用”），并使用
> `-G Ninja`；`CMakeLists.txt` 已设置 `WINDOWS_EXPORT_ALL_SYMBOLS ON` 为所有全局
> 符号生成 `.def`（源码无 `__declspec(dllexport)`），缺它则 DLL 导出表为空、能加载
> 但找不到符号。

验证产物已生成：

```sh
ls wrapper/build/*xdrfile_shared.*
```

#### 使用别处编译好的动态库

若手头已有一份预编译的 SHARED 库（例如别人在另一台机器上用
`wrapper/CMakeLists.txt` 编好、分发给你），按以下约定即可免编译调用——这
正是 ctypes 兜底“不需要编译环境”的实际用法：

1. **库文件名必须符合固定命名**，`_load_shared()` 只会按这个名字查找：

   | 平台 | 库文件名 |
   |---|---|
   | Windows | `xdrfile_shared.dll` |
   | macOS | `libxdrfile_shared.dylib` |
   | Linux / 其他 | `libxdrfile_shared.so` |

   从别处拿到的库请先重命名为上表对应的名字。

2. **把库放到三处候选位置之一**（按优先级搜索）：

   1. `xdrfile_ctypes.py` 所在的同一目录（`wrapper/`）；
   2. `wrapper/build/`（上文自行构建时的默认产物目录）；
   3. 系统 `PATH` 中的任意目录。

3. **就地调用**（该模块不参与 `pip` 打包，需在源码目录内直接 import）：

   ```python
   import sys
   sys.path.insert(0, "wrapper")     # 让 Python 找到 xdrfile_ctypes.py
   import xdrfile_ctypes as xtc

   n = xtc.natoms("traj.xtc")
   xyz, box, time, step = xtc.read_all("traj.xtc")   # 与 Cython 版同名同形
   xtc.write_frame("out.xtc", xyz[0], box[0])
   ```

   暴露的 `natoms` / `read_all` / `write_frame` 签名与 Cython 生产路径一致。

4. **找不到库会抛 `OSError`**，提示改用 CMake 构建，或回到编译好的
   `_xdrfile` 扩展。

> 再次提醒：此路径在 Windows 上存在 C 侧 `malloc` 跨 CRT 释放风险，且多一次
> 内存拷贝，仅建议在没有编译环境的临时场景使用。

---

## 许可

BSD 3-Clause，见 [COPYING](COPYING)。