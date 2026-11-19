# RegQry 基建工具链、依赖图与 Windows 验证能力

研究日期：2026-11-19。研究分支基线为 `main` 的 `34e02fa1a021689a61c059172737a53994180d1e`。本报告供基建工单决策使用；依赖选型及支持矩阵来自已解决的「选择注册表适配方案与模块边界」（06）与「确定平台支持矩阵与分发约定」（07），帮助体验对齐「验证查询命令与默认结果的终端体验」（08）的已评审原型。研究期间用户已选择只维护一个固定 Rust 版本、声明要求与之对齐，不另设旧版最低支持 Rust 版本（Minimum Supported Rust Version，MSRV）测试线；下文 1.85 是依赖图事实，不是要求增加测试线。精确固定版本仍待主对话确认。

证据标记：**事实**指官方文档或已发布归档源码；**观察**指本次下载、哈希或元数据探针；**推断 / 候选**指由事实得到的工程后果；**未验证**不构成支持保证。没有实现产品、修改工作流、调用任何注册表 API、运行上游注册表测试、读取凭据或查询账号私有状态。

## 1. 直接影响决策的事实

- 选定的 `clap` 4.6.8、实际依赖 `clap_builder` 4.6.7，均声明 **edition 2024 / Rust 1.85**。项目采用 edition 2021 也不能降低这些依赖的下限；Rust 2024 在 1.85.0 稳定。保留已评审 80 列帮助的 `wrap_help` 候选在两个 Windows 目标均有 27 个外部活动包，未发现更高的**已声明**下限；尚未用 1.85 实际编译。[clap 发布包][p-clap]、[builder 发布包][p-builder]、[Rust 1.85 发布公告][rust-185]
- 官方 stable 发布清单本次返回 **1.100.0，2026-11-12**；本机默认 `rustc / cargo 1.99.1` 是本地观察，不是项目版本决定。Cargo **1.100 起** `install` 默认使用包内锁文件；此前版本默认重新解析，需 `--locked`。不能把这两代 Cargo 的行为混写。[stable 清单][rust-channel]、[1.100.0 发布说明][rust-1100]、[当前 install 文档][cargo-install]
- `cargo-deny` 0.21.0 发布包声明 **Rust 1.89 / edition 2024**；它与产品依赖的最低要求不同。若固定 1.100.0，当前这些声明均低于该版本，无须据此拆分编译器。工具仍需独立固定版本，未来升级也不能默认沿用旧要求。候选测试库 `proptest` 1.12.0 声明 1.88。[deny 发布包][p-deny]、[proptest 发布包][p-proptest]
- 当前 GitHub 原生 ARM64 标签是 `windows-11-arm` / `windows-11-vs2026-arm`；映像清单为 **Windows 11 build 26200（25H2）**。它不能证明 ARM64 最低 **24H2 / build 26100**。原生 x64 托管映像是 Windows **Server**，不能替代已承诺的 Windows 10 22H2 / Windows 11 客户端验收。[runner 标签][gh-runners]、[ARM64 清单][gh-arm-image]、[Windows 版本表][ms-win11]
- 普通 `HKCU\Software` 测试键是共享区域；用两种 WOW64 flag 打开它，不能证明两视图隔离。微软明确将 `HKCU\Software\Classes\CLSID` 列为重定向区域，可在一次性环境中为随机 GUID 准备两份不同 sentinel；实际 x64 / ARM64 映射仍须分别验证。[WOW64 官方表][ms-shared]

## 2. 精确依赖版本与候选 features

### 2.1 已发布 manifest

**观察：** 使用空的、位于本研究工作树内的 `CARGO_HOME` 从公开 crates.io 索引解析并下载生产依赖；再次计算以下十个归档（含实际 builder）的 SHA-256，全部等于该次 Cargo.lock 的 registry checksum。不是用旧研究报告替代发布物。也独立获取部分版本 API 元数据与归档；先前超时的 `clap` API 请求没有被当作版本不存在，新的 Cargo 索引及归档已证实 4.6.8。完整校验值见附录。

| 发布包 | `rust-version` | edition | 候选 Cargo feature 选择及边界 |
| --- | --- | --- | --- |
| [winreg 0.56.0][p-winreg] | 1.60 | 2021 | `default-features = false`，无额外 feature。`transactions`、`serialization-serde`、可选 `chrono` 均不是当前只读通路所需 |
| [windows-sys 0.61.2][p-sys] | 1.71 | 2021 | 默认 feature 为空。直接使用 `Win32_Foundation`、`Win32_System_Registry`、`Win32_Globalization`，分别服务原始结构/状态、注册表 W API、`CompareStringOrdinal` |
| [clap 4.6.8][p-clap] / [clap_builder 4.6.7][p-builder] | 1.85 | 2024 | 对齐已评审帮助的 builder API 候选：关闭默认，开 `std, help, usage, error-context, wrap_help`，固定 `term_width(80)` / `max_term_width(80)`。不启用 derive / color / suggestions；unicode / env / string 亦非该候选必需 |
| [regex 1.13.2][p-regex] | 1.65 | 2021 | 保留 Unicode 和既定正则语法；**组合后实际有默认 features**，原因见下文。不能宣称根声明的 `default-features = false` 已去除 perf / Unicode 表 |
| [yash-fnmatch 1.1.2][p-yash] | 1.65.0 | 2021 | 没有公开 feature 开关；直接依赖启用默认 features 的 regex / regex-syntax，以及 thiserror 2 |
| [chrono 0.4.45][p-chrono] | 1.62.0 | 2021 | 关闭默认，仅 `clock`：它已导入 `now -> std -> alloc`、Windows 的 `winapi -> windows-link`，满足本地日期与查询开始时刻；不需要 serde / rkyv / locales / wasm 便利功能 |
| [humantime 2.4.0][p-humantime] | 1.60 | 2021 | 无默认 feature；不启用可选 `mu`。短整数单位的产品词法校验仍由既定适配承担 |
| [hex 0.4.3][p-hex] | **未声明** | 2018 | 默认 `std -> alloc` 可用；没有 `rust-version` 不等于任意旧编译器均受支持 |
| [ctrlc 3.5.3][p-ctrlc] | 1.71 | 2021 | 无默认 feature；仅 Ctrl+C 不需 `termination`。Windows 路径依赖 windows-sys 0.61 |

**事实与推断：** Cargo feature 对同一版本是加法合并。yash-fnmatch 的发布 manifest 没有关闭 regex / regex-syntax 默认 features，因此根依赖即使写 `regex = { default-features = false, features = ["std", "unicode"] }`，最终仍开启 `default, perf, unicode` 等。本次 metadata 确实如此；要改掉需改变依赖或修补其 manifest，不属于本次已确认组合的“免费精简”。[yash manifest][p-yash]、[feature 合并规则][cargo-features]

winreg 自带的 windows-sys features 是 `Foundation, System_Time, System_Registry, Security, Storage_FileSystem, System_Diagnostics_Debug`；ctrlc 再带 `Foundation, System_Threading, Security, System_Console`。最终加上项目直接的 `Globalization` 是上述集合的并集，外加层级父 features；不能靠根上的 `default-features = false` 清掉上游必选项。这里启用写入 API 的绑定不代表产品会请求写入权限或调用写入 API。[winreg manifest][p-winreg]、[ctrlc manifest][p-ctrlc]、[sys manifest][p-sys]

