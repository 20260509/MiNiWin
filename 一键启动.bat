@echo off
:: ============================================================
::  MiniWin 一键启动器 v8.0 (可读写硬盘版)
::  功能：编译、创建硬盘镜像、启动、清理、检查依赖
::  依赖：nasm, qemu-system-x86_64
::  数据持久化：所有 Ctrl+S 保存到 hd.img
:: ============================================================

setlocal enabledelayedexpansion

:: 设置代码页（UTF-8 → GBK 回退）
chcp 65001 >nul 2>&1
if errorlevel 1 chcp 936 >nul 2>&1

title MiniWin 启动器 v8.0
color 0A

:: 获取脚本所在目录（处理带空格的路径）
set "SCRIPT_DIR=%~dp0"
cd /d "%SCRIPT_DIR%" 2>nul

:menu
cls
echo ============================================================
echo                    MiniWin 启动器 v8.0
echo ============================================================
echo.
echo   [1] 编译 + 启动 (QEMU 硬盘模式，可读写)
echo   [2] 编译 + 启动 (QEMU 标准模式，仅内存)
echo   [3] 编译 + 启动 (带 USB 鼠标，仅内存)
echo   [4] 仅编译 (不启动)
echo   [5] 仅启动 (使用已有镜像)
echo   [6] 清理 (删除生成的文件)
echo   [7] 检查依赖 (nasm, qemu 是否可用)
echo   [0] 退出
echo.
echo ============================================================
set /p choice="请选择 [0-7]: "

:: 空输入处理
if "%choice%"=="" goto menu

:: 选项跳转
if "%choice%"=="1" goto compile_and_run_hd
if "%choice%"=="2" goto compile_and_run_mem
if "%choice%"=="3" goto compile_and_run_usb
if "%choice%"=="4" goto compile_only
if "%choice%"=="5" goto run_only
if "%choice%"=="6" goto clean
if "%choice%"=="7" goto check_deps
if "%choice%"=="0" goto exit_script

:: 非法输入
echo [错误] 无效选项，请重新选择！
timeout /t 2 /nobreak >nul 2>&1 || ping -n 3 127.0.0.1 >nul 2>&1
goto menu

:exit_script
endlocal
exit /b 0

:: ============================================================
::  [1] 编译 + 启动 (硬盘模式，可读写)
:: ============================================================
:compile_and_run_hd
cls
echo ============================================================
echo  模式: 编译 + 启动 (硬盘模式，可读写)
echo ============================================================
echo.
echo  提示: 所有 Ctrl+S 保存的数据将写入 hd.img
echo.
call :compile
if errorlevel 1 goto menu
call :create_hd_image
if errorlevel 1 goto menu
call :run_hd
goto menu

:: ============================================================
::  [2] 编译 + 启动 (标准模式，仅内存)
:: ============================================================
:compile_and_run_mem
cls
echo ============================================================
echo  模式: 编译 + 启动 (标准模式，仅内存)
echo ============================================================
echo.
call :compile
if errorlevel 1 goto menu
call :run_mem
goto menu

:: ============================================================
::  [3] 编译 + 启动 (带 USB 鼠标，仅内存)
:: ============================================================
:compile_and_run_usb
cls
echo ============================================================
echo  模式: 编译 + 启动 (带 USB 鼠标，仅内存)
echo ============================================================
echo.
call :compile
if errorlevel 1 goto menu
call :run_usb
goto menu

:: ============================================================
::  [4] 仅编译
:: ============================================================
:compile_only
cls
echo ============================================================
echo  模式: 仅编译
echo ============================================================
echo.
call :compile
echo.
pause
goto menu

:: ============================================================
::  [5] 仅启动 (让用户选择启动方式)
:: ============================================================
:run_only
cls
echo ============================================================
echo  模式: 仅启动
echo ============================================================
echo.

