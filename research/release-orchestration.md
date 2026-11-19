# RegQry 候选发布、认证与双渠道恢复研究

核实日期：2026-11-19。研究基线：`main` 的 `34e02fa1a021689a61c059172737a53994180d1e`。本报告只记录发布能力与可实施分支，不选择工具、不创建工作流、不读取凭据、不创建真实 Release 或发布 crate。

项目约束来自已确认的工程方案及本轮主对话：普通 merge；Rust 1.100.0 / edition 2024 单工具链；两个原生 MSVC 目标；Git tag 触发发布准备，普通 main merge 不自动发布；首发 `0.1.0`；GitHub 只分发双架构 ZIP，另提供 crates.io 源码安装；候选必须经过最低 Windows、普通用户、干净系统验收，之后晋升，不重建已验收的二进制。用户已选 Cargo + gh + 少量 PowerShell / Actions 编排，不采用 dist / release-plz；首版签名延期；没有额外安装器或自动更新渠道。工具比较保留为事实与未采用路线的依据。

证据标记：**文档**是当前官方契约；**代码**是所列精确版本的实现；**推断 / 候选方案**是由二者得到的编排设计；**未验证**不能当作本项目已经支持。下述脚本、故障恢复及远程权限均未实际演练。

## 1. 直接影响方案的结论

| 核查项 | 结果 |
| --- | --- |
| 当前稳定版本 | cargo-dist **0.34.0**，Release 标题日期 2026-11-01，实际发布 2026-11-02；release-plz **0.4.3**，发布 2026-11-02。以下代码链接固定相应 tag；不是把浮动 action tag 当工具版本。[dist 发布][dist-version]、[release-plz 发布][plz-version] |
| 候选 ZIP 原样晋升 | **可行**：先把最终字节上传 draft，验收绑定其 SHA-256，最后只公开同一 draft。GitHub 自身提供 draft / upload / edit；工具之间、验收证据和两渠道恢复仍需编排。[创建][gh-create]、[编辑][gh-edit] |
| cargo-dist 默认流程 | 自动构建和发布有用，但默认 `host` 阶段已经上传并公开 Release；不是“构建后永久等待人工验收”。`create-release=false` 仍会自动公开已有 draft。[配置][dist-config]、[0.34 模板][dist-template] |
| release-plz 默认流程 | 负责版本 / changelog / release PR、Cargo 发布及 tag / Release，不构建 ZIP。默认 main merge 自动发布示例与本项目触发策略不同，不能照搬。[更新][plz-update]、[发布][plz-release]、[二进制边界][plz-binaries] |
| crate 原归档直接发布 | **`cargo publish` 没有 archive 参数**，会重新打包；`--no-verify` 也不改变此事。固定同输入与逐文件比较可证明源码等价，发布后下载真实 registry 包才能验证实际上传 hash；不声称复用了 archive 路径。[命令][cargo-publish]、[归档机制][cargo-package-code] |
| crates.io 新包首发 | 当前仍须 API token；后续才由 crate owner 配置 trusted publishing。没有核实出新包 OIDC 首发能力。[官方文档源码][crates-trust] |
| 双渠道事务 | Cargo 与 GitHub 没有共同提交 / 回滚事务；恢复必须先读取真实远程状态，再按版本、commit、完整资产集合与 hash 继续。Cargo 索引超时不撤销已完成的上传。[Cargo 发布][cargo-publish]、[GitHub 非原子创建][gh-create] |

## 2. 工具能负责的部分与外部编排

| 路线 | 能负责 | 本项目仍须负责 |
| --- | --- | --- |
| Cargo + gh + 少量 Actions / PowerShell | Cargo 打包、验证、发布；原生 Cargo 构建；既有 ZIP 能力；gh 创建草稿、上传和公开 | 版本/changelog 的人工审阅或其他准备工具；候选身份、证据门禁、权限、下载核对、恢复状态机 |
| cargo-dist 0.34.0 + 自己编排发布 | 目标构建、ZIP、校验文件、分发 manifest、可选 attestation | 明确原生 runner；与候选 `.crate` 的源码对应；长期 draft；验收；Cargo 发布；防重复创建 / 上传及重试 |
| release-plz 0.4.3 只做准备 | `update` / `release-pr` 提议版本和 changelog | 审阅结果、tag 触发与候选流程；无须调用其 `release` 才能使用准备能力 |
| release-plz 同时做发布 | 调用 `cargo publish`，并可创建 tag / draft Release；配置可关闭 git release、git tag、或 Cargo 发布 | 必须与候选流程协商唯一 Release 创建者、固定发布提交及门禁；它没有提供验收后重用既有归档上传的能力 |