clap 最终若选择颜色、建议或 derive，需要重核依赖图和行为；这些 features 的取舍是实现/体验决定。这份候选保留帮助、usage 和错误上下文，不声称是所有可行实现中数学意义的最小集合。

### 2.2 Windows 活动图，而非整个锁文件的最大值

**观察：** 第一份 metadata-only 探针用 edition 2024、`rust-version = "1.85"`、上表精确直接依赖，但 clap **尚未启用 wrap_help**。先在线解析 x64，再用同一 lock `--offline --locked` 查询 ARM64；从 `resolve.root` 遍历活动边，两个目标均为 **26 个外部包 + 探针根**。这是无 wrap 的较小对照，**不是保留已评审帮助体验后的拟采用图**。没有编译、链接或执行。对照锁文件 SHA-256 为 `8246cd0f668ce24fae639ad55ebfcc8ca54166f2a48c9303bc31f7be70c3b276`。

除九个直接包之外，活动图中的全部传递包如下；这些版本是本次解析快照，不是永久锁定承诺。每个数字来自下载归档的 normalized manifest，可沿链接复核。

| 路径 / 包版本 | 声明 MSRV | edition / 需注意处 |
| --- | --- | --- |
| clap → [clap_builder 4.6.7][p-builder] → [clap_lex 1.1.2][t-clap-lex] | 1.85 / 1.85 | 均 2024，是本图最高已声明下限 |
| builder → [anstyle 1.0.14][t-anstyle] | 1.66 | 2021；关闭颜色也仍有基础样式类型依赖 |
| regex → [regex-automata 0.4.19][t-automata]、[regex-syntax 0.8.12][t-syntax] | 1.65 / 1.65 | 2021 |
| regex / automata → [aho-corasick 1.1.5][t-aho]、[memchr 2.8.3][t-memchr] | 1.60 / 1.61 | 2021 |
| yash-fnmatch → [thiserror 2.0.21][t-thiserror] → [thiserror-impl 2.0.21][t-thiserror-impl] | 1.77 / 1.77 | 2021；比 yash 本身自报的 1.65 高 |
| derive 依赖链 → [proc-macro2 1.0.107][t-proc2]、[quote 1.0.47][t-quote]、[syn 3.0.10][t-syn]、[unicode-ident 1.0.27][t-ident] | 均 1.71 | 2021；unicode-ident 许可另含 `AND Unicode-3.0` |
| chrono → [num-traits 0.2.19][t-num] → build dependency [autocfg 1.5.1][t-autocfg] | 1.60 / 1.0 | 2021 / 2015 |
| winreg → [cfg-if 1.0.5][t-cfg] | 1.32 | 2018 |
| chrono / windows-sys → [windows-link 0.2.1][t-link] | 1.71 | 2021；没有发现另一版 windows-sys 或 windows-targets 活动路径 |

**边界：** 完整 lock / metadata 包列表还可能含 Unix、Apple、Wasm 或未活动的可选包；这不等于它们在两个 Windows 二进制中参与编译。反过来，MSRV 核查必须包含在宿主上编译的 build dependencies 和 proc macros，不能只看目标端运行库。这里没有把 ctrlc 的 Unix nix、chrono 的其他平台时区实现当作 Windows 活动依赖。[Cargo metadata 的平台过滤][cargo-metadata]、[Cargo resolver][cargo-resolver]

**保留 80 列帮助的差异实查：** 已评审终端原型使用 `wrap_help` 与 `term_width(80).max_term_width(80)`。第二份探针在其余九个直接版本/设置不变时启用该 feature，在线解析后以同锁查询两个目标；均变为 **27 个外部包**。唯一新增活动包是 [terminal_size 0.4.4][t-terminal]，声明 **Rust 1.71 / edition 2021 / MIT OR Apache-2.0**，无 feature 表。其 Windows 依赖为 `windows-sys >=0.59, <=0.61` 的 Foundation / System_Console，复用现有 0.61.2；两项本来已由 winreg / ctrlc 启用，没有新 Windows 活动 feature 或更高声明下限。Unix rustix 仅进完整 lock，不进这两个 Windows 活动包图。第二份锁文件 SHA-256 为 `6e01b9584bb750147cdb8c8bd3a6731772db9e4fcb397eb28f060f0c7cbd0e76`。[builder 的 wrap_help 定义][p-builder]、[terminal_size 发布 manifest][t-terminal]

**feature 证据注意：** 此次 metadata 的 `nodes[].features` 在平台过滤后仍出现由非 Windows 图合并来的 WinSock feature；因此没有据这个字段声称 Windows 实际构建多了 WinSock。另用 `cargo tree --target <两个 triple> -e features -i windows-sys` 交叉核对活动边，Windows Foundation / Console 与已有集合相同，未出现 Networking / WinSock。metadata 活动包数、完整 lock 范围与目标构建 feature 不能混为一谈。[Cargo tree 的 feature 图说明][cargo-tree]

**推断：** 1.85 是这份图的已声明下限，因为较低版本连已选 clap 的 2024 manifest 都无法支持；它不是已经证明的项目 MSRV。缺失/错误的声明、依赖内部新 API、编译器 bug、SDK/链接器要求和项目代码都可能另增约束。真正保证需要在项目实际声明的固定工具链上对两个原生目标构建、测试及安装。没有安装 1.85 或擅自 pin 本机工具链。

## 3. 固定工具链、MSRV 与锁文件各保证什么

| 机制 | 实际保证 | 不自动保证 |
| --- | --- | --- |
| `rust-toolchain.toml` 的精确 `channel = "1.x.y"` 与 components | rustup 在该目录选择固定 compiler / Cargo / rustfmt / Clippy；也可显式 `cargo +<版本>` 运行 | 系统 SDK、MSVC linker、runner 映像、第三方 CLI 和用户安装时的工具链没有随之全固定 |
| `[package] rust-version` | Cargo 对太旧工具链给出明确错误；可被 `--ignore-rust-version` 绕过 | 它不是 CI 证书，不会替依赖补全或纠正 MSRV 声明 |
| `Cargo.lock` + 构建的 `--locked` | 固定所解析的版本 / 来源 / registry checksum；要求锁文件不变 | 不固定 compiler、feature 集合、target、外部本机工具、环境或运行系统，也不消除已知漏洞 |
| edition 2024 / resolver 3 | Rust 1.85 可用；默认偏好与 `rust-version` 兼容的依赖 | `fallback` 不是严格上限：若范围内没有兼容版本，仍会选不兼容包；未知 MSRV 也不是兼容证明 |

上述来自 [rustup overrides][rustup-overrides]、[rust-version 文档][cargo-rust-version]、[resolver 规则][cargo-resolver]。Rust 1.84 的 Cargo 已能显式选择 MSRV-aware fallback；**2024 edition 本身在 1.85 才稳定**，不能把 resolver 的 1.84 下限误当成 edition 下限。[Rust 2024 resolver 指南][cargo-resolver-2024]、[1.85 公告][rust-185]

### Cargo 安装必须区分版本

