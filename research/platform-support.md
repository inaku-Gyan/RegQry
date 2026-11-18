# Windows 平台支持与分发边界

核实日期：2026-11-19。对应「核实平台矩阵与 ARM64 注册表视图边界」，
服务父决策「确定平台支持矩阵与分发约定」；补充 windows-release 研究。
本报告只核查事实，不选择支持矩阵、发布工具或 CRT 策略。
未安装软件、运行 CI、构建程序、访问注册表或发布制品。
“事实”指直接一手文档；“推断”指组合文档所得；“待验证”指本次没有执行的检查。

## 1. Rust 目标、运行系统与 Cargo 安装

### 当前官方支持

| MSVC 目标 | Rust 支持级别 | 本机宿主工具（host tools） |
| --- | --- | --- |
| `x86_64-pc-windows-msvc` | Tier 1 | 支持本机 rustc、cargo |
| `aarch64-pc-windows-msvc` | Tier 1 | 支持本机 rustc、cargo |
| `i686-pc-windows-msvc` | Tier 1 | 不再分发本机宿主工具；仍分发、测试标准库 |

事实：Tier 1 with host tools 另包含编译器与 Cargo 的本机运行、自动测试保证；
普通 Tier 1 编译目标支持不能据此解释为本机开发平台支持。
见 [Rust 平台表](https://doc.rust-lang.org/rustc/platform-support.html#tier-1-with-host-tools)。

事实：MSVC 共用要求是客户端 Windows 10 或更高、服务器 Windows Server 2016 或更高；
当前专页**未指定 Windows 10 的最低 feature release、build 或补丁号**。
不能把未注明的 build 改写为“至少 1607”，也不能把文档支持当成本项目已测所有 build。
见 [MSVC OS requirements](https://doc.rust-lang.org/rustc/platform-support/windows-msvc.html#os-version)。

事实：Rust 从 1.78 起把常规 Windows 目标下限提升至 Windows 10，
此基线适用于 Rust 工具链和它产生的二进制。
见 [Rust 官方基线公告](https://blog.rust-lang.org/2024/02/26/Windows-7/)。

事实：i686 宿主工具从 Rust 1.100 起停止分发；32 位 Windows 用户不能安装后续本机工具链。
官方要求从仍支持的宿主工具链交叉编译 i686，而不是停止提供 i686 程序。
因此“提供 x86 exe”和“承诺当前 Cargo 可在纯 32 位 Windows 本机安装”是两个不同承诺。
见 [Rust i686 降级公告](https://blog.rust-lang.org/2026/10/02/demoting-i686-windows-targets-to-std-only/)。

推断：Server 2016 是 Rust 文档的服务器系列下限，不是各 CPU 架构均存在相应 Server 产品的保证，
也不能由此承诺本项目已支持 Server；需把 Server 是否列入产品矩阵单独决定。

### 本机源码安装的附加条件

事实：`cargo install` 构建并安装源码包中的二进制，默认构建目标为宿主架构；
它不下载 GitHub Release 中的 exe。
见 [Cargo install](https://doc.rust-lang.org/cargo/commands/cargo-install.html)。

事实：MSVC 构建还需要链接器、库和 Windows API 导入库；Rustup 文档通过 Visual Studio /
Build Tools 与 Windows SDK 提供这些前提。
见 [Rustup MSVC prerequisites](https://rust-lang.github.io/rustup/installation/windows-msvc.html)。

事实：Rust MSVC 专页列最低 VS 2017，但该最低版本未被 CI 主动测试，并推荐最新 VS；
Windows 主机间跨架构构建由 MSVC 支持，前提是安装对应组件；
从非 Windows 主机交叉到 MSVC 可能可行，但不在该官方支持范围。
见 [Rust MSVC host / cross tooling](https://doc.rust-lang.org/rustc/platform-support/windows-msvc.html#host-tooling)。

事实：原生 ARM64 Visual Studio 从 2022 17.4 提供；其 ARM64 安装只支持 Windows 11，
并提供 HostARM64 的 ARM64 / x64 / x86 编译工具。
见 [Visual Studio on Arm](https://learn.microsoft.com/en-us/visualstudio/install/visual-studio-on-arm-devices)。
VS 2022 系统要求也明确排除 ARM64 Windows 10。
见 [VS 2022 系统要求](https://learn.microsoft.com/en-us/visualstudio/releases/2022/system-requirements#supported-operating-systems)。

推断：Rust 的 ARM64 宿主工具支持 Windows 10，不足以保证“当前微软原生开发环境可在
Windows 10 ARM 上顺畅 cargo install”。预编译程序的运行下限与开发主机要求必须分别写明。
本次没有证明 Win10 ARM 上其他工具组合的可行性；不据此宣称所有组合均不可用。

## 2. GitHub Windows runner 能证明什么

事实：标准 runner 文档分别列 x64 与 arm64 架构的 Windows VM。
当前映射如下；镜像内容和补丁持续更新，本表只是核查时快照。
见 [GitHub runner 架构与标签](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for-public-repositories)、
[官方镜像标签表](https://github.com/actions/runner-images#available-images)。

| 可用标签 | 架构 / 官方实际 OS | 镜像 README 核查值 |
| --- | --- | --- |
| `windows-2022` | x64 / Windows Server 2022 | OS 10.0.20348，Build 5870；Image 20261112.366.7 |
| `windows-2025`、`windows-2025-vs2026`；当前 `windows-latest` | x64 / Windows Server 2025 | VS2026 镜像 OS 10.0.26100，Build 33674；Image 20261103.298.1 |
| `windows-11-arm`、`windows-11-vs2026-arm` | arm64 / Windows 11 Enterprise | OS 10.0.26200，Build 9974；Image 20261112.217.1 |

快照直接来源：[Server 2022 README](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)、
[Server 2025 VS2026 README](https://github.com/actions/runner-images/blob/main/images/windows/Windows2025-VS2026-Readme.md)、
[Windows 11 ARM64 README](https://github.com/actions/runner-images/blob/main/images/windows/Windows11-VS2026-Arm64-Readme.md)。
旧 `actions/partner-runner-images` 的 ARM 镜像记录不能代替当前镜像记录；
GitHub 已接管 ARM 镜像维护，见 [官方迁移公告](https://github.blog/changelog/2026-05-14-github-actions-upcoming-image-migrations/)。

事实：Windows hosted VM 以管理员身份运行，关闭用户账户控制（User Account Control，UAC）。
见 [GitHub administrative privileges](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#administrative-privileges)。

推断：x64 runner 可原生执行 x64；ARM64 runner 可原生执行 ARM64，
但还应确保构建和测试选择相应目标，而非误用 runner 内的仿真工具。
在 ARM64 VM 上通过 x64 exe 的测试是仿真测试，不是 x64 原生硬件测试。

推断：这些标签适合构建与各自系统的运行测试；不能证明 Windows 10、Server 2016、
纯 32 位 OS 或普通用户权限环境。管理员 CI 中成功读取的键不代表普通用户可读。
若产品承诺这些环境，需另设对应 VM / self-hosted / 人工验证。
可选 CI 标签使用明确年份 / ARM 标签，仍须记录每次 job 的实际 OS、架构和镜像版本；
年份标签也不固定每个补丁或软件版本。

## 3. 注册表视图（Registry View）与 ARM 仿真

### 文档直接保证的映射

事实：以下只针对被重定向的注册表键（Registry Key）；
共享键不因两个 WOW64 标志产生独立数据。默认视图由进程架构决定。
微软另明确：Windows 10 on ARM 存在相互分开的 x86 32 位与 ARM32 视图。
见 [Registry Redirector](https://learn.microsoft.com/en-us/windows/win32/winprog64/registry-redirector)。

| OS / 进程 | 默认视图 | `KEY_WOW64_32KEY` | `KEY_WOW64_64KEY` |
| --- | --- | --- | --- |
| x64 Windows / 原生 x64 | 64 位 | x86 32 位 | 64 位 |
| x64 Windows / x86 WOW64 | x86 32 位 | x86 32 位 | 64 位 |
| Win10 ARM / 原生 ARM64 | 原生 64 位 | **x86 32 位** | 原生 64 位 |
| Win10 ARM / x86 仿真 | x86 32 位 | x86 32 位 | 原生 64 位 |
| Win10 ARM / ARM32 | ARM32 | **ARM32** | 原生 64 位 |

此表依据 [Accessing an Alternate Registry View](https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view)；
该页对 ARM 的精确措辞写的是 Windows 10 on ARM。
标志必须与查询 / 枚举等访问权组合；纯 32 位 Windows 会忽略这两个标志。
见 [Registry Key Security and Access Rights](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights)。

事实：同一调用不能同时设置两个标志，否则失败；
进入备用视图后对子键的后续 open / create / delete 应继续明确使用相同标志。
微软保留 `Wow6432Node` 与 `WowAA32Node`，应用不应直接通过这些物理路径绕开视图 API。
见 [备用视图接口约定](https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view)。

推断：单个原生 ARM64 进程依赖这两个公开标志，只能承诺原生 64 位和 x86 32 位视图；
文档没有提供让该进程选择 ARM32 视图的第三个标志。
因此 `--view 32` / `--view 64` 不能宣称覆盖所有 ARM 架构视图。
“两遍枚举所有视图”的一般说明，在 ARM 三视图情形不能直接扩张为全部架构覆盖。

### Windows 11 与仿真边界

事实：Windows 10 ARM 仅支持 x86 仿真；Windows 11 ARM 支持 x86 和 x64 仿真。
x86 使用 WOW64 注册表重定向；x64 仿真没有独立的注册表或系统二进制目录。
见 [Microsoft：How emulation works on Arm](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation)。

推断：Win11 ARM 的 x64 仿真进程默认使用与 ARM64 同一 64 位注册表视图；
其 `64KEY` 对应原生 64 位；按一般标志语义，`32KEY` 应选 x86 32 位。
后一个对应关系没有在上述 ARM 专用表中单列 x64 仿真进程，仍需在选定 Win11 版本实测。
原生 ARM64 在 Win11 上也应验证两标志行为，不把 Win10 专门措辞升级为所有后续版本的实测结论。

事实：微软当前迁移页写 AArch32 / ARM32 已不再受支持，且 sysarm32 系统二进制已移除；
但页内链接和废弃表仍写“future release”，没有明确稳定版起点。
见 [ARM32 → ARM64 迁移](https://learn.microsoft.com/en-us/windows/arm/arm32-to-arm64)、
[Windows 弃用功能表](https://learn.microsoft.com/en-us/windows/whats-new/deprecated-features)。
官方能精确追溯的首次移除公告为 2023-07-12 的 Canary Insider build 25905，限定 Arm32 UWP。
见 [Insider 25905 公告](https://blogs.windows.com/windows-insider/2023/07/12/announcing-windows-11-insider-preview-build-25905/)。
**未核实：**本次未找到足以确定“从 Win11 哪个稳定版本开始移除”的一手明文；
不将 Insider build 推导为“全部 Win11”或未经证实的 24H2 稳定版契约。
同样，ARM32 执行支持移除不自动证明历史 ARM32 注册表数据已被删除或可被原生 ARM64 完整访问。

## 4. CRT 链接与下载 exe 的前提

事实：普通 Rust MSVC 构建默认动态链接 C 运行库（C Runtime，CRT）；
可通过 `-C target-feature=+crt-static` 选择静态 CRT。
Rust 文档要求检查最终二进制，不能只因编译成功就认为链接方式正确。
见 [Rust 静态 / 动态 CRT](https://doc.rust-lang.org/reference/linkage.html#static-and-dynamic-c-runtimes)。

事实：cargo-dist 的 `msvc-crt-static` 默认 `true`，与普通 Cargo / Rust 默认不同；
这是 dist 构建策略，不会让所有用户的 `cargo install` 自动采用相同策略。
见 [dist msvc-crt-static](https://axodotdev.github.io/cargo-dist/book/reference/config.html#msvc-crt-static)。
Cargo registry 安装忽略包目录的本地配置发现，从用户 `CARGO_HOME/config.toml` 开始；
不能只放仓库 `.cargo/config.toml` 就承诺 crates.io 安装的 CRT 模式。
见 [Cargo install 配置发现](https://doc.rust-lang.org/cargo/commands/cargo-install.html#configuration-discovery)。

事实：UCRT 是 Windows 10 / Server 2016 起的系统组件；
动态 MSVC runtime 还涉及 VCRuntime，不能把“系统有 UCRT”解释成全部所需 DLL 均存在。
见 [UCRT deployment](https://learn.microsoft.com/en-us/cpp/windows/universal-crt-deployment)、
[CRT 库与 DLL 对照](https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features)。

推断：下载的已编译 exe 不需要 Rust 或 Build Tools，条件是目标架构与 OS 匹配，
所需系统 API、CRT / 第三方 DLL 均满足或按许可随包部署。
静态 CRT 可减少 CRT 运行时部署要求，但不把 Windows 系统 DLL、第三方 DLL 变成静态代码。
含 C/C++ 或 DLL 依赖时，应验证依赖采用的 CRT 与跨边界内存所有权；
微软说明各静态 CRT 实例拥有独立状态，见 [CRT 实例边界](https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features#c-runtime-lib-files)。
**待验证：**锁定依赖后检查每架构 Release 的导入表，并在无开发工具的干净系统实际启动。

## 5. Windows-only 源码包的真实约束

可行表达：在 crate root 使用 `#[cfg(not(windows))] compile_error!("This program supports Windows only.");`，
并为 Windows 模块、入口及平台依赖配置 `#[cfg(windows)]` /
`[target.'cfg(windows)'.dependencies]`，使非 Windows 目标收到明确构建错误。
依据 [compile_error!](https://doc.rust-lang.org/std/macro.compile_error.html)、
[条件编译](https://doc.rust-lang.org/reference/conditional-compilation.html)、
[平台依赖](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#platform-specific-dependencies)。

边界：`cfg(windows)` 检查**编译目标**，不检查构建宿主，也不表达 MSVC / CPU / Windows build 下限。
若最终仅支持部分 Windows target，需另行表达并实测这些限制；本报告不替人工选择。

事实：Cargo 发布上传包含源码的 `.crate`；注册表下载接口按包名、版本取得同一源码归档，
下载 URL 标记没有 OS / target 参数。
见 [Cargo publish](https://doc.rust-lang.org/cargo/commands/cargo-publish.html)、
[Registry download endpoint](https://doc.rust-lang.org/cargo/reference/registry-index.html#download-endpoint)。
推断：Windows-only guard 是构建拒绝，**不能在 crates.io 阻止其他 OS 下载源码**。
`cargo publish --target` 影响本地编译验证；不会产生仅 Windows 可下载的分包。

## 6. 供人工选择的有据选项

| 决策点 | 可行选项与额外承诺 |
| --- | --- |
| OS 范围 | Win10+ 客户端，或收窄到选定 Win11；Server 可单列纳入 / 排除。Rust 下限是必要背景，本项目最低 build 与测试清单仍需确定。 |
| 二进制架构 | x64；x64 + 原生 ARM64；另增 i686。i686 有程序支持，但当前不具备纯 32 位系统的本机 Cargo 工具链支持。 |
| ARM 视图契约 | 可承诺原生 64 位 + x86 32 位两视图；若要求历史 ARM32 数据完整性，需额外研究与验证，不能只调整两个 view flag。 |
| Release CRT | 普通动态 CRT并明确运行时要求；或显式静态 CRT并核验依赖。两者都需干净系统验证，Cargo 安装另述开发工具前提。 |

支持目标（supported target）、可构建（buildable）、已测试（tested）与可发布（distributable）
应分开记录。当前报告核实的是工具与 OS 契约；尚无本项目实现、最小系统测试、
普通用户权限测试、ARM 视图测试或各渠道安装测试可用于宣称产品兼容性。
