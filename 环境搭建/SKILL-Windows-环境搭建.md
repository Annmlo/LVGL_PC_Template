# SKILL：Windows 上从零搭建 LVGL PC 模拟器工程

> **适用范围**：`lv_port_pc_vscode` 及其派生工程（本仓库即母版）
> **目标平台**：Windows 10/11 x64 + MinGW-w64 + SDL2 + VS Code
> **本文档性质**：可复用操作手册。每一节都写明「为什么」，因为不理解原因的修法换个环境就会失效。
> **最后验证**：2026-10-11，Windows 10.0.26200，全部命令实测通过

---

## 0. 这份文档怎么用

三种用法：

| 你的情况 | 看哪几节 |
|---|---|
| 全新电脑，从零开始 | 第 1 节 → 第 2 节 → 第 3 节，按顺序做 |
| 遇到报错 | 直接跳 **第 4 节错误大全**，按症状查 |
| 想改工程 / 派生新项目 | 第 5 节原理 + 第 6 节改动清单 + 第 7 节派生指南 |

**一键脚本**：同目录下的 `setup-windows.ps1` 会把第 3 节全部自动做完。但第一次务必**手工读一遍第 3 节**，知道脚本在干什么。

> **这两个文件放在工程外面**：本文档和 `setup-windows.ps1` 都在 `D:\A_study_document\LVGL\环境搭建\`，**不在 LVGL 工程里**。
> 脚本会自动找到工程（顺序：`-ProjectRoot` 参数 → 当前目录 → 脚本所在目录 → 常见位置搜索），也可以手动指定：
> ```powershell
> .\setup-windows.ps1 -ProjectRoot "D:\A_study_document\LVGL\EXAMPLE\NEWTEST\lv_port_pc_vscode-master"
> ```

---

## 1. 成品状态（做完之后应该长什么样）

```
lv_port_pc_vscode-master\
├── .gitignore
├── .vscode\                        ← 可选，VS Code 用 .code-workspace 时不需要
├── CMakeLists.txt                  ← 213 行，含 DLL 自动拷贝
├── licence.txt
├── manifest.json
├── lv_conf.h                       ← LVGL 配置（LV_USE_THORVG 必须是 1）
├── lv_conf.defaults                ← lv_conf.h 的模板源
├── README.md                       ← 已改写为「纯 LVGL」
├── simulator.code-workspace        ← 已修好 Windows 路径
├── bin\                            ← 构建产物，构建后应含 5 个文件
│   ├── main.exe                    ~13.9 MB
│   ├── SDL2.dll                    1,785,344 B
│   ├── libgcc_s_seh-1.dll          928,912 B
│   ├── libstdc++-6.dll             2,376,329 B
│   └── libmain.dll.a               235,858 B
├── build\                          ← CMake 构建目录（可删，删了重新 configure）
├── lvgl\                           ← 子模块，LVGL master
└── src\
    ├── main.c                      1,784 B
    ├── mouse_cursor_icon.c         7,096 B
    └── hal\
        ├── hal.c                   1,027 B
        └── hal.h                     686 B
```

**验收标准**（三条全过才算成功）：

1. `cmake --build build -j` 输出 `[100%] Built target main`，退出码 0
2. 构建日志里能看到三行 `Copying xxx.dll next to the executable`
3. 双击 `bin\main.exe`（**不需要任何 PATH 配置**）弹出标题为 `LVGL Simulator` 的窗口

---

## 2. 依赖清单（精确版本）

| 组件 | 本文档验证版本 | 下载地址 | 必需？ |
|---|---|---|---|
| **MinGW-w64** | `x86_64-ucrt-posix-seh` GCC **15.1.0**（Brecht Sanders r1 构建） | <https://github.com/niXman/mingw-builds-binaries/releases> | ✅ 必需 |
| **GDB** | **16.3**（同上一包内） | 同上 | 只在调试时需要 |
| **CMake** | **4.0.1** | <https://cmake.org/download/> | ✅ 必需 |
| **Ninja** | **1.12.1** | 同 MinGW 包内 / <https://github.com/ninja-build/ninja/releases> | 可选（也可用 `mingw32-make`） |
| **SDL2** | **2.32.10**（SDL2 系列最终版） | 见下方 §3.3 | ✅ 必需 |
| **Python** | **3.11.2** | <https://www.python.org/downloads/> | ✅ 必需（LVGL 构建脚本用） |
| **Git** | 2.50.1 | <https://git-scm.com/> | ✅ 必需（拉子模块） |
| **VS Code** | 任意近期版本 | <https://code.visualstudio.com/> | 可选 |

### 版本陷阱（务必记住）

- **SDL2 必须是 2.x，不能用 SDL3。** LVGL 9.5 的 SDL 驱动写死了 SDL2：
  - `lvgl/src/drivers/sdl/lv_sdl_egl.c:13` → `#include <SDL2/SDL_syswm.h>`
  - `lvgl/src/drivers/sdl/lv_sdl_mouse.c:119` → `#if SDL_VERSION_ATLEAST(2,0,12)`
  - CMake 找的是 `find_package(SDL2)`，而 SDL3 的包名叫 `SDL3`，**根本找不到**。
- **SDL2 的 2.32.11 / 2.32.12 / 2.34.x / 2.36.0 / 2.40.0 都不存在**（实测全 404）。2.32.10 是 2.32 分支最后一版。
- **不要用 `-VC` 结尾的 SDL2 包**（那是给 MSVC 的），**也不要用 `SDL2-2.32.10-win32-x64.zip`**（里面只有运行时 DLL，没有头文件和 `.a` 导入库，编译不了）。

---

## 3. 全新电脑：完整步骤

### 3.1 装 MinGW-w64

1. 从 <https://github.com/niXman/mingw-builds-binaries/releases> 下载
   `x86_64-15.1.0-release-posix-seh-ucrt-rt_v12-rev1.7z`（或更新的同系列）。
   **认准四个关键词**：`x86_64` + `posix` + `seh` + `ucrt`。