**事实：** 1.100.0 的官方发布说明明确将 `cargo install` 改为默认使用 `.crate` 内现有 Cargo.lock，`--locked` 在 install 中成为 no-op；当前在线 install 文档与之相符。1.99.1 本机随工具链分发的官方手册仍写默认忽略锁文件、`--locked` 强制使用它。旧版安装行为不能依据滚动的 stable 文档来说明。[1.100 release][rust-1100]、[当前 install][cargo-install]、[1.99 版本文档入口][cargo-install-199]

**候选：** 安装说明持续使用 `cargo install regqry --version <精确发行版> --locked`，可覆盖 1.85–1.99 的旧行为，1.100 下也可接受；这不是现在执行安装或预定包版本。没有包内锁文件时，当前 Cargo 仍会正常解析并对 `--locked` 给警告，不应将它视为“无锁必拒绝”的承诺。[install 文档][cargo-install]

**事实：** registry / git 来源安装忽略调用目录的项目级 Cargo 配置，从 `$CARGO_HOME/config.toml` 开始；`--path` 才从路径所在配置发现。故仓库 `.cargo/config.toml` 的 CRT 设置不会天然约束所有 crates.io 用户。`cargo package` 会规范化 manifest、去除 workspace/patch、生成或包含锁文件并解包重建（除非跳过验证）。本次官网 package 页仍有旧的 `--locked` 描述，涉及 1.100 新 install 默认行为时应以版本发布说明及该命令文档为准。[install 配置发现][cargo-install]、[package 行为][cargo-package]

**与单固定版本政策的关系：** Cargo 接受含 patch 的裸 `rust-version`，例如 `"1.100.0"`，不接受 `^` / `>=` 或预发布标记；可与 rustup 精确 `channel = "1.100.0"` 对齐。但 `rust-version` 仍表示最低要求，**不会拒绝更高版本**，所以它不能表达“仅允许这个编译器”。仓库/发布的精确选择靠工具链 pin 和执行记录；用户明确 `cargo +其他版本` 可覆盖 pin。若最终声明 1.100.0，则旧 Cargo 安装行为仅是历史兼容说明，无须因此承诺旧工具链安装或增设旧 MSRV CI。[rust-version 格式][cargo-rust-version]、[rustup 选择优先级][rustup-overrides]

**推断 / 验证候选：** 用选定的同一固定工具链构建、测试和发行，用发行 `.crate` 的真实内容做安装验证。直接依赖精确 `=` 也不会锁住其所有传递范围。锁文件固定、工具链固定和定期更新是独立事项，更新时一并审阅图、features、许可、公告及原生验收差异，报告没有替用户决定更新周期。

## 4. 原生 Windows CI 的可用能力与空白

### 4.1 官方标签与当前映像快照

| 原生架构 | 当前标准标签 | 官方映像清单观测 | 能提供的证据 |
| --- | --- | --- | --- |
| x64 | `windows-latest`, `windows-2025`, `windows-2025-vs2026`；另有 `windows-2022` | 当前 latest / 2025 映射为 Server 2025 + VS2026；所读清单 image `20261103.298.1`、OS `10.0.26100` build `33674` | x64 MSVC 构建及该 Server 映像上的原生运行 |
| ARM64 | `windows-11-arm`, `windows-11-vs2026-arm` | Windows 11 Enterprise，image `20261112.217.1`、OS `10.0.26200` build `9974`，VS2026 | 原生 ARM64 构建及 Win11 25H2 上原生运行 |

来源：[官方标签表][gh-runners]、[runner-images 当前映射][gh-images]、[x64 映像清单][gh-x64-image]、[ARM64 映像清单][gh-arm-image]。GitHub 已接管原 ARM 合作方映像；`partner-runner-images` 在 2026-06 归档，其旧 2026-01 清单不能替代现在的 runner-images。[归档通知][gh-partner]

**事实：** public repository 的标准托管 runner 免费且不限使用分钟（仍受并发等服务限制）；当前官方表也列出 private 的 Windows ARM64，不能沿用初期“仅 public preview”说法。没有查询这个仓库账号的用量、资格或设置。`-latest` 仅表示 GitHub 提供的稳定映像，既非 OS 厂商最新的保证，也非固定 image build。Windows VM 以管理员运行并关闭 UAC。[GitHub runner 参考][gh-runners]

### 4.2 不能从托管成功推出的承诺

**推断：** 下列证据须分别保留，普通 CI 与最低系统/干净系统验收不能互相替代。

| 已有或候选证据 | 尚缺的证明 |
| --- | --- |
| x64 Server runner `cargo test` 成功 | Win10 22H2 客户端、Win11 稳定客户端实际兼容性 |
| ARM64 25H2 runner 成功 | ARM64 Win11 **24H2** 最低系统；官方版本表将 26100 / 26200 明确分开 |
| 任一管理员 runner 测试成功 | 普通用户 token、受限范围、访问拒绝后继续和不完整退出语义 |
| 构建宿主自带 Rust、VS、SDK、运行库 | 最终下载包在没有 Rust / Build Tools / SDK、无另装运行库条件下运行 |
| x64 跨编译 ARM64，或 ARM64 上启动 x64 仿真程序 | 原生 ARM64 程序及其已承诺的 x86 32 / 原生 64 注册表视图 |
| 共享 HKCU fixture 的两次 flag 打开 | 两个真正重定向视图中不同数据的选择与身份保留 |

Windows 版本对应：[微软版本表][ms-win11]；其余空白由 runner 的系统/软件/权限事实与项目支持承诺对照得出，不是 GitHub 声称这些环境等价。

### 4.3 PR 安全与验收证据候选

**官方事实：** 不应在拥有 secrets / 写权限的 `pull_request_target` 或 `workflow_run` 上 checkout 并执行不受信任 PR 代码；GitHub 建议最小 token 权限。依赖 action 可固定完整 commit SHA；当前安全文档另提供 workflow dependency lockfile 方案，是否采用留给后续工作流设计。自托管 runner 不应直接承接不受信任公开 PR。[GitHub Secure use][gh-secure]

**候选：** 普通 PR 使用一次性托管 VM、只读仓库 token、无发布凭据；最低系统与干净环境人工验收使用审阅过的特定提交/产物，不让公开 PR 获得长期 VM 的运行权。该段是据官方机制整理的设计候选，**不是声称仓库已有规则或受保护分支门禁生效**。

候选证据单可记录：commit / package 版本、产物与源码包 SHA-256、锁文件和工具版本、目标/进程/OS 架构、Windows edition/version/build、实际 token 与提升状态、image 标识、fixture 清单和 seed、命令/预期/实际退出码、stdout/stderr、各视图结果、清理结果、DLL 导入检查、执行时间与测试人。普通身份的证据应来自 token/组/提升状态，不能只写“未右键管理员”。

GitHub 的 artifact 上传工具提供 artifact ID / URL / SHA-256 digest 与保留期；过期或删除后链接会失效，包级 hash 也不同于外层 artifact 归档 hash。可保留原始记录到约定的长久发行证据位置，同时让每次 run 指向它；记录失败与未执行状态，不能把 skip 写成 pass。[upload-artifact 官方说明][gh-artifact]。本次未配置、上传或公布任何真实日志/产物。

