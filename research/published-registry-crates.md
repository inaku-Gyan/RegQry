# 已发布 Rust 注册表库的保真与遍历能力

研究日期：2026-11-19。基线：`main` 的 `34e02fa1a021689a61c059172737a53994180d1e`。本报告只研究本机只读查询（read-only query），不选择最终依赖，也不提供产品实现。

已读主工作树工单 01 / 02 / 04 / 07 / 16 的当前 Answer、22 的问题与根词汇表。当前契约是统一 `regqry [QUERY OPTIONS]`，没有独立查看入口；保留原始类型码、原始值数据（Raw Value Data）、异常名称身份和逐项失败，分别处理所选注册表视图（Registry View）。键查询不因便利接口强制变成值查询。x64 与原生 ARM64 的 32 / 64 视图仍须分别验收。

下文标记含义：**事实**是发布归档源码或注明适用范围的第一方文档；**推断**是由它们导出的工程后果；**候选**是供后续决策的已有库组合；**未验证**不是支持保证。本次没有调用注册表读取、写入、创建、删除或权限修改 API，也没有运行会创建测试键的上游测试。

## 1. 交付结论与能力矩阵

**事实：** `winreg` 0.56.0 不能通过 `RegValue` 保留大于 11 的类型码；但它已经提供 `OsStr` / `OsString`、逐项 `Result`、显式权限和 `REG_OPTION_OPEN_LINK`。可以保留这些能力，在借用的 `raw_handle()` 上仅补原始值枚举 / 读取，毋须重造整套注册表库。[打开与句柄源码][w-open]、[读取源码][w-read]、[枚举源码][w-enum]。

**事实：** `windows-registry` 0.100.0 的 `Type::Other(u32)` 和字节存储可表达未知类型；但其发布版名称枚举仍是有损 `String`，逐项错误仍可能表现为迭代结束。此前主分支观察现已由实际发布归档确认。[类型源码][r-type]、[键迭代][r-keys]、[值迭代][r-values]。

**推断：** 两个便利封装都不能原封不动满足整个契约。缺口可以由同一 Windows 绑定库补齐；“复用已有库”和“写少量 Win32 适配”可以同时成立。下表的“有”表示接口可表达，不代表已经完成本项目 Windows 集成验收。

| 能力 | `winreg` 0.56.0 | `windows-registry` 0.100.0 | `windows` 0.62.2 / `windows-sys` 0.61.2 |
| --- | --- | --- | --- |
| 任意原始 `u32` 类型码 | **缺口**：读取和枚举对 `> REG_QWORD` 返回 `ERROR_BAD_FILE_TYPE` | 有：`Other(u32)`，可无损转换回 `u32` | 有：公开 `REG_VALUE_TYPE(pub u32)` / `type = u32` |
| 原始数据字节 | 已知类型可保留；未知类型整项无法返回 | 有；稳定数据下 `Value` 保留字节，变更竞争见第 4 节 | 有：调用者保存成功调用的实际长度与字节 |
| 异常 UTF-16 键 / 值名 | 有 `OsString` 路径；**值名长度另有缺口** | 常规路径只接受 `str`；两种枚举均 `from_utf16_lossy`；原始值名输入可用 `PCWSTR` | 有 `W` 接口，可使用原始 `u16` 缓冲区 |
| 逐项错误 | `Option<io::Result<_>>`；仅 `NO_MORE_ITEMS` 正常结束 | 初始化是 `Result`；迭代项没有 `Result`，非零状态变为 `None` / debug 断言 | 原始状态完整暴露；需把结束与失败分开 |
| 显式 32 / 64 视图 | `*_with_flags` 加 WOW64 标志 | `wow64_32` / `wow64_64`，也可 `access(u32)` | `samDesired` 可显式传标志 |
| 最小读取权限 | 自选 flags；普通 `open_subkey` 请求较宽的 `KEY_READ` | 新 `options().access(...)` 可自选；`open()` 请求 `KEY_READ` | 可自选；操作需求见第 6 节 |
| 打开链接源 | 已有 `open_subkey_with_options_flags(..., OPEN_LINK, ...)` | 普通 open 的选项固定为 0；须组合直接绑定 | 有 `RegOpenKeyExW` 和选项常量 |
| 准确 `is_link` / 整条路径 no-follow | 没有独立判断 / 策略 API | 没有独立判断 / 策略 API | Win32 绑定本身也不提供独立 `is_link`；见第 7 节 |
| 子键时间且不增加值读取权 | `query_info` 需要 `KEY_QUERY_VALUE`；现有子键枚举不返回时间 | 未暴露键时间查询；迭代初始化先调 `RegQueryInfoKeyW` | `RegEnumKeyExW` 可连同子键名取得时间，只需父键枚举权 |
| 句柄所有权 | `RegKey` 的 `Drop`；借用 `raw_handle()` | `Key` 的 `Drop`；借用 `as_raw()` / 接管 `from_raw()` | `windows::HKEY` 可配现有 `windows_core::Owned<HKEY>`；sys 仅原始句柄 |

矩阵实现依据是上述封装源码及两个绑定的精确版本模块。[`windows` 注册表模块][b-win]、[`windows-sys` 注册表模块][b-sys]、[`windows-core` 所有权包装][b-owned]。

