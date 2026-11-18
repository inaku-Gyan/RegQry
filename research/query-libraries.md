# 查询语法与数据解释：已发布 Rust 库适配核实

调研日期：2026-11-19。基线：`main` 的 `34e02fa1a021689a61c059172737a53994180d1e`。本报告服务“核实查询语法与数据解释的现有库适配”工单，按工单 01 / 04 / 16 / 17 / 21 的当前 Answer 核实，不采用历史 `show` / `search` / 子命令提案。唯一入口是 `regqry [QUERY OPTIONS]`；裸命令帮助并退出 0。

证据标记：**文档**为第一方公开契约；**源码**为指定已发布版本的实现；**实测**为本机隔离构造探针；**推论**为如何组合现有能力；**待定**为产品决定。未编写产品 CLI，未访问注册表，未修改持久环境或项目工具链。依赖及探针仅存在隔离工作树的忽略目录；提交仅含本报告。

## 结论与选型边界

- **clap 4.6.8** 能承担参数收集、别名、重复、空模式和 `OsString` 保真。需要的小适配是裸命令的成功帮助、产品参数验证以及字段组合，不需要自行编写 CLI 解析器。探针实际解析器依赖为 **clap_builder 4.6.7**。[clap 发布版本](https://crates.io/api/v1/crates/clap/4.6.8)、[clap 4.6.8 源码包](https://static.crates.io/crates/clap/clap-4.6.8.crate)
- **regex 1.13.2** 可直接承担正则子串匹配与 Unicode 简单大小写折叠（simple case folding）；它不直接接收非良构 UTF-16，也不支持回溯引用及前后查找。无损名称与可解释的匹配文本应是两个层次。[regex 1.13.2 文档](https://docs.rs/regex/1.13.2/regex/)、[源码包](https://static.crates.io/crates/regex/regex-1.13.2.crate)
- **yash-fnmatch 1.1.2 的公开 AST→regex 接口是保持当前 Unicode glob 契约的更适配候选**：已有解析器负责 `* / ? / []`，使用 `without_escape` 保留字面 `/`、`\`，公开 AST 可白名单排除未承诺的 POSIX 扩展，再交 regex 统一 Unicode 大小写。KEY 的分层和独立 `**` 只需领域组件适配。globset 0.4.21 的直接路径 API 则有实际差异，不能只靠配置满足契约。[yash-fnmatch 1.1.2 发布源码](https://static.crates.io/crates/yash-fnmatch/yash-fnmatch-1.1.2.crate)、[globset 语法](https://docs.rs/globset/0.4.21/globset/)
- **chrono 0.4.45 + humantime 2.4.0** 可组合覆盖本地日期、带偏移 RFC 3339 和固定时长。统一查询时刻、严格输入词法以及本地午夜的歧义策略仍由小范围产品适配承担。[chrono](https://docs.rs/chrono/0.4.45/chrono/)、[humantime](https://docs.rs/humantime/2.4.0/humantime/)
- **环境快照不需要额外环境管理 crate**：标准库 `vars_os()` 已有快照保证；现有 `regex::replace_all` 闭包可以只查这份 Map，单遍替换、不递归并保留未知引用。Windows 名称比较、特殊百分号和非良构环境值仍需明确。[Rust vars_os](https://doc.rust-lang.org/std/env/fn.vars_os.html)、[regex 替换](https://docs.rs/regex/1.13.2/regex/struct.Regex.html#method.replace_all)
- **标准库 OsString / `[u16]` 已能保留 Windows 字符串，无需新增 widestring 依赖**；本报告也核实了可选 widestring 1.2.1。**hex 0.4.3** 可解码原始字节查询参数；**ctrlc 3.5.3** 能接收取消事件。字符串布局解释、取消检查及退出 130 是项目责任，库不会代替产品决定。[widestring](https://docs.rs/widestring/1.2.1/widestring/)、[hex 0.4.3](https://docs.rs/hex/0.4.3/hex/)、[ctrlc 3.5.3 源码包](https://static.crates.io/crates/ctrlc/ctrlc-3.5.3.crate)

以上是有证据的候选及缺口，不是已决定的依赖清单。以 crates.io 发布元数据及源码包确证版本，未把 GitHub `main` 当发布版；检索时部分 docs.rs `latest` 缓存仍显示 globset 0.4.20 / ctrlc 3.5.2，实际已发布源码分别为 0.4.21 / 3.5.3。

## clap：已有解析器与产品语义的分工

下表为 **clap 4.6.8 / clap_builder 4.6.7 的文档、源码及实测**。clap_builder 的 `builder/value_parser.rs` 中，`OsStringValueParser` 保留 OS 字符串，`StringValueParser` 要求合法 Unicode；二者不能混为一谈。[clap_builder 4.6.7 源码包](https://static.crates.io/crates/clap_builder/clap_builder-4.6.7.crate)、[原始 OS 参数解析器](https://docs.rs/clap/4.6.8/clap/builder/struct.OsStringValueParser.html)

| 已定要求 | 现成能力及必要配置 |
| --- | --- |
| 每次一个值，重复累积 | `num_args(1)` + `ArgAction::Append`；`Vec<T>` 的 derive 推导也采用 Append。不能用默认 Set 后期待自动累积。 |
| 同义别名共用集合 | 同一个 `Arg` 配置 `visible_alias("data-case-insensitive")` 等；按主名和别名交替输入，仍进入同一个 `get_many` 集合。 |
| 无参数状态条件重复幂等 | `SetTrue` 默认再次出现会冲突；可用 `overrides_with(自身 id)` 得到重复仍为 true。无需自行计数再解释。 |
| 空正则 / 空 glob | `--name=` 可以接收空串；默认 String / OsString 解析器不等于 `NonEmptyStringValueParser`。ROOT / TYPE / TIME / HEX 的非空校验须另配。 |
| 前导 `-` 值 | `--name=-legacy` 绑定成功。无需为此全局开启允许连字符值，避免吞掉本应是选项的输入。 |
| ROOT 的非良构 UTF-16 | 使用 `OsStringValueParser` / `value_parser!(OsString)`；构造的孤立代理项 `D800` 经解析后 `encode_wide()` 完全相同。 |
| 正则 / glob 模式文本 | 使用 String 解析器可在编译模式前拒绝非 Unicode 参数；该拒绝不同于被检索注册表名称的解释失败。 |
| 正常帮助 / 版本 | 自带 `-h / --help`，配置版本后有 `-V / --version`；显式帮助为 stdout、退出 0。 |
| 裸命令帮助且退出 0 | **不能直接采用 `arg_required_else_help(true)`**：实测它产生 `DisplayHelpOnMissingArgumentOrSubcommand`，stderr、退出 2。可正常解析空参数后检测“没有显式查询选项”，调用已有 `print_help`，再返回 0。 |
| 没有位置参数及子命令 | 不定义它们即可；未知参数和意外位置参数由解析器报错。产品组合验证在打开注册表前完成。 |

`ArgAction`、别名、值个数、`overrides_with`、`value_delimiter` 和帮助行为见 [Arg](https://docs.rs/clap/4.6.8/clap/struct.Arg.html)、[ArgAction](https://docs.rs/clap/4.6.8/clap/enum.ArgAction.html)、[Command](https://docs.rs/clap/4.6.8/clap/struct.Command.html)、[Error::exit_code / use_stderr](https://docs.rs/clap/4.6.8/clap/error/struct.Error.html)。不设置逗号分隔器即可保持 TYPE 每次一个值，不因库提供该能力而加入逗号列表。

**推论**：ROOT 收集用 `OsString`，仅将五组 ASCII 根关键字作专门比较；路径其余部分保存原始 UTF-16。TYPE 的 u32 十进制 / 十六进制范围、同码别名以及 ROOT 尾分隔符规则属于有限产品词法，不能用文件系统 `Path` 规范化代替。clap 不会恢复 shell 先前丢失的字符，也不应再作通用反斜杠或环境展开。

## regex：子串、大小写与 UTF-16 边界

**文档与实测**：`Regex::is_match` 默认搜索子串；`Path` 命中 `InstallPath`，空正则可以命中空位置。`RegexBuilder::case_insensitive(true)` 按 Unicode 简单大小写折叠；`É` 命中 `é`，但 `ß` 不因完整折叠而命中 `ss`。键 / 值名的 builder 默认可开启该选项，数据条件各自单独配置，不能由相邻参数改变。[Regex](https://docs.rs/regex/1.13.2/regex/struct.Regex.html)、[RegexBuilder](https://docs.rs/regex/1.13.2/regex/struct.RegexBuilder.html)

**语法边界**：支持锚点、Unicode 类、交替、重复、分组和内联标志；不支持 look-around 或 backreference，`(?=a)`、`(a)\1` 实测编译报错。`.` 默认不含换行，`(?s)` 可开启；`(?m)` 改变行锚点，整串要求可用 `\A...\z`。内联 `(?-i)` 可覆盖外层 builder 的大小写默认值；若产品要禁止覆盖，就需要额外决定，不能声称 builder 强制了不可覆盖的规则。[regex 语法、Unicode 与复杂度](https://docs.rs/regex/1.13.2/regex/)

匹配对象是 `&str`，即合法 UTF-8；模式本身也要是 `&str`。`regex::bytes` 可以匹配任意字节，但没有把 UTF-16 代码单元（code unit）作为字符的保证。把孤立代理项转成替换字符、把 UTF-16 原始字节交给 UTF-8 正则，或匹配输出用的 `\u{D800}` 文字，都会改变字段含义。Windows `OsString::from_wide` / `encode_wide` 则明确保证非良构 UTF-16 往返无损。[bytes::Regex](https://docs.rs/regex/1.13.2/regex/bytes/struct.Regex.html)、[OsStringExt](https://doc.rust-lang.org/std/os/windows/ffi/trait.OsStringExt.html)、[OsStrExt](https://doc.rust-lang.org/std/os/windows/ffi/trait.OsStrExt.html)

**待定**：对非良构名称，如果当前条件必须做 Unicode 名称匹配，是否记判断不完整并退出 2；如果只需类型 / 原始字节等条件，是否继续查询并以代码单元转义显示。此方案与现有库边界相容，但本报告不将它冒充已确认产品决定。名称身份必须始终保留原始内容。正则简单折叠也不能冒充 Windows 注册表身份或环境变量名的原生比较规则。

## glob：已有纯字符串解析器可保留字符契约

### 更适配的候选：yash-fnmatch 1.1.2 + regex

**发布事实**：1.1.2 于 2024-12-14T02:52:21Z 发布，MIT OR Apache-2.0。以下已从发布归档核实，并在本机以同版本运行，不是依据仓库未发布 `main`。[发布元数据](https://crates.io/api/v1/crates/yash-fnmatch/1.1.2)、[正式归档](https://static.crates.io/crates/yash-fnmatch/yash-fnmatch-1.1.2.crate)

**文档 / 源码**：该库提供 `ast::Ast::new(without_escape(pattern))`，按 Unicode `char` 解析 `* / ? / []`；`/` 没有文件系统特殊含义，`without_escape` 使 `\` 成为普通字符。`Ast::to_regex(&config)` 是公开 API，输出库负责生成的正则；设置 `anchor_begin / anchor_end` 得到 `\A...\z`。再用已有 `RegexBuilder` 开启 `dot_matches_new_line(true)` 和对应字段的 `case_insensitive`，即可统一使用 Unicode 简单折叠。[固定发布源码：char_iter.rs](https://github.com/magicant/yash-rs/blob/e333d14230fdbbeecd086f7eeb037053bbc0356e/yash-fnmatch/src/char_iter.rs)、[AST 转换](https://github.com/magicant/yash-rs/blob/e333d14230fdbbeecd086f7eeb037053bbc0356e/yash-fnmatch/src/ast/regex.rs)

```rust
let ast = yash_fnmatch::ast::Ast::new(yash_fnmatch::without_escape(pattern));
// 对公开 AST 做基本语法白名单检查，见下文；不修改生成的正则。
let mut config = yash_fnmatch::Config::default();
config.anchor_begin = true;
config.anchor_end = true;
let source = ast.to_regex(&config)?;
let matcher = regex::RegexBuilder::new(&source)
    .case_insensitive(ignore_case)
    .dot_matches_new_line(true)
    .build()?;
```

**必须注意的公开 API 陷阱**：不要直接依赖 `Pattern::parse_with_config` 达成所有 caseless 模式。其文档及实现明确：纯字面模式的快路径忽略 `Config.case_insensitive`；实测字面 `É` 不匹配 `é`。上述公开 AST→regex 路径将所有模式交给同一现成 regex builder，可避免这个限制；不需要 fork 或重写 glob 解析器。[固定发布源码：Config / Pattern](https://github.com/magicant/yash-rs/blob/e333d14230fdbbeecd086f7eeb037053bbc0356e/yash-fnmatch/src/lib.rs)

**范围验证可用公开结构完成**：`Ast.atoms`、`Atom::Bracket`、`Bracket.items`、`BracketItem::{Atom,Range}` 及 `BracketAtom` 都公开。对 bracket 直接成员及 range 两端只允许 `BracketAtom::Char`，即可拒绝 `CollatingSymbol`、`EquivalenceClass`、`CharClass`，保留当前只承诺的普通集合 / 范围 / 否定集合。此为使用已有 AST 的薄白名单，不是手写第二个 glob parser。[公开 AST](https://github.com/magicant/yash-rs/blob/e333d14230fdbbeecd086f7eeb037053bbc0356e/yash-fnmatch/src/ast.rs)

这项白名单有实际依据：**实测**未受限的 `[[.x|y.]]` 被库生成为 `\A(?:x|y)\z`，匹配 `x`；对应源码把多字符 collating/equivalence 内容直接写进正则。不能不加限制就把完整 POSIX 扩展接进产品，也不要自行修补生成的正则。白名单可以在上述三个扩展节点上准确拒绝，不会因为字面文本恰含 `[:` 就保守误拒。是否采用这个基本语法范围交用户确认。

**已测**：`?` 分别匹配 `中` / `😀`；`[中]`、`[!中]`、`[À-Ö]` 按标量匹配；`É` / `[É]` 在 caseless 下匹配 `é`，`Σ` 匹配 `ς`，`ß` 不匹配 `ss`；`A\B` 不混同 `A/B`，`A*B` 可跨字段里的真实 `/` 或 `\`；换行、空 glob、整字段锚及 `[*]` 均符合目标。未闭合 `[` 按字面处理，`[z-a]` 由生成 regex 的编译报错；这是库的既有语法，不另写“修复器”。这些边界仍需随依赖选择一同确认为产品语法。

**KEY 的最小领域适配（推论）**：模式和候选按真正的注册表 `\` 层级分成组件；组件恰为 `**` 才表示零或多层，其余组件使用上面现成引擎。因为普通组件的 matcher 从不收到跨层文本，`* / ? / []` 自然不跨层，而组件中的 `/` 仍是普通字符；零组件分支也自然保留 `Vendor\**` 匹配 `Vendor`。名称 / 数据不分组件，直接使用纯字符串引擎。该组合不要求把用户模式翻译为文件路径、不改变 Unicode 字符语义；本研究未编写最终组件序列匹配器。

另一新发布候选 **fnmatch-rs 0.1.0**（2026-06-22）也提供 `translate(&str)`→Unicode regex，20 个主要组合与上述相同；但实际 `[a[b]` 翻译后不能编译，公开便利 `fnmatchcase` 把编译错误变成 false。未闭合 `[` 当字面，倒序范围还会被删除。相较之下，yash 的公开 AST、范围验证和类处理更容易准确控制。它是已发布的备选，不能因短实现就省略这些缺口。[发布元数据](https://crates.io/api/v1/crates/fnmatch-rs/0.1.0)、[固定源码](https://github.com/VoiceLessQ/fnmatch-rs/blob/a3461632e595ce1f1824f54c3c70286e311c1a23/src/lib.rs)

### globset 0.4.21 的逐项核实

源码位置：`src/glob.rs` 的 `parse_backslash`、`parse_star`、`parse_class`、`Tokens::to_regex_with`、`char_to_escaped_literal`；`src/lib.rs` 的 `Candidate::new / from_bytes / from_cow`；`src/pathutil.rs` 的 `normalize_path`。可从 [0.4.21 发布源码包](https://static.crates.io/crates/globset/globset-0.4.21.crate) 或 [固定版本源码浏览](https://docs.rs/crate/globset/0.4.21/source/src/glob.rs) 复核。

| 当前契约 | 已发布库事实 / Windows x64 实测 |
| --- | --- |
| glob 整字段 | 生成正则有 `^...$`；空 glob 只匹配空字段。 |
| key 仅 `\` 分层，`/` 是真实名称字符 | **不直接满足**。Windows `parse_backslash` 在禁反斜杠转义时把 `\` 变 `/`；Candidate 又把候选中的 `\` 变 `/`。`A\B` 与 `A/B` 会混同。 |
| `* / ? / 字符类` 不跨 key 组件 | `literal_separator(true)` 限制 `*` / `?`，但 `A[!x]B` 仍会匹配候选 `A\B`；字符类未自动排除 `/`。 |
| 独立 `**` 跨零或多层 | `**\Acme` 包含直接 `Acme`；但 `Vendor\**` **不包含 `Vendor` 自身**。库文档也明确 `foo/**` 不匹配 `foo`。 |
| name / data 中 `\` 是普通字符 | `backslash_escape(false)` 仍会在 Windows 把它当路径分隔符；开启转义则它又不是普通字符。单改这个配置不足。 |
| Unicode 字符与不区分大小写 | 生成正则先置 `(?-u)`。`?` 不匹配 `é`，`??` 匹配 `é`；忽略大小写时 `A` 匹配 `a`，`É` 不匹配 `é`。字符类也是 UTF-8 **字节类**。 |
| 非良构 Windows 字符串 | Candidate 的 Path 入口使用有损 UTF-8 转换；`from_bytes` 虽可接收字节，仍执行路径归一化，文档也不定义把 UTF-16 字节交入的匹配语义。 |

这些不是缓存或终端显示造成的差异，而是指定版本源码及探针结果。文档中的 “character” 不能据此扩大解释为 Unicode 标量值（Unicode scalar value）。[GlobBuilder](https://docs.rs/globset/0.4.21/globset/struct.GlobBuilder.html)、[Glob::regex](https://docs.rs/globset/0.4.21/globset/struct.Glob.html#method.regex)、[Candidate](https://docs.rs/globset/0.4.21/globset/struct.Candidate.html)

**不可用的捷径**：不能仅删 `Glob::regex()` 的 `(?-u)` 前缀，再按 Unicode regex 编译。源码先把非 ASCII 字符编码成 UTF-8 `\xNN` 序列；`É` 产生 `\xc3\x89`，Unicode 模式会把它们解释为两个标量值，实测不再匹配 `É`。字符类端点也用同一转换。修复需要重建字面量 / 类，不能称“只移除前缀的小适配”。

### 少数替代引擎

| 精确发布版本 | 覆盖与剩余缺口 |
| --- | --- |
| **glob 0.3.4** | `Pattern::matches_with(&str, ...)` 按 `char` 迭代，`?` 可匹配 `é`，有字符类；`require_literal_separator(false)` 可让通配符跨 `/`。但 Windows `chars_eq` 无条件把 `/` 与 `\` 当相等；不区分大小写仅 ASCII。逐 key 组件匹配仍不能消除真实 `/` 与 `\` 的别名问题。 |
| **wax 0.7.0** | Unicode 正则、Unicode 简单折叠；`?` 匹配 `é`、`(?i)É` 匹配 `é`。但 Windows 将 `/` 和 `\` 硬编码为分隔符，通配符与类排除二者，无“纯字符串 / 可指定单一分隔符”配置。`CandidatePath::from(&str)` 不需有损转换，仍不能改变这些匹配规则。公有 API 没有导出可改写的完整 token AST 或底层 Regex；`captures()` 不是完整语法树。 |
| **glob-match 0.2.1** | 紧凑的路径 glob 引擎，源码先转 `as_bytes()`，并使用平台 `is_separator`；不能解决本题的 Unicode `?` 与纯字段分隔符要求。 |
| **wildmatch 2.7.0** | 纯字符串 `char` 匹配，`/`、`\` 为普通字符；但只有 `*` / `?`，无 `[]`，不满足已定字符类。新版本 caseless 逐字符 `to_lowercase` 比较，也不是 regex 的完整简单折叠等价关系。 |

证据：[glob MatchOptions](https://docs.rs/glob/0.3.4/glob/struct.MatchOptions.html)、[glob 源码包，`chars_eq` / `matches_from`](https://static.crates.io/crates/glob/glob-0.3.4.crate)；[wax 文档](https://docs.rs/wax/0.7.0/wax/)、[wax 源码包，`src/encode.rs` / `src/lib.rs`](https://static.crates.io/crates/wax/wax-0.7.0.crate)；[glob-match 源码包](https://static.crates.io/crates/glob-match/glob-match-0.2.1.crate)；[wildmatch 源码包](https://static.crates.io/crates/wildmatch/wildmatch-2.7.0.crate)。本机执行了 glob 与 wax 表中示例；另两项为源码核实。

### 能具体评审的适配 / 契约取舍

以下是**可选方向，未获用户接受**，不是替实际模块选型：

1. **直接采用 globset 路径语义**：工程最少，但须修改真实 `/`、字段 `\`、字符类不跨层、`Vendor\**` 包含自身，以及 Unicode 字符 / 大小写等多个既定规则。不能把它描述为兼容现有契约。
2. **globset 语法前端 + bytes Regex + key 组件适配**：可保留注册表分层与真实 `/`，不重写 glob 解析器。普通字段先以已有 regex 把连续 `*` 归为单 `*`，用 `str::replace` 将字面 `\` 加倍；`GlobBuilder` 开启 `backslash_escape(true)`、`literal_separator(false)`。保持 `Glob::regex()` 的 `(?-u)`，以 `regex::bytes::RegexBuilder` 编译并开启 `dot_matches_new_line(true)`，**绕过所有 Candidate / Path API**。KEY 先按领域 `\` 分为组件，独立组件 `**` 由组件序列匹配处理，其他组件使用同一现成引擎；零层分支可自然让 `Vendor\**` 包含 `Vendor`。这保留了路径契约，但**必须接受 byte glob**：`?` 是一字节，`[中]` 不匹配 `中`，caseless 仅 ASCII。外层完整组件序列匹配是推论，未实现或验证产品级 DP。
3. **坚持 Unicode 标量 glob 和原有分隔符规则**：优先评审上文已有的 yash-fnmatch AST→regex 方案，而非为 globset 重建字面量或字符类。另一方向是上游修补 / fork，但那已不是仅采用已发布 crate；例如 fork glob 涉及平台分隔符等价比较、`**` 的解析 / 组件匹配以及 Unicode 大小写和类范围，不能可靠承诺只改一行。

方向 2 的**已测部分**：`A\B` 匹配同名且不匹配 `A/B`；`A*B` 匹配真实 `A/B`；`中文😀` 字面匹配；否定类匹配换行；`A/**/B` 归并连续星后不会因文件系统递归语义错误匹配 `A/B`。归并连续星也让字段中的 `**` 保持普通字符串通配语义，不因真实 `/` 触发库的目录递归识别。字符类里的重复 `*` 集合不变。上述均是指定版本的有限探针，未证明所有模式组合兼容，也未接受这些字节语义作为产品规则。

## 时间：chrono 与 humantime 的组合边界

| 输入 / 规则 | 现有能力与最小适配 |
| --- | --- |
| `YYYY-MM-DD` → 当日本地午夜 | chrono `NaiveDate::parse_from_str(..., "%Y-%m-%d")`、`and_hms_opt(0,0,0)`、`Local.from_local_datetime`。需要 `clock` 功能读取本机时区。不能把日期先解释为 UTC 午夜。 |
| 严格日期词法 | **实测** chrono 仍接受 `2026-1-2`；若产品只接受十字符 `YYYY-MM-DD`，先作小范围形状检查，再交库验证真实日期，无需自己实现日历。 |
| 带时区 RFC 3339 | chrono `DateTime::parse_from_rfc3339` 接收 `2026-11-19T00:00:00+08:00`，得到 FixedOffset 时间后可转 UTC。 |
| `7d` / `12h`；1d = 24h | humantime `parse_duration` 分别得到 604800 / 43200 秒，`1d` = 86400 秒。它解析固定时长，不是“上个本地日历日”。 |
| 更宽的时长语法 | humantime 还接受 `1day 2hours`、周、月、年等语法；若不想产品自动接受，先限定允许的单位 / 形状。月年为库定义的固定时长，不能误称日历算术。 |
| 相对同一次查询开始 | 捕获一次 wall-clock `query_started_at`，对所有相对参数用同一对象的 `checked_sub_signed`；不得每个 TIME 独立调用 `now()`。这属于上下文组合，不是库自动保证。 |
| 重复上下界 | 在同一时间域取 after 最大值、before 最小值，再用严格 `>` / `<`；相反边界产生零命中，不是解析错误。 |

上述能力见 [chrono DateTime](https://docs.rs/chrono/0.4.45/chrono/struct.DateTime.html)、[TimeZone](https://docs.rs/chrono/0.4.45/chrono/trait.TimeZone.html)、[Local](https://docs.rs/chrono/0.4.45/chrono/struct.Local.html)、[humantime duration 源码](https://docs.rs/crate/humantime/2.4.0/source/src/duration.rs)。本地日期 / 时长的组合为推论；数值和日期宽松词法已实测。

**薄词法校验候选**：已有 regex `\A(?:[0-9]+(?:ns|us|ms|s|m|h|d|w))+\z` 可先限定整数字段及已列单位，再交 humantime 做数值 / 溢出解析；无须自写通用 duration parser。`1h30m` 实测为 5400 秒；`1ns / 1us / 1ms / 1s / 1m / 1h / 1d / 1w` 均解析成功。是否接受这组单位 / 组合以及排除月年，是产品词法决定，不由“库能解析更多”自动扩张。

**不要仅用 humantime 解析全部 TIME**：2.4.0 的 `parse_rfc3339` 接受 UTC `Z` / `+00:00`，但本机实测拒绝非零偏移 `+08:00`；`parse_rfc3339_weak` 还允许缺少时区并按 UTC，不能满足本地日期和必须带偏移的完整时间契约。[humantime 时间戳源码 `src/date.rs`](https://static.crates.io/crates/humantime/humantime-2.4.0.crate)

**待定**：本地 00:00 可能处于时区跳变的重叠或缺口，chrono 返回 `Single / Ambiguous / None`，没有替用户默认选择；不能 `.unwrap()`。还需明确闰秒、超出 FILETIME / chrono 可比较范围、相对时长下溢、允许的时长单位及小数精度。查询时刻统一不代表整个注册表是一致快照，也不会把键修改时间变成值级时间。[MappedLocalTime](https://docs.rs/chrono/0.4.45/chrono/offset/type.MappedLocalTime.html)

## 环境：现有能力可兑现捕获 Map 的单遍展开

### 两个现成环境库为何不直接适配

| 精确发布版本 | 核实结果 |
| --- | --- |
| **envmnt 0.10.4** | `ExpansionType::Windows` 支持 `%NAME%`，`ExpandOptions.default_to_empty=false` 可保留未找到的引用，Windows 分支对原始输入逐字符扫描、插入值不重扫。但公开 `expand(&str, Option<ExpandOptions>)` 没有 Map / lookup closure；`src/expansion.rs` 对每个引用直接 `std::env::var`。它读实时环境且只返回 String，不能仅靠配置兑现捕获快照 / 非良构值保真。默认还会把未知变量变空串，不能照默认调用。 |
| **shellexpand 3.1.2** | 有 context 闭包，可保留未知引用，但语法是 `$A` / `${B}`，还包含默认值及 `~` 展开；没有 Windows `%NAME%` 模式。将 `%` 改成 `$` 会引入额外语法和歧义，不能当无损规范化。 |

证据：[envmnt 公开 API](https://docs.rs/envmnt/0.10.4/envmnt/fn.expand.html)、[envmnt 发布源码包](https://static.crates.io/crates/envmnt/envmnt-0.10.4.crate)；[shellexpand 文档](https://docs.rs/shellexpand/3.1.2/shellexpand/)、[发布源码包](https://static.crates.io/crates/shellexpand/shellexpand-3.1.2.crate)。本表为文档 / 源码核实，未临时改进程环境来迎合这些库。

### 更小的现成组合

**文档**：`std::env::vars_os()` 已保证返回调用时进程环境的快照，后续环境修改不会进入该迭代器；它保留 OS 字符串而不要求合法 Unicode。收集成一次拥有的集合即可绑定查询生命周期，不能改用每个命中时的 `std::env::var`。[vars_os 快照保证](https://doc.rust-lang.org/std/env/fn.vars_os.html)

**推论与有限实测**：用固定 regex `%([^%]*)%` 的 `replace_all` 闭包，查捕获 Map，找到即返回保存的替换串，找不到返回整个捕获原文。库扫描原始 haystack 的非重叠匹配，不重扫闭包产生的文本；闭包返回的 `$1` 是文字，不是又一次捕获引用插值。构造 Map `A=%B%`、`B=$1`、`E=""`，输入 `%a%|%B%|%MISSING%|%E%|%%|tail%` 得到 `%B%|$1|%MISSING%||%%|tail%`。允许空捕获可以让 `%%` 成对消耗并原样保留，故 `%%A%` 不会误把第二个 `%` 当 `%A%` 起点，实测完整保留。此探针仅用 ASCII 忽略大小写查找，**不证明完整 Windows 名称比较**。[replace_all](https://docs.rs/regex/1.13.2/regex/struct.Regex.html#method.replace_all)、[Replacer 闭包](https://docs.rs/regex/1.13.2/regex/trait.Replacer.html)

```rust
// 构造示意：snapshot 在查询开始捕获，此函数不再读实时环境。
let refs = regex::Regex::new(r"%([^%]*)%")?;
let expanded = refs.replace_all(saved_text, |c: &regex::Captures<'_>| {
    if c[1].is_empty() { return c[0].to_owned(); }
    lookup_in_snapshot(&c[1])
        .map(str::to_owned)
        .unwrap_or_else(|| c[0].to_owned())
});
```

`lookup_in_snapshot` 的名字比较不能用普通 `HashMap<String, _>` 的默认大小写敏感查找，也不能未经验证用 Unicode `to_lowercase` 冒充 Windows。第一方 Rust 1.99.1 的 Windows `EnvKey` 比较使用 `CompareStringOrdinal(..., TRUE)`；该 Win32 API 按操作系统大写表作 ordinal 比较，接受显式 UTF-16 长度。小适配可采用同类比较来索引 / 查找捕获 Map；这需要现成 Windows 绑定，**不是新写 Unicode 折叠表**。`EnvKey` 是标准库内部实现，不能直接导入。[Rust 1.99.1 EnvKey 源码](https://github.com/rust-lang/rust/blob/1.99.1/library/std/src/sys/process/windows.rs)、[CompareStringOrdinal](https://learn.microsoft.com/en-us/windows/win32/api/stringapiset/nf-stringapiset-comparestringordinal)

**待确认的具体扫描契约**：从左向右、非重叠取最近一对 `%`，空段 `%%` 原样保留并消耗，未知 / 未闭合保留，已知空变量替换为空串，插入值不重扫。上面固定 regex 已能表达这套候选，无需通用环境语法解析器；它不声称复制 Windows 全部未文档化行为。引用名包含空白 / `=` / `:` 时按捕获 Map 查找，不能引入 cmd 子串 / 替换语法。环境快照中的非良构 UTF-16 名称 / 替换值不能经有损转换进入 String；若该引用确实用于判断，应交已有“解释不可用”策略处理，不当未知变量蒙混过去。

适用类型的检查放在展开调用前，**只处理 REG_EXPAND_SZ**，模式参数自身不展开；未知变量保留与空变量替换为空串是不同情况。保存数据、派生展开文本及逻辑空状态仍分开；库不应改变已定的数据组 OR 规则。原生 `ExpandEnvironmentStringsW` 没有传入捕获 Map 的参数，不能以“先获取快照，再照常调用原生函数”代替上述保证。[ExpandEnvironmentStringsW](https://learn.microsoft.com/en-us/windows/win32/api/processenv/nf-processenv-expandenvironmentstringsw)

## Windows 字符串、MULTI_SZ 与整数：事实不等于拒绝策略

### 保真工具

**文档与实测**：`OsString::from_wide` / `encode_wide` 能无损往返，包括孤立代理项；`encode_wide` 不补末尾 NUL。可选 `widestring 1.2.1` 的 `U16String / U16Str` 保存任意 u16 序列与内嵌 NUL，不强制 UTF-16 合法；`to_string()` 校验，`to_string_lossy()` 会改变内容。`U16CString` 可用于需要单个 NUL 结尾且禁止内嵌 NUL 的名称 FFI，但不能用它直接代表整块原始值数据或 MULTI_SZ。[OsStrExt](https://doc.rust-lang.org/std/os/windows/ffi/trait.OsStrExt.html)、[widestring 类型分工](https://docs.rs/widestring/1.2.1/widestring/)

原始字节仍用 `Vec<u8>`；即使预期 UTF-16，也先检查偶数字节再按字节序形成 u16，不能直接把任意字节切片强转为要求对齐的 `[u16]`。`String::from_utf16` 支持内嵌 NUL但拒绝孤立代理项；NUL 本身不是非法 Unicode。[String::from_utf16](https://doc.rust-lang.org/std/string/struct.String.html#method.from_utf16)

### Microsoft 的原始依据

- Microsoft 定义 SZ / EXPAND_SZ 为 NUL 终止字符串；MULTI_SZ 是 NUL 终止的多个字符串，最后由空字符串结束，不能在序列中表示零长度元素；同页明确给出空序列 `\0`，也提醒正常非空 MULTI_SZ 需双 NUL。**不能只看“双 NUL”一句就把单 NUL 的空序列强行判错**。[Registry value types](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types)
- `RegQueryValueExW` 明确**不保证**读回字符串具有正确终止符；实际字节数包括已经存储的终止符，若写入时没有则也不会凭空包含。缺 NUL 是真实可读的布局，不等于 API 读取失败。[RegQueryValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)
- `RegSetValueExW` 要求字符串写入长度计入终止符、MULTI_SZ 计入最后两个 NUL；这规定正确布局，不证明存储中的所有旧值已满足。[RegSetValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw)
- `RegGetValueW` 会检查 / 补字符串终止符，并默认展开 EXPAND_SZ；`RRF_NOEXPAND` 只能关闭展开，不关闭补终止符。该输出不能普遍证明原始存储字节。[RegGetValueW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew)
- DWORD 为 32 位，DWORD_BIG_ENDIAN 有明确大端类型；QWORD 为 64 位。`RegGetValueW` 的 DWORD / QWORD 限制 flag 可接受对应宽度的 binary，而这不代表项目应把 REG_BINARY 自动当整数。[Registry value types](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types)、[RegGetValueW flags](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew)

### 用户已确认的解释规则与 Microsoft 事实边界

下表用 UTF-16 代码单元表示字符串，`0` 为 NUL；数据读回本身均可成功。**研究期间用户已确认下列解释规则；这是产品选择，不是 Microsoft 强制要求。** 它接受 SZ / EXPAND_SZ 缺末尾 NUL，但对 MULTI_SZ 采用严格双 NUL 布局；这种差别应明确记录，而不是笼统宣称“所有字符串终止异常都不可解释”。

| 类型 / 原始布局 | 可证事实 | 本次用户选择及必须保留的边界 |
| --- | --- | --- |
| SZ / EXPAND_SZ：`A,0` | 常规单字符串布局 | 去一个格式终止符，匹配保存文本 `A`；保留原始字节。 |
| SZ / EXPAND_SZ：`A`，没有末尾 0 | UTF-16 可以完全有效；Microsoft 明说真实存储可能未终止 | 按保存长度严格解码为 `A`，缺末 NUL 仍接受。没有文档要求只因这点就拒绝按长度文本匹配。向 NUL 终止 FFI 传递前只能在独立缓冲补 NUL，不改原始数据。 |
| SZ / EXPAND_SZ：`A,0,0` 或更多尾 0 | Microsoft 没定义查询工具应剥几个 | 最多剥一个末尾格式 NUL；其余 NUL 是数据匹配文本内容。不能 `trim_end_matches(0)`。 |
| SZ / EXPAND_SZ：`A,0,B,0` | 中间 NUL 是有效码点 | 保留文本 `A\0B`；不能只取 `A` 后忽略剩余字节。原生 NUL 终止展开会截断，基于 regex / Map 的按长度展开可以保留它。 |
| 字符串类：奇数字节数 | 不能把全部字节分成 UTF-16 单元 | 不应丢末字节 / 补零后冒充原文。原始字节和类型仍可查询；需要完整文本判断时依既定失败策略。 |
| 字符串 / 名称：孤立代理项 | u16 仍可无损保存，但不是 Unicode 标量序列 | 数据文本严格解码失败，保留原始内容；名称的必要判断失败处理仍按最终名称契约，不能用替换字符伪造。 |
| MULTI_SZ：`A,0,B,0,0` | 两个元素加结束空字符串 | 按元素匹配 `A`、`B`，不拼接；末尾格式 NUL 不进入元素文本。 |
| MULTI_SZ：`0`；`0,0` | Microsoft 明写空序列为 `\0`；第二种是常见双终止布局 | 产品严格要求双 NUL：`0,0` 恰好表示空序列；`0` 不可解释。**拒绝单 NUL 空序列是产品额外限制，不能引用 Microsoft 说它必然无效。** |
| MULTI_SZ：`A,0,B` 或 `A,0,B,0` | 最后元素 / 序列缺结束布局，但元素编码可能完整 | 产品选择不可解释，不补终止符后冒充保存布局。 |
| MULTI_SZ：`A,0,0,B,0,0`；多余尾 NUL | 标准空字符串已结束序列；后面仍有存储单元 | 产品选择提前终止后残留 / 多余尾 NUL 均不可解释；不能当正常空元素或丢后缀。MULTI_SZ 各元素也要严格 UTF-16。 |
| 任意类型：零字节 | 实际存在、长度为 0，与缺失不同 | `--data-zero-length` 据原始长度判断；SZ / EXPAND_SZ 解释为空字符串，MULTI_SZ 不满足双 NUL 布局不可解释，整数不满足宽度不可解释。不能假造整数 0。 |
| DWORD / DWORD_BE 长度 4，QWORD 长度 8 | 与声明位宽一致 | 已有 `u32::from_le_bytes / from_be_bytes`、`u64::from_le_bytes` 足够；转无符号十进制文本，无需新整数库。 |
| 整数长度 0 / 1 / 3 / 5 / 7 / 9 等 | 不是对应位宽的完整表示 | 产品选择 DWORD 恰 4、QWORD 恰 8 字节，其他长度不可解释；不得截断、补零或读越界。原始 bytes / type 判断仍可用。 |

表中“可证事实”来自长度、Unicode 与 Microsoft 类型结构；右列是本次用户明确选择。解释只在当前谓词确实需要时进行，其他 OR 条件已足以决定命中时，不需强制触发多余解码失败。

## 原始十六进制参数：hex 0.4.3

**发布事实 / 源码 / 实测**：当前稳定发布版为 hex 0.4.3。`hex::decode` 已处理大小写十六进制字符、奇数位及非法字符错误；输入前用标准库筛去已允许的 ASCII 空白，即可支持 `DEADBEEF` 与 `DE AD BE EF`。`decode("")` 自身成功得到空 Vec，产品要另行拒绝空 HEX / 规范化后为空，不能把它当“匹配空数据”。这只是格式规范化和产品非空约束，不需自写通用 hex parser。[版本元数据](https://crates.io/api/v1/crates/hex/0.4.3)、[hex::decode](https://docs.rs/hex/0.4.3/hex/fn.decode.html)、[发布源码](https://static.crates.io/crates/hex/hex-0.4.3.crate)

## 取消：ctrlc 足够接事件，查询层决定结束

**文档 / 源码**：ctrlc 3.5.3 设置一个闭包，建立专用处理线程；Windows 后端使用 `SetConsoleCtrlHandler`、信号量与等待循环。可用闭包置 `AtomicBool`，避免另写 Console Handler FFI。只能安装一个 crate 级处理器，注册失败必须向调用方返回；处理器不会自动使产品以 130 退出。[ctrlc 3.5.3 源码包，`src/lib.rs` 与 `src/platform/windows/mod.rs`](https://static.crates.io/crates/ctrlc/ctrlc-3.5.3.crate)

**推论**：串行流式查询在枚举、读取前后及结果写出边界检查取消标记，关闭持有资源，保留已输出结果后返回 130；正常输出失败仍是另一种失败。该 crate 不会抢占正在执行的注册表 Win32 调用，也不保证强制关闭窗口 / 系统关机时能够完整清理。Windows 控制事件的系统超时与终止规则见 [HandlerRoutine](https://learn.microsoft.com/en-us/windows/console/handlerroutine)。本次未向用户控制台发送 Ctrl+C，也未实测取消延迟、第二次 Ctrl+C、管道输出阻塞或跨终端行为。

## 探针范围、复现与未验证事项

环境：本机 `rustc 1.99.1 (58cf8f9c3 2026-10-13)`，`x86_64-pc-windows-msvc`。使用现有编译器，无安装 / pin 工具链。独立 manifest 直接依赖精确锁定 `clap=4.6.8`、`regex=1.13.2`、`globset=0.4.21`、`glob=0.3.4`、`wax=0.7.0`（关闭 walk）、`yash-fnmatch=1.1.2`、`fnmatch-rs=0.1.0`、`chrono=0.4.45`、`humantime=2.4.0`、`widestring=1.2.1`、`hex=0.4.3`；Cargo.lock 中 clap_builder=4.6.7、regex-syntax=0.8.12。总计 **114 个带预期值的构造断言通过**，不是产品集成测试或全组合证明。

核心 glob 反例可在同版本独立项目复现：

```rust
use globset::GlobBuilder;
fn direct(p: &str, s: &str, sep: bool, ci: bool) -> bool {
    GlobBuilder::new(p).backslash_escape(false)
        .literal_separator(sep).case_insensitive(ci)
        .build().unwrap().compile_matcher().is_match(s)
}
assert!(direct(r"A\B", "A/B", true, false));       // 两种名称混同
assert!(direct("A[!x]B", r"A\B", true, false));    // 类仍跨层
assert!(!direct(r"Vendor\**", "Vendor", true, false));
assert!(!direct("?", "é", false, false));
assert!(direct("??", "é", false, false));
assert!(!direct("É", "é", false, true));

// 只用于明确接受 byte glob 后的普通字段 / 单组件小适配。
fn byte_field(p: &str, s: &str) -> bool {
    let collapsed = regex::Regex::new(r"\*+").unwrap()
        .replace_all(p, "*").into_owned();
    let quoted = collapsed.replace('\\', "\\\\");
    let g = GlobBuilder::new(&quoted).backslash_escape(true)
        .literal_separator(false).build().unwrap();
    regex::bytes::RegexBuilder::new(g.regex())
        .dot_matches_new_line(true).build().unwrap().is_match(s.as_bytes())
}
assert!(byte_field(r"A\B", r"A\B"));
assert!(!byte_field(r"A\B", "A/B"));
assert!(byte_field("A*B", "A/B"));
assert!(byte_field("中文😀", "中文😀"));
assert!(!byte_field("[中]", "中")); // 这个限制没有被适配消除
```

其余断言验证：clap 主名 / 别名累积、空串 / 前导连字符、重复 bool、孤立代理项 `OsString` 往返、String 拒绝该参数、裸帮助错误码差异；regex 子串 / 空模式 / 简单折叠 / 不支持语法；widestring 的原始保留与 checked 解码；捕获 Map 的单遍替换；chrono 的 RFC 3339 偏移与宽松日期、humantime 固定时长和非零时区拒绝。

未验证：ARM64 / x86、最低支持系统、最终 shell 端到端传参；真实注册表异常数据；所有 glob 类 / 替代 / 范围组合及组件 DP；本地午夜在实际 Windows 历史时区跳变中的解析、闰秒与 FILETIME 边界；完整 Unicode 环境名比较及非良构环境值；实际控制台取消。资源上限、错误优先级与用户尚未接受的异常策略不由库调研代为确定。