2. 解压到比如 `D:\A_software_study\GCC_MingGW64\`，最终路径是
   `D:\A_software_study\GCC_MingGW64\mingw64\bin\gcc.exe`。
3. **把这个 `bin` 目录加到系统 PATH**（不是当前会话，要永久）：
   ```powershell
   $mingw = 'D:\A_software_study\GCC_MingGW64\mingw64\bin'
   $old = [Environment]::GetEnvironmentVariable('Path','Machine')
   if ($old -notlike "*$mingw*") {
       [Environment]::SetEnvironmentVariable('Path', "$old;$mingw", 'Machine')
   }
   ```
   > 改 Machine 级 PATH 需要管理员权限。若不想动系统，可以只在 `run_simulator.bat` / `.vscode` 里注入（本母版就是这么做的，见 §3.7）。
4. **验证**（新开一个终端）：
   ```
   gcc --version     → gcc.exe (MinGW-W64 x86_64-ucrt-posix-seh, ...) 15.1.0
   g++ --version     → g++.exe (...) 15.1.0
   gdb --version     → GNU gdb (GDB for MinGW-W64 x86_64, ...) 16.3
   ```

> **为什么必须是 `posix` 线程模型？** LVGL 的 C++ 部分（ThorVG）和 SDL2 的某些路径依赖 POSIX 线程语义；`win32` 线程模型下链接会出问题。
> **为什么必须是 `ucrt`？** 它对应 Universal CRT，生成的 exe 依赖 `api-ms-win-crt-*.dll`（Windows 10+ 自带，在 `C:\Windows\System32\downlevel\`）。用 `msvcrt` 老运行时会有兼容问题。

### 3.2 装 CMake / Ninja / Python

- **CMake**：从 <https://cmake.org/download/> 下 `cmake-4.x.x-windows-x86_64.msi`，安装时**勾选 "Add CMake to the system PATH"**。
- **Ninja**：MinGW 包里通常自带 `ninja.exe`；没有的话从 GitHub 下单个 exe 丢进 MinGW 的 `bin`。
- **Python**：安装时**勾选 "Add python.exe to PATH"**。

验证：
```
cmake --version    → cmake version 4.0.1
ninja --version    → 1.12.1
python --version   → Python 3.11.2
```

> **`make` 不是必需的**。本工程用 Ninja 或 `mingw32-make` 都行。如果你的 `make` 不在 PATH 里，**不要慌**——CMake 会自动挑可用的生成器。

### 3.3 装 SDL2

1. 打开 <https://github.com/libsdl-org/SDL/releases/tag/release-2.32.10>
2. 下载 **`SDL2-devel-2.32.10-mingw.tar.gz`**（13,892,870 B）
   - 校验：`SHA-256 = 83A5D74012311EDC3C0D40EA6FAECBE57AD692AA033FA5DC273CC937E3938FF2`
3. 解压。**注意：tar 包里多套了一层目录**，解压后是：
   ```
   SDL2-2.32.10\
   ├── i686-w64-mingw32\          ← 32 位，用不到
   └── x86_64-w64-mingw32\        ← 你要的是这个
       ├── bin\SDL2.dll                        1,785,344 B
       ├── include\SDL2\SDL.h
       └── lib\
           ├── cmake\SDL2\sdl2-config.cmake    8,703 B   ← 关键文件
           ├── cmake\SDL2\sdl2-config-version.cmake
           ├── libSDL2.a                      15,679,018 B
           ├── libSDL2.dll.a                     553,152 B
           └── libSDL2main.a                       9,540 B
   ```
4. 把它放到一个固定位置，例如 `D:\A_software_study\SDL2\SDL2-2.32.10\`。

> **不要下 `SDL2-devel-2.32.10-VC.zip`**（MSVC 版，MinGW 链接不了）。
> **不要下 `SDL2-2.32.10-win32-x64.zip`**（只有 `SDL2.dll`，没有 `.a` 和头文件）。

### 3.4 设置 `SDL2_DIR`（这一步是「一劳永逸」的关键）

不设也能编译（用 `-DCMAKE_PREFIX_PATH=` 每次指定），但设一次之后**以后所有工程都不用再管**。

```powershell
[Environment]::SetEnvironmentVariable(
    'SDL2_DIR',
    'D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32\lib\cmake\SDL2',
    'User')
```

**⚠️ 层级差两级，这是最容易错的地方：**

| 变量 | 应该指向 | 判断标准 |
|---|---|---|
| `SDL2_DIR` | `...\x86_64-w64-mingw32\lib\cmake\SDL2` | 这个目录里**有** `sdl2-config.cmake` |
| `CMAKE_PREFIX_PATH` | `...\x86_64-w64-mingw32` | 这个目录里有 `bin\` `include\` `lib\` |

**为什么不干脆设 `CMAKE_PREFIX_PATH`？** 它是**全局**的，会影响**每一个** `find_package()` 的搜索顺序。以后你装了别的库，可能出现被抢先命中的诡异问题。`SDL2_DIR` 只对 SDL2 生效，零副作用。

**让它立即生效**（不重启资源管理器/VS Code）：
```powershell
$sig = @'
using System;using System.Runtime.InteropServices;
public class W { [DllImport("user32.dll",CharSet=CharSet.Auto,SetLastError=true)]
public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,string l,uint f,uint t,out UIntPtr r); }
'@
Add-Type $sig
$r = [UIntPtr]::Zero
[W]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, "Environment", 0x0002, 5000, [ref]$r) | Out-Null
```

**验证**（必须开一个**全新的**终端）：
```
echo %SDL2_DIR%
→ D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32\lib\cmake\SDL2
```

**撤销**：
```powershell
[Environment]::SetEnvironmentVariable('SDL2_DIR', $null, 'User')
```

### 3.5 拿工程（**必须用 git，不能下 ZIP**）

```bash
git clone --recursive https://github.com/lvgl/lv_port_pc_vscode
```

或者如果已经有本母版：
```bash
git clone --recursive <你的仓库地址>
```

**⚠️ 绝对不要用 GitHub 网页上的 "Download ZIP"。** 原因见 §4.2 —— ZIP **不含子模块**，你会拿到一个残缺的 `FreeRTOS/` 和 `lvgl/`，直接构建失败。

已经下了 ZIP 的补救：
```bash
git init
git remote add origin https://github.com/lvgl/lv_port_pc_vscode
git fetch
git checkout -f master
git submodule update --init --recursive
```

### 3.6 构建

**方式 A：一键脚本（推荐）**
```powershell
cd D:\A_study_document\LVGL\环境搭建
.\setup-windows.ps1
# 脚本会自动找到工程；也可以显式指定：
# .\setup-windows.ps1 -ProjectRoot "D:\A_study_document\LVGL\EXAMPLE\NEWTEST\lv_port_pc_vscode-master"
```

**方式 B：手动（知道在干什么）**
```bash
cd <工程根目录>
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
```

**方式 C：VS Code**
1. 双击 `simulator.code-workspace`
2. 装推荐插件（弹窗会提示）
3. `Ctrl+Shift+B` 构建，或 `F5` 编译并调试

构建成功的标志：
```
[100%] Linking CXX executable ...\bin\main.exe
Copying SDL2.dll next to the executable
Copying libgcc_s_seh-1.dll next to the executable
Copying libstdc++-6.dll next to the executable
[100%] Built target main
```

### 3.7 VS Code 配置

本母版的 `simulator.code-workspace` 已经修好，但如果你是从上游重新拉的，需要自己改这 4 处：

| 位置 | 上游原值（错的） | 改成 |
|---|---|---|
| 两个 launch 配置的 `"program"` | `"${workspaceFolder}/bin/main"` | `"${workspaceFolder}/bin/main.exe"` |
| `windows.miDebuggerPath` | `"C:\\MinGW\\bin\\gdb.exe"` | 你的真实 gdb 路径，如 `"D:/A_software_study/GCC_MingGW64/mingw64/bin/gdb.exe"` |
| 两个 launch 配置 | 无 `environment` | 加 `"environment": [{"name":"PATH","value":"<SDL2 bin>;<MinGW bin>;${env:PATH}"}]` |
| `Build and Run` 任务 | `"command": ".../bin/main"` | `".../bin/main.exe"` + `"options": {"env": {"PATH": "<同上>"}}` |

**为什么 `program` 要带 `.exe`？** Windows 上文件叫 `bin\main.exe`，没有无扩展名的 `bin\main`。VS Code 拿不到文件就会静默失败（「点了没反应」）。

**为什么第二个配置别选？** 上游还带一个 `Debug LVGL demo with LLVM`，它用 `"MIMode": "lldb"`。**MinGW 工具链里没有 lldb**，选了必然失败。用 gdb 那条。

### 3.8 运行

三种方式，任选：

```powershell
# 1. 直接双击
explorer bin\main.exe