## 5. 格式、lint 与依赖检查工具

### 5.1 Rust 自带工具能做的事

| 命令能力 | 适用边界 |
| --- | --- |
| `cargo fmt --all -- --check` | rustfmt 检查格式差异并以非零状态报告；不编译、不验证产品行为。固定 Rust 版本的 rustfmt component 可避免滚动升级造成未审阅的格式变化；一些配置仍仅 nightly 支持 |
| `cargo clippy --all-targets --locked -- -D warnings` | 编译并执行默认 lint，把 rustc / Clippy warnings 作为失败；不执行测试。`--all-targets` 是 lib/bin/test/example/bench，不是所有 CPU / OS，需要另选 `--target` 或原生 matrix |
| Cargo 1.97+ 的 `CARGO_BUILD_WARNINGS=deny` | 当前 Clippy 文档推荐此配置表达 warnings-as-errors，以避免 `-D warnings` 对缓存的影响；具体写法可随最终固定工具链选择，效果范围仍须明确 |
| `cargo check` / `build` / `test` | check 省略最终代码生成，某些错误只在 codegen/link 发生；build 也不证明运行；test 才执行所选测试。不能用 check 替代发布构建和原生运行 |
| `cargo tree -e features` / `-d`、`cargo metadata --format-version 1` | 查看活动 feature、重复依赖和结构，便于审阅；它们本身不是安全公告、许可合规或运行兼容性检查 |

依据：[rustfmt 官方 README][rustfmt]、[Clippy usage][clippy-usage]、[cargo check][cargo-check]、[cargo tree][cargo-tree]。Clippy 的 `msrv` 设置只影响认识该设置的 lint 建议，不能代替在声明编译器上编译；默认 lint 集不等于全部 pedantic / restriction，官方特别不建议整体打开 restriction。[Clippy configuration][clippy-config]、[usage][clippy-usage]

用户已在主对话接受 fmt、Clippy warnings-as-errors；本报告只核实命令语义，不添加新的 lint 政策或工具配置。

### 5.2 cargo-deny 单工具的四类检查

**观察：** crates.io API 与归档 checksum 一致的 0.21.0，发布于 2026-11-16，`rust-version = "1.89.0"`、edition 2024、`MIT OR Apache-2.0`，归档记录 VCS `4b1f2002a11077f25437c2983f0a1a5439a886f4`。官方 release 页也明确为 0.21.0。本次只读源码，没有安装或执行检查。[发布包][p-deny]、[官方 release][deny-release]

| 检查 | 真实能力 | 重要边界 / 0.21.0 配置事实 |
| --- | --- | --- |
| `licenses` | Cargo SPDX expression、许可文件检测、`allow`、逐包 `exceptions` 和带文件 hash 的 `clarify` | 不是完整法律审计：包 metadata 与实际代码授权不一致、遗漏 native code / 外部授权时可漏检。`include-dev` **默认 false**，`include-build` 默认 true；想覆盖测试依赖许可，需显式开启前者 |
| `advisories` | 根据 RustSec 或兼容自建数据库检查已知漏洞及维护/健全性公告；可查 yanked | 不保证发现未知漏洞或恶意代码。`yanked` 默认 warn；0.21 源码实际支持 `unmaintained` / `unsound` 的 scope，默认分别为 `all` / `workspace`。ignore 可记录 reason / expiry / 允许依赖范围，例外也是需要审阅的配置 |
| `sources` | registry / git 来源允许列表、未知来源等级、git spec 最低精度 | 默认未知 registry / git 是 warn，不会自动成为拒绝门禁；默认允许 crates.io。信任来源 URL 不证明每个发布者或代码内容可信；本地 path 内容也不是它的恶意代码扫描对象 |
| `bans` | 特定 crate/版本禁用、重复版本检测、feature 约束、重复例外 / skip-tree 等 | 发现重复不等于不安全；允许的必要重复须作明确例外。它不会替项目选升级方案或强迫所有相同包名统一到同一版本 |

文档：[licenses][deny-licenses]、[advisories][deny-advisories]、[sources][deny-sources]、[bans][deny-bans]。上述 **0.21.0 精确字段与默认值**另检查了发布归档 `src/licenses/cfg.rs`、`src/advisories/cfg.rs`、`src/sources/cfg.rs`、`src/bans/cfg.rs`，不是直接复制在线书中可能过时的模板。[归档源码][p-deny]

**图范围事实：** `[graph].targets` 可列两个 Windows triple；不设置时默认考虑 Cargo 解析的所有 target 依赖。`all-features`、`no-default-features`、`features` 决定 metadata 的 feature 选择；`exclude-dev = true` 会把开发依赖从各检查图中排除。即使没有排除 dev，licenses 仍有自己的 `include-dev` 开关。门禁配置应能复现产品和测试用到的图，不要把“运行一次 deny”误写成全部范围已覆盖。[graph 配置][deny-graph]、[发布源码][p-deny]

**联网事实：** 正常检查可刷新公告 DB / crate 索引；离线结果受已缓存公告和 yanked 索引时效限制。0.21.0 统一用 `--offline` 禁止抓取 crate、advisory DB 和 std-replacement 数据；`--frozen` 等于 locked + offline。源码中旧的 `check --disable-fetch` 已移除，在线书个别段落仍引用旧旗标，不能照抄。0.21 的 `fetch` 子命令接受 `db / index / std-replacement / all`，不是 `fetch advisories`。`maximum-db-staleness` 默认 90 天，在禁止抓取时限制数据库陈旧度，不等于一次离线 pass 已涵盖当天新公告。[0.21 的 main / check / fetch / advisories 源码][p-deny]、[在线 common 说明][deny-common]

**到期 ignore 的精确语义：** 0.21.0 的 `src/advisories/diags.rs` 优先使用 `[advisories].ignore` 单条对象的 `expiry`，否则采用全局 `[advisories].ignore-expiry`；可写 `YYYY-MM-DD`，或自公告发布日期起算的时长。`check.rs` 传入当前 UTC 日期；当 `date > deadline` 时不再忽略，发出 `advisory-ignore-expired` 说明并将该公告设为 **Deny**，并非只警告到期后继续放行。日期当天仍有效。单条 `reason` / `allow` 可约束原因与允许的直接依赖者。这是 advisory ignore 的原生机制，不能推定其他许可/重复例外也都有相同自动到期功能。[0.21 发布源码][p-deny]、[0.21 release 的新增字段][deny-release]

**抓取失败是否可用旧缓存通过：** 对在线 advisory DB，`git::fetch_repo` 的失败由 `AdvisoryDb::load`、`DbSet::load` 及 `check` 的 `?` 逐层传播，**不会回退旧 DB 后 pass**。但 `check.rs` 对预备的 crate/index `fetch_krates` 失败只记录 error，再继续 gather metadata；若缓存足够，不能仅靠这个日志推定最终一定非零。需要将每类抓取失败都作为阻断时，可先单独执行 `cargo deny --locked fetch db index` 并检查退出码；`fetch.rs` 对两者的错误均传播失败，再执行检查。[src/git.rs / advisories/helpers/db.rs / cargo-deny/check.rs / fetch.rs][p-deny]

