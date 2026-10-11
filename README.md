# VSCode Simulator project for LVGL

[LVGL](https://github.com/lvgl/lvgl) is written mainly for microcontrollers and embedded systems, however you can run the library **on your PC** as well without any embedded hardware. The code written on PC can be simply copied when you are using an embedded system.

This project is pre-configured for VSCode and should work on Windows, Linux and macOS as well.

> **This is a pure LVGL project.** FreeRTOS and the POSIX port that used to ship with the upstream
> `lv_port_pc_vscode` template have been removed — the simulator runs LVGL directly on the host OS.
> If you need an RTOS on the PC, add it yourself; on real hardware (ESP32 / STM32) the RTOS comes
> with the SDK and needs no configuration here.

## Get started

### Install SDL and the build tools

- **Windows:** install [SDL2](https://github.com/libsdl-org/SDL/releases) (`SDL2-devel-<ver>-mingw.tar.gz`
  for MinGW — **not** the `-VC` package and **not** SDL3), plus MinGW-w64 and `cmake`.
  Then point CMake at SDL2 once, so every configure finds it automatically:
  ```powershell
  [Environment]::SetEnvironmentVariable('SDL2_DIR',
    'D:\A_software_study\SDL2\SDL2-2.32.10\x86_64-w64-mingw32\lib\cmake\SDL2', 'User')
  ```
  The path must be the folder that contains `sdl2-config.cmake` (two levels below the SDL2 root).
- **Windows (vcpkg):** `vcpkg install sdl2` (`vcpkg` can be installed from
  [https://github.com/microsoft/vcpkg](https://github.com/microsoft/vcpkg))
- **macOS (Homebrew):** `brew install sdl2 cmake make`
- **Linux:**
  - **Debian/Ubuntu:** `sudo apt install build-essential cmake libsdl2-dev`
  - **Arch:** `sudo pacman -S base-devel cmake sdl2`
  - **Fedora:** `sudo dnf install @development-tools cmake SDL2-devel`
- **Manual installation of SDL:** download from [SDL's website](https://github.com/libsdl-org/SDL/releases)
  and place headers/libraries in your project.
- **Verify installation:** `sdl2-config --version`, `cmake --version`, `gcc --version`, `g++ --version`
  (should return the installed version).

### Get the PC project

Clone the PC project and the related sub modules:

```bash
git clone --recursive https://github.com/lvgl/lv_port_pc_vscode
```

## Usage

### Visual Studio Code

1. Be sure you have installed [SDL and the build tools](#install-sdl-and-the-build-tools)
2. Open the project by double clicking on `simulator.code-workspace` or opening it with `File/Open Workspace from File`
3. Install the recommended plugins
4. Click the Run and Debug page on the left, and select `Debug LVGL demo with gdb` from the drop-down on the top. Like this:
![image](https://github.com/lvgl/lv_port_pc_vscode/assets/7599318/f527b235-5718-4949-b5f0-bd807b3a64ba)
5. Click the Play button or hit F5 to start debugging.

> On Windows the executable is `bin\main.exe` — the launch configurations in `simulator.code-workspace`
> already use that name and the correct `gdb.exe` path. Pick the **gdb** configuration; the
> `Debug LVGL demo with LLVM` one needs `lldb`, which is not part of a MinGW toolchain.

#### ArchLinux User

VSCode does not officially provide an installation package under Arch, you need to use the AUR manager `paru` to install it.
The command is as follows:

```bash
paru -S visual-studio-code-bin
```

#### macOS

Apple's default clang does not support the `-fsanitize=leak` flag.

to build using the latest version of clang from homebrew, do the following:

1. `brew install llvm`

2. cmd+shift+p and run `Cmake: select a kit`, then `[Scan for kits]`

3. then cmd+shift+p and run `Cmake: select a kit`, select the version of clang you just installed from homebrew (it should say `Using compilers C=/opt/homebrew/opt/llvm/bin/clang ...`)

4. reconfigure by running cmd+shift+p `Cmake: Configure`

5. build using [step 4 above](#visual-studio-code)

### Windows: the runtime DLLs

`bin\main.exe` needs `SDL2.dll`, `libgcc_s_seh-1.dll` and `libstdc++-6.dll` next to it (Windows looks
for DLLs in the executable's own folder first). You do **not** have to copy them by hand: the build
does it for you.

`CMakeLists.txt` registers a `POST_BUILD` step on the `main` target that copies all three DLLs into the
output folder after every link, so you will see this at the end of a build:

```
[100%] Linking CXX executable ...\bin\main.exe
Copying SDL2.dll next to the executable
Copying libgcc_s_seh-1.dll next to the executable
Copying libstdc++-6.dll next to the executable
[100%] Built target main
```

`SDL2.dll` is taken from `SDL2_BINDIR` (falling back to the `bin/` folder derived from
`SDL2_INCLUDE_DIRS`); the two MinGW runtime DLLs are taken from the folder holding `CMAKE_C_COMPILER`.
If `SDL2.dll` cannot be located the configure step prints a warning instead of failing.

### CMake

This project uses CMake under the hood which can be used without Visual Studio Code too. Just type these in a Terminal when you are in the project's root folder:

```bash
mkdir build
cd build
cmake ..
make -j
```

## Run demos and examples

By default, the widgets demo (`lv_demo_widgets()`) will run. If you want to run a different demo or example from the LVGL library,
simply replace the demo function call in the code with another one—such as `lv_demo_benchmark()` or `lv_example_label_1()`.

```c
int main(int argc, char **argv)
{
  /* ... */
  /* Run the default demo */
  /* To try a different demo or example, replace this with one of: */
  /* - lv_demo_benchmark(); */
  /* - lv_demo_stress(); */
  /* - lv_example_label_1(); */
  /* - etc. */
  lv_demo_widgets(); 

  while(1) {
      /* ... */
  }
  return 0;
}
```

## Optional library

There are also FreeType and FFmpeg support. You can install these according to the followings:

### Linux

```bash
# FreeType support
wget https://kumisystems.dl.sourceforge.net/project/freetype/freetype2/2.13.2/freetype-2.13.2.tar.xz
tar -xf freetype-2.13.2.tar.xz
cd freetype-2.13.2
make
make install
```

```bash
# FFmpeg support
git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
cd ffmpeg
git checkout release/6.0
./configure --disable-all --disable-autodetect --disable-podpages --disable-asm --enable-avcodec --enable-avformat --enable-decoders --enable-encoders --enable-demuxers --enable-parsers --enable-protocol='file' --enable-swscale --enable-zlib
make
sudo make install
```

### (RT)OS support

LVGL itself can be driven from any OS or bare metal. On the PC this project runs it directly on the
host OS; on an embedded target the RTOS is supplied by the vendor SDK. The LVGL-side knobs for this
are `LV_USE_OS` and the `LV_OS_*` values in `lv_conf.h` — they are part of the LVGL library and are
left at their defaults here.

## Test

This project is configured for [VSCode](https://code.visualstudio.com) and is tested on:

- Ubuntu Linux
- Windows WSL (Ubuntu Linux)
- Windows 10/11 with MinGW-w64 + Ninja or MinGW Makefiles

It requires a working version of GCC, GDB and make in your path.

To allow debugging inside VSCode you will also require a GDB [extension](https://marketplace.visualstudio.com/items?itemName=webfreak.debug) or other suitable debugger. All the requirements, build and debug settings have been pre-configured in the [.workspace](simulator.code-workspace) file.

The project can use **SDL** but it can be easily replaced by any other built-in LVGL driver.

## Changes from upstream

- **FreeRTOS removed.** The `FreeRTOS/` submodule, `src/freertos_main.c`, `src/freertos/`,
  `config/FreeRTOSConfig.h`, `.gitmodules` and every FreeRTOS branch in `CMakeLists.txt` are gone.
  The build always compiles `src/main.c`; there is no `USE_FREERTOS` option any more.
- **Windows DLL auto-copy** added to `CMakeLists.txt` (see above).
- **`simulator.code-workspace` fixed for Windows:** launch `program` is `bin/main.exe`,
  `miDebuggerPath` points at the real gdb, and the debug/run tasks prepend SDL2's and MinGW's `bin`
  folders to `PATH`.
- `lv_conf.h` sets `LV_USE_THORVG 1` so that the `LV_USE_VECTOR_GRAPHIC` / `LV_USE_LOTTIE`
  requirements are satisfied (ThorVG is compiled from the bundled source).

## Integration with LVGL Pro

This project supports integration with LVGL Pro projects for UI development.

### Setup

1. Configure CMake with your LVGL Pro project folder:

```bash
cmake -B build -DLVGL_PRO_PROJECT_DIR=<path-to-lvgl-pro-project>
```

Build your project:

```bash
cmake --build build
```

### Usage in Code

In your main.c, include the UI header from your LVGL Pro project and replace the default demo with your screen.

```c
#include "ui.h"

int main(void) {

    /*Initialization code for LVGL*/
    
    /* Initialize the LVGL Pro UI */
    ui_init("<path-to-lvgl-pro-project>");
    
    /* ... rest of your application ...*/
}
```