上述工具职责依据 [dist CI][dist-ci]、[release-plz update][plz-update]、[release][plz-release] 和[固定版配置][plz-config]。表中组合方式是可选设计，不是额外依赖要求。单包、双 ZIP 和 Cargo 足以使用已有命令完成；没有必要自己实现 ZIP 格式或 SemVer 推导算法。

### cargo-dist 的具体限制

**代码：**0.34.0 的 `host-jobs` 与内置 `host` 都等待构建，二者之间没有先后依赖；所以在 custom host job 等待验收，并不能阻止默认 host 先公开。默认 `auto` 选择 `host`；`github-release="announce"` 将内置上传 / 公开放到 announce，而 announce 会等待 custom host / publish jobs。`post-announce-jobs` 已在公开之后，不能作发布前门禁。[工作流模板][dist-template]、[配置][dist-config]

**推断：**若采用 `announce`，可以让 custom job 检查证据，但此前还需自行提供可下载候选。先自行上传同名资产，再让 dist `create-release=false` 接管也不是天然幂等：其固定版 partial 会再次执行 `gh release upload`，没有按远程 digest 跳过同名资产。完整生成工作流加长期 draft / promote 需要定制并演练；不能把三个配置字段拼成已经存在的独立 promote 功能。[固定版上传 partial][dist-publish]

`dispatch-releases=true` 会把初始触发从 tag push 改成 dispatch；其 `dry-run` 构建只上传 Actions artifacts，不执行 hosting / publish / announce。它不是“初始 tag 构建，随后单独 dispatch 复用该构建”的等价配置。后者需要自己的恢复 / 晋升入口。[配置][dist-config]

**ARM64 必须显式配置：**在线定制文档列 ARM64 默认 `windows-11-arm`，但 0.34.0 的 `default_runner` 源码对非 x64 Windows 选择 Ubuntu 上的 cargo-xwin，存在文档与固定版实现差异。固定版已识别 `windows-2025-vs2026` 和 `windows-11-vs2026-arm` 的 host triple；可显式覆盖 runner 与 host 为已确认的两个原生目标，并审查实际 plan matrix。不能仅因 `targets` 含 ARM64 就声称原生构建或测试。[在线文档][dist-custom]、[默认 runner 代码][dist-ci-code]、[runner 表][dist-runners]

### release-plz 与普通 merge

**文档：**版本和 changelog 从实际 Git commits 的 Conventional Commits 分析，不从普通 merge 的 PR 标题自动替换所有中间提交。普通 merge 保留的有效 `feat` / `fix` / breaking commits 可以参与分析；默认 merge message 本身不是约定式提交。release PR 仍需人工审阅 CLI 参数、输出、退出码等兼容性，库 API 的 semver-check 不能覆盖这些契约。[update][plz-update]、[SemVer 检查边界][plz-semver]

还有一个不能忽略的提交身份问题：`release-plz release` 在普通 merge 下可能 checkout 已合并 release PR 的最后一个提交，发布该提交而不是 main 的 merge commit。若本项目 tag 已选定 merge commit，不能允许发布工具静默切到另一个 SHA。可只用准备命令，或另行证明并控制发布命令行为。[What commit is released][plz-release]

**Windows-only：**`cargo package` / `publish` 默认会解包并编译验证；应让验证及发布 job 在原生 Windows，使用本项目固定工具链和锁。release-plz 发布本质上仍调用 Cargo，Ubuntu 示例不绕过项目的非 Windows 编译拒绝。`publish_no_verify=true` 只省掉验证，不能代替之前对同一包的 Windows 验证。0.4.3 Release 同时提供 x64 / ARM64 Windows CLI assets；action 包装器和工具版本须分别固定核实。[Cargo package][cargo-package]、[plz 配置][plz-config]、[发布资产 API][plz-assets]

## 3. 可实施的候选与晋升边界