:: 检查有哪些镜像可用
set "has_hd=0"
set "has_bin=0"
if exist "hd.img" set "has_hd=1"
if exist "MiniWin.bin" set "has_bin=1"

if "%has_hd%"=="0" if "%has_bin%"=="0" (
    echo [错误] 没有找到 MiniWin.bin 或 hd.img，请先编译！
    echo.
    pause
    goto menu
)

:: 显示可用选项
echo  可用启动方式：
if "%has_hd%"=="1" echo     [A] 硬盘镜像 hd.img (可读写模式)
if "%has_bin%"=="1" echo     [B] 引导扇区 MiniWin.bin (内存模式)
echo.
set /p boot_choice="请选择启动方式 [A/B]: "

:: 处理用户选择
if /i "!boot_choice!"=="A" (
    if "%has_hd%"=="1" (
        call :run_hd
        goto menu
    ) else (
        echo [错误] hd.img 不存在！
        timeout /t 2 /nobreak >nul 2>&1 || ping -n 3 127.0.0.1 >nul 2>&1
        goto menu
    )
)
if /i "!boot_choice!"=="B" (
    if "%has_bin%"=="1" (
        call :run_mem
        goto menu
    ) else (
        echo [错误] MiniWin.bin 不存在！
        timeout /t 2 /nobreak >nul 2>&1 || ping -n 3 127.0.0.1 >nul 2>&1
        goto menu
    )
)

:: 非法输入
echo [错误] 无效选择，请输入 A 或 B
timeout /t 2 /nobreak >nul 2>&1 || ping -n 3 127.0.0.1 >nul 2>&1
goto menu

:: ============================================================
::  [6] 清理 (增强版)
:: ============================================================
:clean
cls
echo ============================================================
echo  模式: 清理
echo ============================================================
echo.
echo 将删除以下文件:
echo   - MiniWin.bin (引导扇区)
echo   - MiniWin.lst (列表文件)
if exist "MiniWin.map" echo   - MiniWin.map (符号映射)
if exist "MiniWin.sym" echo   - MiniWin.sym (符号表)
if exist "MiniWin.err" echo   - MiniWin.err (错误日志)
if exist "MiniWin.hex" echo   - MiniWin.hex (临时十六进制)
if exist "hd.img" echo   - hd.img (硬盘镜像，包含所有保存的数据！)
if exist "floppy.img" echo   - floppy.img (软盘镜像)
echo.
set /p confirm="确认删除？[Y/N]: "
if /i not "%confirm%"=="Y" (
    echo 操作已取消。
    pause
    goto menu
)

set "deleted_count=0"

if exist "MiniWin.bin" (
    del /f /q "MiniWin.bin" 2>nul
    if exist "MiniWin.bin" (
        echo [失败] 无法删除 MiniWin.bin (文件可能被占用)
    ) else (
        echo [成功] 已删除 MiniWin.bin
        set /a deleted_count+=1
    )
) else (
    echo [信息] MiniWin.bin 不存在
)

if exist "MiniWin.lst" (
    del /f /q "MiniWin.lst" 2>nul
    echo [成功] 已删除 MiniWin.lst
    set /a deleted_count+=1
)

if exist "MiniWin.map" (
    del /f /q "MiniWin.map" 2>nul
    echo [成功] 已删除 MiniWin.map
    set /a deleted_count+=1
)

if exist "MiniWin.sym" (
    del /f /q "MiniWin.sym" 2>nul
    echo [成功] 已删除 MiniWin.sym
    set /a deleted_count+=1
)

if exist "MiniWin.err" (
    del /f /q "MiniWin.err" 2>nul
    echo [成功] 已删除 MiniWin.err
    set /a deleted_count+=1
)

if exist "MiniWin.hex" (
    del /f /q "MiniWin.hex" 2>nul
    echo [成功] 已删除 MiniWin.hex
    set /a deleted_count+=1
)