**yanked 新鲜度另有边界：** 0.21 的 yanked 检查使用缓存 Cargo index；`fetch index` 实际调用的是 `cargo fetch`，其公开契约是解析/下载所需依赖，并非“强制重取每个缓存 crate 的 yanked 元数据”。显式 fetch 阶段能保证该阶段返回的错误被捕获，仍不能据此声称所有索引条目已被当天强制刷新。若需这种更强保证，后续 CI 应明确缓存/刷新策略并验证，而不是只记录一次 check 退出 0。[deny 发布源码][p-deny]、[cargo fetch][cargo-fetch]

**候选推论，未运行验证：** 审计 job 每次使用新的、隔离的 `CARGO_HOME`，不恢复 registry index / advisory DB 缓存，且不将 `db-path` 覆盖到旧目录；先执行并检查 `cargo deny --locked fetch db index` 的退出，再检查四项，可消除将历史本地索引/DB 回退误当最新结果的条件。普通构建 job 仍可另用缓存。这组合现有机制，不需要新写 yanked API 客户端，也不承诺任意缓存条件下的 cargo fetch 强制刷新。本次未安装/执行 deny 或跑此 job，首次实施须验证实际目录、抓取失败退出和记录的新索引/DB；远端 HTTP 缓存与抓取后的新变更亦不由本地隔离机制原子保证。[CARGO_HOME 作用][cargo-env]、[fetch 契约][cargo-fetch]、[deny 数据库/抓取实现][p-deny]

**候选操作边界：** 可使用固定版本 `cargo-deny 0.21.0` 执行 `cargo deny --locked check advisories bans licenses sources`；要重放既定数据库，可先抓取、记录 DB commit/时间，再离线检查。是否允许陈旧度、哪些许可放行、重复是 warn/deny、例外期限和网络失败如何处理，都应由项目配置明确；报告没有将默认值当作已接受政策。与其重复安装 cargo-audit 做同类已知公告检查，单 deny 已有该能力，但不会覆盖全部供应链风险。[check 子命令][deny-check]、[advisories][deny-advisories]

### 5.3 固定与升级的对象

**候选：** Rust pin 同时固定 rustfmt / Clippy components；cargo-deny 另固定工具版本（从源码安装时 `cargo install --version 0.21.0 --locked cargo-deny`，或选择对应 release 固定预编译物及 hash）。工具自身的声明 MSRV 只是安装下限线索，若由源码构建还应核实其锁定传递图和实际构建；本研究未验证 cargo-deny 在 1.89 或 1.100 下安装。预编译工具的可用平台是上游 best-effort 发布，不推定包含每个架构。[deny 安装文档][deny-install]

Cargo.lock 不固定这些工具的可执行版本、action 的引用或公告数据库。升级 compiler / components、依赖 lock / features、deny 工具、action、DB 是不同输入；可在一次受审阅更新中记录变化并重跑相应检查。工具更新后 lint / 解析规则可能变化，数据库刷新后旧 lock 也可能产生新公告。不能为了“固定”把公告数据库永久冻结，也不能将浮动 `stable` 或浮动工具 latest 说成可重放。

## 6. Windows 隔离 fixture 的现成机制

### 6.1 先区分三种隔离范围

| 机制 | 能安全验证什么 | 不能替代什么 |
| --- | --- | --- |
| 已定内部只读接口的构造实现（纯内存数据） | 任意 `u32` 类型、`Vec<u16>` 名称、原始字节、逐项错误、动态尺寸/重试、取消与解码边界 | OS 是否接受构造输入、实际权限、链接源、视图映射 |
| 临时文件 + `RegLoadAppKeyW` application hive，交给真实 adapter 的测试句柄 | 真实 Win32 枚举、读取和缓冲区；不占用可导航的真实注册表命名空间 | 根路径 CLI 端到端、真实 WOW64 路径重定向、不同子键 ACL |
| 一次性 Windows VM 上显式命名的私有 fixture | CLI 根路径、跨进程查询、重定向视图、ACL、链接及普通用户证据 | 普通本机无授权地修改任意用户或系统数据；不能作为默认扫描真实配置的理由 |

**事实：** `RegLoadAppKeyW` 返回只能通过 handle 访问、不能从绝对注册表命名空间导航的 application hive。不存在的文件名会创建空 hive；`REG_PROCESS_APPKEY` 可阻止其他 caller 再加载；所有 key handles 关闭后自动卸载。winreg 0.56 已有 `load_app_key` / `load_app_key_with_flags`，其发布测试用 `tempfile::tempdir()` + 不存在的文件名来创建它，无须另造通用注册表 fixture 库。[Microsoft API][ms-appkey]、[winreg 发布源码与 tests/reg_key.rs][p-winreg]

**限制：** app hive 要求所有键同一 security descriptor，且不能调用 RegSetKeySecurity 修改内部键；所以无法用它构造一棵同时含可读 / 拒绝访问子键的 ACL 树。不可导航也意味着现有公开 ROOT CLI 无法直接寻址它；用测试注入句柄可以测 adapter，但不能把这当成真实根路径 CLI 验收。`RegOverridePredefKey` 只影响调用进程，不会自动把父进程重映射传给新启动的 CLI；它还改变进程内全局状态，需隔离进程，不能让平行测试彼此污染。[app hive 限制][ms-appkey]、[OverridePredefKey][ms-override]

**推断 / 候选：** 日常纯逻辑测试不需要真实注册表；Windows adapter 可优先用应用 hive。实际 CLI / 视图 / ACL / 链接测试在一次性 VM 中，仅在随机命名、明确记录所有权的私有范围准备数据。创建、断言和清理属于测试 harness；生产查询仍只读。RAII（资源获取即初始化，Resource Acquisition Is Initialization）有助异常退出清理，但进程强杀时仍需 VM 回滚或专用范围清理，不能承诺 Drop 总会执行。

### 6.2 两视图 fixture 必须真的分开

**事实：** Windows 7 及更新版本的官方表列出：`HKCU\Software` 共享，`HKCU\Software\Classes` 共享，**`HKCU\Software\Classes\CLSID` 重定向**，`HKLM\Software` 重定向；子键继承表中父级行为，除非另列。不要硬编码 `Wow6432Node` 物理路径。[官方映射表][ms-shared]

**候选：** 在一次性 VM 中，于 `HKCU\Software\Classes\CLSID\{本次随机 GUID}` 建立只含测试 sentinel 的私有子键，分别用 32 / 64 flag 写入不同名称/数据，随后以只读 CLI 验证显式视图、默认两视图及去重身份；不放 `InprocServer32` 等指向可执行组件的真实 COM 注册内容。一般 HKCU 的写入授权来自当前用户 ACL，**是否可创建要检查实际 ACL / 返回码**，不能只凭 HKCU 名称宣布成功。另一个选项是管理员只在隔离 VM 的 `HKLM\Software\<专用随机路径>` 预置两视图，再给普通用户所需读取权，查询本身降到普通身份。

ARM64 上的 `KEY_WOW64_32KEY` 对原生 ARM64 进程指向 x86 32 位视图，`KEY_WOW64_64KEY` 指向原生 64 位；官方规则不能替代项目的双架构实际 sentinel 结果。app hive 上带两个 flag，或共享 HKCU 上两次成功打开，都不是此验证。[Alternate Registry View][ms-views]