以下是**此前约束下的候选编排**，不是已经确认的流水线。用户随后要求参考 inclean 的简洁 tag 流程（第 8 节）；尚不能把这里的 Environment、长期 draft 或独立 dispatch 当作新增已选要求。最低系统等验收承诺仍有效，具体衔接由主对话继续确定。

1. **固定身份。**已审阅的 main 提交上创建最终 `v0.1.0` tag；工作流核对 tag、commit SHA、Cargo 版本和命令版本一致。tag filter 只是筛选，另用 Cargo / metadata 检查合法版本与支持策略。候选是最终版本的 draft，不必先公开 `0.1.0-rc.1`。
2. **生成一次候选输入。**清洁 checkout；固定 Rust/Cargo、lock、features、配置和源码包清单，执行 Windows `cargo package --locked`。保存最终 `.crate` 及 SHA-256；从该归档解包，用相同输入原生构建两个目标及测试包，或者逐文件证明二进制构建 checkout 与归档中实际构建输入一致。不能把 GitHub 自动 Source code ZIP、dist source tarball 和 Cargo `.crate` 当作同一对象。
3. **完成最终字节。**若要签名，此时签名后再 ZIP、hash、验收。创建唯一 draft Release，附双 ZIP、checksum、候选 `.crate`、manifest 与必要验收材料；从上传位置重新下载核对。draft 尚可修改，manifest 必须记 asset ID / name / size / SHA、tag SHA、工具链 / lock / features / 构建配置。任何替换都生成新候选身份并重做受影响验收。
4. **验收门禁。**最低 x64 Windows 10 22H2、ARM64 Windows 11 24H2、普通用户、干净系统和源码安装等已定证据绑定这组 hashes。晋升 job 解析证据文件，验证 case 完成、环境、candidate ID 与 hash 一致；缺项失败。GitHub Environment 人工批准只授权开始该 job，不能证明测试已执行。
5. **只晋升。**恢复精确 candidate；核对远程 draft / tag / 所有资产无变化，执行被选的 Cargo 发布路径并核验 registry 包，然后公开同一 draft；或采用用户另选的渠道次序。此时不重建、重签名或重压缩已验收 ZIP。`gh release edit TAG --draft=false` 是公开已有 draft 的操作。[gh edit][gh-edit]

Cargo 归档内容和验证规则见 [cargo package][cargo-package]；GitHub 支持先 draft / assets 再公开，而且 `gh release create` 的资产上传本身也不是原子事务。[gh create][gh-create]。以上第 1–5 步的证据格式、比较规则与串行恢复是项目的编排责任。

**为什么使用最终版本 draft：**crates.io 的 `0.1.0-rc.1` 与 `0.1.0` 是不同版本；去掉后缀需要改变 manifest / lock 及可能嵌入的版本，不能原样晋升同一归档或二进制。`cargo install` 默认避开 prerelease，需要显式请求；GitHub 的 draft / prerelease / latest 是另一套状态，不能控制 Cargo 版本选择。[Cargo 预发布规则][cargo-prerelease]、[gh create][gh-create]

**长期等待的两条实现分支：**

- 同一次 tag workflow 在上传候选后等待 Environment，批准后校验证据再发布；GitHub 当前 approval 上限 **30 天**，整个 run（含等待）上限 **35 天**。超过时限不会保留一个可无限恢复的挂起 run。[Actions limits][gh-limits]
- tag workflow 完成候选 draft 后结束；后续专门的 dispatch / recovery workflow 以 tag、candidate manifest 和证据指针恢复。它必须只晋升，不触发新构建；workflow 文件须在 default branch，dispatch 的实际 ref 还须满足 environment 规则。新增该恢复入口不等于把初始触发改成 dispatch。[事件规则][gh-events]

Draft 是可继续编辑的 Release 对象；它不使用 Actions artifact 作为唯一候选存储。官方没有在所核文档中给出 draft 保存期限的永久 SLA，仍须保留已选长期证据归档。draft 也不是公开下载渠道：Release API 明确只有具 push access 的用户能看到 draft listings；给外部验收者发未经授权的 draft URL 不能替代下载权限。[Release API][gh-releases]

## 4. Cargo 归档：重打包、等价与核验门槛

### 4.1 已核实的命令和固定版机制

**文档：**`cargo publish` 创建新的 `.crate`、上传、等待索引；没有接受既有 archive 路径的选项。`--manifest-path` 指向清单，`--no-verify` 跳过解包编译，`--locked` 约束依赖解析，都不是复用 `.crate` 参数。[publish][cargo-publish]