if exist "hd.img" (
    del /f /q "hd.img" 2>nul
    echo [成功] 已删除 hd.img
    set /a deleted_count+=1
) else (
    echo [信息] hd.img 不存在
)

if exist "floppy.img" (
    del /f /q "floppy.img" 2>nul
    echo [成功] 已删除 floppy.img
    set /a deleted_count+=1
)

echo.
if !deleted_count! gtr 0 (
    echo [成功] 共清理了 !deleted_count! 个文件
) else (
    echo [信息] 没有文件需要清理
)
echo.
pause
goto menu

:: ============================================================
::  [7] 检查依赖
:: ============================================================
:check_deps
cls
echo ============================================================
echo  检查依赖
echo ============================================================
echo.
set "all_ok=1"

echo [1] 检查 NASM...
where nasm >nul 2>&1
if errorlevel 1 (
    echo   [×] NASM 未找到！请安装 NASM 并添加到 PATH
    echo       下载: https://www.nasm.us/pub/nasm/releasebuilds/
    set "all_ok=0"
) else (
    for /f "delims=" %%i in ('nasm -v 2^>^&1 ^| findstr /i "version"') do echo   [√] %%i
)

echo.
echo [2] 检查 QEMU...
where qemu-system-x86_64 >nul 2>&1
if errorlevel 1 (
    echo   [×] QEMU 未找到！请安装 QEMU 并添加到 PATH
    echo       下载: https://www.qemu.org/download/#windows
    set "all_ok=0"
) else (
    for /f "delims=" %%i in ('qemu-system-x86_64 -version 2^>^&1 ^| findstr /i "version"') do echo   [√] %%i
)

echo.
echo [3] 检查 qemu-img (推荐工具)...
where qemu-img >nul 2>&1
if errorlevel 1 (
    echo   [×] qemu-img 未找到 (可选，但推荐安装)
    echo       安装 QEMU 时请勾选 qemu-img 组件
) else (
    for /f "delims=" %%i in ('qemu-img --version 2^>^&1 ^| findstr /i "qemu-img"') do echo   [√] %%i
)

echo.
echo [4] 检查源码文件...
if exist "MiniWin.asm" (
    echo   [√] MiniWin.asm 存在
    call :getsize "MiniWin.asm"
) else (
    echo   [×] MiniWin.asm 不存在！请确保该文件在同目录下
    set "all_ok=0"
)

echo.
echo [5] 检查已编译文件...
if exist "MiniWin.bin" (
    echo   [√] MiniWin.bin 存在
    call :getsize "MiniWin.bin"
) else (
    echo   [×] MiniWin.bin 不存在 (需要编译)
)

if exist "hd.img" (
    echo   [√] hd.img 存在 (可读写硬盘镜像)
    call :getsize "hd.img"
) else (
    echo   [×] hd.img 不存在 (选项1会自动创建)
)

echo.
if "%all_ok%"=="1" (
    echo [√] 所有关键依赖已就绪，可以开始使用！
) else (
    echo [×] 部分关键依赖缺失，请安装后重试。
)
echo.
pause
goto menu

:: ============================================================
::  子过程: 编译
:: ============================================================
:compile
if not exist "MiniWin.asm" (
    echo [错误] MiniWin.asm 不存在！
    echo.
    pause
    exit /b 1
)

echo [1/3] 正在编译 MiniWin.asm ...
nasm -f bin -Ox "MiniWin.asm" -o "MiniWin.bin" -l "MiniWin.lst" 2>&1
if errorlevel 1 (
    echo.
    echo [错误] 编译失败！请检查 MiniWin.asm 文件。
    echo.
    pause
    exit /b 1
)

