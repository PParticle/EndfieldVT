# EndfieldVT

[![Windows CI and Release](https://github.com/PParticle/EndfieldVT/actions/workflows/release.yml/badge.svg)](https://github.com/PParticle/EndfieldVT/actions/workflows/release.yml)

EndfieldVT 是《明日方舟：终末地》的自定义界面工具。你可以做出图标、进度条、文字和 Buff 列表，让它们按照游戏里的 Buff、技力、连携技冷却、HP、失衡等数据显示和变化，再叠加到游戏画面上。

EndfieldVT 是一个独立程序，不修改游戏，也不往游戏里注入任何东西。游戏数据来自 [EndfieldDataBridge](https://github.com/PParticle/EndfieldDataBridge) 插件写出的只读共享内存。

## 功能

- **可视化编辑器**：所有设置都在界面里完成，不用写代码；在 1280×720 的预览画布上直接拖动摆放控件，实时看到效果。
- **四种控件**：
  - 图标：方形、圆形、三角、六边形，可旋转，带冷却转圈和扩散动画。
  - 进度条：长条或圆环，支持分段、圆头、平滑过渡和扣血残影。
  - 文本：静态文字、实时数值，或带占位符的模板，例如 `{技力} / {上限}`、`剩余 {剩余:mm:ss}`。
  - Buff 列表：某个单位身上的全部 Buff，新获得的排在后面，结束的自动补位。
- **触发器**：按 Buff / Debuff（是否存在、层数、剩余时间）、技力、终结技、连携技冷却、HP、失衡、锁定目标、战斗状态、技能释放来决定控件何时显示、显示什么。多个条件可以取「全部满足」或「任一满足」。
- **满足时样式**：条件满足时变色、改透明度、发光（外发光、流光、像素边框），或播放循环动画（脉冲、呼吸、闪烁、抖动、旋转）。例如 Buff 剩 3 秒时变红，连携技就绪时发光。
- **出现与消失动画**：淡入淡出、滑动、弹出缩回。
- **队伍成员 ×4**：一个控件自动展开成 4 份，分别对应 1–4 号位，共用外观和触发器。
- **组**：整体移动、缩放、调整透明度；组的触发器作用于所有成员。
- **多份配置**：程序目录里的每个配置文件（`.json`）都能在标题栏里切换，所有修改自动保存。
- **调试页**：查看 EndfieldDataBridge 当前提供的全部数据和事件，方便确认触发器为什么亮或不亮。

## 下载

在 [Releases](https://github.com/PParticle/EndfieldVT/releases) 下载最新的 `EndfieldVT.exe`。它是单个文件，自带 Qt 和运行库，不用安装。

需要：

- Windows 10 / 11 x64。
- 游戏里装好 [EndfieldDataBridge](https://github.com/PParticle/EndfieldDataBridge) 和它的前置插件管理器 [Applepie Manager](https://github.com/zonemodAE/ApplepieManager)，安装方法见各自的说明。

## 快速开始

1. 把 `EndfieldVT.exe` 放进一个单独的文件夹。配置文件 `default.json` 会保存在同一个文件夹里。
2. 启动游戏，再启动 EndfieldVT。启动顺序不限，Bridge 连上后右下角的状态栏会显示「Bridge 已连接」。
3. 点击标题栏的「新建」，选一种控件。
4. 在「触发器」页设置条件。例如：类型选「连携技」，状态选「冷却中」，效果选「顺时针填充」。
5. 在「外观」页调整形状、颜色、大小。点击「预览与编辑」打开 1280×720 的预览窗口，拖动摆放位置。
6. 标题栏的「游戏内显示」默认开启，控件会叠加在游戏画面上；再点一次可以关掉。

游戏内的覆盖层是一个透明窗口，跟随游戏窗口的位置和大小，鼠标点击会穿透到游戏。

## 从源码构建

环境：

- Windows x64，Visual Studio 2022 C++ 生成工具（x64 MSVC 和 Windows SDK）。
- [Qt 6.12](https://www.qt.io/download-qt-installer) MSVC 2022 64 位版，包含 Qt Quick。
- [EndfieldDataBridge](https://github.com/PParticle/EndfieldDataBridge) 的源码，放在本仓库旁边：

```text
src/
├── EndfieldDataBridge/
└── EndfieldVT/
```

在 EndfieldVT 目录下运行：

```powershell
build.bat
```

脚本会用 `vswhere` 找到生成工具并初始化 x64 MSVC 环境，再用 `windeployqt` 把 Qt 的运行文件复制到 `bin\`。Qt 默认从 `D:\QT\6.12.0\msvc2022_64` 查找，装在别处时先设置 `QT_DIR`：

```powershell
set QT_DIR=C:\Qt\6.12.0\msvc2022_64
build.bat
```

这样编出来的 `bin\` 是动态链接版，适合开发调试。Releases 里的单文件版由 [GitHub Actions](.github/workflows/release.yml) 构建：先从源码编译一份静态 Qt（只含 qtbase、qtshadertools、qtdeclarative），再把 EndfieldVT 静态链接成一个 exe。版本号写在 `src/version.rc`，发布标签 `v*` 必须和它一致。

## 问题反馈

遇到问题、发现 bug，或者有功能建议，请到 [Issues](https://github.com/PParticle/EndfieldVT/issues) 提出。反馈时最好附上：

- EndfieldVT 和 EndfieldDataBridge 的版本号（都在文件属性的「详细信息」里：`EndfieldVT.exe`、`EndfieldDataBridge.dll`）。
- 出问题的控件设置。可以把配置文件 `.json` 一起附上。
- 当时调试页里显示的相关数据。

开发进度和待办事项见 [docs/TODO.md](docs/TODO.md)。

## 许可

本项目使用 [AGPL-3.0](LICENSE) 许可证。发布版静态链接了 [Qt](https://www.qt.io/) 的开源版（LGPL-3.0）；完整源码就在本仓库，可以按上面的步骤自行编译。

## 致谢

- [WeakAuras](https://github.com/WeakAuras/WeakAuras2)：《魔兽世界》的界面插件。EndfieldVT 的控件、触发器、条件样式和动画这一套设计思路都参考了它。
- [EndfieldDataBridge](https://github.com/PParticle/EndfieldDataBridge)：提供全部游戏数据。
- [Applepie Manager](https://github.com/zonemodAE/ApplepieManager)：EndfieldDataBridge 所依赖的插件管理器。
- [Qt](https://www.qt.io/)：界面框架。