# 2. 命令行（工作目录必须是工程根目录，因为 A: 盘 = 当前目录）
cd <工程根目录>
.\bin\main.exe

# 3. CMake target
cmake --build build --target run
```

**⚠️ 不要在资源管理器里双击 `build\bin\` 之外的路径，也不要 `cd build\bin` 再跑。** 工作目录必须是**工程根目录**（原因见 §5.6）。

---

## 4. 错误大全

> 按「你会看到的报错原文」排序。用 `Ctrl+F` 搜报错里的关键词。

### 4.1 `Could not find a package configuration file provided by "SDL2"`

**完整报错：**
```
CMake Error at CMakeLists.txt:28 (find_package):
  By not providing "FindSDL2.cmake" in CMAKE_MODULE_PATH this project has
  asked CMake to find a package configuration file provided by "SDL2", but
  CMake did not find one.

  Could not find a package configuration file provided by "SDL2" with any of
  the following names:

    SDL2Config.cmake
    sdl2-config.cmake

  Add the installation prefix of "SDL2" to CMAKE_PREFIX_PATH or set
  "SDL2_DIR" to a directory containing one of the above files.
```

**根因：** CMake 找不到 SDL2。三种可能：
1. 根本没装 SDL2（或下错了包，见 §2 版本陷阱）
2. 装了但 `SDL2_DIR` 没设
3. 设了但**当前进程没继承到**（环境变量是在这个进程启动之后才设的）

**修法（按推荐顺序）：**

```powershell
# A. 一劳永逸：设用户级环境变量（见 §3.4）
[Environment]::SetEnvironmentVariable('SDL2_DIR', 'D:\...\x86_64-w64-mingw32\lib\cmake\SDL2', 'User')

# B. 一次性：命令行传
cmake -S . -B build -DCMAKE_PREFIX_PATH="D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32"

# C. 如果 build 目录里已经缓存了错误的值，先删掉再重来
Remove-Item -Recurse -Force build
cmake -S . -B build
```

**踩坑记录：** 我曾经在后台任务里 configure 失败，原因是**那个后台进程在我设 `SDL2_DIR` 之前就启动了**，没继承到新环境。**设完环境变量后必须新开终端/新起进程。**

---

### 4.2 `CMake Error at FreeRTOS/portable/CMakeLists.txt:18 (add_library): Cannot find source file`

**完整报错：**
```
CMake Error at FreeRTOS/portable/CMakeLists.txt:18 (add_library):
  Cannot find source file:

    ...

CMake Error at FreeRTOS/portable/CMakeLists.txt:18 (add_library):
  No SOURCES given to target: freertos_kernel_port
```

**根因：** 你用 **ZIP 下载**代替了 `git clone --recursive`。GitHub 的 ZIP **只打包主仓库，不含子模块内容**。结果 `FreeRTOS/portable/MemMang` 和 `FreeRTOS/portable/ThirdParty` 这两个目录**根本不存在**。

**验证方法：**
```powershell
Test-Path .\FreeRTOS\portable\MemMang      # → False 就是中招了
Test-Path .\FreeRTOS\portable\ThirdParty   # → False 就是中招了
```

**修法（二选一）：**
```bash
# A. 正确姿势：重新用 git 拉
rm -rf FreeRTOS lvgl
git clone --recursive https://github.com/lvgl/lv_port_pc_vscode

# B. 本母版已删除 FreeRTOS，不需要它 —— 如果你的工程还有 FreeRTOS 目录，
#    直接按 §6 的清单删干净即可
```

> **顺带一个坑**：用 ZIP 拿到的 `lvgl/` 也是**某个具体 commit 的快照**，可能比你预期的版本新或旧。本母版的 `lvgl/` 是 **master 分支，比 v9.5.0 新**——公开头文件搬到了 `lvgl/include/lvgl/`，`src/` 里只剩实现。用 `git submodule` 才能保证版本可复现。

---

### 4.3 `undefined reference to 'SDL_main'`

**完整报错：**
```
libSDL2main.a(SDL_windows_main.o): in function 'main_getcmdline':
/tmp/tardir/SDL2-2.32.10/src/main/windows/SDL_windows_main.c:80:
(.text+0x152): undefined reference to 'SDL_main'
collect2.exe: error: ld returned 1 exit status
```

**根因：** SDL2 导出的 `SDL2_LIBRARIES` 变量**包含 `SDL2::SDL2main`**。这个库定义了 `WinMain`，并且**要求你的程序导出一个叫 `SDL_main` 的函数**。但本工程有自己的标准 `main()` 并且定义了 `SDL_MAIN_HANDLED`，于是链接器找不到 `SDL_main`。

SDL2 的 `sdl2-config.cmake` 里是这么写的：
```cmake
set(SDL2_LIBRARIES SDL2::SDL2)
if(_sdl2_libraries MATCHES ".*SDL2main.*")
    list(INSERT SDL2_LIBRARIES 0 SDL2::SDL2main)