**代码：**通过 Rust `1.100.0` 的 Cargo submodule 得到精确 revision `3acc79c0c841844675bc53a605922dbfc441e750`。该版打包对路径排序、用 deterministic tar metadata，生成文件固定 timestamp，并规范化 manifest / lock / VCS 信息。因此固定同一平台、Cargo binary 与全部输入，有重新生成相同归档的实现基础；这不是 Cargo 对任意主机 / 版本 / 文件 mode 的跨环境字节保证。[Rust submodule][rust-cargo]、[package 实现][cargo-package-code]

**特别容易查错：**本版 `cargo publish` 调用 `package_with_dep_graph`，上传其内部临时 tarball；普通 `cargo package` 才将包提升到 `target/package/NAME-VERSION.crate`。所以发布后检查后者可能只是检查先前候选，不能证明实际上传字节。最终必须下载 registry 归档核验。[publish 实现][cargo-publish-code]、[package 实现][cargo-package-code]

### 4.2 源码等价与更强的发布前后核对

**源码等价路径：**从同一 clean tag 用同一固定 Windows Cargo 环境重打包，发布前比较归档全部路径和逐文件字节；保留归档 hash。必须包含 `Cargo.toml`（normalized）、`Cargo.toml.orig`、实际 `Cargo.lock`、`.cargo_vcs_info.json` 以及所有构建输入，不能忽略它们后仅比较 `src/`。VCS 文件只是 best-effort 自报，不独立证明归档与 Git SHA 对应。[package 文档][cargo-package]

不要直接对解包目录运行 `cargo publish` 并宣称必然相同：原清单已经被规范化，生成 / 保留的文件和 VCS 上下文不同；固定版对把 `Cargo.toml.orig` / `.cargo_vcs_info.json` 当普通源文件重新纳入还设有保留名检查。用于构建 / 安装的解包目录，与用于重新发布的原始 clean checkout 是不同输入。[固定版 package][cargo-package-code]

**更强门槛候选（主对话仍在确认，未演练）：**发布前从同一个 clean tag、同一个 Windows 平台 / Cargo binary、lock 与配置重新 `cargo package --locked`；其 SHA-256 须等于已验收候选，再调用 `cargo publish`。发布后下载真实 registry 归档，验证 index `cksum`、下载 SHA 和候选 SHA 全相同，并逐文件核对。任何不一致都阻断 GitHub draft 公开；此时 Cargo 可能已公开，必须记录部分成功且不可回滚。[索引 checksum][cargo-index]、[发布永久性][cargo-publishing]

发布前 hash 一致是有效 preflight，但普通 `publish` 仍会再打包一次；它不是实际内部上传文件的上传前检查，不能据此声称 API 直接复用了候选 archive。固定版 deterministic 机制使相同输入重打包具有基础，实际项目仍须重复打包演练。这个边界即使选择更强门槛也不能隐藏。

**未采用的能力：**官方 credential-provider 的 publish 请求含 `name / vers / cksum`，可另做上传前 checksum gate；registry Web API 也允许正文带原归档，但两者都需要额外实现，本项目不引入自写 provider 或上传协议。[provider 协议][cargo-provider]、[Registry Web API][cargo-api]

## 5. 认证、ref 与 Release 创建权限

**crates.io：**新包先发布，owner 才能在 Settings 添加 GitHub repository owner/name、workflow filename 和可选 environment。当前文档仍明确 initial publish requires an API token；token scopes 应覆盖新包发布而非只更新已有包。后续认证 job 用 `id-token: write` 交换短期 token，官方 auth action 在 job 结束时撤销；不要在构建候选时就申请一个等待数天的 30 分钟 token。release-plz 已内建同一交换，不与 auth action /长期 token 混用。[Trusted publishing][crates-trust]、[auth action][crates-auth-action]、[release-plz 认证与 scopes][plz-auth]

Trusted publisher 配置列出的字段没有 branch/tag 筛选；**推断：**这不能代替 GitHub Environment 的选定 branch/tag 规则、tag 权限和 workflow 中的候选身份核对。tag-trigger job 的 ref 是 tag，不是 main；不能给 environment 只允许 main 却期望 tag job 通过。恢复 workflow 若用 main ref 但输入 candidate tag，应明确批准的是哪个 ref、发布的是哪个 SHA。Environment approval 通过后才给该 job environment secrets；在此之后即时取发布凭据。[Environment 规则][gh-environments]