## 2. 实际发布物与复核方法

**事实：** 本次从 `static.crates.io` 下载下表归档，在研究 worktree 的忽略目录 `.scratch/evidence/` 解包；每个归档的 SHA-256 均与 `crates.io/api/v1/crates/<name>/<version>` 返回的 `version.checksum` 相等，查询时均未 yanked。版本是下表固定版本，不以 `latest` 页面或 GitHub 主分支替代。

| 发布包 | 发布日期（UTC） | 归档声明的最低 Rust 版本（MSRV） | 归档记录的 VCS 提交 |
| --- | --- | --- | --- |
| [`winreg` 0.56.0][pkg-w] | 2026-03-14 | 1.60 / edition 2021 | `d14c8bd6758810ec679533ac4dc7b0420f598d23` |
| [`windows-registry` 0.100.0][pkg-r] | 2026-09-03 | **1.95 / edition 2024** | `a57cc321bfdbac6bb98c488ba49f399da8fcb98a` |
| [`windows-registry` 0.6.1][pkg-r6]（对照） | 2025-10-06 | 1.82 / edition 2021 | `32c3144490c016fe496a0aed769bce60987a2e9d` |
| [`windows` 0.62.2][pkg-bw] | 2025-10-06 | 1.82 / edition 2021 | `32c3144490c016fe496a0aed769bce60987a2e9d` |
| [`windows-sys` 0.61.2][pkg-bs] | 2025-10-06 | 1.71 / edition 2021 | `32c3144490c016fe496a0aed769bce60987a2e9d` |
| [`windows-core` 0.62.2][pkg-bc]（现有所有权工具） | 2025-10-06 | 1.82 / edition 2021 | 与上述绑定同批源码 |

日期 / 校验值来自固定版本 metadata：[winreg][meta-w]、[registry 0.100.0][meta-r]、[registry 0.6.1][meta-r6]、[windows][meta-bw]、[sys][meta-bs]、[core][meta-bc]；MSRV 与 VCS 来自对应归档的 `Cargo.toml` / `.cargo_vcs_info.json`。`winreg` 声明的 `windows-sys` 范围是 `>=0.59, <=0.61`；可与 0.61.2 共用依赖。0.100.0 的 MSRV 增长是实际发布物的差异，不能从 0.6.1 推断新版本仍支持 Rust 1.82。[`winreg` manifest][w-manifest]、[0.100.0 manifest][r-manifest]、[0.6.1 manifest][r6-manifest]。

| 归档 | 已核对 SHA-256 |
| --- | --- |
| `winreg-0.56.0.crate` | `7d6f32a0ff4a9f6f01231eb2059cc85479330739333e0e58cadf03b6af2cca10` |
| `windows-registry-0.100.0.crate` | `a14b75dbbc0f2bb1ebbf6dcb6dc0035ae17f10ec280045d10fa27ad8874903b2` |
| `windows-registry-0.6.1.crate` | `02752bf7fbdcce7f2a27a742f798510f3e5ad88dbe84871e5168e2120c3d5720` |
| `windows-0.62.2.crate` | `527fadee13e0c05939a6a05d5bd6eec6cd2e3dbd648b9f8e447c6518133d8580` |
| `windows-sys-0.61.2.crate` | `ae137229bcbd6cdf0f7b80a31df61766145077ddf49416a728b02cb3921ff3fc` |
| `windows-core-0.62.2.crate` | `b8e83a14d34d0623b51dce9581199302a221863196a1dde71a7663a4c2be9deb` |

为使报告可在线复核，又下载 VCS 提交的原始文件与归档作逐字节 SHA-256 比较：winreg 的 `reg_key.rs` / `common.rs` / `enum_values_os_string.rs`；0.100.0 的 `key.rs` / 两种 iterator / `open_options.rs` / `type.rs`；两种绑定的 Registry 模块；core 的 `handles.rs`，11 项全部相等。以下 GitHub 引用均固定在这些发布提交；其他文件直接引用固定版本的发布源码。归档、metadata 与下载的比对副本均留在忽略目录，不作为额外交付文件提交。

## 3. `winreg` 0.56.0：已有优势与局部缺口

**源码事实：**

