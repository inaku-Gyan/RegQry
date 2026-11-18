# Windows 原生 CLI 字面参数与 ROOT / TYPE 事实研究

研究日期：2026-11-19。对应 registry-cli 研究工单 21；独立分支自 `main` 的 `34e02fa` 建立。只确认传输和系统语义，不决定 RegQry 的命令布局、参数名、解析库或产品工具链。文中的 `--option` / `--value` 只是探针收到的普通文本；这些事实同样适用于 ROOT / REGEX / GLOB / TYPE / HEX 等过滤输入，不假定另设查看命令。

## 结论与证据等级

- **文档保证**：Windows `CreateProcessW` 接收一条以 NUL 终止的宽字符命令行，并没有由操作系统直接提供统一的 `argv` 数组；分参取决于被调用程序的运行时。Microsoft CRT、`CommandLineToArgvW`、Rust 的解析器不能一概视为同一实现。[CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)、[CommandLineToArgvW](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-commandlinetoargvw)、[Rust 1.99 Windows 参数源码](https://github.com/rust-lang/rust/blob/1.99.0/library/std/src/sys/args/windows.rs)
- **文档保证 + 本机观察**：PowerShell 7.3 起的 `Standard` / `Windows` 原生参数模式保留空字符串和内嵌双引号；Windows PowerShell 5.1 与 `Legacy` 不具有这项保证。不能只写“支持 PowerShell 7”而省略版本与模式。[about_Parsing](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5)
- **推论，由探针支持**：`--option=value` 可使空值与前导 `-` 的值成为一个明确的非空参数；是否接受这种形式仍由 CLI 解析器决定。它不能修复 shell 已吞掉的引号、展开的变量或被 NUL 截断的命令行。
- **本机观察**：普通 Unicode、构造的非零控制字符、孤立 UTF-16 代理项可以到达原生宽字符参数接口。可到达不等于可以方便地在终端键入，也不等于任何 CLI 字符串类型都能无损接收。
- **文档推论 + 本机观察**：真实 U+0000 不是普通 Win32 命令行参数内容；ASCII 编码后再由 CLI 解码不能解除注册表名称 API 自身的 NUL 终止边界。编码入口是否纳入首版属于产品决定，本报告不预选。

## 调用分层：哪里可能先损坏

`shell 源文本 → shell 展开及引用 → Windows 宽字符命令行 → 运行时 argv → CLI 选项解析 → 名称传给 Win32 API`。

1. **shell 引用（quoting）**首先处理语法。PowerShell 单引号字符串不展开变量，双引号字符串会展开变量及子表达式；反引号是其转义字符。单引号能保护 PowerShell 表达式层的字面内容，但 Windows PowerShell 5.1 后续的原生参数序列化仍可能损坏其中的双引号。[about_Quoting_Rules](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_quoting_rules?view=powershell-5.1)
2. `cmd` 会处理 `%NAME%`；延迟展开启用时还处理 `!NAME!`。引号不意味着禁止变量展开。`/d` 禁止 AutoRun，`/v:off` 禁止延迟展开，二者都是子进程本次调用设置，不改持久配置。元字符和 `/c` 的外层引号又是一层规则。[cmd](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/cmd)
3. **原生分参（native argument parsing）**再解释引号、反斜杠、空格和 Tab。CRT 规则中，普通反斜杠保持原样；紧邻引号时，反斜杠数目的奇偶决定引号是字面字符还是界定符。带空格、末尾为反斜杠的参数若手工包装为原生命令行引号，结束引号前需相应加倍反斜杠；这不是要求注册表值名中的每个反斜杠都加倍。[CRT 参数规则](https://learn.microsoft.com/en-us/cpp/c-language/parsing-c-command-line-arguments?view=msvc-170)
4. CLI 才能决定 `--`、`--value=`、大小写别名、错误检查等规则。单引号/双引号在 shell 中通常已被移除；CLI 收到相同参数后无法知道用户用了哪种引号。给 `-name` 加 shell 引号也不会让 CLI 知道它“曾被引用”。

PowerShell 的 `--%`（停止解析，stop-parsing）面向 Windows 原生命令，仅到换行或管道为止；其后仍替换 `%NAME%`，且不能使用普通 PowerShell 动态表达式或重定向。它不是任意字面输入编码。`--`（结束选项，end-of-options）与它不同，不能阻止此前的 shell 展开。[about_Parsing 的 stop-parsing 说明](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5)

Windows 上 PowerShell 7 的默认模式为 `Windows`；对普通探针 `.exe` 与 `Standard` 相同，但 `cmd.exe`、`cscript.exe`、`wscript.exe`、`.bat/.cmd/.js/.vbs/.wsf` 会自动使用历史传参行为。因此将原生 CLI 包在批处理或 `cmd /c` 中会再引入一层解析。[about_Parsing 的模式列表](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_parsing?view=powershell-7.5)

## 隔离探针与本机结果

环境仅用于说明本次观察：Windows 版本 API 报告 `10.0.26300.0`，Windows PowerShell `5.1.26100.9818`，PowerShell `7.7.0`，已安装 `rustc 1.99.1 (58cf8f9c3 2026-10-13)`，编译器宿主为 `x86_64-pc-windows-msvc`。这不是产品版本要求，也不是正式支持矩阵验收。

PowerShell 7 通过已安装应用入口 `C:/Users/inaku/AppData/Local/Microsoft/WindowsApps/Microsoft.PowerShell_8wekyb3d8bbwe/pwsh.exe` 启动；不把该入口称为真实二进制位置。默认沙箱不能启动它，本次经正常工具审批运行，未修改执行策略。探针只有 `args_os` 和代码单元输出，不读环境内容、文件内容或注册表；启动器只额外设置了一个人工构造的子进程变量。临时源码、可执行文件及日志未提交。

输出 `argc` 不含程序名，随后为 `索引:UTF-16代码单元数:十六进制代码单元`。每个样本单独启动探针，避免一个坏引号干扰后面的样本。下表的“相同”指代码单元完全相同；`\t/\n/\r/ESC` 在输入中为实际字符，表格中只是显示转义。

| 构造的单个参数 | Windows PS 5.1 | PS7 Legacy | PS7 Standard / Windows |
| --- | --- | --- | --- |
| 空字符串 | `argc=0`，丢失 | 丢失 | 一个长度为 0 的参数 |
| `a b` | 相同 | 相同 | 相同 |
| `-name`、`--` | 相同 | 相同 | 相同 |
| `C:\trail\` | 相同 | 相同 | 相同 |
| `C:\has space\` | 末尾 `005C` 变成 `0022` | 相同 | 相同 |
| `a"b` | 收到 `ab` | 收到 `ab` | 相同：`0061 0022 0062` |
| `a\"b`，实际含一个反斜杠及引号 | 收到 `a"b`，反斜杠丢失 | 同左 | 相同：`0061 005C 0022 0062` |
| `中文😀` | `4E2D 6587 D83D DE00` | 相同 | 相同 |
| `a<TAB>b` | `0061 0009 0062` | 相同 | 相同 |
| `a<LF>b`、`a<CR>b`、`a<ESC>b` | 分别保留 `000A/000D/001B` | 相同 | 相同 |
| `[D800,0078]` / `[DC00,0078]` | 孤立高/低代理项原样保留 | 相同 | 相同 |
| `--option=` | 一个末尾为 `003D` 的参数 | 相同 | 相同 |
| `--option=-name` | 一个完整参数 | 相同 | 相同 |
| `--option=a"b` | 收到 `--option=ab` | 同左 | 完整保留引号 |
| `[0061,0000,0062]`，后接另一个 `after` 参数 | 只收到 `0061`，后续参数消失 | 同左 | 同左 |

PS5.1 与 PS7 Legacy 在带空格的尾反斜杠例中有差异，故 `Legacy` 的总体意图不能用来推断两代实现的所有细节。多个未经转义的引号参数放在同次历史模式调用中还实测发生参数合并；不能仅检查显示文本看起来是否正确。

`cmd.exe /d /v:off /s /c` 用宽字符启动器输入下列原生命令行片段，探针结果如下。这不经过 OEM/ANSI 批处理文件编码，也不证明交互键盘和粘贴行为。

| 传给 cmd 的参数片段 | 原生探针收到 |
| --- | --- |
| `""` | 一个空参数 |
| `"a b"` | `a b` |
| `-name`、`--`、`C:\trail\` | 各自原样 |
| `"C:\has space\\"` | `C:\has space\` |
| `"a\"b"` | `a"b` |
| `"a\\\"b"` | `a\"b`，保留一个反斜杠及引号 |
| `"中文😀"` | `4E2D 6587 D83D DE00` |
| 包含实际 Tab / ESC 的带引号参数 | 各自原样保留 |
| 包含人工构造的 D800 或 DC00 的带引号参数 | 各自原样保留 |
| `--option=`、`--option=-name` | 各自一个完整参数 |
| `"--option=a\"b"` | `--option=a"b` |
| `"%RQ_LITERAL_TEST%"`，子进程变量设为 `EXPANDED` | `EXPANDED`，即使有引号也展开 |
| `"!RQ_LITERAL_TEST!"`，本次 `/v:off` | 保留字面 `!RQ_LITERAL_TEST!` |

cmd 的 LF / CR、交互输入孤立代理项、不同控制台和批处理文件编码未测。不能从宽字符启动器能构造某个输入，推断普通用户能直接键入它。

### 可使用的引用例子

这些命令仅运行探针，不访问注册表。显示引号与原生收到的字面引号是不同层次。

cmd 的命令提示符中，当前目录为探针所在目录时：

```bat
argprobe.exe "" "a b" -name "C:\has space\\" "a\"b"
```

Windows PowerShell 5.1，或明确设为 `Legacy` 的本次 PS7 会话中（同一行）：

```powershell
& $probe --% "" "a b" -name "C:\trail\\" "a\"b"
```

两者实测分别收到空串、`a b`、`-name`、末尾反斜杠、`a"b`。`--%` 之后不能将任意变量值直接拼进源文本；该例也不适用于包含 `%NAME%` 的任意字面名称。

PowerShell 7 的 `Standard` / `Windows` 模式直接传普通 `.exe`：

```powershell
& $probe '' 'a b' '-name' 'C:\has space\' 'a"b'
& $probe '--option=-name' '--option=' '--option=a"b'
```

**本机发现的限制**：在 PS7 `Windows` 模式下，上述 `--%` 示例反而把引号作为内容并发生拆分；在 PS7 `Legacy` 与 Windows PS5.1 下成功。报告不将这项本机现象外推为所有 PS7 版本规则，也不把 `--%` 当成跨模式万能写法。正常新模式示例不需要它。

## `--option=value` 的准确作用

**能做的事，前提是 CLI 支持等号形式**：将值与参数名绑定为一个 token；即使值是空串，整个 token `--option=` 仍非空，因此本机历史 PowerShell 也能传到 CLI；值以 `-` 开头时不必依靠下一个 token 是否被解析为新选项。对于位置参数，结束选项 `--` 是否可用仍是解析器约定。此处是分层推论，探针不实现选项解析。

**不能做的事**：等号不关闭 shell 展开、空格分词、引号处理，也不保护 `%NAME%` / `$name`、NUL 或运行时的有损 Unicode 转换。带空格的完整 token 仍需 shell 引用；本机 `--option=a"b` 在历史模式中仍丢引号。CLI 若只收到 `--option=ab`，无法推断原值应当是 `ab` 还是 `a"b`。

若 CLI 约定参数按字面解释，再自动将 `\n`、`\uD800` 或十六进制解码，会使真实反斜杠与显示转义无法区分。shell 本身不会替 CLI 定义这样的解码协议。显式编码与字面文本是不同的输入约定；本报告仅确认能力边界，不建议新增编码入口。当前 `--data-hex` 是数据匹配，不是名称编码。

## Unicode、异常 UTF-16 与显式编码边界

**文档保证**：Rust `args_os()` 不要求有效 Unicode，`OsStrExt::encode_wide()` 可无损得到可能不合法的 UTF-16 代码单元。探针因此没有使用 `args()`、UTF-8 强制转换或替换字符显示。产品无论选择何种语言/库，都需独立审查“获取 argv → 内部名称 → Win32 W API”是否保留孤立代理项；本次 Rust 是现有编译器上的临时研究资产。[args_os](https://doc.rust-lang.org/std/env/fn.args_os.html)、[encode_wide](https://doc.rust-lang.org/std/os/windows/ffi/trait.OsStrExt.html)

**能力推论，不是产品选择**：显式的 ASCII UTF-16LE 十六进制可以表达任意代码单元序列，例如 `610000d82200` 按每两字节小端解码为 `[0061,D800,0022]`。这里字节 `00` 不等于出现 U+0000；只有完整代码单元 `0000` 才是 NUL。解码需按 16 位单元构造，不应先经要求有效 Unicode 的 UTF-8/JSON 字符串转换。需要明确字节序、是否允许 BOM、长度倍数、非法十六进制及 NUL 检查；本报告不规定它们的产品拼写。ASCII 负载本机在 PS5.1 / cmd 传输原样保留，PS7 的其他 ASCII 样本也保留；未实现或验收产品解码器。

**硬边界**：`LPCWSTR` 是以 NUL 终止的 16 位字符串；`RegOpenKeyExW.lpSubKey` 与 `RegQueryValueExW.lpValueName` 均采用它而没有独立名称长度参数。故即便编码输入在程序内还原了 U+0000，也不能通过这两个 API 精确表示含该单元的名称；在传给 API 前必须拒绝内嵌 NUL，不能静默截断。这不声明所有底层 NT 对象名称的可能性。值数据中的零字节不受“名称”这条结论限制。[Windows Data Types：LPCWSTR](https://learn.microsoft.com/en-us/windows/win32/winprog/windows-data-types)、[RegOpenKeyExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw)、[RegQueryValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)

**长度边界**：命令行编码还会膨胀长度。`CreateProcessW` 的整条命令行上限是含终止 NUL 的 32,767 个字符；cmd 的文档限制为 8,191 个字符。不能承诺“编码参数可通过 cmd 定位全部合法长值名”：官方列出的值名上限为 16,383 字符，仅十六进制文本就可能超限。若以后要求覆盖全部长度，可能需要文件/stdin等传输，但本报告不替产品选入口。[CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw)、[cmd 长度限制](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/command-line-string-limitation)、[注册表元素限制](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-element-size-limits)

## ROOT / KEY 与 TYPE 的系统事实

以下五组简称对应官方全名；简称是常见工具的文本语法，不是新增的物理配置单元。Microsoft `reg add` 文档逐组列出映射，本研究仅查文档，未执行写操作。[官方简称映射](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add)

| 简称 | 官方全名 |
| --- | --- |
| HKCR | HKEY_CLASSES_ROOT |
| HKCU | HKEY_CURRENT_USER |
| HKLM | HKEY_LOCAL_MACHINE |
| HKU | HKEY_USERS |
| HKCC | HKEY_CURRENT_CONFIG |

`RegOpenKeyExW` 的普通预定义根列表正是这五个全名。HKCU 映射到当前用户分支，HKCC 是当前硬件配置的别名；HKCR 的合并来源继续遵循现有工单契约。是否大小写不敏感地接受 ROOT 全名/简称、是否允许尾分隔符、是否把空 KEY 解释为根，本质上是 RegQry 文本语法选择；API 的键名不区分大小写不自动决定 CLI 关键字规则。[RegOpenKeyExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw)、[Predefined Keys](https://learn.microsoft.com/en-us/windows/win32/sysinfo/predefined-keys)

`HKEY_PERFORMANCE_DATA` 是特殊性能数据入口：数据不实际存储在注册表，查询会向提供程序采集；`HKEY_PERFORMANCE_TEXT` / `HKEY_PERFORMANCE_NLSTEXT` 提供英语/本地化计数器文本。它们不能因同样有 HKEY 句柄就被推断为普通可递归配置树。查询的缓冲区语义也有差异：`HKEY_PERFORMANCE_DATA` 返回 `ERROR_MORE_DATA` 时大小值可未定义，不能直接套普通值的重分配逻辑。[Predefined Keys](https://learn.microsoft.com/en-us/windows/win32/sysinfo/predefined-keys)、[性能计数器入口](https://learn.microsoft.com/en-us/windows/win32/perfctrs/using-the-registry-functions-to-consume-counter-data)、[RegQueryValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)

官方 SDK 的预定义值类型码为下表，覆盖 `0..11`；同码别名不能作为两种不同类型计算。这些类型码是数据标签，不是过滤掩码。表中符号与数字由 Microsoft 的 `winnt.h` 直接核对；普通说明页没有完整列出资源类型 8–10。[Microsoft SDK winnt.h：Predefined Value Types](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/um/winnt.h#L23953-L23969)、[Registry value types](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types)

| 十进制码 | 官方符号及同码别名 |
| --- | --- |
| 0 | REG_NONE |
| 1 | REG_SZ |
| 2 | REG_EXPAND_SZ |
| 3 | REG_BINARY |
| 4 | REG_DWORD；REG_DWORD_LITTLE_ENDIAN |
| 5 | REG_DWORD_BIG_ENDIAN |
| 6 | REG_LINK |
| 7 | REG_MULTI_SZ |
| 8 | REG_RESOURCE_LIST |
| 9 | REG_FULL_RESOURCE_DESCRIPTOR |
| 10 | REG_RESOURCE_REQUIREMENTS_LIST |
| 11 | REG_QWORD；REG_QWORD_LITTLE_ENDIAN |

没有官方 `REG_QWORD_BIG_ENDIAN` 常量。官方 `DWORD` 为无符号 32 位，`RegQueryValueExW` 返回的类型码使用 `DWORD`；若后续语法允许未知数字码，不能只依据已知名称表把范围收窄到 0–11。是否接受 `DWORD` 等去掉 `REG_` 的简称、十六进制数字、重复项等，仍留给 TYPE 产品语法。`REG_NONE` 是实际类型码 0；缺失值没有类型，空值名是默认值，不是类型。[Windows Data Types：DWORD](https://learn.microsoft.com/en-us/windows/win32/winprog/windows-data-types)、[RegQueryValueExW](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)

## 可复现探针片段

只需已有 Windows Rust 编译器；不创建 Cargo 工程、不安装依赖、不触碰注册表。将下列源码保存为临时 `argprobe.rs`，运行 `rustc argprobe.rs -o argprobe.exe`。编译命令及版本仅描述本次研究。

```rust
use std::os::windows::ffi::OsStrExt;
fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    println!("argc={}", args.len());
    for (i, a) in args.iter().enumerate() {
        let w: Vec<u16> = a.encode_wide().collect();
        println!("{}:{}:{}", i, w.len(), w.iter()
            .map(|u| format!("{:04X}", u)).collect::<Vec<_>>().join(" "));
    }
}
```

在各 PowerShell 的 `-NoProfile -NonInteractive -Command` 中执行以下内容；`$probe` 是该临时 exe 的绝对路径。可在 PS7 子进程中循环设置进程内偏好变量为 `Legacy/Standard/Windows`；PS5.1 不存在这个模式功能。启动器本次用 `-EncodedCommand` 承载 UTF-16LE 的**测试脚本文本**，避免外层 shell 引号/脚本文件编码成为干扰；这不是被测 CLI 的参数编码方案，没有使用 `-ExecutionPolicy`。

```powershell
$cases = @('', 'a b', '-name', '--', 'C:\trail\', 'C:\has space\',
  'a"b', 'a\"b',
  ([string][char]0x4E2D+[char]0x6587+[char]0xD83D+[char]0xDE00),
  "a`tb", "a`nb", "a`rb", ('a'+[char]0x1B+'b'),
  ([string][char]0xD800+'x'), ([string][char]0xDC00+'x'),
  '--option=', '--option=-name', '--option=a"b')
for ($i=0; $i -lt $cases.Length; $i++) {
  'CASE='+$i
  & $probe $cases[$i]
}
& $probe ('a'+[char]0+'b') 'after'
```

PowerShell 的反引号序列仅在双引号内解码；`e` 和 `u{...}` 是 PowerShell 6 起新增，因此通用探针用 `[char]0x1B`、16 位单元构造，避免把 PS7 语法误写为 PS5.1 示例。[about_Special_Characters](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_special_characters?view=powershell-7.5)

cmd 可用下面启动器逐个测试上表的 `$tail`，避免外层 PowerShell 再解释它。命令解释器路径用 Windows 反斜杠形式。启动器仅把人工变量设到此子进程：

```powershell
$si = New-Object Diagnostics.ProcessStartInfo
$si.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
$si.Arguments = '/d /v:off /s /c "'+$probe+' '+$tail+'"'
$si.UseShellExecute = $false
$si.CreateNoWindow = $true
$si.RedirectStandardOutput = $true
$si.RedirectStandardError = $true
$si.EnvironmentVariables['RQ_LITERAL_TEST'] = 'EXPANDED'
$p = [Diagnostics.Process]::Start($si)
$p.StandardOutput.ReadToEnd()
$p.StandardError.ReadToEnd()
$p.WaitForExit()
```

本次第一版 cmd 启动器误用 `/` 路径，cmd 将其误解析为命令开关；该轮结果废弃，产生的人工空目录经限定工作区、确认无文件后清理。上表均来自修正为反斜杠路径后的成功运行。没有遗留产品修改。

## 尚未验证

- 未读取/创建任何真实注册表键或值；因此没有把“参数可达”说成“所有相同单元的注册表名称都能成功寻址”。键路径分隔符、值名字面反斜杠和名称合法性仍需适配层契约实现。
- 未验证 ARM64、正式最低支持系统、Windows Terminal/传统控制台的交互输入、不同代码页的批处理文件、PS7 7.0–7.2、每种控制字符和所有引号/反斜杠组合。
- 未测试生产 CLI 的选项解析库及内部字符串类型，未实现显式名称解码器；不能据此宣布最终工具已无损。
- 本机 PS7 `Windows` + `--%` 的异常表现需在将其写入产品帮助前另行按目标版本复测；本研究已有不依赖它的新模式示例和可用的历史模式引用写法。