**GitHub：**Release 操作通常用该仓库 `contents: write` 的 `GITHUB_TOKEN`；只让一个工具 / job 创建和公开同一版本的 Release，其他工具仅准备、上传或验证。`gh release create --draft --verify-tag` 防止无意从 default branch 自动造 tag；另行解析实际 tag SHA，不能仅信任 `target_commitish`（既有 tag 时它不决定 tag）。如果目标提交相对 default branch 修改 workflow，当前 API 还可能要求额外 Workflows write，而 `GITHUB_TOKEN` 不能获该权限；本项目应在已审阅 main 提交打 tag并演练权限，不据此默认要求 PAT。[gh create][gh-create]、[Release API][gh-releases]

`GITHUB_TOKEN` 产生的普通 tag / release 事件不自动启动后续 tag / release workflow，不能假定“工具发布后另一个 workflow 会跑”。显式 dispatch 是允许的例外；同一 workflow 的依赖链也可直接编排。当前 GitHub 已对部分 bot 创建 PR 事件增加需批准的例外，但它不改变 tag / release 这条约束。[Triggering workflow][gh-trigger]

## 6. 远程状态核对和部分失败恢复

下表是**项目应实现的恢复规则**，不是 Cargo / gh 自动提供的事务。按版本串行，恢复先校验 tag SHA、candidate ID、预期资产集合及证据，再判断具体状态。不要重跑整个构建流程来“修复”已有版本。

| 实际状态 | 继续动作 / 停止条件 |
| --- | --- |
| Cargo upload / index 等待超时，结果不明 | 不立即再发布。查询准确版本，刷新索引并取得该版本 `cksum`，下载该 `.crate` 计算 SHA-256；版本、registry、checksum 与候选一致才记 Cargo 成功。索引未可见时等待 / 重查，不能把一次 404 当作永远未上传。 |
| Cargo 同版本存在 | hash 相同则跳过上传；不同则停止并调查身份 / 来源。不得覆盖同一版本，也不把 release-plz 的“已发布，跳过”当作 hash 验证。[永久性][cargo-publishing] |
| ZIP 部分上传或网络返回不明 | 按 release ID / asset ID / name / size / digest 和实际下载 hash 核对。已存在且相同则跳过，缺失则上传被冻结的候选；同名不同 hash 停止。不要自动 `--clobber`。 |
| Cargo 已成功，GitHub 仍 draft | 校验 registry 包及所有候选资产；补齐冻结资产和记录后公开同一 draft。没有 Cargo 回滚可以替代这一步。 |
| GitHub 已公开，Cargo 未成功 | 不再改 ZIP；只补被验收的 Cargo 版本，再完成 registry 安装验证。公开的一侧已有用户可见，必须明确记录部分完成。 |
| 两侧均成功，但 workflow 失败 | 读取远程状态并补核验 / 记录；不要重复上传或创建 Release。 |
| 已公开 immutable Release 缺资产 / 错 hash | 该版本不能追加、替换或删除资产。停止原版本修复并准备新的修复版本；不能重开草稿绕过。 |

**依据：**Cargo 上传与索引等待独立；registry index 的 `cksum` 是完整 `.crate` 的 SHA-256，下载 URL 从 index config 得到；这两项构成 registry 侧字节核对。[cargo publish][cargo-publish]、[registry index][cargo-index]。GitHub assets API 提供 `digest` / size / ID，可下载实际内容；`gh --clobber` 是先删再传，失败会丢原资产，不是安全重试。[assets API][gh-assets]、[gh upload][gh-upload]

**registry 安装验证：**发布前在原生目标做候选 `.crate` 解包安装；发布后用新的隔离 `CARGO_HOME` / install root，从明确的 crates.io registry 安装准确版本，例如 `cargo +1.100.0 install regqry --version 0.1.0 --locked --root <isolated-root>`，执行命令版本和既定冒烟用例。两原生架构分别验证，不能用已有本地安装或 `--path` 的成功冒充 registry 安装。当前 Cargo 默认采用包内 lock；仍记录实际 lock / 来源，`--locked` 不让用户项目目录的配置变成 registry 安装配置。[cargo install][cargo-install]

