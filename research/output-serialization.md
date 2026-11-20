# 流式结构化输出与无损序列化：标准、消费者与已发布 Rust 库

研究日期：2026-11-20。源码基线：`main` 的 `337b568bd77f48bb778a88ab62adde7ee1b91721`，已发布产品 v0.1.3。研究分支：`research/output-serialization`。

本文回答第二版地图的研究票 02；只确认能力、限制和候选适配成本，不选定用户可见格式、字段名、记录协议或旗标。遵循项目词汇：注册表键（Registry Key）、注册表值（Registry Value）、默认值未设置（Unset Default Value）、原始值数据（Raw Value Data）分别处理。[基线架构][project-architecture]、[词汇表][project-glossary]。

下文 **文档／源码事实** 来自标准、第一方文档或固定发布物；**探针** 是本次实际执行的合成实验；**推断／候选** 是据此导出的工程后果。探针没有创建、读取、修改或删除注册表测试键，没有调用 RegQry 查询，没有更改产品依赖、版本、标签、发布资产或凭据。仅本报告提交；下载归档、探针源码、锁文件和结果保留在本研究工作树忽略的 `.scratch/evidence/`。

## 1. 直接影响后续决策的发现

- **探针：** JSON 字符串中的孤立代理代码单元（unpaired surrogate）不能跨已测试消费者保真：`"\uD800"` 在 Windows PowerShell 5.1.26100.9818 和 PowerShell 7.7.0 中都变成 U+FFFD，在 `serde_json` 的 `String` 入口报错；Node 26.13.1 内部保留 D800，但转普通 UTF-8 字节会替换。详见第 3、7 节；这与 JSON 标准所述互操作边界一致。[RFC 8259 §8.2][json-unicode]、[Serde JSON 解码源码][sj-read]。
- **源码事实＋探针：** 已有 Serde 的 Windows `OsString` 实现能直接保留 `u16` 序列；不必为了异常名称手写 JSON 转义器。它的现成表示为带 `Windows` 标签的数组，是否采用该外形仍是产品决定。[Serde 名称序列化][s-os-ser]、[名称反序列化][s-os-de]。
- **探针：** Rust 能精确输出并读回 `u64::MAX`，不代表普通 JavaScript `JSON.parse` 可以。两个测试 PowerShell 则都保留了测试的大整数；不能把 JavaScript 的二进制浮点限制推广到所有 PowerShell JSON 消费。[Serde JSON 数字源码][sj-number]、[ECMAScript Number][js-number]。详见第 4 节。
- **源码事实：** ripgrep 15.2.0 的逐条消息、总计消息和文本／字节分支是有用先例；但它在非 Unix 平台对路径调用 `to_string_lossy()`，并不是 Windows 异常 UTF-16 名称无损输出的先例。[ripgrep CLI 契约][rg-flags]、[实际路径转换][rg-types]。
- **探针＋推断：** 成功输出一个 JSON 值、成功写出行尾、成功 flush、遍历完成是不同事件；任何 framing 都不能独自证明查询完成。序列化库能传播错误，但不能保证故障后的终结消息还能写到已经失效的 stdout。[Serde JSON writer][sj-ser]、[Rust Write][rust-write]。

## 2. 帧边界（framing）与完成状态是两件事

| 候选／标准 | 文档事实 | 空结果与中断的后果（推断） |
| --- | --- | --- |
| 单个 JSON 文档，例如数组 | JSON 文本是一个值；数组由方括号和逗号构成。Serde 提供 `SerializeSeq`，可以逐项写，不要求先收集全部结果。[RFC 8259 §2、§5][json-grammar]、[Serde 序列接口][s-seq] | 空数组 `[]` 是合法文档；零字节不是。写到一半缺 `]` 的整体文档不合法；消费者若要在结束前逐项使用，须使用相应增量解析接口，不能只假定常规整文档 parse 会提前返回。 |
| JSON Lines | UTF-8、每行一个合法 JSON 值；空白行不是值；接受 CRLF；末项 LF 强烈建议但非必须；不含 BOM。其网站仍注明 MIME 类型尚未标准化。[JSON Lines 原始说明][jsonlines] | 完整行能单独解析。没有数据行可以表达零条数据，但单凭空流无法区分零命中和启动前／途中失败；无 LF 的最后一项不必然违反 JSON Lines。 |
| NDJSON 1.0.0 | 每个 JSON 文本后 **必须** LF，可前置 CR；文本内部不得含实际 CR／LF；UTF-8。解析器可忽略空行，但须记录／配置该行为。[NDJSON §3][ndjson] | 与 JSON Lines 的末尾 LF、空行措辞不完全相同，产品需说明所采用的精确规则。字符串中的换行应由 JSON 库转义；pretty JSON 不符合“一记录一行”。 |
| JSON Text Sequences | RFC 7464 为每项加前缀 RS `0x1E`、后缀 LF，媒体类型 `application/json-seq`；允许解析器跳过损坏项后在下个 RS 继续；没有序列结束标志。[RFC 7464 §2][jsonseq] | 空序列可为零字节；允许多行 JSON，但消费者须理解 RS。恢复到下一项只证明能继续读取，不能证明损坏项／尾部没有丢失。 |

