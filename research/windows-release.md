# Windows 双渠道发布与 Rust 基建研究

核实日期：2026-11-18。范围：公开 MIT、Windows 注册表 CLI，GitHub Releases 预编译包与 Cargo 源码安装。以下区分事实、推断和建议；没有选定名称、架构、工具或发布版本，也未安装工具、运行发布或读取凭据。

## 安装契约与平台

**事实：**`cargo install PACKAGE` 下载源码并编译二进制，默认目标是本机架构；它不会下载 GitHub 的 `.exe`。包名来自 `[package].name`，命令名可由 `[[bin]].name` 独立指定。crates.io 名称先到先得、版本不可覆盖；应填版本、描述、MIT 许可及仓库/README 元数据。当前名称均未选择或占用。[Cargo 安装](https://doc.rust-lang.org/cargo/commands/cargo-install.html)、[二进制命名](https://doc.rust-lang.org/cargo/reference/cargo-targets.html#binaries)、[清单](https://doc.rust-lang.org/cargo/reference/manifest.html)、[发布约束](https://doc.rust-lang.org/cargo/reference/publishing.html)

**可行表达：**README 承诺“仅支持列明的 Windows 版本和架构；Cargo 安装需要 Rust 及相应 MSVC/Windows SDK”。依赖放入 `[target.'cfg(windows)'.dependencies]`，Windows 模块用 `#[cfg(windows)]`，非 Windows 入口用 `#[cfg(not(windows))] compile_error!("Windows only")` 明确失败。**推断：**这限制构建支持，不阻止其他系统下载源码；`cargo publish --target` 也不会建立按操作系统分发的包。[Windows 工具](https://rust-lang.github.io/rustup/installation/windows.html)、[条件依赖](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#platform-specific-dependencies)、[条件编译](https://doc.rust-lang.org/reference/conditional-compilation.html)、[编译错误](https://doc.rust-lang.org/std/macro.compile_error.html)、[源码发布](https://doc.rust-lang.org/cargo/commands/cargo-publish.html)

| 候选 MSVC 目标 | 当前 Rust 支持 | 构建与运行测试 |
| --- | --- | --- |
| `x86_64-pc-windows-msvc` | Tier 1，含本机工具 | `windows-2022` / `windows-2025` 可原生构建、测试 |
| `aarch64-pc-windows-msvc` | Tier 1，含本机工具 | `windows-11-arm` 可原生测试；也可从 x64 Windows 交叉构建 |
| `i686-pc-windows-msvc` | Tier 1，不含本机工具 | x64 Windows 交叉构建、WOW64 运行；没有标准 x86 runner，不能据此承诺纯 32 位系统的 Cargo 安装 |

**事实：**MSVC 支持 Windows 主机间跨架构构建，须装对应 VS 组件；非 Windows 主机交叉到 MSVC 不受官方支持。当前 Rust 文档列 Windows 10 / Server 2016 为系统下限。GitHub 公开库标准 runner 免费，Windows runner 默认管理员且关闭 UAC。[Rust MSVC](https://doc.rust-lang.org/rustc/platform-support/windows-msvc.html)、[runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)、[WOW64](https://learn.microsoft.com/en-us/windows/win32/winprog64/running-32-bit-applications)

**推断：**构建成功不能证明最低 Windows 版本可运行；WOW64 测试不能代替 32 位系统测试；管理员 CI 不能证明普通用户权限错误处理正确。具体系统下限还受依赖与 Win32 API 影响。

## 工具职责比较

| 路线 | 负责什么 | 成本与边界 |
| --- | --- | --- |
| 手写 Actions | 自行编排测试、ZIP、校验、Cargo 与 Releases | 小矩阵直接；版本、上传、重试逻辑均自行维护 |
| cargo-dist | 生成构建/打包/Release 工作流，支持 ZIP、许可证收集和校验文件 | 固定工具版本、通过配置更新；不负责改版本、写 changelog 或发布 crates.io，避免手改生成文件 |
| release-plz | 版本/changelog 的 release PR，以及 Cargo 发布、tag、Release | 不构建分发二进制；增加提交规范和配置。其 SemVer 检查针对 Rust 库，不能验证 CLI 参数/输出兼容性 |

上述职责为文档事实，成本为本项目的推断，依据：[dist 职责](https://axodotdev.github.io/cargo-dist/book/workspaces/cargo-release-guide.html)、[生成配置](https://axodotdev.github.io/cargo-dist/book/workspaces/simple-guide.html)、[dist 配置](https://axodotdev.github.io/cargo-dist/book/reference/config.html)、[release-plz 更新](https://release-plz.dev/docs/usage/update)、[发布](https://release-plz.dev/docs/usage/release)、[二进制边界](https://release-plz.dev/docs/extra/releasing-binaries)、[SemVer 边界](https://release-plz.dev/docs/semver-check)。

**建议：**三者均非额外必选项。可用手写 Actions 完成双渠道；也可用 dist 加独立 Cargo job；需要自动 release PR 时再评估 release-plz。组合时只让一方创建 GitHub Release；例如 release-plz 设置 `git_release_draft=true`，dist 设置 `create-release=false` 使用已有草稿。dist 文档明确列 x64/ARM64，未列 i686，若选择 x86 应验证所锁版本，不推断其必然不支持。使用非 Windows 编译拒绝后，照搬 Ubuntu 发布示例会使默认 Cargo 打包验证失败：应在 Windows 发布，或先在 Windows 验证同一包，再明确采用 `publish_no_verify`。后者是取舍，不是默认建议。[release-plz 配置](https://release-plz.dev/docs/config)

## 一条具体可行流程

以下为**建议方案**，适用于手写 Actions，也可映射到上述工具，尚未执行：

1. 发布准备提交更新 Cargo SemVer、changelog、README；版本、`--version`、tag `vVERSION` 一致。人工 tag push 或 `workflow_dispatch` 选定同一提交，发布按版本串行。
2. Windows job 执行测试、`cargo package --list`、`cargo publish --dry-run`，确认解包后可独立编译、许可和必要源码齐全；本仓库 `.scratch` 保持排除。
3. 为承诺目标执行 `cargo build --release --locked --target TARGET` 和相应运行测试，ZIP 内含命令、README、MIT LICENSE、所需第三方声明。若签名，先签再归档、计算 SHA-256；核实 CRT/DLL 依赖，不能仅凭 `.exe` 宣称免运行库。
4. 创建草稿 Release，上传带版本/架构名的 ZIP 与校验文件，下载冒烟验证；Windows Cargo job 发布同一版本，确认索引可见后公开草稿。

打包、干跑和 tag/changelog 依据 [Cargo 发布指南](https://doc.rust-lang.org/cargo/reference/publishing.html)；dist 默认 Windows ZIP、SHA-256，并默认静态链接 MSVC CRT，而普通 Rust 构建默认不同，见 [dist 配置](https://axodotdev.github.io/cargo-dist/book/reference/config.html)。

**事实：**Cargo 超时可能发生在上传之后，同版本不可覆盖；GitHub 重跑保留原 SHA/ref；已公开的 immutable release 不能增删替换资产；`gh release upload --clobber` 会先删旧文件。[Cargo 超时](https://doc.rust-lang.org/cargo/commands/cargo-publish.html)、[重跑](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)、[不可变发布](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)、[上传语义](https://cli.github.com/manual/gh_release_upload)

**推断及恢复建议：**两渠道不构成共同事务。先查 Cargo 版本是否已发布；已有资产同哈希跳过、不同哈希停止。Cargo 成功而上传失败时补草稿资产；GitHub 成功而 Cargo 失败时只补 Cargo；immutable release 缺资产时发布新版本。

## 认证、检查与可选增强

**事实：**crates.io 已支持基于 OIDC 的 Trusted Publishing；新包首次仍需 API token，随后由包所有者绑定仓库、workflow 文件及可选 environment，发布 job 配置 `id-token: write`，官方 auth action 交换短期令牌。release-plz 已内置交换能力，不同时配置 auth action/长期 registry token。GitHub 发布使用具有相应 `contents: write` 的身份。`GITHUB_TOKEN` 创建的 tag/release 不触发普通后续 workflow；组合可通过同一 workflow 的输出、显式 dispatch 或 App/PAT 串联。[crates.io 官方文档源码](https://github.com/rust-lang/crates.io/blob/main/svelte/src/routes/docs/trusted-publishing/%2Bpage.svelte)、[官方 auth action](https://github.com/rust-lang/crates-io-auth-action)、[release-plz 认证](https://release-plz.dev/docs/github/quickstart)、[GitHub 权限](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)、[触发约束](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow)

**建议的基础检查：**Windows 上 `cargo fmt --all -- --check`、默认 Clippy lint、`cargo test --locked`，加隔离的注册表及打包安装冒烟测试。严格 warnings 可按工具链采用配置或 `-D warnings`；不必全开 pedantic/restriction。提交 Cargo.lock；用 `rust-toolchain.toml` 固定开发/发布工具链，并以 `[package].rust-version` 声明、实测 MSRV；固定版本与最低支持版本是不同承诺。[rustfmt](https://github.com/rust-lang/rustfmt#checking-style-on-a-ci-server)、[Clippy](https://doc.rust-lang.org/clippy/usage.html)、[工具链文件](https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file)、[MSRV](https://doc.rust-lang.org/cargo/reference/rust-version.html)

**可选：**cargo-deny 可检查许可、来源、重复依赖及公告；cargo-audit 专注 RustSec 已知漏洞，无须首版同时引入。签名、MSI/PowerShell 安装器、winget/Scoop、构建证明另行评估；校验和不等于发布者签名。dist 当前内置 Windows 签名限 x64；有效签名也不保证立即消除 SmartScreen 提示，服务另有费用与身份/地域条件。[cargo-deny](https://embarkstudios.github.io/cargo-deny/)、[cargo-audit](https://github.com/rustsec/rustsec/tree/main/cargo-audit)、[dist 签名范围](https://axodotdev.github.io/cargo-dist/book/reference/config.html#azure-windows-sign)、[Microsoft 签名选择](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)

## 后续需人的决策及未验证项

需选择包名/命令名、最低 Windows、x64/ARM64/x86 承诺、MSRV及更新策略、发布工具、首次发布身份和是否签名。待实现后验证普通用户/最低系统、各目标依赖与运行库、Cargo 安装及部分失败恢复；本研究未验证仓库权限、账号资格、名称可用性或真实 CI。