:: 显示编译后的大小（允许任意大小，只需 >= 512 字节）
for %%A in ("MiniWin.bin") do set "bin_size=%%~zA"
if !bin_size! LSS 512 (
    echo [警告] MiniWin.bin 只有 !bin_size! 字节，可能不是有效的引导镜像！
    echo        请确认 MiniWin.asm 包含完整的多阶段引导代码。
    echo.
    set /p continue="是否继续？[Y/N]: "
    if /i not "!continue!"=="Y" (
        echo 操作已取消。
        pause
        exit /b 1
    )
) else (
    echo [成功] 编译完成！文件大小: !bin_size! 字节
)
echo.
exit /b 0

:: ============================================================
::  子过程: 创建硬盘镜像 (16MB)
:: ============================================================
:create_hd_image
echo [2/3] 正在创建 16MB 可读写硬盘镜像...

:: 如果 hd.img 已存在，询问是否保留
if exist "hd.img" (
    echo [信息] hd.img 已存在 (包含之前保存的数据)
    set /p keep="保留已有数据？[Y/N]: "
    if /i "!keep!"=="Y" (
        echo [信息] 保留已有硬盘镜像
        exit /b 0
    )
    :: 用户选择不保留，删除旧文件
    del /f /q "hd.img" 2>nul
)

:: ========================================
::  方式1：qemu-img (最可靠，QEMU 官方工具)
:: ========================================
qemu-img create -f raw hd.img 16M >nul 2>&1
if not errorlevel 1 (
    echo [成功] 使用 qemu-img 创建硬盘镜像完成！
    goto :write_boot_sector
)

:: ========================================
::  方式2：dd (Git Bash / Cygwin / MSYS2)
:: ========================================
echo [信息] qemu-img 不可用，尝试 dd...
dd if=/dev/zero of=hd.img bs=512 count=32768 2>nul
if not errorlevel 1 (
    echo [成功] 使用 dd 创建硬盘镜像完成！
    goto :write_boot_sector
)

:: ========================================
::  方式3：fsutil (Windows 原生)
:: ========================================
echo [信息] dd 不可用，使用 fsutil...
fsutil file createnew hd.img 16777216 >nul 2>&1
if errorlevel 1 (
    echo [错误] 所有创建方式均失败！
    echo        请安装 QEMU (包含 qemu-img) 或 dd
    exit /b 1
)
echo [成功] 使用 fsutil 创建硬盘镜像完成！
goto :write_boot_sector_fsutil

:: ============================================================
::  子过程: 写入完整 MiniWin.bin 到硬盘镜像 (适用于 qemu-img 和 dd)
::  修改：写入完整文件，而非仅 512 字节
:: ============================================================
:write_boot_sector
echo [信息] 正在写入完整的 MiniWin.bin 到硬盘镜像...

:: 获取 MiniWin.bin 大小
for %%A in ("MiniWin.bin") do set "bin_size=%%~zA"
set /a "sectors=!bin_size! / 512"
if !sectors! equ 0 set sectors=1
echo [信息] 将写入 !sectors! 个扇区 (!bin_size! 字节)

:: 优先使用 dd 写入完整文件
dd if=MiniWin.bin of=hd.img bs=512 conv=notrunc 2>nul
if not errorlevel 1 (
    echo [成功] 使用 dd 写入完整镜像完成！
    exit /b 0
)

:: dd 写入失败，尝试 dd 分块写入 (先写引导扇区，再写剩余部分)
echo [信息] 尝试分块写入...
dd if=MiniWin.bin of=hd.img bs=512 count=1 conv=notrunc 2>nul
if not errorlevel 1 (
    dd if=MiniWin.bin of=hd.img bs=512 skip=1 seek=1 conv=notrunc 2>nul
    if not errorlevel 1 (
        echo [成功] 使用 dd 分块写入完成！
        exit /b 0
    )
)

:: dd 失败，尝试 PowerShell (写入完整文件)
echo [信息] dd 写入失败，尝试 PowerShell...
powershell -command "$bytes=[IO.File]::ReadAllBytes('MiniWin.bin'); $fs=[IO.File]::Open('hd.img','Open','Write'); $fs.SetLength($bytes.Length); $fs.Write($bytes,0,$bytes.Length); $fs.Close()" 2>nul
if not errorlevel 1 (
    echo [成功] 使用 PowerShell 写入完整镜像完成！
    exit /b 0
)