**推断：** 行边界不是一次 `write` 调用或一次管道读取的边界。消费者仍需积累到完整 framing；保留已经成功解析的记录，不等于取得了完整查询集合。即使最后一条记录恰好完整，进程也可能在它之后、计划中的下一条之前被终止。RFC 7464 明确承认元素可能整个缺失。[RFC 7464 §2.1][jsonseq]、[Rust 部分写入契约][rust-write]。

**待决问题，不是本报告的协议：** 零命中如何与未完成区分；正常完成／部分失败／取消如何表达；诊断放在哪个流；最终记录与进程退出状态的关系；stdout 失效或强制终止时如何判断缺少终结证据。现有 `Summary` 已区分 `matched`、`incomplete`、`cancelled`、`output_failed` 和错误数；输出研究没有授权改变其查询含义。[现有 Sink／Summary 与退出优先级][project-query]。

### 2.1 现有 CLI 实践与消费者的真实流式行为

**文档／源码事实：** ripgrep 15.2.0 的 `--json` 输出五种消息：`begin`、`end`、`match`、`context`、最后的 `summary`；JSON 隐含启用统计。文件级 begin/end 默认只在有 match/context 时输出；库的四种消息不包括 CLI 额外生成的总计消息。它把合法 UTF-8 数据放进文本分支，非法 UTF-8 数据用 base64；但 Windows 路径有上述有损例外。不要把库文档和完整 CLI 消息集合混为一谈，也不要照搬它自己的手写 base64 实现；本项目已有“采用现成库”的约束。[CLI 文档定义][rg-flags]、[库配置与四类消息][rg-printer]、[消息数据源码][rg-types]。

**文档事实：** jq 默认读取空白分隔的 JSON 值；`--slurp` 才先读入整流，`--compact-output` 每项单行，`--unbuffered` 每项 flush，`--seq` 理解 RS 并可跳过损坏项。这些分别解决消费、布局、延迟和 framing，不能互相代替。[jq 1.8 手册][jq-manual]。

**源码事实＋探针：** PowerShell 7.7.0 的 `ConvertFrom-Json` 在 `ProcessRecord` 中先缓存所有输入，在 `EndProcessing` 才解析。5.1 和 7.7 的合成管道事件轨迹都为 `emit1, emit2, source-end, consume1, consume2`；用 `ForEach-Object { $_ | ConvertFrom-Json }` 后都为 `emit1, consume1, emit2, consume2, source-end`。所以“能解析逐行 JSON”和“搜索中逐条消费”不是相同保证。[PowerShell 7.7.0 源码][ps-from-source]。本次轨迹不包含原生进程管道编码或实时注册表查询。

PowerShell 文档还指出默认对象不能表达仅大小写不同的重复属性，`-AsHashtable` 可处理一些此类情形；5.1 没有该参数。注册表默认值又有合法空值名。因此把任意原始值名直接变成 JSON 对象成员名会增加消费者限制；名称是否作为普通字段载荷、如何分组，交由后续 schema 决定。[PowerShell 7 转换限制][ps-from-doc]、[5.1 参数集][ps51-from-doc]、[默认值 API][win-query]。

## 3. 无损名称：代码单元（code units）与 JSON 字符串

**文档事实：** `OsString::from_wide` 接受不合法 UTF-16，`encode_wide` 保证还原原始 `u16`；`String::from_utf16_lossy` 会替换不合法序列；`OsStr::as_encoded_bytes` 的编码未指定，不能当成跨平台／跨 Rust 版本的交换编码。[Windows 名称往返保证][rust-wide]、[有损转换][rust-string]、[未指定的内部字节编码][rust-os-bytes]。

**标准事实：** RFC 8259 的语法允许 `\uXXXX` 形成孤立代理，但 §8.2 不给它稳定互操作保证。把 D800 手写成 JSON 的 `"\uD800"` 并不能解决跨消费者保真。[JSON Unicode 边界][json-unicode]。