endif()
```
→ 在 MinGW 上 `SDL2_LIBRARIES` 实际等于 `SDL2::SDL2main;SDL2::SDL2`。

**修法：** 不要用 `${SDL2_LIBRARIES}`，直接链 `SDL2::SDL2` 这个 target：

```cmake
# ❌ 错的
target_link_libraries(main ${MAIN_LIBS})     # MAIN_LIBS 里有 ${SDL2_LIBRARIES}

# ✅ 对的
if(TARGET SDL2::SDL2)
    target_link_libraries(${PROJECT_NAME} PRIVATE lvgl SDL2::SDL2)
else()
    target_link_libraries(${PROJECT_NAME} PRIVATE lvgl ${SDL2_LIBRARIES})
endif()
```

---

### 4.4 `main.exe - 系统错误 / 由于找不到 SDL2.dll，无法继续执行代码`

**症状：** 双击 `bin\main.exe`，弹出系统错误对话框。退出码 `-1073741515`（= `0xC0000135` = `STATUS_DLL_NOT_FOUND`）。

**根因（这是最反直觉的一个）：** **下载了 SDL2 ≠ DLL 在 exe 旁边。**

你下载的是「**编译用 SDK**」——头文件（编译期用）+ `.a` 导入库（链接期用）+ 一份 `SDL2.dll`。但 **Windows 加载 DLL 的顺序是**：

1. **exe 自己所在的目录** ← 这里没有
2. 系统目录（`C:\Windows\System32`）
3. 16 位系统目录、Windows 目录
4. **当前工作目录**
5. `PATH` 里的每个目录 ← `D:\...\SDL2\...\bin\` 不在里面

所以找不到。

**修法 A（本母版采用，一劳永逸）：在 `CMakeLists.txt` 里加 `POST_BUILD` 自动拷贝**

放在 `add_executable(main ...)` 和 `target_link_libraries(main ...)` **之后**：

```cmake
# Copy the runtime DLLs next to the executable, so that bin/main.exe can be
# started by double-clicking it (or from any working directory) without needing
# SDL2 or MinGW on the PATH. Windows resolves DLLs from the executable's own
# directory first, so this makes the build self-contained.
if (WIN32)
    # --- SDL2.dll ---------------------------------------------------------
    set(_sdl2_dll "")
    if (SDL2_BINDIR AND EXISTS "${SDL2_BINDIR}/SDL2.dll")
        set(_sdl2_dll "${SDL2_BINDIR}/SDL2.dll")
    else()
        # SDL2_INCLUDE_DIRS is a list: <prefix>/include;<prefix>/include/SDL2
        list(LENGTH SDL2_INCLUDE_DIRS _sdl2_inc_count)
        if (_sdl2_inc_count GREATER 0)
            math(EXPR _sdl2_last "${_sdl2_inc_count} - 1")
            list(GET SDL2_INCLUDE_DIRS ${_sdl2_last} _sdl2_inc)
            get_filename_component(_sdl2_inc "${_sdl2_inc}" ABSOLUTE)
            get_filename_component(_sdl2_prefix "${_sdl2_inc}" DIRECTORY)
            if (EXISTS "${_sdl2_prefix}/bin/SDL2.dll")
                set(_sdl2_dll "${_sdl2_prefix}/bin/SDL2.dll")
            endif()
        endif()
    endif()

    if (_sdl2_dll)
        add_custom_command(
            TARGET main POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${_sdl2_dll}" "$<TARGET_FILE_DIR:main>"
            COMMENT "Copying SDL2.dll next to the executable"
        )
    else()
        message(WARNING
            "SDL2.dll was not found. bin/main.exe will need SDL2 on the PATH at runtime.")
    endif()

    # --- MinGW runtime DLLs (ThorVG is C++, so libstdc++ is required) -----
    get_filename_component(_mingw_bin "${CMAKE_C_COMPILER}" DIRECTORY)
    foreach (_dll libgcc_s_seh-1.dll libstdc++-6.dll)
        if (EXISTS "${_mingw_bin}/${_dll}")
            add_custom_command(
                TARGET main POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${_mingw_bin}/${_dll}" "$<TARGET_FILE_DIR:main>"
                COMMENT "Copying ${_dll} next to the executable"
            )
        endif()
    endforeach()
endif()
```

**修法 B（应急）：手动拷**
```powershell
$bin = "<工程>\bin"
Copy-Item "D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32\bin\SDL2.dll" $bin
Copy-Item "D:\A_software_study\GCC_MingGW64\mingw64\bin\libgcc_s_seh-1.dll"     $bin
Copy-Item "D:\A_software_study\GCC_MingGW64\mingw64\bin\libstdc++-6.dll"       $bin
```

**为什么还需要 `libgcc_s_seh-1.dll` 和 `libstdc++-6.dll`？**
`objdump -p bin\main.exe | findstr "DLL Name"` 的结果：
```
libgcc_s_seh-1.dll      ← MinGW 的 GCC 运行时（异常处理）
libstdc++-6.dll         ← C++ 标准库 —— 因为 ThorVG 是 C++ 写的
KERNEL32.dll
api-ms-win-crt-*.dll    ← Windows 自带，在 System32\downlevel\，不用管
SHELL32.dll
SDL2.dll
```

> **验证 DLL 到底缺哪个**：
> ```powershell
> $objdump = "D:\A_software_study\GCC_MingGW64\mingw64\bin\objdump.exe"
> & $objdump -p .\bin\main.exe | Select-String 'DLL Name:'
> ```
> **验证 PATH 无关性**（证明靠的是同目录 DLL）：
> ```powershell
> $env:PATH = "C:\Windows\system32;C:\Windows"
> .\bin\main.exe
> ```

---

### 4.5 `#error "LV_USE_VECTOR_GRAPHIC requires ..."`

**完整报错**（在 `lvgl/src/draw/lv_draw_vector.c:17`）：
```
error: #error "LV_USE_VECTOR_GRAPHIC requires (LV_USE_DRAW_SW and LV_USE_THORVG)
or LV_USE_DRAW_VG_LITE or (LV_USE_NEMA_GFX and LV_USE_NEMA_VG) or LV_USE_DRAW_NANOVG"
```

**⚠️ 这个错误最难定位的地方：** VS Code / `make` 只给你这一行
```
[build] mingw32-make[2]: *** [lvgl\CMakeFiles\lvgl.dir\build.make:964:
  lvgl/CMakeFiles/lvgl.dir/src/draw/lv_draw_vector.c.obj] Error 1
```
**看不到真正的 `#error` 内容。** 用这个办法挖出来：

