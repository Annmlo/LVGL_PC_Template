<#
.SYNOPSIS
    LVGL PC 模拟器（lv_port_pc_vscode）Windows 一键搭建脚本。

.DESCRIPTION
    自动完成：
      1. 检查工具链（gcc / g++ / gdb / cmake / python / git）
      2. 定位 SDL2（自动搜索常见位置，找不到就提示下载）
      3. 必要时设置用户级环境变量 SDL2_DIR（只影响 SDL2，不动 PATH）
      4. CMake configure + build
      5. 校验 bin\ 里的运行时 DLL 是否齐全
      6. 可选：启动模拟器

    所有检查都是「先报告、再询问」，不会静默改动你的系统。

.PARAMETER ProjectRoot
    LVGL 工程根目录（含 CMakeLists.txt 和 lvgl\ 的那一层），例如
    D:\A_study_document\LVGL\EXAMPLE\NEWTEST\lv_port_pc_vscode-master。
    不给就按顺序自动找：当前目录 → 脚本所在目录 → 常见位置搜索。

.PARAMETER Sdl2Root
    SDL2 解压根目录，例如 D:\A_software_study\SDL2\SDL2-2.32.10。
    不给就自动搜索常见位置。

.PARAMETER SkipRun
    构建完成后不启动模拟器。

.PARAMETER Clean
    先删掉 build\ 再重新 configure。

.PARAMETER Release
    用 Release 配置（默认 Debug）。

.EXAMPLE
    .\setup-windows.ps1
    自动检测 + 构建 + 启动

.EXAMPLE
    .\setup-windows.ps1 -Sdl2Root "D:\SDL2\SDL2-2.32.10" -Clean
    指定 SDL2 位置并清理重建

.NOTES
    需要 PowerShell 5.1+。若报「禁止运行脚本」，先执行：
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#>

[CmdletBinding()]
param(
    [string] $ProjectRoot,
    [string] $Sdl2Root,
    [switch] $SkipRun,
    [switch] $Clean,
    [switch] $Release
)

$ErrorActionPreference = 'Stop'
$script:Problems = @()
$script:Warnings = @()