| 合成输入／路径 | 本次探针观察 | 后果 |
| --- | --- | --- |
| JSON `"\uD800"` / `"\uDC00"` | 两个 PowerShell 均读成代码单元 65533；`serde_json::from_str::<String>` 均报 Syntax 错误；Node 分别保留 55296／56320 | 不可把这些转义字符串作为通用无损身份通道。 |
| 合法配对 `"\uD83D\uDE00"` | Rust、两个 PowerShell、Node 均还原 `[55357, 56832]` | 正常 Unicode 字符串路径没有本次孤立代理的缺口。 |
| JSON `"\\uD800"`（字面反斜杠＋uD800） | 所有测试消费者均保留 `[92,117,68,56,48,48]` | JSON 库能够区分字面文本与 JSON 转义；终端显示转义不能未经约定就充当身份编码。 |
| Serde 直接序列化 Windows `OsString` | `[D800,005C,0075,0044,0038,0030,0030,FFFD]` 得到 `{"Windows":[55296,92,117,68,56,48,48,65533]}`，Rust 读回逐单元相等 | 现成库已经能保真；是否接受平台标签、始终数组等外形仍须决定。[序列化][s-os-ser]、[反序列化][s-os-de] |
| 字节 `[00,D8]` 解码 | 两个 PowerShell 的默认 `Encoding.Unicode.GetString` 都产生 FFFD；用原始 char 数组构造字符串保留 D800 | base64／hex 保留字节，并不保证随后使用“Unicode 文本解码器”还保留异常代码单元。[.NET 编码回退说明][dotnet-unicode] |

Node 的孤立代理经过 `JSON.stringify` 再 `JSON.parse` 仍保留代码单元，但 `Buffer.from(s, 'utf8')` 得到 `efbfbd`。这是探针中“内部可往返”与“下游字节可往返”的差别，不是对所有 JS 宿主的测试结果。ECMAScript 的字符串模型与 JSON 字符串序列化定义可解释其内部行为。[ECMAScript String][js-string]、[JSON 序列化][js-json]。

**候选适配成本：** 对异常名称，可用既有 Serde 的 `u16` 数组表示；也可把 `encode_wide` 的代码单元按明确字节序转换后交给现成 base64／hex 库。后一种必须在契约中写明代码单元宽度、字节序、是否含终止符，不能用未指定的 Rust 内部字节替代。正常文本＋异常分支、始终原始代码单元、原始表示＋便读文本都是可构造的候选；本报告不选择分支形状或字段。不能通过有损替换后再匹配、去重或恢复名称。[Rust 无损接口][rust-wide]、[现有原始身份契约][project-architecture]。

## 4. 整数：u32 类型码与完整 u64

**源码事实：** `serde_json` 1.0.154 默认数字实现能保存无符号 64 位整数，`to_writer` 把 `u64` 输出为十进制 JSON number；本次 `u64::MAX` 的 typed 与 `Value::as_u64()` 往返都精确，不需 `arbitrary_precision`。转 `as_f64()` 则是另一条有精度损失可能的路径。[Number 实现][sj-number]、[serializer 实现][sj-ser]。

**标准事实：** JavaScript `Number` 使用 binary64；其安全整数上限为 `2^53-1`。JSON 本身的数字语法并没有一个独立的“u64 类型”。[ECMAScript 数字模型][js-number]、[MAX_SAFE_INTEGER][js-safe]。

本次合成 JSON 整数 token 的实际解析如下；不是先把数值存在浮点变量再序列化。

| 原始 token | Rust `u64`／`Value` | Windows PowerShell 5.1 | PowerShell 7.7 | Node 普通 `JSON.parse` |
| --- | --- | --- | --- | --- |
| `4294967295`（u32::MAX） | 精确 | Int64，精确 | Int64，精确 | 精确、安全整数 |
| `9007199254740993` | 精确 | Int64，精确 | Int64，精确 | 变成 `9007199254740992` |
| `9223372036854775807` | 精确 | Int64，精确 | Int64，精确 | `BigInt(parsed)` 为 `9223372036854775808` |
| `9223372036854775808` | 精确 | Decimal，精确 | BigInteger，精确 | 此值本身可精确表示，但不是安全整数 |
| `18446744073709551615`（u64::MAX） | 精确 | Decimal，精确 | BigInteger，精确 | `BigInt(parsed)` 为 `18446744073709551616` |

两个 PowerShell 还都能把上述解析对象 `ConvertTo-Json -Compress` 输出为原整数 token，及显式转成 `[UInt64]`；这只是所列版本、整数 token 和这些样本的探针，不保证所有 PowerShell 7 版本、科学计数法、后续算术或外部系统。PowerShell 7.5 起的 BigInteger JSON 数字序列化另有官方说明。[ConvertTo-Json 变更说明][ps-to-doc]。

