# EndfieldVT

《Arknights: Endfield》自定义信息覆盖层

## 用户协议与免责声明

本项目为非官方项目，不代表鹰角网络。项目的公开、开源或发布不代表获得游戏官方的授权、认可或安全保证。游戏名称、商标及相关内容的权利归其各自权利人所有。

EndfieldVT 独立运行，以只读方式读取 EndfieldDataBridge 发布的共享内存数据并显示覆盖层。实时数据由前置插件 EndfieldDataBridge 采集，利用 IL2CPP 元数据定位游戏对象并读取战斗状态。因此，使用本程序的实时游戏数据功能仍依赖游戏进程内的第三方插件。

使用前请阅读并遵守[《鹰角网络游戏使用许可及服务协议》](https://user.hypergryph.com/protocol/plain/endfield/service)及适用规则。**使用本程序及其前置插件可能导致账号限制、封禁或其他处理；本项目不保证符合游戏协议，也不保证不会被检测或处罚。** 请在确认适用法律及相关授权允许后再使用；如无法确认或无法承担风险，请勿使用。

软件按现状提供，显示的数据可能延迟、缺失或不准确；软件及其前置插件也可能因缺陷、游戏更新或兼容性问题导致崩溃或其他损失。作者及贡献者在适用法律允许的范围内不提供担保，责任限制见 [LICENSE](LICENSE)。本声明不免除依法不得免除的责任；项目的开源许可证不授予游戏软件、游戏内容或游戏服务的使用授权。

## 下载与运行

需要前置插件 [EndfieldDataBridge](https://github.com/PParticle/EndfieldDataBridge)。

1. 从 [Releases](https://github.com/PParticle/EndfieldVT/releases) 下载。
2. 启动游戏并加载 EndfieldDataBridge，运行 EndfieldVT。

## 控件与触发器


| 控件      | 用途与设置                                                                       |
| --------- | -------------------------------------------------------------------------------- |
| 图标      | 方形、圆形、三角形或六边形；支持顺逆时针填充、中心扩散，以及剩余时间和层数显示。 |
| 进度条    | 矩形条或圆环；支持自定义数值范围、分段、平滑过渡和消耗残影。                     |
| 文本      | 静态文字、动态数值或多数据源模板；可设置字号、描边、对齐和无数据时的处理方式。   |
| Buff 列表 | 展示指定目标的 Buff/Debuff；可按类型、来源和 ID 黑白名单过滤，并自动排列、补位。 |

### 条件、显示与样式

触发条件包括 Buff/Debuff、技力、终结技、连携技、生命值、失衡、锁定目标、战斗状态和技能释放，也可以设为「始终满足」。监控目标随条件类型选择，例如主控干员、指定队伍位置或锁定目标。

- **显示模式**决定控件始终显示、仅在触发器满足时显示，还是始终隐藏。
- **每个触发器**可以包含多个条件，按「全部满足 (AND)」或「任一满足 (OR)」判断。进度与数值取自该触发器的第一个条件。
- **多个触发器**按顺序执行：图标采用首个满足且设有效果的触发器；进度条采用首个满足且启用「给出进度」的触发器。满足条件的样式会叠加，同一属性以后面的设置为准。

例如，监控 Buff 剩余时间时，可以在条件中选择「Buff/Debuff」，填写 Buff ID，再设置「存在」且「剩余时间 ≤ 3 s」，在「满足时样式」中设置变色或发光。Buff ID 可通过「从当前 Buff 选择」获取，也可在「调试」页查找。

样式支持颜色、透明度、发光和循环动画；控件还可设置淡入淡出、滑动、缩放等出现与消失动画。文本和 Buff 列表的内容单独设置，触发器控制其显示与样式。

### 动态文本

在文本的「内容」页选择「模板 (占位符)」，先配置动态数据源，再填写模板：


| 数据源      | 模板示例                         |
| ----------- | -------------------------------- |
| 技力        | `{技力} / {上限}`                |
| 生命值      | `HP {数值} / {上限} ({百分比})`  |
| Buff/Debuff | `剩余 {剩余:mm:ss} · {层数} 层` |

占位符默认读取数据源 1；添加更多数据源后，用 `{数值2}`、`{上限2}` 等引用对应编号。`{技力}`、`{HP}` 等是数值字段的别名，实际读取哪类数据仍由所选数据源决定。缺少数据时，可以隐藏整个文本或显示回退文本。

### 组与队伍展开

- **组**：新建组后，将左侧列表中的控件拖入组内，即可整体移动、缩放和调整透明度。组触发器可控制整组显示，成员仍保留各自的触发器和样式。
- **队伍成员 ×4**：在支持的监控目标中选择此项，一个控件会按队伍 1–4 号位展开为四份，共享外观和触发逻辑；可设置展开方向与间距，空位不显示。

## 配置与分享

配置保存在 `EndfieldVT.exe` 所在目录，默认使用 `default.json`。标题栏的「配置」菜单可以切换配置、新建空配置、复制当前配置或打开配置文件夹。`EndfieldVT.ini` 记录上次使用的配置。

分享时复制对应的 `.json` 文件即可。将收到的配置放入程序目录，再打开「配置」菜单选择它；菜单会识别包含 `controls` 数组的配置文件。备份或更新程序时保留这些文件；手动修改当前配置前先退出程序，避免被自动保存覆盖。

## 从源码构建

需要 Windows x64、Visual Studio 2022 C++ 生成工具（MSVC x64 与 Windows SDK）、Qt 的 MSVC 2022 64 位套件（含 Qt Quick）、CMake 3.21+ 和 Ninja。CMake 要求 Qt 6.8+；当前构建脚本和 CI 使用 Qt 6.12.0。

构建时需要 EndfieldDataBridge 的公开头文件，默认目录结构为：

```text
workspace/
├── EndfieldDataBridge/
│   └── include/
└── EndfieldVT/
```

在 Shell 中运行：

```powershell
build.bat
```

脚本自动查找 MSVC，使用 CMake/Ninja 构建，并通过 `windeployqt` 将 Qt 依赖部署到 `bin\`。此方式生成动态链接版，运行时需保留 `bin\` 中的依赖文件；脚本不部署 MSVC 运行库。

手动配置 CMake 时，可用 `-DEFB_INCLUDE_DIR=路径` 指定 Bridge 的 `include` 目录。发布版的静态 Qt 和单文件打包流程见 [GitHub Actions](.github/workflows/release.yml)。

## Acknowledgements

This project is licensed under the [AGPL-3.0](LICENSE) license.

Special thanks to [WeakAuras](https://github.com/WeakAuras/WeakAuras2) for its design inspiration, [EndfieldDataBridge](https://github.com/PParticle/EndfieldDataBridge) for providing game data, [Applepie Manager](https://github.com/zonemodAE/ApplepieManager) for plugin loading support,，and [Qt](https://www.qt.io/) for the UI framework.