# ─────────────────────────────────────────────────────────────────────────────
# 输出助手
# ─────────────────────────────────────────────────────────────────────────────
function Say      { param([string]$m) Write-Host $m }
function Head     { param([string]$m) Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Ok       { param([string]$m) Write-Host "  [OK]   $m" -ForegroundColor Green }
function Warn     { param([string]$m) Write-Host "  [警告] $m" -ForegroundColor Yellow; $script:Warnings += $m }
function Bad      { param([string]$m) Write-Host "  [缺失] $m" -ForegroundColor Red;    $script:Problems += $m }
function Info     { param([string]$m) Write-Host "  ·      $m" -ForegroundColor Gray }

# ─────────────────────────────────────────────────────────────────────────────
# 0. 定位工程根目录
#    本脚本可以放在任何地方（推荐 D:\A_study_document\LVGL\环境搭建\）。
#    找工程的顺序：-ProjectRoot 参数 → 当前目录 → 脚本所在目录 → 常见位置搜索。
# ─────────────────────────────────────────────────────────────────────────────
function Test-ProjectRoot {
    param([string] $p)
    if (-not $p) { return $false }
    if (-not (Test-Path $p)) { return $false }
    return (Test-Path (Join-Path $p 'CMakeLists.txt')) -and (Test-Path (Join-Path $p 'lvgl'))
}

$Root = $null

if ($ProjectRoot) {
    if (Test-ProjectRoot $ProjectRoot) {
        $Root = (Resolve-Path $ProjectRoot).Path
    } else {
        Write-Host "错误：-ProjectRoot 指向的 $ProjectRoot 里没有 CMakeLists.txt 或 lvgl\。" -ForegroundColor Red
        exit 1
    }
}

if (-not $Root -and (Test-ProjectRoot (Get-Location).Path)) { $Root = (Get-Location).Path }
if (-not $Root -and (Test-ProjectRoot $PSScriptRoot))       { $Root = $PSScriptRoot }

if (-not $Root) {
    Write-Host "  没指定工程目录，正在搜索常见位置……" -ForegroundColor Gray
    $candidates = @(
        "D:\A_study_document\LVGL\EXAMPLE\NEWTEST\lv_port_pc_vscode-master",
        "D:\A_study_document\LVGL\EXAMPLE\NEWTEST",
        "D:\A_study_document\LVGL\EXAMPLE"
    )
    foreach ($c in $candidates) {
        if (-not (Test-Path $c)) { continue }
        if (Test-ProjectRoot $c) { $Root = (Resolve-Path $c).Path; break }
        $hit = Get-ChildItem -Path $c -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
               Where-Object { Test-ProjectRoot $_.FullName } | Select-Object -First 1
        if ($hit) { $Root = $hit.FullName; break }
    }
}

if (-not $Root) {
    Write-Host "错误：没找到 LVGL 工程（需要同时有 CMakeLists.txt 和 lvgl\ 目录）。" -ForegroundColor Red
    Write-Host "请用 -ProjectRoot 指定，例如：" -ForegroundColor Red
    Write-Host '    .\setup-windows.ps1 -ProjectRoot "D:\path\to\lv_port_pc_vscode-master"' -ForegroundColor Yellow
    exit 1
}
Set-Location $Root

Say ""
Say "  LVGL PC 模拟器 —— Windows 一键搭建" -ForegroundColor White
Say "  工程目录：$Root"
Say "  " + ('─' * 60) -ForegroundColor DarkGray

# ─────────────────────────────────────────────────────────────────────────────
# 1. 检查工具链
# ─────────────────────────────────────────────────────────────────────────────
Head "1/6  检查工具链"

function Test-Tool {
    param([string]$Name, [string]$Exe, [string[]]$VersionArgs, [string]$Why)
    $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) { Bad "$Name  —— $Why"; return $null }
    try {
        $v = (& $cmd.Source @VersionArgs 2>&1 | Select-Object -First 1)
    } catch { $v = '(版本未知)' }
    Ok ("{0,-10} {1}" -f $Name, $v)
    return $cmd.Source
}

$gcc    = Test-Tool 'gcc'    'gcc'    @('--version') '需要 MinGW-w64（x86_64 / posix / seh / ucrt）'
$gpp    = Test-Tool 'g++'    'g++'    @('--version') '需要 MinGW-w64 的 C++ 前端'
$gdb    = Test-Tool 'gdb'    'gdb'    @('--version') '调试用；没有也能构建，但 VS Code 调试不可用'
$cmake  = Test-Tool 'cmake'  'cmake'  @('--version') '必需：https://cmake.org/download/'
$python = Test-Tool 'python' 'python' @('--version') '必需：LVGL 的构建脚本用它'
$git    = Test-Tool 'git'    'git'    @('--version') '拉子模块用；本仓库已含子模块则可不装'

$ninja  = Get-Command 'ninja'         -ErrorAction SilentlyContinue
$mmake  = Get-Command 'mingw32-make'  -ErrorAction SilentlyContinue
if ($ninja) { Ok ("{0,-10} {1}" -f 'ninja', (& $ninja.Source --version)) }
elseif ($mmake) { Info 'ninja 没装，将使用 mingw32-make' }
else { Warn 'ninja 和 mingw32-make 都没有；CMake 可能找不到可用的构建工具' }