**候选：** 十进制字符串在测试 Node 中经 `BigInt(string)`、两个 PowerShell 中经 `[UInt64]` 可精确还原；原始 8 字节也能保留。字符串需要消费者显式转换；JSON number 需要消费者具备足够精度。Node 26 的 source-aware reviver 用 `BigInt(context.source)` 也能恢复原 token；只对已经舍入的 `value` 调 `BigInt(value)` 不行。该 reviver 是运行时能力，不能假设所有脚本环境都有。普通 `JSON.stringify(BigInt)` 在本次 Node 抛 TypeError。[ECMAScript JSON.parse／reviver 与序列化][js-json]。

**文档事实：** jq 1.8 是否保留原始数字字面量受构建配置和操作影响；算术会转 binary64。`jq .` 看起来保留数字，不足以证明后续计算精确。本次未执行 jq 数字探针。[jq 精度说明][jq-manual]。

**推断：** 原始 `u32` 类型码最大值处于上述所有测试消费者的精确范围；未知类型可以保留数字，不必硬塞进已知类型枚举或映成 `REG_NONE`。同样的 u64 决策可能影响完整 QWORD、FILETIME 或长计数，而不只值数据；哪些字段实际输出、时间是否另给文本仍由后续票决定。[项目原始类型契约][project-architecture]、[Win32 类型输出参数][win-query]。

## 5. 原始字节、解释结果与缺失状态

| 表示候选 | 已有能力／限制 | 适配成本与边界 |
| --- | --- | --- |
| JSON 整数数组 | `Vec<u8>` 与 `serde_bytes::Bytes` 在本次 `serde_json` 中都输出 `[0,216,255]`；`serde_bytes` **不会自动产生 base64**。[字节 serializer][sj-ser]、[serde_bytes 源码][sb-lib] | 消费简单、每元素在精确范围；逗号和十进制数增加体积。类型为 bytes 的提示不能代替 wire encoding 决策。 |
| base64 字符串 | RFC 4648 定义字母表、padding 和无自动换行规则；标准 padded 编码长为 `4*ceil(n/3)`。[RFC 4648][base-spec] | 约 4/3 原字节，不含 JSON 引号；需决定 alphabet／padding。不要选会自行 MIME 折行的调用方式。`base64` crate 提供现成 engine。[base64 API][b-engine] |
| hex 字符串 | `hex` 0.4.3 已在项目中；提供大小写字符串、`encode_to_slice` 和可选 Serde 支持。[hex 源码][h-lib] | 每字节两个字符，便于逐字节核对；字节总长仍可能很大。选定大小写／有无分隔符是 schema 契约。 |

**探针：** `[00,D8,FF]` 经标准 base64 为 `ANj/`，小写 hex 为 `00d8ff`；Rust、两个 PowerShell 与 Node 均还原同三个字节。三个消费者也都保留测试的代码单元数组 `[55296,56320,65535]`。空字节经 base64／hex 编码均为 `""`，数组为 `[]`；这些空表示本身不表示注册表值不存在。

**文档／项目事实：** 默认值不自动存在，空值名用于查询它；不存在返回 `ERROR_FILE_NOT_FOUND`。`REG_NONE` 是类型，`REG_SZ` 等的已读字节不保证终止 NUL；`REG_QWORD` 的类型解释是 64 位数。原始字节须保留真实长度、终止符、字节序、奇数字节或无法解释数据，不能以解释结果重新编码来冒充原始保存数据。[RegQueryValueExW][win-query]、[Win32 值类型][win-types]、[项目架构][project-architecture]。

**源码事实＋探针：** Serde JSON 的 `None` 写为 `null`，`Some(value)` 继续写 value；故 `None::<Option<u8>>` 与 `Some(None::<u8>)` 都成为 `null`。仅在 Rust 内部嵌套 `Option` 并不能建立外部多状态协议。[option 序列化][sj-ser]。

**推断／待决：** 选定的 schema 需能区分：键结果、实际默认值／具名值、默认值未设置；原始数据零字节、解释后逻辑为空、数值零；字段未请求、不适用、读取失败、解释失败。`null`、省略、空字符串、空数组都只是可用材料，标准不会替产品赋予这些含义。两个测试 PowerShell 可通过属性存在性区分缺成员与值为 null 的成员；直接访问 `$obj.x` 却都可得到 `$null`。未知类型保留数值码与原始数据后，便读标签可另外解释；不能让未知标签导致整项丢弃。[项目词汇表][project-glossary]、[现有 RawValue][project-value]。

