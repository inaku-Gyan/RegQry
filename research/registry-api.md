# Rust 注册表访问方案与 Windows 语义调查

调查日期：2026-11-18。问题：本机实时注册表搜索，以及明确单个键（key）或值（value）的创建、修改、删除，可以采用哪些接口，哪些 Windows 语义必须进入后续产品契约？

范围沿用地图：Windows、Rust、个人本机排查兼顾脚本；不调查远程、离线 hive、批量替换或批量删除。以下“事实”来自第一方文档/源码；“推断”“建议”均不代表已经采用的设计。未安装 crate，也未读写用户注册表。

## 方案比较：已核实事实

| 方案 | 覆盖与约束 |
| --- | --- |
| `winreg` 0.56.0 | 专用封装，底层依赖 `windows-sys`；`RegKey` 负责关闭句柄，方法返回 `io::Result`。有键/值枚举、`OsString` 名称接口、原始值读写、创建/删除、显式权限/视图，以及 `REG_OPTION_OPEN_LINK` 选项。普通 `open_subkey` 请求 `KEY_READ`，普通 `create_subkey` 请求 `KEY_ALL_ACCESS`，均可改用 flags 方法。[RegKey 与源码](https://docs.rs/winreg/latest/winreg/reg_key/struct.RegKey.html)、[依赖及 MIT 元数据](https://raw.githubusercontent.com/gentoo90/winreg-rs/master/Cargo.toml)。 |
| `windows-registry`（当前文档 0.100.0） | Microsoft 专用安全封装；`Key::open` 请求 `KEY_READ`，`create` 请求 `KEY_READ` 与 `KEY_WRITE`，`Drop` 关闭句柄。常规路径/名称接受 `AsRef<str>`，枚举返回 `String` 且源码用 `from_utf16_lossy`，未见 OsString/原始 UTF-16 名称枚举；原始值接口另接受 `PCWSTR` 值名。`Value` 保留字节，`Type::Other(u32)` 保留未知类型码；`get_bytes` 只接受 BINARY，任意类型用 `get_value`/原始接口。文档列 `wow64_32`/`wow64_64`；未见 `OPEN_LINK` 公开选项或非递归键删除，仅 `remove_value`、递归 `remove_tree`，可通过 `as_raw`/`from_raw` 与直接绑定互通。[Key 源码](https://docs.rs/windows-registry/latest/src/windows_registry/key.rs.html)、[权限/视图](https://docs.rs/windows-registry/latest/windows_registry/struct.OpenOptions.html)、[枚举源码](https://raw.githubusercontent.com/microsoft/windows-rs/master/crates/libs/registry/src/value_iterator.rs)、[原始 Value](https://docs.rs/windows-registry/latest/windows_registry/struct.Value.html)、[Type](https://docs.rs/windows-registry/latest/windows_registry/enum.Type.html)。 |
| `windows` 0.62.2 | Microsoft 的类型化绑定；能直接调用相同 Win32 注册表 API。这里的 `RegQueryValueExW` 仍为 `unsafe`，返回 `WIN32_ERROR`，不是自动生成的 `Result`；`HKEY` 可复制，未实现 `Drop`，调用方仍须安排关闭与缓冲区管理。[函数签名](https://microsoft.github.io/windows-docs-rs/doc/windows/Win32/System/Registry/fn.RegQueryValueExW.html)、[HKEY](https://microsoft.github.io/windows-docs-rs/doc/windows/Win32/System/Registry/struct.HKEY.html)。 |
| `windows-sys` 0.61.2 | 原始函数、结构体和常量，无便利封装；指针、长度、错误码和资源所有权由调用方处理。`REG_VALUE_TYPE` 是 `u32`；`windows` 对应类型也是公开包裹 `u32`，可表达非标准类型码。[crate 说明](https://docs.rs/crate/windows-sys/latest)、[函数签名](https://docs.rs/windows-sys/latest/windows_sys/Win32/System/Registry/fn.RegQueryValueExW.html)、[原始类型](https://docs.rs/windows-sys/latest/windows_sys/Win32/System/Registry/type.REG_VALUE_TYPE.html)、[类型化类型](https://microsoft.github.io/windows-docs-rs/doc/windows/Win32/System/Registry/struct.REG_VALUE_TYPE.html)。 |
| `reg.exe` 子进程 | `query` 支持递归、键名/数据模式及 32/64 位视图；`add`、`delete /v`、`delete /ve` 覆盖键/命名值/未命名值操作。文档返回码只有成功 `0`、失败 `1`；未规定 JSON 等结构化输出或逐键错误模型。`delete` 不指定值时会删除整棵子树，与 Win32 非递归删除不同。[query](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-query)、[add](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add)、[delete](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-delete)。 |

版本限制：`windows-registry` 的常规迭代项不含 `Result`；当前主分支源码将枚举中的非零返回转为 `None`，并有 debug 断言，这与 `winreg` 的逐项错误接口不同。[键迭代](https://raw.githubusercontent.com/microsoft/windows-rs/master/crates/libs/registry/src/key_iterator.rs)、[值迭代](https://raw.githubusercontent.com/microsoft/windows-rs/master/crates/libs/registry/src/value_iterator.rs)。检索所得 latest 文档与部分源文件缓存存在版本差异；上行区分了文档与主分支源码，未成功取得 0.100.0 发布包复核，不能把主分支行为直接视为版本保证。选定版本后须复核上述接口，特别是视图、错误和异常数据行为；Microsoft 当前推荐优先考虑覆盖任务的专用 crate。[官方项目说明](https://github.com/microsoft/windows-rs)。

## Windows 特有语义：已核实事实

**身份与默认值。** 键构成层级，键名不能含反斜杠；值名可以含反斜杠，不能把值名当子路径。键名和值名均不区分大小写。空值名 `""` 表示未命名值（unnamed/default value），它可以不存在，也可以是任何类型；“缺失”“空字符串”“零字节数据”不是同一状态。[结构](https://learn.microsoft.com/en-us/windows/win32/sysinfo/structure-of-the-registry)、[值名大小写](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletevaluew)、[默认值语义](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)。

**保真。** Win32 读取返回类型码和字节长度；字符串可能缺失终止 NUL。`REG_EXPAND_SZ` 是未展开的环境变量字符串，`REG_MULTI_SZ` 有双 NUL 终止，DWORD 另有大端类型；还存在 NONE、BINARY、QWORD、LINK、资源描述类型。`RegGetValueW` 会补字符串终止符，且需 `RRF_NOEXPAND` 才禁止环境展开，因此便利读取不等于原始存储。[类型](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types)、[RegGetValueW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew)。`winreg` 原始值保存字节和 `RegType`，但只接受类型码 0..11，其他码报 `ERROR_BAD_FILE_TYPE`；`String` 转换使用 `from_utf16_lossy`、去尾 NUL，并把 MULTI_SZ 分隔 NUL 转为换行；名称的 String 枚举转换失败会报错，另有 OsString 枚举。[原始读取源码](https://docs.rs/winreg/latest/src/winreg/reg_key.rs.html)、[转换源码](https://docs.rs/winreg/latest/src/winreg/types.rs.html)、[名称枚举源码](https://docs.rs/winreg/latest/src/winreg/enum_values.rs.html)。

**视图与根键。** WOW64 的默认视图取决于进程架构；`KEY_WOW64_32KEY`/`64KEY` 可明确选视图，不能同时指定。子键后续 open/create/delete 应继续显式携带相同标志；搜索两视图要分两遍，共享键可能指向同一存储。`Wow6432Node`/`WowAA32Node` 是保留实现路径。ARM 的 32 位视图还与进程架构相关，不能直接把 x64 观察外推至 ARM64。[替代视图](https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view)、[共享/重定向键](https://learn.microsoft.com/en-us/windows/win32/winprog64/shared-registry-keys)。HKCU 映射当前用户在 HKU 下的分支；HKCC 是 HKLM 硬件配置路径的别名；HKCR 合并用户/机器 `Software\Classes`，用户设置优先，写键和值的落点规则不同。[预定义根键](https://learn.microsoft.com/en-us/windows/win32/sysinfo/predefined-keys)、[HKCR 合并与写入](https://learn.microsoft.com/en-us/windows/win32/sysinfo/hkey-classes-root-key)。UAC 注册表虚拟化（registry virtualization）另是旧程序兼容机制，可把写入导向用户存储；64 位进程或含 `requestedExecutionLevel` 的进程禁用它，不能与 WOW64 视图混为一谈。[虚拟化范围](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-virtualization)。

**枚举和权限。** `RegEnumKeyExW`/`RegEnumValueW` 按索引逐项读取，顺序未定义；结束是 `ERROR_NO_MORE_ITEMS`，缓冲区过小是 `ERROR_MORE_DATA`。Microsoft 明示枚举期间应用不应修改该键；大小查询后的数据也可能增长，不能把预先取得的长度视为恒定。[键枚举](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regenumkeyexw)、[值枚举](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regenumvaluew)、[读取缓冲区](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)。枚举子键、读取值、设置/删除值分别需要 `KEY_ENUMERATE_SUB_KEYS`、`KEY_QUERY_VALUE`、`KEY_SET_VALUE`；ACL 决定访问，打开父键成功不保证子键可读。部分创建/删除检查安全描述符而非父句柄权限，`KEY_READ` 句柄不是通用防写边界。[访问权](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights)、[打开键的访问检查](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw)。

**编辑与链接边界。** `RegCreateKeyExW` 会打开已有键并可创建缺失的中间键；`RegSetValueExW` 设置类型及数据，值不存在则新增。`RegDeleteKeyExW` 仅接受没有子键的键，但连同该键所有值删除；最后句柄关闭后才移除。[创建](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcreatekeyexw)、[设置](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw)、[删除](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletekeyexw)。Win32 有 `REG_OPTION_OPEN_LINK`；Microsoft 的 MS-RRP 协议进一步规定未指定它时跟随目标、指定时打开链接源，并支持链接链。协议说明不能代替本机所有链接/删除行为的实测。[Win32 选项](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw)、[MS-RRP 链接语义](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-rrp/d5ce9dcc-1f90-4f5a-b076-cc1d2c9b4195)。

## 推断与建议，留待决定

- 推断：实时树遍历不能承诺一致快照；搜索后到编辑前也可能被其他进程改动。结果完整性、缺失/拒绝访问如何报告，以及覆盖前是否复查，仍是产品契约问题。
- 推断：直接绑定的工程成本在安全封装、重试和错误上下文；`reg.exe` 的成本在启动/取消子进程、文本与编码解析、错误细分，尚无基准证明性能差距。若后续试验子进程，可用 `Command::arg` 逐项传参；Rust 文档说明它不经过 shell。[Rust Command](https://doc.rust-lang.org/std/process/struct.Command.html#method.arg)。
- 建议：后续选型明确需要何种原始保真和非 UTF-8 名称能力，并分别决定视图、HKCR 写入、链接跟随与非空键删除；本报告不指定最终库或编辑策略。

## 尚未验证

后续可在专用临时测试键中验证：异常 UTF-16/缺失 NUL/未知类型码和原始读写往返（含 `windows-registry` 原始写入对缺失 NUL 的 debug 断言）；两视图、共享键及目标架构；并发增删、数据增长、访问拒绝及各库迭代错误；断链/链接链或循环；创建中间键、删除非空键和编辑前目标变化。若保留 `reg.exe` 候选，另测不同语言/重定向输出编码、特殊名称/引号、取消、错误信息及本机 `/?` 与在线文档的参数差异（在线 `reg delete` 未列视图参数）。这些验证尚未运行，不能作为首版支持保证。