```powershell
# 从 compile_commands.json 里取出该文件的原编译命令，单独重跑
$cc = Get-Content .\build\compile_commands.json -Raw | ConvertFrom-Json
$e = $cc | Where-Object { $_.file -like '*lv_draw_vector.c' }
Set-Location $e.directory
Invoke-Expression $e.command      # 这时才会打印真正的 #error
```

**根因：** `lv_conf.h` 自相矛盾：

| `lv_conf.h` 行 | 值 | 含义 |
|---|---|---|
| `:211` | `LV_USE_VECTOR_GRAPHIC 1` | 要矢量图形 |
| `:217` | `LV_USE_THORVG 0` | 但**关掉了 ThorVG 后端** ❌ |
| `:226` | `LV_USE_DRAW_SW 1` | 软件渲染开了 |
| `:326` | `LV_USE_DRAW_VG_LITE 0` | 后端 2 关 |
| `:418` | `LV_USE_NEMA_GFX 0` | 后端 3 关 |
| `:477` | `LV_USE_NEMA_VG 0` | 后端 3 关 |
| `:627` | `LV_USE_DRAW_NANOVG 0` | 后端 4 关 |

四个后端**一个都没满足** → `#error`。

**为什么不能简单地关掉 `LV_USE_VECTOR_GRAPHIC`？** 因为 `lv_conf.h:1460` 是 `LV_USE_LOTTIE 1`，而 `lv_conf_internal.h:5500` 写着：
```c
#if LV_USE_LOTTIE && !(LV_DRAW_HAS_VECTOR_SUPPORT && LV_USE_THORVG)
    #error "LV_USE_LOTTIE requires LV_DRAW_HAS_VECTOR_SUPPORT && LV_USE_THORVG (Kconfig depends on)"
#endif
```
→ 关掉矢量图形只会**把错误换成 Lottie 的 `#error`**。所以必须往「**打开 THORVG**」方向修。

**修法（唯一改动）：**
```c
// lv_conf.h:217
- #define LV_USE_THORVG 0
+ #define LV_USE_THORVG 1
```
连带 `:219-223` 的 `#if LV_USE_THORVG / #define LV_USE_THORVG_INTERNAL 1 / #endif` 自动激活，正好对上 CMake 的 `CONFIG_LV_USE_THORVG_INTERNAL=ON`。

**为什么 CMake 的 `-DCONFIG_LV_USE_THORVG=ON` 没用？** 看 `lv_conf_internal.h:478-494`：
```c
#ifndef LV_USE_THORVG
    #ifdef CONFIG_LV_USE_THORVG
        #define LV_USE_THORVG CONFIG_LV_USE_THORVG
    #else
        #define LV_USE_THORVG 0
    #endif
#endif
```
**`lv_conf.h` 里的显式 `#define` 优先级高于 CMake 的 `CONFIG_LV_*`。** 一旦 `lv_conf.h` 写了 `0`，CMake 传什么都白搭。这是 LVGL 配置系统最反直觉的一点。

> **补充**：`lvgl::thorvg` 这个 target 定义在 `lvgl/env_support/cmake/main.cmake`（不是 `lvgl/CMakeLists.txt`，所以在后者里 grep `thorvg` 会 0 命中，别被误导）：
> ```cmake
> :68  option(CONFIG_LV_USE_THORVG "Enable ThorVG" ON)
> :69  option(CONFIG_LV_USE_THORVG_INTERNAL "Use the internal version of ThorVG" ON)
> :313 if(CONFIG_LV_USE_THORVG AND CONFIG_LV_USE_THORVG_INTERNAL)
> :314     set(LV_BUILD_THORVG_INTERNAL ON)
> :320     add_library(lvgl_thorvg ${THORVG_SOURCES})
> :321     add_library(lvgl::thorvg ALIAS lvgl_thorvg)
> :327     target_link_libraries(lvgl PRIVATE lvgl_thorvg)
> ```

---

### 4.6 `run_simulator.bat` 满屏 `'xxx' is not recognized as an internal or external command`

**症状：** 双击 `.bat`，cmd 窗口里刷出几十行
```
'鍒犻櫎' is not recognized as an internal or external command
'@echo' is not recognized as an internal or external command
```
（中文变成乱码，命令被拆碎）

**根因（两个叠加）：**
1. **换行符**：文件是 **LF**（Unix 换行），而 `cmd.exe` 要求 **CRLF**。LF 会让 cmd 把多行当成一行，命令全乱。
2. **编码**：文件是 **UTF-8**，而这台机器的 cmd 代码页是 **GBK（936）**。中文注释变乱码。
   ```powershell
   chcp        # → Active code page: 936
   ```

**修法：转成 CRLF + GBK**
```powershell
$f = ".\run_simulator.bat"
$txt = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
$txt = $txt -replace "`r`n", "`n" -replace "`n", "`r`n"     # 统一成 CRLF
[System.IO.File]::WriteAllText($f, $txt, [System.Text.Encoding]::GetEncoding(936))
```

**验证：**
```powershell
$b = [System.IO.File]::ReadAllBytes($f)
"CR = $(($b | Where-Object { $_ -eq 13 }).Count)  LF = $(($b | Where-Object { $_ -eq 10 }).Count)"
# 两者数量应该相等
```

> **更好的办法：干脆不用 `.bat`，用 `.ps1`**。PowerShell 对 UTF-8 友好得多（不过要注意执行策略：`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`）。

---

### 4.7 VS Code 里按 F5「完全没反应」

**症状：** 选了调试配置，点绿三角或按 F5，**什么都没有发生**——没有窗口、没有错误、状态栏也不变色。

**根因排查顺序**（按命中率排序）：

1. **`"program"` 路径不存在**（最常见）
   `"program": "${workspaceFolder}/bin/main"` 但实际文件是 `bin\main.exe`。
   → 改成带 `.exe` 的完整路径。

2. **`miDebuggerPath` 指向不存在的 gdb**
   上游写死 `"C:\\MinGW\\bin\\gdb.exe"`，但你的 gdb 在别处。
   → 改成真实路径，**用正斜杠** `"D:/.../bin/gdb.exe"`。

3. **`debug.onTaskErrors` 是 `"abort"`**
   这个设置的含义是「**preLaunchTask 失败就静默中止调试会话**」——正是「点了没反应」的完美解释。
   → 改成 `"showErrors"`：
   ```json
   { "debug.onTaskErrors": "showErrors" }
   ```