- `open_subkey_with_options_flags` 接受 `AsRef<OsStr>`、options、permissions，并直接调用 `RegOpenKeyExW`；`raw_handle()` 返回借用中的底层句柄。`Drop` 关闭所拥有的普通句柄，预定义根另作处理。`RegKey` 未实现 `AsRawHandle` / `FromRawHandle` / `IntoRawHandle`；这些 trait 在包中出现在 `Transaction`，不能移植为 `RegKey` 的 API 承诺。[打开 / 句柄][w-open]、[关闭][w-close]、[发布包 transaction 源码][w-transaction]。
- `enum_keys_os_string` / `enum_values_os_string` 的项带 `io::Result`；错误后迭代索引仍前进。底层 `ERROR_NO_MORE_ITEMS` 才产生 `None`。子键枚举使用 `OsString::from_wide`，输入名称以 `encode_wide` 加末尾 NUL 编码，不经过 `String`。Rust 标准库明确保证该 `OsString` 往返保留不合法 UTF-16 代码单元（code units）。常规 `String` 枚举在转换失败时报 `ERROR_INVALID_DATA`，并不具备这种原始身份能力。[枚举][w-enum]、[OsString 迭代][w-os-iter]、[名称编码][w-common]、[Rust 保真保证][rust-os]。
- `get_raw_value` / `enum_value` 得到字节后，先拒绝 `buf_type > REG_QWORD`，再构造 `RegType`。因此未知类型既不能假装成 `REG_NONE`，也不能通过捕获这一错误取得已被封装丢弃的字节 / 类型 / 名称。`RegValue` 的类型字段不是原始 `u32`。[原始读取][w-read]、[值枚举][w-enum]、[RegValue][w-value]。
- 原始单值读取从 2048 字节开始，在 `ERROR_MORE_DATA` 时增加数据容量；没有产品级的重试次数、累计内存、取消或截止时间参数。名称枚举另是固定 `[u16; 2048]`。子键名的这一区间覆盖文档规定的普通键名长度；**值名可有 16,383 字符，不能据此保证全部合法值名都能枚举**。[读取][w-read]、[枚举][w-enum]、[官方长度限制][ms-limits]。
- `enum_value` 遇 `ERROR_MORE_DATA` 只执行 `name_len += 1` 与数据 `reserve`，不增长名称数组；后续调用也未把声明的名称容量重新设回数组实际容量。这是发布源码中的容量处理缺口。此处未运行长名称写入或复现，不给它编造实测错误码、无限循环或内存破坏结果。[精确代码][w-enum]。

**输入边界：** 保留异常 UTF-16 不等于可以把内嵌 NUL 直接交给这些 Win32 路径 / 值名输入。winreg 的转换只是追加终止 NUL，未拒绝既有 NUL；Microsoft wrapper 的 `pcwstr` 也只是编码并追加 NUL。适配层仍需落实已定“实际内嵌 NUL 报输入错误”，避免被系统当成另一个较短名称。这是产品输入验证，不是新造名称编码格式。[winreg 转换][w-common]、[0.100.0 名称转换][r-pcwstr]。

**推断 / 最小适配候选：** 沿用 `RegKey` 打开、视图、权限、链接选项和生命周期；在其 `raw_handle()` 上借用调用 `RegEnumValueW`，返回原始 `u16` 名称、`u32` 类型和实际字节，可一次补齐未知类型、长值名和原始错误语义。需要点查默认值时用 `RegQueryValueExW` 补原始读取；如果键时间要避免 `KEY_QUERY_VALUE`，再补带时间的 `RegEnumKeyExW`。这些是几个系统调用的边界适配，不是重写键打开、资源管理或通用文本解码。

## 4. `windows-registry` 0.100.0，并与 0.6.1 对照

**源码事实：** `Type::Other(u32)` 保留所有未匹配类型，包括已知但没有专门 variant 的 `REG_NONE`、`REG_LINK`、大端 DWORD、资源类型，以及超出标准集合的类型码；`From<Type> for u32` 能还原。`Value` 提供 `AsRef<[u8]>` / `Deref<Target=[u8]>`。不要把 `Type::Other` 误解释为“数据读取失败”。[类型][r-type]、[Value][r-value]。

**源码事实：** 常规 open / 名称参数是 `AsRef<str>`。键和值迭代返回 `String`，均使用 `from_utf16_lossy`。原始单值接口 `raw_get_info` / `raw_get_bytes` 接受 `AsRef<PCWSTR>`，故可为一个已知的异常 UTF-16 值名构造有末尾 NUL 的原始输入；它不补出无损键路径或无损名称枚举。[Key][r-key]、[两种迭代][r-keys]、[值迭代][r-values]。

**源码事实：** 两个迭代器初始化时先用 `RegQueryInfoKeyW` 取初始 count / 最大长度，固定 `range = 0..count` 和缓冲区。`next()` 中非零状态只做 `debug_assert_eq!(..., ERROR_NO_MORE_ITEMS)` 并返回 `None`。没有 `ERROR_MORE_DATA` 重试，没有逐项 `Result`；release 中访问失败 / 缓冲区不足可能让通常的 `for` / `collect` 提前停止，debug 中则可能断言失败。初始化错误能返回给调用者，不代表迭代中错误也能返回。[键迭代][r-keys]、[值迭代][r-values]。

**源码事实与推断：**

- `get_value` 先获取 `(ty, len)`，按该长度分配，再调用 `raw_get_bytes`，但忽略后者回传的实际类型和切片。源码因此在两次调用之间缩短 / 改型的竞争下，可能保留先前类型或原分配长度中的补零尾部。增长通常返回 `ERROR_MORE_DATA`，高层没有重试。此为静态源码推断，未模拟并发变更。对保真读取，可复用 `raw_get_bytes` 并使用它返回的**成功调用实际类型与切片**；`MORE_DATA` 后重新取长度 / 重试，由适配层设资源边界。[`get_value` 与原始方法][r-key]、[Data 初始化][r-data]。
- 新 `options()` 的 access 起点为 0；使用 `.access(required_bits)` 可避免 `.read()` 额外请求 `KEY_READ` 的全部权利。0.100.0 的 `wow64_32` / `wow64_64` 会清掉另一标志，最后一次调用生效；这不是产品“重复视图取并集”的实现，后者仍要分别打开两遍。普通 open 对 `RegOpenKeyExW` 的 options 硬编码 0；`.volatile()` 等字段用于 create 路径，不能充当 OPEN_LINK。[OpenOptions][r-open]。
- `as_raw()` 借用句柄；`unsafe from_raw()` 明确接管调用者拥有且能被 `RegCloseKey` 关闭的句柄。没有借用 raw 句柄构造 `Key` 的公开方法。补 OPEN_LINK 可用现有绑定打开新的 owned 句柄后交给 `from_raw()`，或只在 `as_raw()` 上做借用调用；不能把另一个 wrapper 的 borrowed 句柄直接交给会 Drop 的 `from_raw()`。[所有权][r-key]。