**immutable：**保护在 draft 公开后生效；tag、资产锁定，不能补资产，标题/正文及 prerelease/latest 标记仍可改；GitHub 会自动生成 release attestation。必须在公开前核对完整集合，并记录 immutable 设置实际已启用，不能因代码计划如此就声称已启用。[Immutable releases][gh-immutable]、[管理 Release][gh-manage]

## 7. 校验和、attestation 与 Windows 签名

| 机制 | 说明与边界 |
| --- | --- |
| SHA-256 checksum | 识别/比较具体字节；校验文件本身也须绑定受信 candidate。它不独立证明发布者身份。 |
| GitHub artifact attestation | 将 artifact hash 与 build workflow、repo、commit、environment / event 等来源声明关联；须验证才能利用。它不能证明最低系统验收通过，除非另有受信的验收声明和验证规则。[官方说明][gh-attestation] |
| immutable release attestation | 绑定最终 Release 的 tag、commit 和资产集合；由 GitHub 在 immutable 发布时产生，与构建证明不是同一个断言。[Immutable releases][gh-immutable] |
| Authenticode | Windows 代码签名证明签名发布者和签名后完整性；不是 ZIP checksum 或 GitHub attestation 的同义词。[Microsoft Authenticode][ms-authenticode] |

cargo-dist 当前内置 Windows signing 文档仍只承诺 x86_64，不能因为它能构建 ARM64 就推断能给 ARM64 签名。双架构签名若要加入须独立研究所选签名服务 / SDK / 账号资格，签名后的最终字节重新 hash 并验收；用户已将首版签名延期。[dist Windows signing][dist-signing]

### 第三方许可材料可复用现有工具

**文档与版本：**当前 cargo-about 稳定 Release 为 **0.9.3**；`generate` 可以从依赖图收集 license text / crate 对应信息，用 Handlebars 模板输出文件（默认示例为 HTML），可加 `--locked --fail`，不必自己实现许可文本收集器。[精确 Release][about-version]、[generate][about-generate]、[模板数据][about-output]

**本项目候选用法：**配置两个 Windows `targets`、与发行构建相同的 features，排除仅 dev 依赖，保留传递依赖；build-only 依赖是否列入须明确，而非默认为进入 EXE。工具当前将 targets 同时求值，可能包含单一目标实际不可达的额外组合；若要精确分别生成，可按每个目标各跑一次再核对。输出材料随候选冻结并进入两个 ZIP，核对版权 / notice 与未知许可，不拿 cargo-deny 的“允许许可证”结果替代分发材料。[配置及限制][about-config]

**推断边界：**自动生成不等于已经审阅本项目最终依赖；Cargo 图外随包携带的运行库 / SDK / 其他资产需单独核对。没有在当前尚未实现的 crate 上运行 cargo-about，也未选择模板或声明已有完整许可文件。

## 8. 用户指定参考：inclean 的实际发布流程

只读核查固定到 inclean `main` 的 **`b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b`**（提交时间 2026-11-16T16:19:38Z），不是首页缓存或将来的 main。以下为 YAML / metadata 的静态观察，没有查询其 secret 值、账号设置或证明这些 jobs 已实际运行成功。[固定提交][inclean-commit]

| 核查面 | 固定提交实际内容 |
| --- | --- |
| 版本来源 | `Cargo.toml` 为 `0.4.1` / edition 2024；没有 `rust-version` 或 rust-toolchain 文件。`pyproject.toml` dynamic version 指向 Cargo manifest；版本由人工 bump，未见自动 changelog / release PR 工具。[Cargo][inclean-cargo]、[Python metadata][inclean-python] |
| 入口与校验 | `release.yml` 监听 main push 及 `v*.*.*` tag；`check-tag` 只在 tag 运行，验证完整 SemVer 并与 Cargo version 相等。其余 jobs 通过 `needs` 依赖它，因此普通 main push 的发布链跳过。[release YAML][inclean-release] |
| CI 与构建 | tag → `verify` 调 reusable CI → `build`；CI 是 stable 工具链、Ubuntu fmt/Clippy，以及 Ubuntu/macOS/Windows tests。构建五目标 Linux/macOS 双架构、Windows 仅 x64；maturin 同时产 wheel 和原始 binary。[CI YAML][inclean-ci] |
| ZIP 与 Release | PowerShell 复制 exe、README、LICENSE 后 `Compress-Archive`；经 Actions artifact 传递，`gh-release` 用 softprops/action-gh-release 公开并生成 notes，YAML 未设长期 draft / 验收等待。没有显式 checksum、attestation、签名或 environment 审批配置。[release YAML][inclean-release] |
| 渠道依赖 / 认证 | GitHub Release 后才 `publish-crate`：Ubuntu stable、长期 `CARGO_REGISTRY_TOKEN`、`cargo publish --no-verify --locked`。PyPI 在 build/sdist 后独立用 OIDC；GH/Cargo 不等待 PyPI。GH 顶层 `contents: write`。[release YAML][inclean-release] |