4. **选了 lldb 配置但没装 lldb**
   `Debug LVGL demo with LLVM` 用 `"MIMode": "lldb"`，MinGW 工具链不带 lldb。
   → 选 gdb 那条。

5. **`.vscode/launch.json` 根本没被读到**
   验证方法：`code --status` 会打印已加载的配置类型和数量：
   ```
   | Launch Configs: cppdbg(3)
   ```
   如果数量/类型不对，说明你改的不是 VS Code 实际在读的那个文件。
   （注意：用 `.code-workspace` 打开时，配置在 workspace 文件里；用「打开文件夹」时，配置在 `.vscode/launch.json`。**两者不会同时生效。**）

**终极诊断手段**（能看到真实原因）：
> `帮助` → `切换开发人员工具`（或 `Ctrl+Shift+I`）→ **Console** 标签页 → 再按 F5 → 看红色报错。

**绕过调试器的办法**（一定能用）：
```jsonc
// .vscode/tasks.json
{
  "label": "Debug in terminal (gdb)",
  "type": "shell",
  "command": "gdb",
  "args": ["--args", "build/bin/main.exe"],
  "options": { "cwd": "${workspaceFolder}" },
  "presentation": { "reveal": "always", "panel": "dedicated", "focus": true, "clear": true }
}
```
在**集成终端**里直接起 gdb，完全不经过 VS Code 的调试 UI。

---

### 4.8 一堆 `[Warn] lv_init: ... checks are enabled ...`

**症状：** 程序正常跑，但 stdout 打印：
```
[Warn] (0.000, +0) lv_init: Memory integrity checks are enabled via LV_USE_ASSERT_MEM_INTEGRITY which makes LVGL much slower lv_init.c:309
[Warn] (0.000, +0) lv_init: Object sanity checks are enabled via LV_USE_ASSERT_OBJ which makes LVGL much slower lv_init.c:313
[Warn] (0.000, +0) lv_init: Style sanity checks are enabled that uses more RAM lv_init.c:317
```

**这不是错误，不用管。** 它们来自 `lv_conf.defaults:11-13`：
```
LV_USE_ASSERT_MEM_INTEGRITY 1
LV_USE_ASSERT_OBJ 1
LV_USE_ASSERT_STYLE 1
```
意思是「调试用的内存/对象自检开着，会慢一点」。**Debug 构建故意开的**，方便抓内存错误。

**想让它闭嘴：** 把 `lv_conf.h` 里这三项改成 `0`。

---

### 4.9 `lv_display_refr_timer: No draw buffer`

```
[Warn] (138717.396, +138717396) lv_display_refr_timer: No draw buffer lv_refr.c:388
```

**无害。** 出现在 `hal_init()` 之后、第一个刷新周期之前，是显示驱动还没配好 draw buffer 时的正常提示。窗口能正常显示就忽略。

---

### 4.10 `No project name in .../project.xml; using folder name`

```
-- No project name in D:/.../project.xml; using folder name "lvgl_ui_project"
```

**无害。** 只在 `project.xml` 没写 `name=` 属性时出现。想消掉就在 `project.xml` 的 `<project>` 上加 `name="你的工程名"`。

---

### 4.11 `Error: ReplaceFileW EIO (Win32 1175)`

**症状：** 用编辑器工具改文件时报
```
Error: ReplaceFileW EIO (Win32 1175)
```

**根因：** Windows 上「写入临时文件 → 原子替换」被占用/杀毒软件/索引服务干扰。

**修法：直接重试。** 实测重试一次就成功了。连续失败就换个方式写（用 `[System.IO.File]::WriteAllText` 直接覆盖）。

---

### 4.12 `LV_COLOR_DEPTH` 找不到 / `.defaults` 与 `lv_conf.h` 对不上

**症状：** 写脚本对比 `lv_conf.defaults` 和 `lv_conf.h`，报告 `LV_COLOR_DEPTH` 在 `lv_conf.h` 里「没有」。

**根因：这不是错，是 LVGL v10 改名了。** `lv_conf_internal.h:161` 的注释原文：
> *"LV_COLOR_DEPTH was replaced by LV_COLOR_FORMAT_DEFAULT"*

所以 `lv_conf.h:141` 是 `#define LV_COLOR_FORMAT_DEFAULT LV_COLOR_FORMAT_RGB565`。
仓库里 `lv_conf.defaults:1` 的 `LV_COLOR_DEPTH 32` 和 `manifest.json` 的 `"toReplace": "#define LV_COLOR_DEPTH \\d+"` 都是**过时命名**，但不影响构建。

---

## 5. 原理：为什么是这样

理解这几条，换任何环境都能自己推理出修法。

### 5.1 Windows 的 DLL 搜索顺序

```
1. exe 所在目录                      ← POST_BUILD 拷贝的目标
2. C:\Windows\System32
3. C:\Windows\System16
4. C:\Windows
5. 当前工作目录
6. PATH 环境变量里的目录（从左到右）
```
**结论：把 DLL 放到 exe 旁边是最可靠的做法**，因为它排第一位，且不受工作目录/PATH 影响。

> `api-ms-win-crt-*.dll` 这 15 个是 **API set**，由 Windows 加载器按内置 schema 解析，实际实现是 `C:\Windows\System32\downlevel\ucrtbase.dll` 之类。**它们不受 PATH 影响，也不需要你拷。**

### 5.2 CMake 怎么找 SDL2

`find_package(SDL2)` 会依次尝试：
1. `CMAKE_PREFIX_PATH` 里的每个目录 → 找 `<dir>/lib/cmake/SDL2/sdl2-config.cmake`
2. **环境变量 `SDL2_DIR`**（CMake 对 `<PackageName>_DIR` 有内置支持）
3. 环境变量 `CMAKE_PREFIX_PATH`
4. 系统默认路径

**实测四种方式都能成功**：

| 方式 | 结果 |
|---|---|
| 什么都不设 | ❌ `NOT FOUND` |
| 用户级环境变量 `CMAKE_PREFIX_PATH` | ✅ |
| 用户级环境变量 `SDL2_DIR` | ✅ |
| 命令行 `-DCMAKE_PREFIX_PATH=` | ✅ |

**选 `SDL2_DIR` 的理由**：只影响 SDL2，不污染全局搜索顺序。

### 5.3 LVGL 的三层配置系统

```
CMakeLists.txt / -D 选项
        ↓  (生成)
   CONFIG_LV_* 宏
        ↓  (lv_conf_internal.h 兜底)
   lv_conf.h 的显式 #define     ← 优先级最高！
        ↓
   LV_USE_* 最终值
```