if (-not $cmake -or -not $python -or -not $gcc -or -not $gpp) {
    Head "无法继续"
    Say "  以下必需组件缺失："
    $script:Problems | ForEach-Object { Say "    - $_" }
    Say ""
    Say "  安装指引见 docs\SKILL-Windows-环境搭建.md 第 3.1 ~ 3.2 节。"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. 定位 SDL2
# ─────────────────────────────────────────────────────────────────────────────
Head "2/6  定位 SDL2"

function Find-Sdl2ConfigDir {
    param([string]$RootPath)
    # 在给定目录下找含 sdl2-config.cmake 的 x86_64-w64-mingw32 子树
    if (-not (Test-Path $RootPath)) { return $null }
    $hits = Get-ChildItem -Path $RootPath -Recurse -Depth 6 `
                -Filter 'sdl2-config.cmake' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'x86_64-w64-mingw32' } |
            Sort-Object FullName
    if ($hits) { return $hits[0].Directory.FullName }
    return $null
}

$sdl2Dir = $null
$sdl2Origin = ''

# 2a. 用户显式指定
if ($Sdl2Root) {
    Info "使用 -Sdl2Root 指定的位置：$Sdl2Root"
    $sdl2Dir = Find-Sdl2ConfigDir $Sdl2Root
    if (-not $sdl2Dir) { Bad "在 $Sdl2Root 下找不到 x86_64-w64-mingw32\...\lib\cmake\SDL2\sdl2-config.cmake" }
    else { $sdl2Origin = '-Sdl2Root 参数' }
}

# 2b. 已有环境变量
if (-not $sdl2Dir) {
    $envDir = [Environment]::GetEnvironmentVariable('SDL2_DIR', 'User')
    if (-not $envDir) { $envDir = [Environment]::GetEnvironmentVariable('SDL2_DIR', 'Machine') }
    if ($envDir -and (Test-Path (Join-Path $envDir 'sdl2-config.cmake'))) {
        $sdl2Dir = $envDir
        $sdl2Origin = '已有的 SDL2_DIR 环境变量'
    }
}

# 2c. CMake 缓存里已经记住的
if (-not $sdl2Dir) {
    $cache = Join-Path $Root 'build\CMakeCache.txt'
    if (Test-Path $cache) {
        $line = Select-String -Path $cache -Pattern '^SDL2_DIR:PATH=(.+)$' -Encoding UTF8 |
                Select-Object -First 1
        if ($line -and (Test-Path (Join-Path $line.Matches[0].Groups[1].Value 'sdl2-config.cmake'))) {
            $sdl2Dir = $line.Matches[0].Groups[1].Value
            $sdl2Origin = 'build\CMakeCache.txt 里的缓存值'
        }
    }
}

# 2d. 常见位置自动搜索
if (-not $sdl2Dir) {
    $guessRoots = @(
        'D:\A_software_study\SDL2'
        'C:\SDL2'
        'D:\SDL2'
        'C:\dev\SDL2'
        'D:\dev\SDL2'
        (Join-Path $env:USERPROFILE 'Downloads')
        (Join-Path $env:USERPROFILE 'SDL2')
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($g in $guessRoots) {
        Info "搜索 $g ..."
        $sdl2Dir = Find-Sdl2ConfigDir $g
        if ($sdl2Dir) { $sdl2Origin = "自动搜索（$g）"; break }
    }
}

if (-not $sdl2Dir) {
    Head "找不到 SDL2"
    Say "  请下载并解压 SDL2 的开发包（不是运行时包，也不是 SDL3）："
    Say ""
    Say "    https://github.com/libsdl-org/SDL/releases/tag/release-2.32.10"
    Say "    文件：SDL2-devel-2.32.10-mingw.tar.gz   (13,892,870 B)"
    Say "    SHA-256: 83A5D74012311EDC3C0D40EA6FAECBE57AD692AA033FA5DC273CC937E3938FF2"
    Say ""
    Say "  解压后目录结构（注意 tar 包多套了一层）："
    Say "    SDL2-2.32.10\x86_64-w64-mingw32\lib\cmake\SDL2\sdl2-config.cmake"
    Say ""
    Say "  然后重跑本脚本，指定位置："
    Say "    .\setup-windows.ps1 -Sdl2Root ""D:\SDL2\SDL2-2.32.10"""
    Say ""
    Say "  详细说明见 docs\SKILL-Windows-环境搭建.md 第 3.3 节。"
    exit 1
}

Ok "找到 SDL2（来源：$sdl2Origin）"
Info $sdl2Dir

# SDL2 前缀 = 含 bin\SDL2.dll 的那一层
#   典型布局： <prefix>\bin\SDL2.dll
#              <prefix>\include\SDL2\SDL.h
#              <prefix>\lib\cmake\SDL2\sdl2-config.cmake   ← $sdl2Dir
#   即 prefix 比 $sdl2Dir 高三级；这里逐级往上探测，不写死级数。
$sdl2Prefix = $null
$probe = $sdl2Dir
for ($i = 0; $i -lt 6 -and $probe; $i++) {
    if (Test-Path (Join-Path $probe 'bin\SDL2.dll')) { $sdl2Prefix = $probe; break }
    $probe = Split-Path $probe -Parent
}
if (-not $sdl2Prefix) {
    # 探测不到就按约定退三级兜底
    $sdl2Prefix = Split-Path (Split-Path (Split-Path $sdl2Dir -Parent) -Parent) -Parent
}

if (Test-Path (Join-Path $sdl2Prefix 'bin\SDL2.dll')) {
    Ok "SDL2 前缀：$sdl2Prefix"
    Ok "SDL2.dll = $((Get-Item (Join-Path $sdl2Prefix 'bin\SDL2.dll')).Length) B"
} else {
    Warn "在 $sdl2Prefix\bin\ 里没找到 SDL2.dll —— 构建能过，但运行时会缺 DLL"
    Warn "请确认你下的是 SDL2-devel-<ver>-mingw.tar.gz（不是 -VC，也不是 win32-x64 运行时包）"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. 设置 SDL2_DIR（用户级，只影响 SDL2）
# ─────────────────────────────────────────────────────────────────────────────
Head "3/6  设置 SDL2_DIR"

$curUser = [Environment]::GetEnvironmentVariable('SDL2_DIR', 'User')
if ($curUser -eq $sdl2Dir) {
    Ok "用户级 SDL2_DIR 已经是正确的值，无需改动"
} else {
    Say "  即将写入用户级环境变量（HKCU\Environment，只影响当前账户）："
    Say "    SDL2_DIR = $sdl2Dir"
    if ($curUser) { Say "    （原值：$curUser）" }
    Say ""
    Say "  为什么是这一层？这个目录里有 sdl2-config.cmake。"
    Say "  注意别和 CMAKE_PREFIX_PATH 搞混 —— 那个要指向高三级的前缀 $sdl2Prefix"
    Say ""
    $ans = Read-Host "  要写入吗？(Y/n)"
    if ($ans -eq '' -or $ans -match '^[Yy]') {
        [Environment]::SetEnvironmentVariable('SDL2_DIR', $sdl2Dir, 'User')
        $env:SDL2_DIR = $sdl2Dir          # 让当前进程也能用
        Ok "已写入"

        # 广播 WM_SETTINGCHANGE，让资源管理器 / VS Code 立即拿到新环境
        try {
            $sig = @'
using System;using System.Runtime.InteropServices;
public class DshWin32 {
  [DllImport("user32.dll",CharSet=CharSet.Auto,SetLastError=true)]
  public static extern IntPtr SendMessageTimeout(IntPtr h,uint m,UIntPtr w,string l,uint f,uint t,out UIntPtr r);
}
'@
            if (-not ('DshWin32' -as [type])) { Add-Type $sig }
            $r = [UIntPtr]::Zero
            [DshWin32]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero,
                                           'Environment', 0x0002, 5000, [ref]$r) | Out-Null
            Info "已广播 WM_SETTINGCHANGE（新开的终端/VS Code 会立即生效）"
        } catch {
            Warn "广播 WM_SETTINGCHANGE 失败，可能需要重启 VS Code / 资源管理器"
        }
    } else {
        Warn "你选择了不写入。本次构建会用命令行 -DCMAKE_PREFIX_PATH 临时指定。"
        $env:SDL2_DIR = $sdl2Dir
    }
}
$env:SDL2_DIR = $sdl2Dir

# ─────────────────────────────────────────────────────────────────────────────
# 4. configure
# ─────────────────────────────────────────────────────────────────────────────
Head "4/6  CMake configure"

$buildDir   = Join-Path $Root 'build'
$buildType  = if ($Release) { 'Release' } else { 'Debug' }

if ($Clean -and (Test-Path $buildDir)) {
    Info "清理旧的 build\ ..."
    Remove-Item -Recurse -Force $buildDir
}

if (Test-Path (Join-Path $buildDir 'CMakeCache.txt')) {
    $cachedPrefix = (Select-String -Path (Join-Path $buildDir 'CMakeCache.txt') `
                        -Pattern '^CMAKE_PREFIX_PATH' -Encoding UTF8 | Select-Object -First 1)
    if ($cachedPrefix -and $cachedPrefix.Line -notmatch [regex]::Escape($sdl2Prefix)) {
        Warn "build\ 里缓存的 SDL2 路径和现在找到的不一致，建议加 -Clean 重建"
    }
}