**文档与实现区别：**CONTRIBUTING 确实要求人工 bump Cargo、创建并 push 同版本 tag，称三渠道一次完成；实际 YAML 是有依赖的多次远程操作，PyPI 还独立，失败可部分公开。README 泛称下载 tarball，但 Windows 实际 ZIP，与 binstall metadata 的 Windows override 一致。CONTRIBUTING 的失败后删 tag、修复再 tag 建议不覆盖 crates.io 版本永久性，也不能照搬到 immutable Release。[贡献指南][inclean-contributing]、[README][inclean-readme]、[Cargo metadata][inclean-cargo]

**可借鉴部分（推断）：**人工版本、tag 驱动、发布前复用 CI、小矩阵、现有 ZIP 命令、GitHub 后接 Cargo 的简单 job 链，与用户已选工具方向一致；无需引入 maturin/PyPI 或发布自动化框架。**本项目差别：**保留 Rust 1.100.0 pin、双原生 Windows、Windows 上验证源码包、最低系统/普通用户/干净系统证据、最终产物 hash / 许可材料、明确的部分失败恢复；不能照抄 Ubuntu `--no-verify` 后声称包已验收。参考仓库 YAML 不声明 immutable 设置，也没有单独等待候选验收的步骤；本次未审计 action 内部 API 次序，不能由未写 `draft` 推断它必然先公开再上传。具体怎样将既有验收衔接到这条简洁 tag 链，仍是方案确认项。

## 9. 实施前仍需证明的事项

1. 实际 `0.1.0` crate 清单 / lock、源码 allowlist、CLI 版本与 tag、两个架构原生 runner、固定工具安装，以及最终 DLL / CRT 行为。
2. 从候选 `.crate` 的双架构构建、最低 OS / 普通用户 / 干净系统及源码安装证据；托管 runner 成功不替代这些验收。
3. 若用 dist：审查生成 plan 和 workflow 的默认 ARM64、上传与公开阶段；若用 release-plz release：证明没有切走已选 tag SHA。以上只做了文档 / 源码审查，没有真实工具执行。
4. 首发 token 账号与 scopes、crate 名称 / ownership、后续 trusted publisher 的 workflow/environment 身份、Environment reviewer/ref 限制、Release 写权限和 immutable 设置。没有查询账户私有状态或建立这些设置。
5. 同输入归档重复性、重打包与候选逐文件等价、发布后真实包 checksum / hash，以及首发和 OIDC 两种路径。若选择更强 hash 门槛，必须验证不一致确实阻断 GitHub 公开，并正确记录已发生的 Cargo 部分发布。
6. 注入 Cargo 上传后超时、GitHub 部分上传、已成功但 job 失败、审批过期和再次 dispatch 等场景；恢复不得重建已验收产物或吞掉不一致。

## 官方来源