**规则：`lv_conf.h` 写了什么就是什么，CMake 的 `CONFIG_LV_*` 只在 `lv_conf.h` 没写时才生效。**

（例外：ESP-IDF 托管的 LVGL 组件没有根目录 `lv_conf.h`，那时才靠 `CONFIG_LV_*` 说话。）

### 5.4 矢量图形依赖链

```
LV_USE_VECTOR_GRAPHIC 1
    └── 必须满足下面之一：
        ├── LV_USE_DRAW_SW 1  AND  LV_USE_THORVG 1   ← 桌面/模拟器走这条
        ├── LV_USE_DRAW_VG_LITE 1                     ← 某些 NXP 芯片
        ├── LV_USE_NEMA_GFX 1 AND LV_USE_NEMA_VG 1    ← 某些 ARM GPU
        └── LV_USE_DRAW_NANOVG 1

LV_USE_LOTTIE 1
    └── 必须 LV_DRAW_HAS_VECTOR_SUPPORT AND LV_USE_THORVG 1
```

ThorVG 是 C++ 库，所以**打开它意味着你的 exe 会依赖 `libstdc++-6.dll`**。这就是为什么 §4.4 要拷那个 DLL。

### 5.5 为什么需要 `libgcc_s_seh-1.dll` 和 `libstdc++-6.dll`

MinGW 默认**动态链接**自己的运行时：
- `libgcc_s_seh-1.dll`：GCC 的异常处理 / 栈展开
- `libstdc++-6.dll`：C++ 标准库

因为工程里有 C++（ThorVG），两个都需要。
**想让 exe 自包含？** 加链接选项 `-static-libgcc -static-libstdc++`，或在 CMake 里：
```cmake
target_link_options(main PRIVATE -static-libgcc -static-libstdc++)
```
（SDL2.dll 还是会动态依赖，那个没办法静态化，除非自己编 SDL2。）

### 5.6 为什么工作目录必须是工程根目录

LVGL 的文件系统驱动配置（`lv_conf.h`）：
```c
LV_USE_FS_STDIO 1
LV_FS_STDIO_LETTER 'A'      // 盘符 A: 映射到当前工作目录
```
工程里所有资源路径都写成 `A:xxx`（如 `A:fonts/simhei.ttf`）。
**`A:` 盘 = 当前工作目录**，所以 `cd build\bin` 之后跑就找不到资源了。

---

## 6. 本母版相对上游的改动清单

发布到 GitHub 时，这份清单就是你的「变更说明」。

| # | 改动 | 文件 | 为什么 |
|---|---|---|---|
| 1 | **删除 FreeRTOS** | `FreeRTOS/`、`src/freertos_main.c`、`src/freertos/`、`config/FreeRTOSConfig.h`、`.gitmodules` | 上游是**可选**功能（默认 OFF），但 ZIP 下载会让它残缺导致构建失败；纯 LVGL 更简单 |
| 2 | **清理 CMakeLists 里的 FreeRTOS 分支** | `CMakeLists.txt` | 删掉 `:4-5` `:11` `:13-38` `:76-81`，改为无条件 `list(APPEND MAIN_SOURCES src/main.c)` |
| 3 | **修复 `SDL_main` 链接错误** | `CMakeLists.txt` | 用 `SDL2::SDL2` target 代替 `${SDL2_LIBRARIES}` |
| 4 | **新增 DLL 自动拷贝** | `CMakeLists.txt` | 见 §4.4 |
| 5 | **修复 `simulator.code-workspace` 的 Windows 路径** | `simulator.code-workspace` | `program` 加 `.exe`、`miDebuggerPath` 改真实路径、加 `PATH` 注入 |
| 6 | **`LV_USE_THORVG` 改为 1** | `lv_conf.h:217` | 修 `#error`，见 §4.5 |
| 7 | **README 改写为「纯 LVGL」** | `README.md` | 删掉过时的 FreeRTOS 章节，补 Windows DLL / SDL2_DIR 说明 |

---

## 7. 从这份母版派生新工程

```bash
# 1. 克隆（保留 git 历史，方便以后同步上游）
git clone --recursive <你的仓库> MyLvglProject
cd MyLvglProject

# 2. 改工程名（可选）
#    CMakeLists.txt: project(lvgl C CXX)  →  project(MyLvglProject C CXX)

# 3. 改默认 demo
#    src/main.c: lv_demo_widgets();  →  你自己的界面创建函数

# 4. 构建
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
```

**换成自己的界面**，在 `src/main.c` 里：
```c
/* 原来是 */
lv_demo_widgets();

/* 换成你自己的 */
my_ui_create();          /* 你的界面创建函数 */
```

**界面放哪：**
```
src/
├── main.c
├── my_ui.c          ← 你的界面
├── my_ui.h
└── hal/             ← 不要动，这是显示/输入驱动
```