### 6.3 权限、链接和异常数据不能交给便利转换掩盖

**ACL 事实：** 键 DACL 可以在创建时指定；修改 DACL 要求所有者/`WRITE_DAC`，并不是所有 ACL fixture 都需管理员。普通用户可在其有权控制的私有键上保留清理 handle、设置拒绝某操作的 ACL，再重新打开被测只读 handle。`ACCESS_SYSTEM_SECURITY` / SACL 是另一回事，不是普通拒绝读取测试的必需项。实际普通身份测试要在普通 token 中运行；管理员进程少请求一点访问权不等于普通用户。[访问权][ms-rights]、[Microsoft CRegKey 安全权限说明][ms-cregkey]

**链接事实：** 注册表链接通过 `REG_OPTION_CREATE_LINK` 创建源键，再以 `REG_LINK` 类型写入 `SymbolicLinkValue`，目标为绝对注册表 Object Name、**无尾 NUL**；`REG_OPTION_OPEN_LINK` 打开源。微软 MS-RRP 要求创建链接检查父键 `KEY_CREATE_SUB_KEY | KEY_CREATE_LINK`，Win32 权限页把后者标为保留系统用途；这与文件系统的 `SeCreateSymbolicLinkPrivilege` 不是同一规则。本次没有发现可把文件链接特权直接套用到注册表的官方依据，也没有证实所有普通用户/系统都能创建链接。[Win32 create][ms-create]、[MS-RRP Symbolic Links][ms-links]、[BaseRegCreateKey][ms-rrp-create]、[访问权][ms-rights]

**候选 / 未验证：** 可在一次性 VM 尝试普通用户控制的私有范围；如 setup 权限不足，明确分成受控预置 fixture 与普通用户只读查询两步，保留权限/错误码。至少覆盖显式 ROOT 经链接到目标、递归只观察源、不进入目标、断链、链/循环、目标超出根、权限失败后的完整性。链接目标和源都必须是本次私有范围。MS-RRP 说明常规 DeleteKey / DeleteKeyEx 对源可能返回不存在，不能盲目递归删除链接路径并误碰目标；候选 cleanup 可用 source handle 的 `NtDeleteKey`（官方明确 user mode 用 Nt 名称，要求 DELETE），或销毁隔离 VM。该清理机制须实际验证后才能采用，不能以源码阅读冒充已跑通。[MS-RRP 链接删除语义][ms-links]、[Nt/ZwDeleteKey 文档][ms-ntdelete]

| 输入 / 失败 | 必要测试机制与证据边界 |
| --- | --- |
| 长值名 | 真实 W API 的动态名称缓冲区；覆盖越过旧 2048 数组的名称、接近文档上限 **16,383 字符**的名称和 ERROR_MORE_DATA。构造成功与枚举读取成功分别记录，不用 display 截断作为读取结果 |
| 未知类型码 | 在内存 seam 中明确构造已知集合外 `u32`，验证保留和非文本行为；原生 fixture 需小型 raw-API setup helper 及回读确认。Win32 文档列已知类型，MS-RRP SetValue 还限制 REG_VALUE_TYPE，**不能从 DWORD 参数类型推论任何未知值都保证可写**；若 OS 不接受，报告测试设施限制并寻找经审阅的准备机制 |
| 异常 UTF-16 名称 / 数据 | 标准库 `OsString::from_wide` / `encode_wide` 可无损往返孤立代理项；fixture 用原始 `u16` / bytes，不能经过 lossy String、JSON Unicode 文本或 reg.exe 文本序列化。具体 Win32 接口是否接受要以原生 setup / 回读记录为准 |
| 缺/额外终止符、奇数字节、整数错长度、零字节 | 构造 seam 覆盖已定解释表；原生 helper 不能用会自动加终止符/修复数据的便利 setter 掩盖输入。RegQueryValueEx 明确不保证返回的字符串已正常终止；setup API 的成功不能代替核对实际保存字节 |
| 并发增长、重试耗尽、逐项拒绝、读取中删除 | seam 可确定性注入各次错误/长度，避免以随机时间竞态当唯一证明；原生压力测试可补证但不能代替可重放的契约断言 |

依据：[元素长度上限][ms-limits]、[RegSetValueExW][ms-set-value]、[MS-RRP SetValue][ms-rrp-set]、[Rust Windows 字符串保证][rust-osstring]、[RegQueryValueExW][ms-query-value]。本次只调查机制，没有执行表中任何注册表 setup / 查询 / 清理。

## 7. 可复用测试 crates 与干净环境测试包

### 7.1 候选而非新增已定依赖

**观察：** 四个候选的精确发布包已通过公开索引下载并检查 manifest；另以隔离 metadata manifest 查询 Windows 图。表中最高下限只按该次活动传递图的声明，仍不是实际编译证明。

| 测试 crate | 发布 manifest MSRV / edition / 许可 | 可复用能力及取舍 |
| --- | --- | --- |
| [assert_cmd 2.2.2][p-assert] | 1.85 / 2024 / MIT OR Apache-2.0 | CLI exit / stdout / stderr 断言、超时、参数与子进程环境。该次图最高声明 1.85。不能自动生成注册表、提升/降低 token 或实现 Ctrl+C 注入 |
| [predicates 3.1.4][p-predicates] | 1.74 / 2021 / MIT OR Apache-2.0 | 复用输出谓词；assert_cmd 已依赖它，根可按需只开 diff / regex。默认还带 float-cmp、换行规范化与颜色；对原始输出保真断言不能无条件规范化 |
| [tempfile 3.27.0][p-tempfile] | 1.63 / 2021 / MIT OR Apache-2.0 | `TempDir` / 临时文件管理 app hive 和日志。默认含 getrandom；本次 Windows 图解析到 [getrandom 0.4.3][t-getrandom]（Rust 1.85 / edition 2024），所以不能凭 tempfile 自报 1.63 宣称整图最低 1.63 |
| [proptest 1.12.0][p-proptest] | 1.88 / 2021 / MIT OR Apache-2.0 | 生成 / 缩减 `u16`、字节、解释布局和过滤组合的反例，保留 seed / regression；默认含 std/fork/timeout/bit-set。它不会代替规定的边界样例，当前固定版本若是 1.100 则声明下限不构成冲突 |

已有 winreg + windows-sys 已能承担 native fixture 的 handle / raw setup 基础；不需要为了临时注册表再次引入完整访问库。Cargo 自带 test harness 与标准库断言也足以先覆盖五模块契约，不因存在这些候选就全部加入。fixture 命名/生命周期、权限与链接 cleanup 仍是项目特定小适配；本报告没有找到一个已核发布 crate 能替项目同时保证所有这些语义。[winreg][p-winreg]、[sys][p-sys]

### 7.2 无 Rust / Build Tools VM 上运行 native 测试包的依据

**官方事实：** `cargo test --no-run` 编译而不执行；正常测试目标是链接 libtest 的可执行文件。`--message-format=json` 的 `compiler-artifact` 提供 `executable`、target 与 profile 等结构信息，可据此收集真实文件，不依赖 target 内部目录布局。doc tests 默认在运行过程中调用 rustdoc/rustc，不能不加区分地混入“无编译器的测试包”。[cargo test][cargo-test]、[artifact messages][cargo-json]