**0.6.1 对照事实：** 已另取实际归档。它有相同的 `Other(u32)`、字节存储、`PCWSTR` 原始读取，以及相同的有损名称 / 非 `Result` 迭代结构；没有 0.100.0 新增的两个 `wow64_*` 便利方法，但已有 `.access(u32)`，可以传 WOW64 位。因此“没有便利方法”不等于“不能显式选视图”。降到 0.6.1 可改变 MSRV，不能消除名称和遍历错误缺口。[0.6.1 OpenOptions][r6-open]、[0.6.1 键迭代][r6-keys]、[0.6.1 值迭代][r6-values]。

## 5. 直接绑定也能复用现成所有权工具

**发布源码事实：** `windows` 0.62.2 的 `RegEnumValueW` 类型输出直接为 `*mut u32`，`RegQueryValueExW` 为 `*mut REG_VALUE_TYPE`，后者公开包裹 `u32`；`windows-sys` 0.61.2 使用 `REG_VALUE_TYPE = u32`。两者均提供 `W` 名称指针、显式长度、options、access 和原始返回状态，能表达异常名称、未知类型与逐项错误。它们不负责索引循环、缓冲区重试或结果完整性。[类型化模块][b-win]、[sys 模块][b-sys]。

**发布源码事实：** `windows::HKEY` 是 `Copy` 类型，没有自身 `Drop`，但已实现 `windows_core::Free`，其释放函数是 `RegCloseKey`；`windows_core` 0.62.2 已有 `Owned<T: Free>`，`unsafe Owned::new` 接管 owned 句柄并在 Drop 调 Free。因此不能把“直接 windows 绑定”描述为必须自写所有 RAII。预定义根和借用句柄不交给这个 owning 包装；对于 sys 原始 `*mut c_void` 则没有相同的 Free 实现。[HKEY][b-hkey]、[Owned][b-owned]。

**候选：** 若选直接 `windows`，可复用 `Owned<HKEY>` 并把适配限于需要的少数只读操作。它补的通用循环比 winreg 组合多；是否值得换取统一底层类型，是后续取舍。没有基准或实现成本测量可证明其整体优于便利封装组合。

## 6. 权限、视图、动态缓冲区与并发

**Win32 文档事实：**

| 必要操作 | 文档所需权利 | 对 key-only 查询的意义 |
| --- | --- | --- |
| `RegEnumKeyExW` | 父键 `KEY_ENUMERATE_SUB_KEYS` | 可直接返回该子键名及其 `FILETIME`；不必先读子键值 |
| `RegEnumValueW` / `RegQueryValueExW` | `KEY_QUERY_VALUE` | 值候选、默认值存在性或按值识别疑似链接时需要 |
| `RegQueryInfoKeyW`，含只查询时间 / 计数 | `KEY_QUERY_VALUE` | 不能声称它仅需枚举权 |
| `KEY_READ` | 含 `STANDARD_RIGHTS_READ`、QUERY、ENUMERATE、NOTIFY | 比“枚举子键”或“查询值”单项更宽 |

来源：[子键枚举][ms-enum-key]、[值枚举][ms-enum-value]、[原始读取][ms-query]、[键元数据][ms-info]、[访问权定义][ms-rights]。打开时请求的权利还须通过目标键 ACL；父键打开成功不保证子键可读。只读行为来自实际调用面；仅有 `KEY_READ` 句柄并不阻止所有安全描述符允许的创建操作。[RegOpenKeyExW 说明][ms-open]。

**推断：** 如果只查询键或按键时间过滤，父键的枚举结果已能给出后代键时间。沿用 winreg 并补带时间枚举，可以避免为了时间在每个子键上追加 `KEY_QUERY_VALUE`。但“每个键都要读 `SymbolicLinkValue` 以分类链接”的策略会重新引入 query 权限；这是策略成本，不能称为所有 key-only 查询的最低权限。值结果所属键本来需要 query 时，可使用 `query_info()`。

**Win32 文档事实：** WOW64 标志在后续每次子键 open 都应继续显式传入；同时设 32 / 64 位标志是错误，扫描两视图应分两遍，共享键不会因此变成两份物理存储。原生 ARM64 的 32 标志访问 x86 32 位视图，不能外推历史 ARM32。便利库都不替递归策略保持这项产品身份。[替代视图][ms-view]。