**中文显示**（LVGL 自带字体没有汉字）：
```c
/* lv_conf.h 里确保 */
#define LV_USE_TINY_TTF 1
#define LV_TINY_TTF_FILE_SUPPORT 1
#define LV_USE_FS_STDIO 1
#define LV_FS_STDIO_LETTER 'A'

/* 代码里 */
lv_font_t * font_cn = lv_tiny_ttf_create_file("A:fonts/simhei.ttf", 20);
lv_obj_set_style_text_font(label, font_cn, LV_PART_MAIN);
```
把 `simhei.ttf`（`C:\Windows\Fonts\simhei.ttf`）或思源黑体放进 `fonts\`。
> ⚠️ **simhei.ttf 有版权，不能随仓库分发。** 让用户自己从系统字体目录拷。

---

## 8. 发布到 GitHub 的建议

### 8.1 仓库结构

> 下面这个结构是**发给别人的仓库**该长的样子。
> 你本机现在是「工程 + 环境搭建文档分开」的布局 —— 工程里一份都没有，这是刻意的。
> 真要发布时，把 `setup-windows.ps1` 和本文档拷进仓库即可（脚本放进仓库根目录也能正常工作，它会自己认出所在目录就是工程）。

```
your-repo/
├── .gitignore              ← 忽略 build/ bin/ .cache/ 等
├── README.md               ← 用法（本母版已写好）
├── docs/
│   └── SKILL-Windows-环境搭建.md   ← 本文档
├── setup-windows.ps1       ← 一键脚本
├── run_simulator.bat       ← 双击即跑
├── CMakeLists.txt
├── simulator.code-workspace
├── lv_conf.h
├── lvgl/                   ← 子模块（或用 FetchContent）
└── src/
```

### 8.2 `.gitignore` 建议

```gitignore
build/
bin/
.cache/
*.exe
*.dll
*.a
*.o
.vs/
```

### 8.3 子模块 vs FetchContent

| 方案 | 优点 | 缺点 |
|---|---|---|
| **git submodule**（上游做法） | 版本固定可复现 | 用户必须 `--recursive`，ZIP 下载会残缺 |
| **CMake FetchContent** | 用户 `git clone` 即可，无需子模块 | 首次 configure 要联网下载 LVGL |

**推荐 FetchContent**，对新手最友好：
```cmake
include(FetchContent)
FetchContent_Declare(lvgl
    GIT_REPOSITORY https://github.com/lvgl/lvgl.git
    GIT_TAG        v9.5.0
    GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(lvgl)
```
这样 `git clone <你的仓库>` → `cmake -S . -B build` 就能跑，不需要 `--recursive`。

### 8.4 README 顶部放「一键开始」

```markdown
## 一键开始（Windows）

```powershell
git clone https://github.com/<你>/<仓库>
cd <仓库>
.\setup-windows.ps1
```
脚本会自动检查依赖、设置 `SDL2_DIR`、配置、构建、启动。
```

### 8.5 给 Linux/macOS 用户的说明

本母版在 Windows 上验证，Linux/macOS 上：
- 装 `libsdl2-dev`（Debian）/ `sdl2`（Arch）/ `SDL2-devel`（Fedora）/ `brew install sdl2`（macOS）
- `cmake -S . -B build && cmake --build build -j`
- 不需要 DLL 拷贝（`.so` / `.dylib` 由系统加载器处理），`POST_BUILD` 块被 `if(WIN32)` 挡住，不影响

---

## 附录 A：全部命令速查

```powershell
# ── 环境检查 ────────────────────────────────────────────────
gcc --version; g++ --version; gdb --version
cmake --version; ninja --version; python --version; git --version
echo %SDL2_DIR%

# ── 设置 SDL2_DIR ───────────────────────────────────────────
[Environment]::SetEnvironmentVariable('SDL2_DIR',
  'D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32\lib\cmake\SDL2', 'User')

# ── 构建 ────────────────────────────────────────────────────
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j
cmake --build build --target run

# ── 清理重建 ────────────────────────────────────────────────
Remove-Item -Recurse -Force build
cmake -S . -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j

# ── 诊断 ────────────────────────────────────────────────────
# 看 exe 依赖哪些 DLL
& "D:\A_software_study\GCC_MingGW64\mingw64\bin\objdump.exe" -p .\bin\main.exe |
  Select-String 'DLL Name:'

# 看真正的编译错误（make 只报 Error 1 时）
$cc = Get-Content .\build\compile_commands.json -Raw | ConvertFrom-Json
$e = $cc | Where-Object { $_.file -like '*出问题的文件.c' }
Set-Location $e.directory; Invoke-Expression $e.command

# 验证 PATH 无关性
$env:PATH = "C:\Windows\system32;C:\Windows"; .\bin\main.exe

# ── VS Code ─────────────────────────────────────────────────
code --status        # 看加载了哪些 launch 配置
```

---

## 附录 B：另一条路 —— Win32 原生驱动（不用 SDL2）

LVGL 自带一个 Windows 原生显示驱动，**完全不需要 SDL2**。想换成它：

```c
/* lv_conf.h */
#define LV_USE_SDL      0
#define LV_USE_WINDOWS  1
#define LV_USE_OS       LV_OS_WINDOWS
```

**优点**：零外部依赖（exe 只链 `user32`/`gdi32`）、高 DPI 感知、不用装 SDL2。
**缺点**：不跨平台、没有 GPU 加速路径、生态小。

**⚠️ 有个真实的死锁坑，必须知道：**

`hal_init()` **必须在 `lv_lock()` 之前**调用。原因是：

- `lv_windows_create_display()`（`lvgl/src/drivers/windows/lv_windows_display.c:44`）会
  `_beginthreadex(...)` 起一个窗口线程，然后在 **line 76** `WaitForSingleObjectEx(data.mutex, INFINITE, FALSE)` 阻塞等它。
- 那个线程在 **line 138** 调 `CreateWindowExW(...)`。**lines 152-160 的两个失败分支（`CreateWindowExW` 失败 / 取窗口上下文返回 NULL）都是 `return 0`，不调 line 167 的 `SetEvent(data->mutex)`** → 主线程**永久阻塞且完全静默**。
- 更糟的是窗口线程的 `WM_NCCREATE` 会调 `lv_display_create()` 去拿 LVGL 互斥锁，而 `main` 里 `lv_lock()` 已经持锁 → **死锁**。

**正确顺序：**
```c
lv_init();
hal_init(UI_WIDTH, UI_HEIGHT);   /* ← 必须在 lv_lock() 之前 */
lv_lock();
UI_INIT("A:");
lv_screen_load(my_screen_create());
lv_unlock();
while (1) {
    uint32_t idle_ms = lv_timer_handler();
    if (idle_ms == LV_NO_TIMER_READY) idle_ms = LV_DEF_REFR_PERIOD;
    lv_sleep_ms(idle_ms);
}
```

**症状对照**：进程存活（`HasExited=False`）但 `MainWindowHandle=0`、CPU 时间约 0.02s、`EnumWindows` 找不到窗口。**遇到这个症状就是这个坑。**

---

## 附录 C：本机验证环境快照

```
OS          Windows 10.0.26200 (x64)
CPU         AMD Ryzen 7 4800H
工具链      D:\A_software_study\GCC_MingGW64\mingw64\bin\
  gcc       15.1.0  (x86_64-ucrt-posix-seh, Brecht Sanders r1)
  g++       15.1.0
  gdb       16.3
  cmake     4.0.1
  ninja     1.12.1
  mingw32-make 4.4.1
Python      3.11.2
Git         2.50.1.windows.1
SDL2        2.32.10  D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32\
  SDL2_DIR  ...\x86_64-w64-mingw32\lib\cmake\SDL2
cmd 代码页  936 (GBK)
```

**最终验收：**
```
[100%] Linking CXX executable ...\bin\main.exe
Copying SDL2.dll next to the executable
Copying libgcc_s_seh-1.dll next to the executable
Copying libstdc++-6.dll next to the executable
[100%] Built target main
EXIT=0

# PATH 只剩 C:\Windows\system32 时：
bin\main.exe → 进程存活，窗口标题 "LVGL Simulator"
```