**候选构建入口：** 在受信任构建环境对每个目标执行 `cargo test --no-run --locked --target <triple> --message-format=json`，仅收集需要的 native 测试可执行物、真实 CLI、setup/helper、固定 fixture 内容、清单与 hashes。测试 exe 可以在目标系统直接运行，不必安装 Cargo 来启动它；它的系统/DLL要求仍来自实际链接结果和测试代码，不是 Cargo 自动消除的。

**迁移限制：** Cargo 正常启动测试时将工作目录设为 package 根；离线手工启动不提供这个目录。`CARGO_MANIFEST_DIR` 是构建时 package 目录，`CARGO_BIN_EXE_<name>` 是 Cargo 给出的构建产物路径；assert_cmd 2.2.2 的 `cargo_bin!` 宏将后一条用 `env!` 编译为路径。因此搬到 VM 后不能仍依赖构建机绝对路径、源码目录、Cargo 可执行文件或未打包 fixture。可嵌入常量数据，或从测试包根显式定位 fixture / CLI，再用 assert_cmd 的 `Command::new`；这只是机制候选，不是已建框架。[Cargo 环境变量][cargo-env]、[assert_cmd 的 src/macros.rs][p-assert]

**CRT / DLL 边界：** CLI 之外的每个测试 exe 和 helper 也须采用相应链接设置并检查最终依赖；静态 CRT 仅控制 CRT，不是“没有 DLL”。Rust 官方建议检查结果，MSVC `dumpbin /DEPENDENTS` 可列导入 DLL，`/IMPORTS` 可进一步列导入函数；还需在目标干净 VM 实际启动与执行。若 helper 仍依赖构建机运行库，整包验收就没有满足无开发工具条件。[Rust 链接规则][rust-linkage]、[DUMPBIN /DEPENDENTS][ms-dependents]

测试包 hash、目标架构、来自哪个正式产物、fixture 版本、执行参数及返回值应和人工验收证据绑定。一个 debug 测试 exe 成功不能代替最终 release CLI 的直接运行；反过来最终 CLI 能启动，也不能证明 helper、最小权限、视图和异常字节读取都已测试。本次没有构建该测试包，也没有认定任何最低系统 / 普通用户 / 干净环境已通过。

## 8. 本次证据、限制及交接

**实际完成：** 阅读精确发布归档；对无 wrap / 保留 wrap_help 两种生产对照分别在线解析与同锁查询双平台 metadata，并用目标 cargo tree 核对 feature；核对 manifest / 校验值；对四个测试候选做 metadata 调查；浏览当前官方 Rust、GitHub、Microsoft、cargo-deny 文档及发布页。探针、下载和本机分发文档副本/读取记录仅在研究工作树忽略目录 `.scratch/`，提交仅本报告。该目录不是产品 fixture，也没有执行会创建注册表键的任何上游测试。

本机观察为 `rustc 1.99.1 (58cf8f9c3 2026-10-13)`、`cargo 1.99.1 (5f94df478 2026-08-27)`、host `x86_64-pc-windows-msvc`；从官方 stable 清单另证实 1.100.0，不能将本地默认工具版本当成网上当前发布版本。本次网络部分 API/文档请求超时，未将超时填成不存在；关键版本另以新 Cargo 索引、公开归档与官方 release 交叉核实。特别记录三处滚动文档差异：cargo install 1.100 行为相对本机 1.99 手册已变；package 页仍留旧 `--locked` 描述；cargo-deny 书中旧 `--disable-fetch` / 部分旧 advisory 配置说明以 0.21 发布解析器为准。

仍需决定或落实的范围是：最终精确 Rust pin（当前官方 stable 1.100.0）、clap 的实际实现 features、cargo-deny 的许可/公告/来源/重复及例外政策、测试依赖最终最小组合，以及两种架构上 fixture 的原生实证。用户已选择的单固定版本、warnings-as-errors、普通 merge 不由本报告重新开题。仅选 assert_cmd + tempfile 已有 CLI 断言和临时文件能力；predicates 可通过 assert_cmd 复用，proptest 仅是可选调查结果，不是首版必加工具。

发布支持仍待实际证据：x64 Win10 22H2 / Win11 稳定客户端、ARM64 Win11 24H2、原生目标、两种已承诺视图、普通用户 token、无开发工具/无另装运行库、发行 `.crate` 安装、最终二进制及测试/helper DLL 审查、长名称/未知类型/异常 UTF-16/链接/逐项失败。此次研究不能把任何一项变成 pass。

### 生产精确归档 SHA-256

| 归档 | 与新解析 Cargo.lock 相符的 SHA-256 |
| --- | --- |
| winreg 0.56.0 | `7d6f32a0ff4a9f6f01231eb2059cc85479330739333e0e58cadf03b6af2cca10` |
| windows-sys 0.61.2 | `ae137229bcbd6cdf0f7b80a31df61766145077ddf49416a728b02cb3921ff3fc` |
| clap 4.6.8 | `ac230478587d0269d8d6998b82ae69ea51509d55df66d9e92edd1f986904cd4a` |
| clap_builder 4.6.7 | `ec0797fb7aeb1406c84efac526901f7ec3ead2124f946b494e72879d4b54704d` |
| regex 1.13.2 | `9807af0e638c12e753aa1b4e601791bf2a8f71274023c8bbeec12fc149950857` |
| yash-fnmatch 1.1.2 | `d33de323788da593d6dff84d7826f849a58df55664a5bb505e52b092d558d3ec` |
| chrono 0.4.45 | `1aa79e62e7697b8e29b513a68abacf485adcd1fe8284a4316c5ae868e6633327` |
| humantime 2.4.0 | `15cdd26707701c53297e2fa6afb323d55fbc1d0810c3aec078ae3ef0424c3c15` |
| hex 0.4.3 | `7f24254aa9a54b5c858eaee2f5bccdb46aaf0e486a595ed5fd8f86ba55232a70` |
| ctrlc 3.5.3 | `11247e6c4f83c2b15748f4873805483deaa2bbc855e773817c07a9f987f55c62` |

以下只列第一方来源。固定 `.crate` 链接指实际发布物；含 `main` / stable 的链接反映研究时滚动文档，具体快照已在正文注明。VCS info 仅作定位线索，不把其自报 SHA 当成发布内容和 Git 源码相等的独立证明。