echo [错误] 所有写入方式均失败！
echo        请手动将 MiniWin.bin 写入 hd.img
echo        可以使用: dd if=MiniWin.bin of=hd.img bs=512 conv=notrunc
exit /b 1

:: ============================================================
::  子过程: 写入完整 MiniWin.bin 到硬盘镜像 (适用于 fsutil)
::  修改：写入完整文件，而非仅 512 字节
:: ============================================================
:write_boot_sector_fsutil
echo [信息] 正在写入完整的 MiniWin.bin 到硬盘镜像...

:: 使用 PowerShell 写入完整文件 (最可靠)
powershell -command "$bytes=[IO.File]::ReadAllBytes('MiniWin.bin'); $fs=[IO.File]::Open('hd.img','Open','Write'); $fs.SetLength($bytes.Length); $fs.Write($bytes,0,$bytes.Length); $fs.Close()" 2>nul
if not errorlevel 1 (
    echo [成功] 使用 PowerShell 写入完整镜像完成！
    exit /b 0
)

:: PowerShell 失败，尝试 copy /b (简单拼接)
echo [信息] PowerShell 失败，尝试 copy /b...
copy /b "MiniWin.bin" "hd.img" >nul 2>&1
if not errorlevel 1 (
    echo [成功] 使用 copy 命令写入完整镜像完成！
    exit /b 0
)

echo [错误] 写入完整镜像失败！
echo        请手动将 MiniWin.bin 写入 hd.img
exit /b 1

:: ============================================================
::  子过程: 获取文件大小
:: ============================================================
:getsize
if not exist "%~1" exit /b 0
echo        文件大小: %~z1 字节
exit /b 0

:: ============================================================
::  子过程: 启动 QEMU (硬盘模式，可读写)
:: ============================================================
:run_hd
if not exist "hd.img" (
    echo [错误] hd.img 不存在，请先创建硬盘镜像！
    echo.
    pause
    exit /b 1
)
echo [3/3] 正在启动 QEMU 虚拟机 (硬盘模式)...
echo.
echo 提示: 鼠标被捕获时按 Ctrl+Alt 释放
echo       在 QEMU monitor 输入 quit 退出
echo.
qemu-system-x86_64 -drive file=hd.img,format=raw,if=ide,cache=unsafe -m 128 -vga std -cpu qemu64 -machine pc -monitor stdio
exit /b 0

:: ============================================================
::  子过程: 启动 QEMU (标准模式，仅内存)
:: ============================================================
:run_mem
if not exist "MiniWin.bin" (
    echo [错误] MiniWin.bin 不存在，请先编译！
    echo.
    pause
    exit /b 1
)
echo [2/2] 正在启动 QEMU 虚拟机 (内存模式)...
echo 提示: 点击窗口捕获鼠标，按 Ctrl+Alt 释放鼠标
echo.
qemu-system-x86_64 -drive format=raw,file="MiniWin.bin",if=floppy -m 128 -vga std -cpu qemu64 -machine pc
exit /b 0

:: ============================================================
::  子过程: 启动 QEMU (带 USB 鼠标，仅内存)
:: ============================================================
:run_usb
if not exist "MiniWin.bin" (
    echo [错误] MiniWin.bin 不存在，请先编译！
    echo.
    pause
    exit /b 1
)
echo [2/2] 正在启动 QEMU 虚拟机 (带 USB 鼠标，内存模式)...
echo 提示: USB 鼠标可能比 PS/2 鼠标更流畅
echo.
qemu-system-x86_64 -drive format=raw,file="MiniWin.bin",if=floppy -m 128 -vga std -cpu qemu64 -machine pc -usb -device usb-mouse
exit /b 0