**Win32 文档事实：** 枚举按索引且顺序无保证，`ERROR_NO_MORE_ITEMS` 是正常结束，`ERROR_MORE_DATA` 是容量不足；名称长度以 UTF-16 单元计，数据以字节计，调用前的容量须含名称终止符。`RegQueryValueExW` 的成功长度包含实际保存的终止符；字符串可能根本没有终止符。`RegGetValueW` 会尝试补字符串终止符，且默认可展开环境变量，因此它不是原始存储字节读取的替代。[枚举键][ms-enum-key]、[枚举值][ms-enum-value]、[原始读取][ms-query]、[便利读取][ms-get]。

**适配候选，未实现：** 预查最大长度仅作初始容量提示；对同一索引的 `MORE_DATA` 增长真正的缓冲区后重试，每次调用将输入长度重置为实际容量；成功才提交返回的类型 / 名称 / 数据长度。对名称长度无可靠需求值的错误可重新查最大长度或有界增长，不能相信未成功调用填充的内容。只有 `NO_MORE_ITEMS` 当结束，其余错误保留操作、逻辑身份 / 视图 / 索引并使查询不完整。资源上限、取消和重试耗尽应显式失败，不能成功截断。

**边界：** 这种循环修复容量处理，不建立一致快照（consistent snapshot）。外部进程增删可能改变索引，初始 count 不是稳定上限；两次读取也不能拼成一个原子观测。文档要求应用在枚举期间不要修改该键，但没有承诺阻止其他进程变更。后续测试应记录并发行为，不把所有变更都伪装成能检测到的遗漏。[枚举说明][ms-enum-key]、[值枚举说明][ms-enum-value]。

## 7. 符号链接：打开源、识别与 no-follow 的不同保证

### 7.1 可引用的官方边界

**Win32 文档事实：** `RegOpenKeyExW` 提供 `REG_OPTION_OPEN_LINK`，但其公开页面没有给出“整条路径所有组件都不解析链接”的承诺。两个直接绑定和 winreg 都能传该选项；windows-registry 的普通 open 不能传。[Win32 打开][ms-open]、[winreg 打开][w-open]。

**协议文档事实，适用范围是 MS-RRP：** §3.1.1.11 与 BaseRegOpenKey 明确区分链接源和目标；不指定 OPEN_LINK 时服务器跟随目标，指定时打开源；源键的 `SymbolicLinkValue` 为 `REG_LINK`，目标使用对象名称，链接源不得有子键。协议支持链接链，深度限制是 SHOULD。它不是本项目所有本机 Win32 行为的独立实测证明。[MS-RRP 链接][rrp-link]、[BaseRegOpenKey][rrp-open]。

**官方文档差异：** Win32 的类型表把 REG_LINK 描述为带终止符的 Unicode 目标路径；MS-RRP 则要求 `SymbolicLinkValue` 目标不带终止 NUL。原始读取必须保留实际字节，不能任选一条说明来“修复”数据；未来解释链接目标须单列规则。[Win32 类型表][ms-types]、[MS-RRP][rrp-link]。

### 7.2 `SymbolicLinkValue` 不能当独立 `is_link` 标志

**事实：** 在所检查的 Win32 注册表 API 和两个 wrapper 中未找到公开独立的 `is_link` / key-type 属性。MS-RRP 描述的是“键具有 symbolic-link KEYTYPE，然后读取特定值”，不是“只要看到这个值就一定具有该 KEYTYPE”。它的 SetValue 规则限制真正链接源的值名，却未建立普通键不可能拥有同名同类型值的逆命题。[BaseRegOpenKey][rrp-open]、[BaseRegSetValue][rrp-set]。

**补充源码证据，非 Microsoft 保证：** Wine 10.0 自己的 Windows 兼容性回归测试在普通目标键上写入名为 `SymbolicLinkValue` 的 `REG_LINK` 并期望成功，明确覆盖这种相似外观。本次只读取其固定版本测试源码，没有运行写入测试。该测试可以反驳“仅凭名字 / 类型足够”的设计假设，不能冒充本项目在两种 Windows 架构上的验证。[Wine 10.0 原始测试，2646–2655 行][wine-lookalike]。

**推断：** 读取该值可报告“符合链接元数据外观”，不能证明实际键类型；缺失 / 拒绝访问也不证明非链接。协议把创建链接源和设置该值分为两个动作，初始化或并发窗口也不能由一次读取排除。要求“显式 root 经过或本身是实际链接时必然准确退出 2”，比“从不主动打开目标”要求更强，当前证据不足以兑现前者。

### 7.3 最终组件、中间组件与逐组件候选

**推断 / 保守边界：** 对 `Root\A\B` 一次调用 OPEN_LINK，不能由已检索的官方文档证明中间组件 A 也未被跟随。仅最终 B 是本次打开的键；“选项是整条路径的 no-follow”不应成为实现前提。稳妥的工程候选是持有父句柄，每次仅打开一个原始名称组件，并在每次 open 传相同视图与 OPEN_LINK。