## 6. 已发布库、Rust 1.100.0 与 writer／错误传播

### 6.1 固定发布物核对

2026-11-20 查询 crates.io 的 `newest_version`／`max_stable_version` 得到以下稳定版，均未 yanked。随后下载实际 `.crate`，逐项 SHA-256 与固定版本 metadata 的 `checksum` 相等；MSRV 来自归档 manifest，不能用 GitHub HEAD 代替。每行链接到版本 metadata 与实际归档。[Serde metadata][meta-s]、[JSON metadata][meta-sj]、[base64 metadata][meta-b]、[hex metadata][meta-h]、[bytes metadata][meta-sb]、[adapters metadata][meta-sw]。

| 发布包 | 发布日期 UTC | manifest Rust 要求／edition | 本次 Rust 1.100.0 x64 探针 |
| --- | --- | --- | --- |
| [`serde` 1.0.229][pkg-s] | 2026-07-18 | 1.56／2021 | 默认 std＋derive，编译运行通过 |
| [`serde_json` 1.0.154][pkg-sj] | 2026-10-11 | 1.71／2021 | 默认 std，编译运行通过 |
| [`base64` 0.23.1][pkg-b] | 2026-08-04 | 1.71.0／2021 | 默认特性，编译运行通过 |
| [`hex` 0.4.3][pkg-h] | 2021-03-03 | 未声明 rust-version／2018 | 默认特性，编译运行通过 |
| [`serde_bytes` 0.11.19][pkg-sb] | 2025-09-15 | 1.68／2018 | 默认特性，编译运行通过 |
| [`serde_with` 3.25.0][pkg-sw] | 2026-11-19 | 1.88／2021 | 关闭默认特性，开 std、macros、base64、hex，编译运行通过 |

这是所列 feature 组合与当次解析出的传递依赖的构建证据，不是所有 feature、最低 Rust 版本或 ARM64 支持测试。`serde_with` 的日期／MSRV 是本次最新实际归档事实；并非沿用旧版 3.x 的 Rust 要求。[固定版本 manifest：Serde][manifest-s]、[JSON][manifest-sj]、[base64][manifest-b]、[hex][manifest-h]、[bytes][manifest-sb]、[serde_with][manifest-sw]。

| 归档 | 核对 SHA-256 |
| --- | --- |
| serde-1.0.229.crate | `4148590afebada386688f18773da617792bf2ef03ffc1e4cbd2b1d45b023e0ba` |
| serde_json-1.0.154.crate | `e7e9cc8b1b85264074fbcc02a88680c4096b1e47df8f739dceb03bf482f04bd6` |
| base64-0.23.1.crate | `ac07cdecf99051d9a5238b80f35af32cdeba5b336e55d957b318b50137e18da5` |
| hex-0.4.3.crate | `7f24254aa9a54b5c858eaee2f5bccdb46aaf0e486a595ed5fd8f86ba55232a70` |
| serde_bytes-0.11.19.crate | `a5d440709e79d88e51ac01c4b72fc6cb7314017bb7da9eeff678aa94c10e3ea8` |
| serde_with-3.25.0.crate | `56cb1ca7c93ae63d6439b5250f6b6b040f7e121f32e5dd2f5d523dd4149b3204` |

归档的 `.cargo_vcs_info.json` 对应下列提交；另下载 14 个关键源码与归档逐字节 SHA-256 比较，全部相等：Serde 的两个名称实现；JSON 的 ser/error/read/number；base64 的 engine/display/writer；hex lib；serde_bytes lib；serde_with 的 base64/hex/ser 实现。Serde 归档 `src/core` 来自上游 `serde_core/src`，不能按归档相对位置拼出不存在的 GitHub 路径。

| 包 | 归档 VCS 提交 |
| --- | --- |
| serde | `7fc3b4c30c94f73a96ebd1553f2b090d928fc3a8` |
| serde_json | `20572a6d066958542d79cdd6cf1a7cd9f0c8e1f8` |
| base64 | `069bf7067b949f5c0a92b6ceb82492920502f2c2` |
| hex | `b2b4370b5bf021b98ee7adc92233e8de3f2de792` |
| serde_bytes | `34f3c7d442716d0f28db7c3641882648ce387b60` |
| serde_with | `d32ab8afca00a5cb56bf522de7340217f8661748` |

### 6.2 现成 writer 与最小适配面

