# MiniWin 操作系统

一个纯汇编语言编写的单文件微型操作系统，适合操作系统原理学习与汇编语言实战练习。

---

## 📁 项目文件说明

| 文件 | 说明 |
|------|------|
| `MiniWin.asm` | 纯汇编语言编写的单文件微型操作系统内核，由 B站UP主 **TnRSYWlzZUhhcmRF** 开发 |
| `一键启动.bat` | 多功能自动化构建脚本，由 **SimpleTools工作室** 提供，集编译、镜像生成、启动、清理于一体 |

---

## 🚀 快速开始

### 1. 安装依赖

在运行脚本之前，请确保以下工具已安装并配置好环境变量：

| 依赖工具 | 用途 | 获取方式 |
|----------|------|----------|
| **NASM** | 汇编编译器 | https://www.nasm.us/pub/nasm/releasebuilds/ |
| **QEMU** | 系统模拟器 | https://www.qemu.org/download/ |

> 💡 **提示**：安装后可在命令行运行 `nasm -version` 和 `qemu-system-i386 -version` 验证是否配置成功。

### 2. 运行脚本

双击 `一键启动.bat`，根据菜单提示选择操作：

| 选项 | 功能 |
|------|------|
| `1` | 编译 `MiniWin.asm` 并生成硬盘镜像 `hd.img` |
| `2` | 启动 `MiniWin.bin` 或 `hd.img`（在 QEMU 中运行） |
| `3` | 清理所有编译产物和镜像文件 |
| `4` | 检查开发依赖环境是否完整 |

### 3. 运行系统

选择启动后，QEMU 将模拟 x86 环境并引导 MiniWin 操作系统。

---

## 🧹 清理文件清单

脚本会自动清理以下编译产物：
MiniWin.bin MiniWin.lst MiniWin.map
MiniWin.sym MiniWin.err MiniWin.hex
hd.img floppy.img

---

## 🛠️ 常见问题

### Q：双击脚本后提示"nasm 不是内部或外部命令"
**A**：请安装 NASM 并确保其安装路径已添加到系统 `PATH` 环境变量中。

### Q：QEMU 启动后黑屏或无反应
**A**：请检查 QEMU 是否正确安装，或尝试以管理员权限运行脚本。

### Q：脚本运行中途报错
**A**：请先选择 `4` 检查依赖环境，确保所有工具可用后再尝试编译。

---

## 🙏 致谢

- **原作者**：B站UP主 [TnRSYWlzZUhhcmRF](https://space.bilibili.com/42488829?spm_id_from=333.337.0.0)，感谢其分享的汇编操作系统实现
- **脚本工具**：由 **SimpleTools工作室** 提供自动化构建支持

---

## 🔗 相关链接

- **SimpleTools工作室 GitHub**：[20260509](https://github.com/20260509)
- **SimpleTools工作室 官方网站**：[SimpleTools.cc](https://SimpleTools.cc)

---

## 📄 许可证

本项目采用 **MIT 许可证**。

- `MiniWin.asm` 由 B站UP主 [TnRSYWlzZUhhcmRF](https://space.bilibili.com/42488829) 开发，已获原作者 MIT 授权
- `一键启动.bat` 及其他脚本由 **SimpleTools工作室** 开发，采用 MIT 许可证

---

## 📸 运行截图

![运行截图](./screenshot.png)