| 场景 | 现有接口能做什么 | 仍不能据文档声称什么 |
| --- | --- | --- |
| 遍历中枚举到一个直接子键 | 以单组件 OPEN_LINK 打开，再只在该句柄上枚举名称 / 值，不解析 `SymbolicLinkValue` 目标 | 不因此获得准确 `is_link`；本机源枚举和竞争边界仍待测试 |
| 显式 root 的最终组件 | 同样能请求源句柄 | 不靠一个特殊值就可靠区分普通叶键 / 链接源，不能自动承诺专门 link 诊断 |
| 显式 root 的中间组件 | 可拆成一次一个组件 | 不应在无法确定的疑似源句柄上继续打开后缀，然后宣称整个寻址已证明不重解析；该相对打开边界尚未核实 |
| 预定义 HKCU / HKCC / HKCR | 从文档化逻辑根与所选视图开始 | 不把 no-follow 描述为绕过这些逻辑根映射或 HKCR 合并，也不推断物理 hive 身份 |

**候选 A：只观察源。** 始终对单组件请求 OPEN_LINK，保持已打开句柄，不用普通 open 重新打开同一路径，也不解析 / 打开目标。对实际链接，按 MS-RRP 的源不得有子键，递归自然止于源。它减少了对准确分类的依赖；但要把这当本机 Windows 的产品保证，必须测试源上的枚举以及显式多组件 root 的中途终止，不能以协议代替本机验收。

**候选 B：保守停止。** 若 root 组件具有链接元数据外观、无法完成分类或无法继续确定安全寻址，就诊断失败并停止该 root，继续其他范围。它可以支持“无法确定则不进入”的规则，但普通键仿同名值可能被拒绝，且会额外需要值查询权。诊断应说明无法确定 / 不支持的寻址，不谎称已经证实实际链接。是否接受这种误拒绝与权限成本，是用户决策。

**未验证：** 没有凭本次材料找到既保证准确识别所有本机链接、又不增加接口 / 平台依赖的完整方案。Native API / 未文档化 key flags 也未在此研究成正式候选，不用它们暗中填补 Win32 保证。

### 7.4 防环证明的条件

**推断：** 若每条遍历边都由已持有源句柄的单组件 OPEN_LINK 获得，且源枚举不会越过链接目标，则在固定、有限的普通注册表层级中不会加入链接回边，因而不需要靠目标路径去重防链接环。这是基于明确前提的证明，不是已完成集成测试的结论。

反之，普通 open 的递归可出现 `A\back -> A`：每次跟随只解析有限链，但 walker 反复得到 `A\back\back...`。操作系统的单次链接链深度限制不保证整次递归终止；按不断增长的完整逻辑路径去重也不能证明防环。若决定跟随目标，需要可靠的目标身份 / 祖先检查或可解释的有界遍历策略。只加深度 / 工作量上限可以保证停机，触发时必须报告不完整，不能声称完整扫描。[协议的链规则][rrp-link]。

即便 no-follow 消除了固定树中的链接回边，外部进程持续增加对象仍可能延长查询；资源 / 取消规则与链接策略分开处理。

## 8. 补充：原始名称的大小写比较与多 root 去重

**文档与发布源码事实：** 注册表键 / 值名不区分大小写；`CompareStringOrdinal(..., TRUE)` 接收 UTF-16 指针及显式长度，以操作系统大写表进行非语言的 ordinal 比较。`windows` 0.62.2 已提供 `&[u16]` 绑定，sys 0.61.2 提供原始绑定，无须另造通用 Unicode 比较库。[注册表结构][ms-structure]、[值名规则][ms-value-name]、[CompareStringOrdinal][ms-compare]、[精确版本绑定][b-compare]。

**证据限制：** 注册表公开文档没有指定它的所有名字等价规则恰好等于 `CompareStringOrdinal(TRUE)`。该函数页面也没有单独承诺任意不合法 UTF-16；Microsoft 的一般 surrogate 文档把孤立代理代码点的行为列为 undefined。因此不能把“可传原始缓冲区”升级成“已文档化地复现注册表对所有异常代码单元的身份比较”。[ordinal 算法][ms-compare-algo]、[surrogate 边界][ms-surrogates]。

**候选 / 待决：** 对正常 UTF-16 名称，可选现有 OS ordinal 比较为产品规则；异常名称仍保留原始 `u16`，不要先 `to_lowercase`、Unicode case folding、规范化或有损替换后再去重。对异常序列采用逐单元相等的保守不合并规则，会保留更多结果而不是错误合并不同身份，但大小写不同的异常名称可能重复；是否接受须明示。也可进一步核实 Native 字符串比较，但本次未证明它与所有注册表查找一致。上述比较只需要名称数据，可作为独立小适配，不让 query 依赖真实注册表句柄。本次没有运行名称比较或异常名称的宿主探针。

## 9. 既有库组合与尚未覆盖的缺口

以下是候选，未作最终选择。所有组合都仍要由产品层负责实时遍历、多个 root 的逻辑身份、筛选语义、继续可读范围、取消与完整性；这些不是某个 wrapper 缺少一个方法后就应重写的通用能力。