[p-winreg]: https://static.crates.io/crates/winreg/winreg-0.56.0.crate
[p-sys]: https://static.crates.io/crates/windows-sys/windows-sys-0.61.2.crate
[p-clap]: https://static.crates.io/crates/clap/clap-4.6.8.crate
[p-builder]: https://static.crates.io/crates/clap_builder/clap_builder-4.6.7.crate
[p-regex]: https://static.crates.io/crates/regex/regex-1.13.2.crate
[p-yash]: https://static.crates.io/crates/yash-fnmatch/yash-fnmatch-1.1.2.crate
[p-chrono]: https://static.crates.io/crates/chrono/chrono-0.4.45.crate
[p-humantime]: https://static.crates.io/crates/humantime/humantime-2.4.0.crate
[p-hex]: https://static.crates.io/crates/hex/hex-0.4.3.crate
[p-ctrlc]: https://static.crates.io/crates/ctrlc/ctrlc-3.5.3.crate
[p-deny]: https://static.crates.io/crates/cargo-deny/cargo-deny-0.21.0.crate
[p-assert]: https://static.crates.io/crates/assert_cmd/assert_cmd-2.2.2.crate
[p-predicates]: https://static.crates.io/crates/predicates/predicates-3.1.4.crate
[p-tempfile]: https://static.crates.io/crates/tempfile/tempfile-3.27.0.crate
[p-proptest]: https://static.crates.io/crates/proptest/proptest-1.12.0.crate
[t-clap-lex]: https://static.crates.io/crates/clap_lex/clap_lex-1.1.2.crate
[t-anstyle]: https://static.crates.io/crates/anstyle/anstyle-1.0.14.crate
[t-automata]: https://static.crates.io/crates/regex-automata/regex-automata-0.4.19.crate
[t-syntax]: https://static.crates.io/crates/regex-syntax/regex-syntax-0.8.12.crate
[t-aho]: https://static.crates.io/crates/aho-corasick/aho-corasick-1.1.5.crate
[t-memchr]: https://static.crates.io/crates/memchr/memchr-2.8.3.crate
[t-thiserror]: https://static.crates.io/crates/thiserror/thiserror-2.0.21.crate
[t-thiserror-impl]: https://static.crates.io/crates/thiserror-impl/thiserror-impl-2.0.21.crate
[t-proc2]: https://static.crates.io/crates/proc-macro2/proc-macro2-1.0.107.crate
[t-quote]: https://static.crates.io/crates/quote/quote-1.0.47.crate
[t-syn]: https://static.crates.io/crates/syn/syn-3.0.10.crate
[t-ident]: https://static.crates.io/crates/unicode-ident/unicode-ident-1.0.27.crate
[t-num]: https://static.crates.io/crates/num-traits/num-traits-0.2.19.crate
[t-autocfg]: https://static.crates.io/crates/autocfg/autocfg-1.5.1.crate
[t-cfg]: https://static.crates.io/crates/cfg-if/cfg-if-1.0.5.crate
[t-link]: https://static.crates.io/crates/windows-link/windows-link-0.2.1.crate
[t-getrandom]: https://static.crates.io/crates/getrandom/getrandom-0.4.3.crate
[t-terminal]: https://static.crates.io/crates/terminal_size/terminal_size-0.4.4.crate
[rust-channel]: https://static.rust-lang.org/dist/channel-rust-stable.toml
[rust-185]: https://blog.rust-lang.org/2025/02/20/Rust-1.85.0/
[rust-1100]: https://github.com/rust-lang/rust/releases/tag/1.100.0
[cargo-install]: https://doc.rust-lang.org/stable/cargo/commands/cargo-install.html
[cargo-install-199]: https://doc.rust-lang.org/1.99.1/cargo/commands/cargo-install.html
[cargo-package]: https://doc.rust-lang.org/cargo/commands/cargo-package.html
[cargo-rust-version]: https://doc.rust-lang.org/stable/cargo/reference/rust-version.html
[cargo-features]: https://doc.rust-lang.org/cargo/reference/features.html#feature-unification
[cargo-resolver]: https://doc.rust-lang.org/stable/cargo/reference/resolver.html
[cargo-resolver-2024]: https://doc.rust-lang.org/stable/edition-guide/rust-2024/cargo-resolver.html
[cargo-metadata]: https://doc.rust-lang.org/cargo/commands/cargo-metadata.html
[cargo-check]: https://doc.rust-lang.org/cargo/commands/cargo-check.html
[cargo-test]: https://doc.rust-lang.org/cargo/commands/cargo-test.html
[cargo-tree]: https://doc.rust-lang.org/cargo/commands/cargo-tree.html
[cargo-fetch]: https://doc.rust-lang.org/cargo/commands/cargo-fetch.html
[cargo-json]: https://doc.rust-lang.org/cargo/reference/external-tools.html#artifact-messages
[cargo-env]: https://doc.rust-lang.org/cargo/reference/environment-variables.html#environment-variables-cargo-sets-for-crates
[rustup-overrides]: https://rust-lang.github.io/rustup/overrides.html
[rustfmt]: https://github.com/rust-lang/rustfmt#verifying-code-is-formatted
[clippy-usage]: https://doc.rust-lang.org/clippy/usage.html
[clippy-config]: https://doc.rust-lang.org/clippy/configuration.html
[rust-linkage]: https://doc.rust-lang.org/reference/linkage.html#static-and-dynamic-c-runtimes
[rust-osstring]: https://doc.rust-lang.org/std/os/windows/ffi/index.html
[gh-runners]: https://docs.github.com/en/actions/reference/runners/github-hosted-runners
[gh-images]: https://github.com/actions/runner-images#available-images
[gh-x64-image]: https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-VS2026-Readme.md
[gh-arm-image]: https://github.com/actions/runner-images/blob/main/images/windows/Windows11-VS2026-Arm64-Readme.md
[gh-partner]: https://github.com/actions/partner-runner-images#notice-arm64-image-ownership-change
[gh-secure]: https://docs.github.com/en/actions/reference/security/secure-use
[gh-artifact]: https://github.com/actions/upload-artifact#outputs
[deny-release]: https://github.com/EmbarkStudios/cargo-deny/releases/tag/0.21.0
[deny-install]: https://embarkstudios.github.io/cargo-deny/cli/index.html
[deny-common]: https://embarkstudios.github.io/cargo-deny/cli/common.html
[deny-check]: https://embarkstudios.github.io/cargo-deny/cli/check.html
[deny-graph]: https://embarkstudios.github.io/cargo-deny/checks/cfg.html#graph
[deny-licenses]: https://embarkstudios.github.io/cargo-deny/checks/licenses/index.html
[deny-advisories]: https://embarkstudios.github.io/cargo-deny/checks/advisories/index.html
[deny-sources]: https://embarkstudios.github.io/cargo-deny/checks/sources/index.html
[deny-bans]: https://embarkstudios.github.io/cargo-deny/checks/bans/index.html
[ms-win11]: https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information
[ms-shared]: https://learn.microsoft.com/en-us/windows/win32/winprog64/shared-registry-keys
[ms-views]: https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view
[ms-appkey]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regloadappkeyw
[ms-override]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regoverridepredefkey
[ms-rights]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights
[ms-cregkey]: https://learn.microsoft.com/en-us/cpp/atl/reference/cregkey-class?view=msvc-170#cregkeysetkeysecurity
[ms-create]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcreatekeyexw
[ms-rrp-create]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/c7186ae2-1c82-45e9-933b-97d9873657e8
[ms-links]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/d5ce9dcc-1f90-4f5a-b076-cc1d2c9b4195
[ms-ntdelete]: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/wdm/nf-wdm-zwdeletekey
[ms-limits]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-element-size-limits
[ms-set-value]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw
[ms-rrp-set]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/2b61fa7e-2a38-46ce-a186-7c91b3ed1b61
[ms-query-value]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw
[ms-dependents]: https://learn.microsoft.com/en-us/cpp/build/reference/dependents?view=msvc-170
