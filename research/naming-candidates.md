# 命名候选的公开记录与命令冲突

核查日期：2026-11-19，Asia/Shanghai（UTC+08:00）。外部项目检索始于约 06:10；包记录与本机枚举的时间逐项列出。
范围：Windows 注册表搜索、查看 CLI，未来可能编辑；只记录事实，展示名、可执行命令名和 Cargo 包名由用户选择。

## 读表规则

- 包查询使用未经认证的 crates.io 第一方精确 API，不以搜索引擎结果推断包名状态。
- HTTP 404 仅表示该时间未找到公开记录；不证明能够发布，也不构成预留。发布前必须复核。
- “命令重名”表示项目自身资料明确使用该入口；不表示其已安装在本机，也不自动等于注册表工具同领域。
- “未证实”表示本次有限检索没有取得正面证据，不是全网、所有版本或所有环境无冲突的保证。

## Reglet / reglet / reglet

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`reglet` API](https://crates.io/api/v1/crates/reglet)：HTTP 404，06:10:22（2026-11-18 22:10:22 UTC）。 |
| 命令 `reglet` | **明确重名**：[reglet-dev/reglet](https://github.com/reglet-dev/reglet) 是合规与基础设施验证 CLI；README 使用 `reglet check`，并明确列出 Windows 的 `reglet.exe`。 |
| 领域 | 该项目是系统合规验证工具；本次没有证实它是 Windows 注册表搜索/编辑器。 |
| 边界 | crate 404 并不能消除已有展示名与 Windows 可执行命令重名；改成 `reglet-cli` 包名也不会改变该事实。 |

## Regrove / rgv 或 regrove / regrove

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`regrove` API](https://crates.io/api/v1/crates/regrove)：HTTP 404，06:10:23（22:10:23 UTC）。 |
| 原始命令 `rgv` | **明确重名**：[lilydjwg/search-and-view](https://github.com/lilydjwg/search-and-view) 把 `rgg` / `rgv` 定义为 ripgrep 包装器；`rgv N` 打开对应结果。 |
| 完整命令 `regrove` | 本次未证实已有同名 CLI；本机两种无 profile PowerShell 均未见，详见下表。 |
| 展示名重名 | [cocopuff2u-gaming/regrove](https://github.com/cocopuff2u-gaming/regrove) 是 Valheim 的服务器端 BepInEx 森林再生 mod，属于异领域项目。 |
| GitHub 补充 | [公开搜索 API](https://api.github.com/search/repositories?q=regrove%20in%3Aname&per_page=100) 在 06:13:53 返回 3 个名称匹配结果，其中精确同名有上述 mod 及 [CeeJank/Regrove](https://github.com/CeeJank/Regrove)；后者无描述，功能未核实。 |

## Reglens / rgl 或 reglens / reglens

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`reglens` API](https://crates.io/api/v1/crates/reglens)：HTTP 404，06:10:24（22:10:24 UTC）。 |
| 原始命令 `rgl` | **明确重名**：[juniorxsound/headless-three-webgpu](https://github.com/juniorxsound/headless-three-webgpu) 的 README 使用 `rgl render`、`rgl inspect` 等渲染 CLI 调用。 |
| 完整命令 `reglens` | 本次未证实独立发布的同名 CLI；本机无 profile 枚举未见。下述同名 macOS 应用仍会造成搜索结果重叠。 |
| 展示名重名 | [aalemoro/RegLens](https://github.com/aalemoro/RegLens) 是通过 SEC EDGAR 分析公司监管足迹的 macOS 应用；[reglens.tech](https://reglens.tech/) 自述为监管合规监控产品。均非本次已证实的 Windows 注册表工具。 |

## Regard / rgd 或 regard / regard

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`regard` API](https://crates.io/api/v1/crates/regard)：HTTP 404，06:10:25（22:10:25 UTC）。 |
| 原始命令 `rgd` | **明确 Windows 命令重名**：AMD 的 [Radeon GPU Detective 资料](https://gpuopen.com/download/GDC2024_Radeon_GPU_Detective.pdf#page=39) 第 39 页明确写出 `rgd.exe` 是命令行应用；[项目自身仓库](https://github.com/GPUOpen-Tools/radeon_gpu_detective) 描述其处理 GPU 崩溃转储。 |
| 完整命令 `regard` | **明确重名**：[AmineZouitine/regard.rs](https://github.com/AmineZouitine/regard.rs) 是 Rust/React 时间跟踪工具，README 明示 `regard display` 与 `regard --help`。 |
| 领域 | 上述项目分别属于 GPU 崩溃分析和时间跟踪；并未证实为 Windows 注册表工具。 |

## Regent / rgt / regent

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`regent` API](https://crates.io/api/v1/crates/regent)：**HTTP 200**，06:10:26（22:10:26 UTC）；`name=regent`、`max_version=0.3.0`，描述是已弃用的 Rust bitfields 包，建议使用 bilge。 |
| 包名补查 | [`regent-cli` API](https://crates.io/api/v1/crates/regent-cli)：HTTP 404，06:12:16（22:12:16 UTC）。这个结果不会释放 `regent`，也不会消除项目与命令重名。 |
| 命令 `rgt` | **明确重名**：[regent-vcs/re_gent](https://github.com/regent-vcs/re_gent) 的 README 指明安装后得到 `rgt`，示例包括 `rgt init`、`rgt log`。 |
| 展示名补充 | [Regent33/Regent](https://github.com/Regent33/Regent) 是个人 AI 助手，其 README 也使用完整命令 `regent`，并有 Windows 安装说明。 |

## Hivis / hivis / hivis

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`hivis` API](https://crates.io/api/v1/crates/hivis)：HTTP 404，06:10:28（22:10:28 UTC）。 |
| 命令 `hivis` | 本次未证实已有同名 CLI；本机无 profile 枚举未见。 |
| 展示名重名 | [roynov01/HiVis](https://github.com/roynov01/HiVis) 是空间转录组（Spatial Transcriptomics）数据分析 Python 工具；[OliverColeman/hivis](https://github.com/OliverColeman/hivis) 是数据处理与可视化 Java 库。 |
| 领域 | 两者均为异领域项目；Python 包/Java 库名称本身不能证明存在同名可执行命令。 |

## Reglo / reglo / reglo

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`reglo` API](https://crates.io/api/v1/crates/reglo)：HTTP 404，06:13:17（22:13:17 UTC）。 |
| 命令 `reglo` | 本次未证实已有同名 CLI 或 Windows 注册表工具；本机无 profile 枚举未见。 |
| 展示名重名 | [sebsan/Reglo](https://github.com/sebsan/Reglo) 是字体；[BU-DEPEND-Lab/REGLO](https://github.com/BU-DEPEND-Lab/REGLO) 是神经网络修复（Neural Network Repair）研究代码。 |
| Windows 应用重名 | [Basta 官方 Reglo 页面](https://basta.com/reglo) 将 Reglo 3.5a 列为 Windows 桌面标尺，并称已由 CaptureStuff 替代。确认旧 Windows 应用同名，未证实同名 CLI；它不是注册表工具。 |
| GitHub 边界 | [公开搜索 API](https://api.github.com/search/repositories?q=reglo%20in%3Aname&per_page=100) 在 06:13:58 返回总数 603；只检查了首 100 项中的精确同名及明显结果，未穷尽全部仓库。 |

## Regma / regma / regma

| 项目 | 核查结果 |
| --- | --- |
| Cargo 包 | [`regma` API](https://crates.io/api/v1/crates/regma)：HTTP 404，06:13:18（22:13:18 UTC）。 |
| 命令 `regma` | 本次未证实已有同名 CLI 或 Windows 注册表工具；本机无 profile 枚举未见。 |
| 展示名重名 | [PoloB/regma](https://github.com/PoloB/regma) 是字符串模板 Python 库；其维护者发布的 [PyPI 项目说明](https://pypi.org/project/regma/)也将其描述为模型式字符串格式化与解析。 |
| GitHub 边界 | [公开搜索 API](https://api.github.com/search/repositories?q=regma%20in%3Aname&per_page=100) 在 06:14:03 返回总数 283；只检查了首 100 项中的精确同名及明显结果，未穷尽全部仓库。 |

## 本机命令与 PowerShell 默认别名

所有时间仍为 2026-11-19 CST。分别启动 `powershell.exe` 与 `pwsh.exe`，使用 `-NoLogo -NoProfile -NonInteractive`；只执行命令/别名枚举，没有执行任何候选程序。

| 无 profile 进程 | 检查时间 | 检查名称 | `Get-Command -All` | `Get-Alias` |
| --- | --- | --- | --- | --- |
| Windows PowerShell 5.1.26100.9818，Desktop | 06:11:15 | `reglet,rgv,rgl,rgd,rgt,hivis` | 0 匹配 | 0 匹配 |
| PowerShell 7.7.0，Core | 06:12:34 | 同上 | 0 匹配 | 0 匹配 |
| Windows PowerShell 5.1.26100.9818，Desktop | 06:14:25 | `regrove,reglens,regard,reglo,regma` | 0 匹配 | 0 匹配 |
| PowerShell 7.7.0，Core | 06:14:25 | 同上 | 0 匹配 | 0 匹配 |

枚举主体如下；实际分成上表两组分别运行，并输出进程版本与 UTC 时间。`Get-Command` 返回元数据，不调用目标。

```powershell
$candidateNames = 'reglet','rgv','rgl','rgd','rgt','hivis','regrove','reglens','regard','reglo','regma'
Get-Command -Name $candidateNames -All -ErrorAction SilentlyContinue |
    Select-Object Name,CommandType,Source,Definition
Get-Alias -Name $candidateNames -ErrorAction SilentlyContinue |
    Select-Object Name,Definition
```

Microsoft 的 [about_Aliases](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_aliases?view=powershell-7.5#built-in-aliases) 说明 `Get-Alias` 枚举内建及会话别名；[PowerShell v7.5.4 默认别名源码](https://github.com/PowerShell/PowerShell/blob/v7.5.4/src/System.Management.Automation/engine/InitialSessionState.cs#L4314) 包括 `r`、`ri`、`rp`、`rv` 等，未包含本报告候选。该源码版本是补充核对，不替代实际 5.1 / 7.7 会话结果。

Microsoft 的 [命令优先级](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_command_precedence?view=powershell-7.5) 是别名、函数、cmdlet、外部程序；`-All` 用来查看同名命令。其 [大小写说明](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_case-sensitivity?view=powershell-7.5) 明确 PowerShell 命令和别名查找不区分大小写，Windows 大多数操作也不区分大小写，因此变更展示名大小写不能视作消除冲突。

Windows 已有的注册表命令是 Microsoft 文档中的 [`reg`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg)；本报告候选均不是这个精确名称。本机零匹配只覆盖当时进程的命令发现范围、PATH 和会话，不能推广到用户安装其他工具/模块、自定义 profile 或未来环境。

## Cargo 命名限制与证据边界

[Cargo 官方索引说明](https://doc.rust-lang.org/cargo/reference/registry-index.html#name-restrictions) 列出 crates.io 规则：ASCII 字母数字、`-`、`_`，首字符为字母，最长 64 字符；重名检测不区分大小写，并将 `-` / `_` 差异视为冲突，且拒绝保留名称。八个小写候选都满足表面字符/长度条件，但仅凭此不能证明服务器会接受发布。

- 本次唯一确认已有公开 crate 记录的是 `regent`；弃用描述不意味着名称可重新使用。
- `regent-cli` 与 `regent_cli` 不能被视为两个独立可占用名称；加后缀也不改变既有展示名或可执行命令的冲突。
- GitHub 仓库按所有者区分；异所有者的同名仓库已经在本次第一方 API 中出现，不能把单个同名仓库视为全站独占包名。
- 公开检索结合候选精确拼写、CLI、GitHub、Windows/registry 关键词，再回到项目自身 README/文档。没有证实八者的同名 Windows 注册表专用工具；这只是本次检索结果。
- 搜索引擎与 GitHub 搜索均可能不完整；没有覆盖私有项目、所有软件包生态、域名或商标，不作全球唯一或法律结论。
- 初始受限网络请求未连通，未把连接错误记成 404；上表 API 状态来自成功联网的第一方 HTTP 请求。网页搜索服务不能访问 crates.io API 时，改用直接只读 HTTP 核查。
- 没有注册/发布 crate、占名、安装或运行候选程序、读取凭据、修改远程仓库名称，也没有据此作出最终命名决定。