| 候选 | 复用的已有能力 | 最小必要适配面 | 留下的边界 / 代价 |
| --- | --- | --- | --- |
| **`winreg` 0.56.0 + `windows-sys` 0.61.2** | `RegKey` 所有权、OsStr 打开、OPEN_LINK、权限 / 视图、无损子键枚举、query_info | 借 `raw_handle()` 做动态 `RegEnumValueW` + `RegQueryValueExW`；若 key-only 时间需最小权限，再做带 FILETIME 的 `RegEnumKeyExW` | wrapper 的值枚举不能作为兜底后再从错误恢复丢失名称；链接分类 / root 中间组件与名称等价仍待解决 |
| **`windows-registry` 0.100.0 + 同一直接绑定** | `Key` 生命周期、`Type` / `Value`、PCWSTR 原始读取、access / view | 替换两种名称枚举以保原始 UTF-16 / 错误并动态重试；直接 OPEN_LINK；时间查询；原始读取使用实际类型 / 切片 | 接触的直接调用面更大；MSRV 1.95；`get_value` 并发边界不能忽略 |
| **`windows-registry` 0.6.1 + 同一直接绑定** | 同类类型 / 字节和所有权，MSRV 1.82 | 上一行缺口；视图用既有 `.access()` 传标志 | 降版本不修遍历 / 名称问题；需重新验收具体版本 |
| **`windows` 0.62.2 + `windows_core::Owned<HKEY>`** | Microsoft 已发布 Win32 类型 / 函数 / 常量及现成 RAII | 仅本项目需要的 open / enum / query 循环、状态 / UTF-16 / 缓冲区适配 | 比 winreg 组合承担更多循环；不是自动完成安全遍历和异常解释 |

**组合约束：** 同一个底层 HKEY 只有一个 owning wrapper；借用调用不得越过其寿命，也不得对同一 handle 二次 Drop。Rust 文档明确说明 `std::os::windows::io::OwnedHandle` 使用 `CloseHandle`，不能用于需要 `RegCloseKey` 的注册表键。本报告不建议同时套两种 owning registry wrapper 来节省一个查询函数；可以在一个 owner 下借用现成绑定。[winreg 释放][w-close]、[Key 所有权][r-key]、[HKEY Free][b-hkey]、[Rust OwnedHandle][rust-owned-handle]。

## 10. 已完成的核对与后续验收清单

**已完成：** 6 个固定版本归档下载及 crates.io checksum / 未 yanked 核对；对应 manifest 和 VCS 信息；11 个关键源文件与不可变上游链接逐字节相等；两个 windows-registry 发布版的接口 / 枚举差异比较；Microsoft Win32 / 协议文档核对。只产生这一份可提交报告；未安装产品依赖，未编写或运行产品实现。

**尚未验证，应在有明确测试键授权的后续集成阶段完成：**

1. 原始类型 `0`、`11`、`12`、`u32::MAX`；缺失默认值、零字节、奇数字节字符串、缺终止符、不合法 UTF-16 数据；读取成功项的真实字节 / 类型一致性。
2. 2047 / 2048 / 16383 单元值名和异常 UTF-16 键 / 值名；验证适配有真实容量增长，错误不会变成结束，身份不会被替换。
3. 子键 / 值枚举途中访问失败、删除和长度增长；缩短 / 改型竞争；重试 / 内存上限和取消；保留已输出结果同时报告未完成。
4. 仅 `KEY_ENUMERATE_SUB_KEYS` 的普通用户 key-only + 时间路径；query 权限被拒时仍能读取的范围；链接探测增加权限的实际影响。
5. 普通键、真正链接、同名 REG_LINK 外观、断链、未初始化源、链与环；显式 root 的每个中间 / 最终组件；始终持有源句柄时的枚举和相对打开行为。准确链接诊断与 no-follow 行为分别验收。
6. x64 Windows 10 22H2 / Windows 11 与原生 ARM64 Windows 11 24H2+ 各自的两个承诺视图、共享键与逻辑根；不能由本机源码阅读推成全平台通过。
7. 正常与异常 UTF-16 名称的 OS 比较 / 去重边界，记录 OS build 和比较规则；不能用若干样本推成等价于全部注册表查找。

这些是后续验证事项，不是本研究执行写入的授权，也不改变现有只读产品范围。