$configureArgs = @('-S', $Root, '-B', $buildDir, "-DCMAKE_BUILD_TYPE=$buildType")
# 即使 SDL2_DIR 已设，也显式带上，防止当前进程没继承到
$configureArgs += "-DCMAKE_PREFIX_PATH=$sdl2Prefix"

Say "  cmake $($configureArgs -join ' ')"
Say ""

& cmake @configureArgs
if ($LASTEXITCODE -ne 0) {
    Head "configure 失败"
    Say "  常见原因见 docs\SKILL-Windows-环境搭建.md 第 4 节："
    Say "    · Could not find a package configuration file provided by ""SDL2""  → §4.1"
    Say "    · Cannot find source file ... freertos_kernel_port                 → §4.2（用了 ZIP 下载）"
    exit $LASTEXITCODE
}
Ok "configure 完成"

# ─────────────────────────────────────────────────────────────────────────────
# 5. build
# ─────────────────────────────────────────────────────────────────────────────
Head "5/6  编译"

$jobs = [Math]::Max(1, [Environment]::ProcessorCount - 1)
Say "  cmake --build build -j $jobs"
Say ""

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& cmake --build $buildDir -j $jobs
$code = $LASTEXITCODE
$sw.Stop()

if ($code -ne 0) {
    Head "编译失败"
    Say "  常见原因见 docs\SKILL-Windows-环境搭建.md 第 4 节："
    Say "    · undefined reference to 'SDL_main'                → §4.3"
    Say "    · #error ""LV_USE_VECTOR_GRAPHIC requires ...""       → §4.5"
    Say "      （make 只报 Error 1 时，用 §4.5 的方法挖出真正的 #error）"
    exit $code
}
Ok ("编译成功，用时 {0:N1} 秒" -f $sw.Elapsed.TotalSeconds)