**源码事实：** `serde_json::to_writer<W: io::Write, T: Serialize>` 直接写一个紧凑 JSON 值并返回 `Result<()>`；它不自动添加 LF 或 flush。I/O 错误可用 `is_io`／`io_error_kind` 检查，转成 `io::Error` 时保留原始 I/O 错误；序列化数据错误和 EOF 则映成适当 kind。[serializer][sj-ser]、[错误分类与转换][sj-error]。这可以适配现有返回 `io::Result<()>` 的 Sink，但非 I/O 序列化错误如何呈现仍应保留原因，而非统一伪报 broken pipe。[现有 Sink][project-query]。

**探针：** 允许每次最多写 3 字节、累计到 4 字节后注入 BrokenPipe 的 `Write`，序列化 `[1,2,3]` 后返回 `Category::Io`／`Some(BrokenPipe)`，已留下 `[1,2`；自定义 Serialize 在第一个元素后失败，留下 `[1`，返回 Data。另一 writer 能写完整 `[1,2,3]` 却在 LF 时失败；再一 writer 写完 LF 后在显式 flush 失败，且 `to_writer` 的隐式 flush 次数为零。这些是故障注入，不是实际关闭管道或磁盘满测试。

**推断：** 直接写出可保持逐结果流式，但错误可能留下半条记录；先 `to_vec` 可避免序列化错误先污染 stdout，却增加整条序列化记录的缓冲，实际写到管道仍可能中途失败。`write_all` 处理短写并传播错误，不提供事务或跨进程原子性。[`to_vec` 实现][sj-ser]、[Rust Write 契约][rust-write]。选择记录缓冲、flush 节奏和超大单值处理须显式评估，不能凭“流式”声称内存恒定或输出原子。

**库能力／代价：**

- `serde_with` 的 `DisplayFromStr` 可用标准 Display 输出数字字符串；`base64::Base64` 和 `hex::Hex` 提供现成字段适配。该发布版 Base64 适配先 `.encode` 得到字符串再交给 Serde，有编码大小的临时分配；便利属性不等于零额外内存。[数字适配][sw-ser]、[base64 适配][sw-base64]、[hex 适配][sw-hex]。
- `base64::display::Base64Display` 提供不堆分配的 Display，`serde_json::collect_str` 可边格式化边转义；组合成小型 Serialize 适配是源码支持的候选，未在本次测量性能。另一现成 `EncoderWriter` 支持 `Write`，必须显式 `finish()` 才能看见最终 padding／尾部写出错误，Drop 会抑制错误。[Base64Display][b-display]、[JSON collect_str][sj-ser]、[EncoderWriter][b-writer]。不要手写 JSON 字符串引号／转义去绕开 serializer。
- `BufWriter` 能合并小写入，但 Drop 的 flush 错误会被忽略；无论是否另包 base64 writer，最终错误都应从显式 flush／finish 获取。[Rust BufWriter][rust-buf]。

这些库只负责已定义数据的编码／写入；是否存在某项、数据是否解释成功、查询是否完整、视图与身份、取消等仍由 RegQry 契约负责。新增 serde_with 或 serde_bytes 并不是本研究的依赖选择。

## 7. 执行证据与未验证事项

**实际探针环境：** Windows x64 宿主；Rust `1.100.0 (0ef1bc386 2026-11-09)`，host `x86_64-pc-windows-msvc`；Windows PowerShell `5.1.26100.9818`／CLR `4.0.30319.42000`；PowerShell `7.7.0`／.NET `11.0.0`；Node `26.13.1`／V8 `14.6.202.34-node.40`。PowerShell 7 报 OS `Microsoft Windows 10.0.26300`；这是环境记录，不解释为项目支持矩阵的验收。两个 PowerShell 探针进程均显式使用 NoProfile／非交互方式，未改宿主编码配置。

合成证据文件：`.scratch/evidence/powershell-5.1.26100.9818.json`、`powershell-7.7.0.json`、`node-consumer.json`、`rust-probe.json`、`crate-summary.json`、`source-comparison.json`。读取这些 UTF-8 文件时显式指定编码；PowerShell 5.1 默认文件解码不能被当作原始探针数据。

关键消费者结果可用下列最小探针复核，输入全是合成常量：

```powershell
$x = '{"n":18446744073709551615,"s":"\uD800"}' | ConvertFrom-Json
$x.n.GetType().FullName
$x.n.ToString([Globalization.CultureInfo]::InvariantCulture)
@($x.s.ToCharArray() | ForEach-Object { [int]$_ })
# Both tested hosts: integer preserved; string code unit becomes 65533.
```

