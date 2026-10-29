# libxdrfile

A fork of GROMACS libxdrfile version 1.1.4, with patches for use within the
chemfiles project. This version is BSD licensed.

The library reads GROMACS **trr** and **xtc** trajectory files, and supports
conversion between formats.

> For the Chinese version, see [README.md](README.md).

---

## Upstream README

The following is the original upstream README, reproduced for attribution.
Written by Erik Lindahl & David van der Spoel (see [AUTHORS](AUTHORS)).

> This library allows to read GROMACS trr and xtc files and also to
> convert from one format to another.
>
> The library itself is offered under the BSD license, which means you are free
> to incorporate it any way you want in other libraries or executables, no
> matter what the final license is.

---

## Building the C library

Standard CMake flow:

```sh
cmake -S . -B build -G Ninja
cmake --build build
ctest --test-dir build --output-on-failure
```

> The repository's `CMakeLists.txt` declares a minimum version of 2.8.12; newer
> CMake (>= 3.5) needs `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`. On Windows, if the
> SDK's `rc.exe` is missing, add `-DCMAKE_EXE_LINKER_FLAGS="/MANIFEST:NO"`.

---

## Python binding

A **Cython binding** ships in the `wrapper/` directory. It reads and writes XTC
trajectories from Python, exposing coordinates as **numpy `float32` arrays**
(zero-copy, no DLPack). This is the recommended path for Python.

### Requirements

- Python >= 3.9
- A C compiler (gcc/clang on Linux; MSVC or BuildTools on Windows)
- `pip install cython numpy setuptools`

### Build (Linux)

```sh
sudo apt install gcc python3-dev        # Debian / Ubuntu
pip install cython numpy setuptools
cd wrapper
pip install .
```

`setup.py` adds `-O2 -fPIC` automatically on Linux and produces
`_xdrfile.cpython-3XX-x86_64-linux-gnu.so`.

### Build (Windows)

First initialize the MSVC toolchain with `vcvars64.bat`, then build same as
Linux:

```bat
cd wrapper
pip install .
```

> If `vcvars64.bat` cannot inject `INCLUDE`/`LIB` because `reg.exe` is blocked
> in a sandboxed environment, manually set the MSVC / Windows SDK
> `INCLUDE`, `LIB`, and `PATH` environment variables before running the
> command above.

### Usage

```python
import _xdrfile as xtc

n = xtc.natoms("traj.xtc")
natoms, nframes = xtc.frame_info("traj.xtc")

xyz, box, time, step = xtc.read_all("traj.xtc")
# xyz: (nframes, natoms, 3) float32, box: (nframes, 3, 3) float32

x, b, t, s = xtc.read_frame("traj.xtc", i)

xtc.write_frame("out.xtc", xyz_i, box_i, time=t, step=s, prec=1000.0)
```

### API

| Function | Signature |
|---|---|
| `natoms` | `natoms(path) -> int` |
| `frame_info` | `frame_info(path) -> (natoms, nframes)` |
| `read_frame` | `read_frame(path, frame) -> (xyz, box, time, step)` |
| `read_all` | `read_all(path) -> (xyz, box, time, step)` |
| `write_frame` | `write_frame(path, xyz, box, time=0.0, step=0, prec=1000.0, append=False)` |

### Semantics & precision

- Coordinates are always `float32`.
- `box` is the full triclinic 3x3 matrix; do not drop off-diagonal terms.
- Units follow the GROMACS convention (nm).
- XTC is lossy; `prec=1000.0` gives ~3 decimal places. Use
  `np.allclose(atol=1e-3)` for round-trip checks, not `==`.

### Known caveats (from libxdrfile internals)

1. `read_xtc` ignores the caller-supplied `natoms` and uses the value in the
   file header. The binding always probes via `read_xtc_natoms()` first.
2. `read_xtc_header`'s `offsets` is `malloc`'d inside the library with no
   matching free; the binding never exposes it.
3. Out-of-range frames raise `IndexError`; a bad magic raises `XtcError`.
4. XTC has no trailer/frame index; truncation silently drops frames.

### ctypes fallback

`wrapper/xdrfile_ctypes.py` is a fallback using a standalone SHARED library
(`libxdrfile_shared`, from `wrapper/CMakeLists.txt`). Not recommended for
production (extra copy, cross-CRT free hazards).

---

## License

BSD 3-Clause, see [COPYING](COPYING).