[dist-version]: https://github.com/axodotdev/cargo-dist/releases/tag/v0.34.0
[plz-version]: https://github.com/release-plz/release-plz/releases/tag/release-plz-v0.4.3
[plz-assets]: https://api.github.com/repos/release-plz/release-plz/releases/tags/release-plz-v0.4.3
[dist-ci]: https://axodotdev.github.io/cargo-dist/book/ci/index.html
[dist-config]: https://axodotdev.github.io/cargo-dist/book/reference/config.html
[dist-custom]: https://axodotdev.github.io/cargo-dist/book/ci/customizing.html
[dist-template]: https://github.com/axodotdev/cargo-dist/blob/v0.34.0/cargo-dist/templates/ci/github/release.yml.j2
[dist-publish]: https://github.com/axodotdev/cargo-dist/blob/v0.34.0/cargo-dist/templates/ci/github/partials/publish_github.yml.j2
[dist-ci-code]: https://github.com/axodotdev/cargo-dist/blob/v0.34.0/cargo-dist/src/backend/ci/github.rs
[dist-runners]: https://github.com/axodotdev/cargo-dist/blob/v0.34.0/cargo-dist/src/platform/github_runners.rs
[dist-signing]: https://axodotdev.github.io/cargo-dist/book/supplychain-security/signing/windows.html
[plz-update]: https://release-plz.dev/docs/usage/update
[plz-release]: https://release-plz.dev/docs/usage/release
[plz-binaries]: https://release-plz.dev/docs/extra/releasing-binaries
[plz-config]: https://github.com/release-plz/release-plz/blob/release-plz-v0.4.3/website/docs/config.md
[plz-semver]: https://release-plz.dev/docs/semver-check
[plz-auth]: https://release-plz.dev/docs/github/quickstart
[cargo-publish]: https://doc.rust-lang.org/cargo/commands/cargo-publish.html
[cargo-publishing]: https://doc.rust-lang.org/cargo/reference/publishing.html
[cargo-package]: https://doc.rust-lang.org/cargo/commands/cargo-package.html
[cargo-install]: https://doc.rust-lang.org/cargo/commands/cargo-install.html
[cargo-prerelease]: https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html#pre-releases
[cargo-api]: https://doc.rust-lang.org/cargo/reference/registry-web-api.html#publish
[cargo-index]: https://doc.rust-lang.org/cargo/reference/registry-index.html
[cargo-provider]: https://doc.rust-lang.org/cargo/reference/credential-provider-protocol.html
[cargo-auth]: https://doc.rust-lang.org/cargo/reference/registry-authentication.html
[rust-cargo]: https://github.com/rust-lang/rust/tree/1.100.0/src/tools/cargo
[cargo-package-code]: https://github.com/rust-lang/cargo/blob/3acc79c0c841844675bc53a605922dbfc441e750/src/ops/cargo_package/mod.rs
[cargo-publish-code]: https://github.com/rust-lang/cargo/blob/3acc79c0c841844675bc53a605922dbfc441e750/src/ops/registry/cargo_publish.rs
[crates-trust]: https://github.com/rust-lang/crates.io/blob/main/svelte/src/routes/docs/trusted-publishing/%2Bpage.svelte
[crates-auth-action]: https://github.com/rust-lang/crates-io-auth-action
[gh-create]: https://cli.github.com/manual/gh_release_create
[gh-upload]: https://cli.github.com/manual/gh_release_upload
[gh-edit]: https://cli.github.com/manual/gh_release_edit
[gh-trigger]: https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow
[gh-events]: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch
[gh-environments]: https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
[gh-limits]: https://docs.github.com/en/actions/reference/limits
[gh-releases]: https://docs.github.com/en/rest/releases/releases
[gh-assets]: https://docs.github.com/en/rest/releases/assets
[gh-immutable]: https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases
[gh-manage]: https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
[gh-attestation]: https://docs.github.com/en/actions/concepts/security/artifact-attestations
[ms-authenticode]: https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode
[about-version]: https://github.com/EmbarkStudios/cargo-about/releases/tag/0.9.3
[about-generate]: https://embarkstudios.github.io/cargo-about/cli/generate/index.html
[about-config]: https://embarkstudios.github.io/cargo-about/cli/generate/config.html
[about-output]: https://embarkstudios.github.io/cargo-about/cli/generate/output.html
[inclean-commit]: https://github.com/inaku-Gyan/inclean/commit/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b
[inclean-release]: https://github.com/inaku-Gyan/inclean/blob/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b/.github/workflows/release.yml
[inclean-ci]: https://github.com/inaku-Gyan/inclean/blob/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b/.github/workflows/ci.yml
[inclean-cargo]: https://github.com/inaku-Gyan/inclean/blob/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b/Cargo.toml
[inclean-python]: https://github.com/inaku-Gyan/inclean/blob/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b/pyproject.toml
[inclean-contributing]: https://github.com/inaku-Gyan/inclean/blob/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b/CONTRIBUTING.md
[inclean-readme]: https://github.com/inaku-Gyan/inclean/blob/b2b74dd439fd178bfb9e5ac3d1b58baa0212f29b/README.md