```javascript
const token = '18446744073709551615';
BigInt(JSON.parse(token)).toString(); // 18446744073709551616
JSON.parse('"\\uD800"').charCodeAt(0); // 55296
JSON.parse(token, (k, v, c) => typeof v === 'number' ? BigInt(c.source) : v);
// Node 26.13.1: 18446744073709551615n; source-aware runtime required.
```

Rust 探针是独立 `publish = false` 包，精确 `=version` 使用第 6 节的六个直接依赖，`[workspace]` 隔离于产品；`serde` 开 derive，`serde_with` 使用表中 feature，其余默认。命令为 `cargo run --manifest-path Cargo.toml`，在 probe 目录设置独立 `CARGO_HOME=../cargo-home`；共编译一个合成程序，后用 `cargo tree --locked --offline -e normal` 复核实际依赖树。没有运行产品／上游注册表测试或新增产品测试。

**未验证／交给后续实施与协议评审：**

1. 没有选择 framing、数字／名称／字节字段表示或版本演进规则；没有承诺最终记录必达。需要在下游票明确空流、损坏末项、整条缺失、未知记录类型与进程退出状态的处理。
2. 没有 ARM64、全部 PowerShell 7 版本、最低受支持 Windows 客户端或完整 shell 矩阵的新证据；没有把本机探针冒充正式平台／发布验收。[现有兼容性界限][project-compat]。
3. 没有实际异常注册表名称、未知类型或并发变更测试；本研究保真结果来自构造的代码单元／字节／类型码。后续应让真实读取路径与所选 wire encoding 端到端对应。
4. 没有实际 broken-pipe、磁盘满、Ctrl+C、进程强杀或消费者提前退出测试；已覆盖的是可控 `Write` 短写、I/O／Serialize／LF／flush 故障。所选终结协议须接受这些事件未必能写出终结记录。
5. 没有超大值、慢消费者、分配失败或吞吐基准；源码确认的中间分配并不是峰值内存或性能测量。逐条流式也不排除单条记录很大。