[pkg-w]: https://static.crates.io/crates/winreg/winreg-0.56.0.crate
[pkg-r]: https://static.crates.io/crates/windows-registry/windows-registry-0.100.0.crate
[pkg-r6]: https://static.crates.io/crates/windows-registry/windows-registry-0.6.1.crate
[pkg-bw]: https://static.crates.io/crates/windows/windows-0.62.2.crate
[pkg-bs]: https://static.crates.io/crates/windows-sys/windows-sys-0.61.2.crate
[pkg-bc]: https://static.crates.io/crates/windows-core/windows-core-0.62.2.crate
[meta-w]: https://crates.io/api/v1/crates/winreg/0.56.0
[meta-r]: https://crates.io/api/v1/crates/windows-registry/0.100.0
[meta-r6]: https://crates.io/api/v1/crates/windows-registry/0.6.1
[meta-bw]: https://crates.io/api/v1/crates/windows/0.62.2
[meta-bs]: https://crates.io/api/v1/crates/windows-sys/0.61.2
[meta-bc]: https://crates.io/api/v1/crates/windows-core/0.62.2
[w-manifest]: https://docs.rs/crate/winreg/0.56.0/source/Cargo.toml
[r-manifest]: https://docs.rs/crate/windows-registry/0.100.0/source/Cargo.toml
[r6-manifest]: https://docs.rs/crate/windows-registry/0.6.1/source/Cargo.toml
[w-open]: https://github.com/gentoo90/winreg-rs/blob/d14c8bd6758810ec679533ac4dc7b0420f598d23/src/reg_key.rs#L115-L199
[w-close]: https://github.com/gentoo90/winreg-rs/blob/d14c8bd6758810ec679533ac4dc7b0420f598d23/src/reg_key.rs#L1053-L1064
[w-transaction]: https://docs.rs/crate/winreg/0.56.0/source/src/transaction.rs
[w-read]: https://github.com/gentoo90/winreg-rs/blob/d14c8bd6758810ec679533ac4dc7b0420f598d23/src/reg_key.rs#L690-L725
[w-enum]: https://github.com/gentoo90/winreg-rs/blob/d14c8bd6758810ec679533ac4dc7b0420f598d23/src/reg_key.rs#L1066-L1135
[w-os-iter]: https://github.com/gentoo90/winreg-rs/blob/d14c8bd6758810ec679533ac4dc7b0420f598d23/src/enum_values_os_string.rs#L16-L28
[w-common]: https://github.com/gentoo90/winreg-rs/blob/d14c8bd6758810ec679533ac4dc7b0420f598d23/src/common.rs#L17-L19
[w-value]: https://docs.rs/crate/winreg/0.56.0/source/src/reg_value.rs
[r-key]: https://github.com/microsoft/windows-rs/blob/a57cc321bfdbac6bb98c488ba49f399da8fcb98a/crates/libs/registry/src/key.rs
[r-type]: https://github.com/microsoft/windows-rs/blob/a57cc321bfdbac6bb98c488ba49f399da8fcb98a/crates/libs/registry/src/type.rs#L5-L53
[r-value]: https://docs.rs/crate/windows-registry/0.100.0/source/src/value.rs
[r-data]: https://docs.rs/crate/windows-registry/0.100.0/source/src/data.rs
[r-pcwstr]: https://docs.rs/crate/windows-registry/0.100.0/source/src/pcwstr.rs
[r-keys]: https://github.com/microsoft/windows-rs/blob/a57cc321bfdbac6bb98c488ba49f399da8fcb98a/crates/libs/registry/src/key_iterator.rs#L11-L67
[r-values]: https://github.com/microsoft/windows-rs/blob/a57cc321bfdbac6bb98c488ba49f399da8fcb98a/crates/libs/registry/src/value_iterator.rs#L12-L81
[r-open]: https://github.com/microsoft/windows-rs/blob/a57cc321bfdbac6bb98c488ba49f399da8fcb98a/crates/libs/registry/src/open_options.rs
[r6-open]: https://docs.rs/crate/windows-registry/0.6.1/source/src/open_options.rs
[r6-keys]: https://docs.rs/crate/windows-registry/0.6.1/source/src/key_iterator.rs
[r6-values]: https://docs.rs/crate/windows-registry/0.6.1/source/src/value_iterator.rs
[b-win]: https://github.com/microsoft/windows-rs/blob/32c3144490c016fe496a0aed769bce60987a2e9d/crates/libs/windows/src/Windows/Win32/System/Registry/mod.rs
[b-sys]: https://github.com/microsoft/windows-rs/blob/32c3144490c016fe496a0aed769bce60987a2e9d/crates/libs/sys/src/Windows/Win32/System/Registry/mod.rs
[b-hkey]: https://github.com/microsoft/windows-rs/blob/32c3144490c016fe496a0aed769bce60987a2e9d/crates/libs/windows/src/Windows/Win32/System/Registry/mod.rs#L711-L729
[b-owned]: https://github.com/microsoft/windows-rs/blob/32c3144490c016fe496a0aed769bce60987a2e9d/crates/libs/core/src/handles.rs#L13-L32
[b-compare]: https://github.com/microsoft/windows-rs/blob/32c3144490c016fe496a0aed769bce60987a2e9d/crates/libs/windows/src/Windows/Win32/Globalization/mod.rs#L19-L23
[rust-os]: https://doc.rust-lang.org/std/os/windows/ffi/trait.OsStringExt.html#tymethod.from_wide
[rust-owned-handle]: https://doc.rust-lang.org/std/os/windows/io/struct.OwnedHandle.html
[ms-open]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw
[ms-enum-key]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regenumkeyexw
[ms-enum-value]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regenumvaluew
[ms-query]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw
[ms-info]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryinfokeyw
[ms-get]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew
[ms-rights]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights
[ms-view]: https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view
[ms-limits]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-element-size-limits
[ms-types]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types
[ms-structure]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/structure-of-the-registry
[ms-value-name]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletevaluew
[rrp-link]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/d5ce9dcc-1f90-4f5a-b076-cc1d2c9b4195
[rrp-open]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/8cb48f55-19e1-4ea2-8d76-dd0f6934f0d9
[rrp-set]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/2b61fa7e-2a38-46ce-a186-7c91b3ed1b61
[wine-lookalike]: https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/advapi32/tests/registry.c#L2646-L2655
[ms-compare]: https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-comparestringordinal
[ms-compare-algo]: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-ucoderef/ba172a49-1971-4448-855e-448f8804127e
[ms-surrogates]: https://learn.microsoft.com/en-us/windows/win32/intl/surrogates-and-supplementary-characters