# ─────────────────────────────────────────────────────────────────────────────
# 6. 校验产物
# ─────────────────────────────────────────────────────────────────────────────
Head "6/6  校验产物"

$binDir = Join-Path $Root 'bin'
if (-not (Test-Path $binDir)) {
    Warn "没有 bin\ 目录 —— 检查 CMakeLists.txt 里的 EXECUTABLE_OUTPUT_PATH"
} else {
    $exe = Join-Path $binDir 'main.exe'
    if (Test-Path $exe) { Ok "main.exe = $((Get-Item $exe).Length) B" }
    else { Bad "bin\main.exe 不存在" }

    # 从 exe 的真实依赖里挑出「需要旁边有」的 DLL
    $objdump = $null
    $gccCmd = Get-Command 'gcc' -ErrorAction SilentlyContinue
    if ($gccCmd) {
        $cand = Join-Path (Split-Path $gccCmd.Source -Parent) 'objdump.exe'
        if (Test-Path $cand) { $objdump = $cand }
    }

    if ($objdump -and (Test-Path $exe)) {
        $deps = & $objdump -p $exe |
                Select-String 'DLL Name:' |
                ForEach-Object { $_.Line.Split(':')[1].Trim() }
        # 系统自带的不用管
        $needLocal = $deps | Where-Object { $_ -notmatch '^(KERNEL32|USER32|GDI32|SHELL32|ADVAPI32|ole32|OLE32|WINMM|IMM32|api-ms-win-)' }
        $missing = @()
        foreach ($d in $needLocal) {
            if (Test-Path (Join-Path $binDir $d)) { Ok ("{0,-24} 在 bin\ 里 ✓" -f $d) }
            else { Bad ("{0,-24} 不在 bin\ 里 ✗" -f $d); $missing += $d }
        }
        if ($missing.Count -gt 0) {
            Say ""
            Warn "缺少 $($missing.Count) 个 DLL —— 双击 main.exe 会报「找不到 xxx.dll」"
            Say "  原因：Windows 从 exe 所在目录开始找 DLL，而这些 DLL 在别处。"
            Say "  本工程已在 CMakeLists.txt 里加了 POST_BUILD 自动拷贝。"
            Say "  若仍然缺失，说明拷贝逻辑没生效，请检查："
            Say "    · CMakeLists.txt 里 add_executable(main ...) 之后是否有那段 if(WIN32) POST_BUILD"
            Say "    · 构建日志里有没有 'Copying xxx.dll next to the executable'"
            Say "  详见 docs\SKILL-Windows-环境搭建.md 第 4.4 节。"
        }
    } else {
        Info "没有 objdump，跳过 DLL 依赖检查"
        foreach ($d in @('SDL2.dll','libgcc_s_seh-1.dll','libstdc++-6.dll')) {
            if (Test-Path (Join-Path $binDir $d)) { Ok ("{0,-24} 在 bin\ 里 ✓" -f $d) }
            else { Bad ("{0,-24} 不在 bin\ 里 ✗" -f $d) }
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 汇总
# ─────────────────────────────────────────────────────────────────────────────
Head "完成"

if ($script:Warnings.Count -gt 0) {
    Say "  警告（不影响使用）：" -ForegroundColor Yellow
    $script:Warnings | ForEach-Object { Say "    · $_" -ForegroundColor Yellow }
    Say ""
}

if ($script:Problems.Count -gt 0) {
    Say "  仍有问题："
    $script:Problems | ForEach-Object { Say "    · $_" -ForegroundColor Red }
    Say ""
    Say "  见 docs\SKILL-Windows-环境搭建.md 第 4 节。"
    exit 1
}

Say "  可执行文件：$binDir\main.exe"
Say ""
Say "  运行方式："
Say "    1. 双击 bin\main.exe"
Say "    2. .\bin\main.exe        （工作目录必须是工程根目录）"
Say "    3. cmake --build build --target run"
Say "    4. VS Code：双击 simulator.code-workspace → F5"
Say ""

if (-not $SkipRun) {
    $ans = Read-Host "  现在启动模拟器吗？(Y/n)"
    if ($ans -eq '' -or $ans -match '^[Yy]') {
        Say ""
        Say "  启动中... 关闭窗口即可退出。" -ForegroundColor Cyan
        Start-Process -FilePath (Join-Path $binDir 'main.exe') -WorkingDirectory $Root
    }
}

Say ""
Say "  " + ('─' * 60) -ForegroundColor DarkGray
Say "  完成。遇到问题查 docs\SKILL-Windows-环境搭建.md" -ForegroundColor White
Say ""