[project-architecture]: https://github.com/inaku-Gyan/RegQry/blob/337b568bd77f48bb778a88ab62adde7ee1b91721/docs/architecture.md
[project-glossary]: https://github.com/inaku-Gyan/RegQry/blob/337b568bd77f48bb778a88ab62adde7ee1b91721/GLOSSARY.md
[project-query]: https://github.com/inaku-Gyan/RegQry/blob/337b568bd77f48bb778a88ab62adde7ee1b91721/src/query.rs#L203-L234
[project-value]: https://github.com/inaku-Gyan/RegQry/blob/337b568bd77f48bb778a88ab62adde7ee1b91721/src/value.rs
[project-compat]: https://github.com/inaku-Gyan/RegQry/blob/337b568bd77f48bb778a88ab62adde7ee1b91721/docs/compatibility.md
[json-grammar]: https://www.rfc-editor.org/rfc/rfc8259.html#section-2
[json-unicode]: https://www.rfc-editor.org/rfc/rfc8259.html#section-8.2
[jsonlines]: https://jsonlines.org/
[ndjson]: https://github.com/ndjson/ndjson-spec/blob/master/README.md#3-functional-specification
[jsonseq]: https://www.rfc-editor.org/rfc/rfc7464.html#section-2
[base-spec]: https://www.rfc-editor.org/rfc/rfc4648.html#section-3
[rg-flags]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/core/flags/defs.rs#L3231-L3297
[rg-printer]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/printer/src/json.rs#L67-L85
[rg-types]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/printer/src/jsont.rs#L148-L201
[jq-manual]: https://jqlang.org/manual/v1.8/
[ps-from-source]: https://github.com/PowerShell/PowerShell/blob/v7.7.0/src/Microsoft.PowerShell.Commands.Utility/commands/utility/WebCmdlet/ConvertFromJsonCommand.cs#L24-L103
[ps-from-doc]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5
[ps51-from-doc]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-5.1
[ps-to-doc]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-json?view=powershell-7.5
[rust-wide]: https://doc.rust-lang.org/1.100.0/std/os/windows/ffi/trait.OsStringExt.html#tymethod.from_wide
[rust-string]: https://doc.rust-lang.org/1.100.0/std/string/struct.String.html#method.from_utf16_lossy
[rust-os-bytes]: https://doc.rust-lang.org/1.100.0/std/ffi/struct.OsStr.html#method.as_encoded_bytes
[rust-write]: https://doc.rust-lang.org/1.100.0/std/io/trait.Write.html#method.write_all
[rust-buf]: https://doc.rust-lang.org/1.100.0/std/io/struct.BufWriter.html
[dotnet-unicode]: https://learn.microsoft.com/en-us/dotnet/api/system.text.unicodeencoding?view=net-10.0
[js-number]: https://tc39.es/ecma262/multipage/ecmascript-data-types-and-values.html#sec-ecmascript-language-types-number-type
[js-safe]: https://tc39.es/ecma262/multipage/numbers-and-dates.html#sec-number.max_safe_integer
[js-string]: https://tc39.es/ecma262/multipage/ecmascript-data-types-and-values.html#sec-ecmascript-language-types-string-type
[js-json]: https://tc39.es/ecma262/multipage/structured-data.html#sec-json-object
[win-query]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw
[win-types]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types
[meta-s]: https://crates.io/api/v1/crates/serde/1.0.229
[meta-sj]: https://crates.io/api/v1/crates/serde_json/1.0.154
[meta-b]: https://crates.io/api/v1/crates/base64/0.23.1
[meta-h]: https://crates.io/api/v1/crates/hex/0.4.3
[meta-sb]: https://crates.io/api/v1/crates/serde_bytes/0.11.19
[meta-sw]: https://crates.io/api/v1/crates/serde_with/3.25.0
[pkg-s]: https://static.crates.io/crates/serde/serde-1.0.229.crate
[pkg-sj]: https://static.crates.io/crates/serde_json/serde_json-1.0.154.crate
[pkg-b]: https://static.crates.io/crates/base64/base64-0.23.1.crate
[pkg-h]: https://static.crates.io/crates/hex/hex-0.4.3.crate
[pkg-sb]: https://static.crates.io/crates/serde_bytes/serde_bytes-0.11.19.crate
[pkg-sw]: https://static.crates.io/crates/serde_with/serde_with-3.25.0.crate
[manifest-s]: https://docs.rs/crate/serde/1.0.229/source/Cargo.toml
[manifest-sj]: https://docs.rs/crate/serde_json/1.0.154/source/Cargo.toml
[manifest-b]: https://docs.rs/crate/base64/0.23.1/source/Cargo.toml
[manifest-h]: https://docs.rs/crate/hex/0.4.3/source/Cargo.toml
[manifest-sb]: https://docs.rs/crate/serde_bytes/0.11.19/source/Cargo.toml
[manifest-sw]: https://docs.rs/crate/serde_with/3.25.0/source/Cargo.toml
[s-os-ser]: https://github.com/serde-rs/serde/blob/7fc3b4c30c94f73a96ebd1553f2b090d928fc3a8/serde_core/src/ser/impls.rs#L931-L962
[s-os-de]: https://github.com/serde-rs/serde/blob/7fc3b4c30c94f73a96ebd1553f2b090d928fc3a8/serde_core/src/de/impls.rs
[s-seq]: https://docs.rs/serde/1.0.229/serde/ser/trait.SerializeSeq.html
[sj-ser]: https://github.com/serde-rs/json/blob/20572a6d066958542d79cdd6cf1a7cd9f0c8e1f8/src/ser.rs
[sj-error]: https://github.com/serde-rs/json/blob/20572a6d066958542d79cdd6cf1a7cd9f0c8e1f8/src/error.rs#L48-L225
[sj-read]: https://github.com/serde-rs/json/blob/20572a6d066958542d79cdd6cf1a7cd9f0c8e1f8/src/read.rs#L948-L1016
[sj-number]: https://github.com/serde-rs/json/blob/20572a6d066958542d79cdd6cf1a7cd9f0c8e1f8/src/number.rs#L92-L167
[b-engine]: https://github.com/marshallpierce/rust-base64/blob/069bf7067b949f5c0a92b6ceb82492920502f2c2/src/engine/mod.rs
[b-display]: https://docs.rs/base64/0.23.1/base64/display/struct.Base64Display.html
[b-writer]: https://docs.rs/base64/0.23.1/base64/write/struct.EncoderWriter.html
[h-lib]: https://github.com/KokaKiwi/rust-hex/blob/b2b4370b5bf021b98ee7adc92233e8de3f2de792/src/lib.rs
[sb-lib]: https://github.com/serde-rs/bytes/blob/34f3c7d442716d0f28db7c3641882648ce387b60/src/lib.rs
[sw-ser]: https://github.com/jonasbb/serde_with/blob/d32ab8afca00a5cb56bf522de7340217f8661748/serde_with/src/ser/impls.rs#L633-L643
[sw-base64]: https://github.com/jonasbb/serde_with/blob/d32ab8afca00a5cb56bf522de7340217f8661748/serde_with/src/base64.rs#L64-L106
[sw-hex]: https://github.com/jonasbb/serde_with/blob/d32ab8afca00a5cb56bf522de7340217f8661748/serde_with/src/hex.rs
