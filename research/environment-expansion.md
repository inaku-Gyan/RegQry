# 环境变量展开与搜索一致性边界

调研日期：2026-11-19。关联工单：核实环境变量展开语义与搜索一致性边界。基线：`34e02fa1a021689a61c059172737a53994180d1e`。本报告仅记录事实、实验与实现边界；选项名称、适用类型、条件组合、正则大小写和失败策略由产品契约决定。

证据等级：**文档保证**来自 Microsoft API 文档；**第一方实现/说明**来自 Microsoft 的公开源码或技术文章，不等同于全部 Windows 版本的 API 保证；**本机观察**来自本文附录直接 P/Invoke Win32 API；**工程推论**明确标出。

## 可用于产品决策的结论

| 拟定规则或问题 | 证据与边界 |
| --- | --- |
| `%NAME%`，变量名忽略大小写，未知变量原样保留 | **文档保证**。它们描述变量查找，与正则表达式（regular expression）是否忽略大小写是两件事。[ExpandEnvironmentStringsW][expand] |
| 展开后再对文本执行正则 | API 只返回展开后的字符串；如何把它纳入数据条件组、与原始文本条件 OR，属于产品规则。Expand API 不接收正则。[ExpandEnvironmentStringsW][expand] |
| 同时适用于 `REG_SZ`、`REG_EXPAND_SZ`、`REG_MULTI_SZ` | **产品规则**。`REG_EXPAND_SZ` 有标准环境引用语义；Expand API 本身只接收字符串，不接收注册表类型。对其他字符串类型应用同一变换是调用方的选择。[注册表值类型][types] |
| `REG_MULTI_SZ` 逐元素展开 | **产品规则，有类型结构依据**。它是多个 NUL 终止字符串；Expand API 接收一个 NUL 终止字符串，不能把整个多字符串块传一次就处理全部元素。[注册表值类型][types]、[LPCWSTR 类型][datatypes] |
| 一遍展开（single-pass expansion） | **应写成产品契约**。官方页面未规定替换值是否递归重扫、动态变量名和嵌套百分号的完整语法。本机一次调用把 `A=%B%` 的 `%A%` 变为 `%B%`，未继续得到 `B` 的值；不要把本机观察升级成文档承诺。见实验表。[ExpandEnvironmentStringsW][expand] |
| 使用查询开始时的进程环境快照（environment snapshot） | **需要额外实现**。取得环境块并不会使之后的 Expand 调用使用该块；Expand 没有环境块参数。本机旧块为 `before` 时，后续 Expand 已读到 `after`。[GetEnvironmentStringsW][getstrings]、[ExpandEnvironmentStringsW][expand] |
| 原始类型与字节不变 | **需要在数据模型中独立保留**。`RegGetValueW` 可自动展开，也可补字符串终止符；其输出不能普遍作为原始存储字节的证据。[RegGetValueW][regget]、[RegQueryValueExW][regquery] |

## Win32 展开契约与缓冲区

**文档保证**：`ExpandEnvironmentStringsW` 识别 `%variableName%`，查找名称时忽略大小写；缺失名称对应的引用保留。它不提供完整的 `cmd.exe` 展开功能，例如 `%NAME:old=new%`、`%NAME:~offset,length%`。不能借助命令解释器来补齐这些语义。[ExpandEnvironmentStringsW][expand]

输入 `LPCWSTR` 是 NUL 终止的 16 位 Unicode 字符串；源和目标缓冲区不能相同。`nSize`、返回值按宽字符计数，即 UTF-16 代码单元（code unit），不是字节或 Unicode 码点。[Windows 数据类型][datatypes]、[ExpandEnvironmentStringsW][expand]

| 结果 | 调用方处理 |
| --- | --- |
| 返回 `0` | API 失败，读取 `GetLastError`；不要把它判成“不匹配”。 |
| 返回值大于目标容量 | 缓冲区不足，返回值是所需容量；重新分配并重试，不能匹配不完整的输出。 |
| 非零返回值不大于目标容量 | 成功，计数包含末尾 NUL；文本长度为返回值减一。 |

上表属于 [ExpandEnvironmentStringsW 文档][expand] 的返回规则。它与 `GetEnvironmentVariableW` 的成功返回计数**不含** NUL 不同，不能共用未经区分的计数逻辑。[GetEnvironmentVariableW][getvariable]

**第一方实现佐证**：Microsoft WIL 的 `ExpandEnvironmentStringsW` 包装器把原生返回的需求长度交给 `AdaptFixedSizeToAllocatedResult`；后者在需求仍大于分配容量时循环，源码明确考虑跨调用结果改变。这是缓冲区重试，不是把展开结果递归再当作输入。[Microsoft WIL：win32_helpers.h][wil]

**工程推论**：Rust 边界应分别检查 `DWORD` 字符数到分配字节数的转换、分配失败、所需容量变化以及产品资源上限。原生 API 的 `0`、未知变量、空展开结果、产品资源上限是不同情况，失败策略仍需产品规定。文档中的 32K 源/目标缓冲区限制特别标注为 Windows XP/Server 2003，不能据此宣称现代 Windows 的展开结果总是最多 32K。[ExpandEnvironmentStringsW][expand]

## 环境来自哪里

**文档保证**：每个进程都有环境块（environment block），子进程默认继承父进程的一份副本，也可以由创建者显式传入不同的环境。进程环境可以同时含用户与系统环境变量，也可以带父进程或启动器的覆盖值。[Environment Variables][environment]、[User Environment Variables][userenvironment]、[CreateProcessW 的 lpEnvironment][createprocess]

`GetEnvironmentVariableW` 查调用进程环境；`SetEnvironmentVariableW` 仅改变当前进程，不修改其他进程或系统环境。系统持久环境位于 `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment`；持久修改及通知应用更新是另一套操作。[GetEnvironmentVariableW][getvariable]、[SetEnvironmentVariableW][setvariable]、[Environment Variables][environment]

**结论与本机证据**：把 Expand API 页面中的“当前用户”理解为每次都去读用户/系统持久注册表，会得到错误的搜索预期。本文只设置子进程临时变量，原生 Expand 随即读到这些值；捕获后再改临时变量也改变了后续 Expand 结果。读取某个 `HKU\<SID>` 下的注册表值，不会仅因目标路径属于另一用户就自动选择该用户的环境；该函数没有注册表键或用户令牌参数。后半句是由 API 接口得出的**工程推论**。[ExpandEnvironmentStringsW][expand]、[进程环境模型][environment]

如需要其他用户或仅系统环境，Windows 提供显式的另一套接口，不能混为当前进程环境：

- `ExpandEnvironmentStringsForUserW(hToken, ...)` 使用指定用户建立的环境；`hToken=NULL` 时只有系统变量。它返回 BOOL，失败后取 `GetLastError`，不采用 ExpandEnvironmentStringsW 的“返回所需长度”协议。[ExpandEnvironmentStringsForUserW][expanduser]
- `CreateEnvironmentBlock` 取得指定用户环境，`bInherit` 控制是否继承当前进程环境；空 token 只取系统变量。用户特有变量的可用性还取决于用户配置文件是否已加载；结果用 `DestroyEnvironmentBlock` 释放。[CreateEnvironmentBlock][createblock]

**第一方说明，非单次 Expand API 的保证**：Microsoft 对用户/系统环境的建立过程另有分阶段说明，`REG_SZ`、`REG_EXPAND_SZ` 和用户层/系统层会影响建立时的展开与覆盖关系。因此，持久注册表里的 `A=%B%` 不保证等于进程环境块中 `A` 此时保存的文字；环境建立阶段与对搜索文本调用一次 Expand 是两个阶段。[Raymond Chen：环境变量依赖的处理顺序][buildorder]

## 进程位数与注册表视图

**文档保证**：WOW64 在创建跨位数进程时会调整部分环境变量。例如，x86 进程的 `PROCESSOR_ARCHITECTURE=x86`，`ProgramFiles` 来自 x86 程序目录；原生 64 位进程通常看到对应的 64 位值，另有 `ProgramW6432`、`PROCESSOR_ARCHITEW6432` 等桥接变量。[WOW64 Implementation Details：Environment Variables][wow64]

**工程推论**：相同原始值 `%ProgramFiles%\App`，在不同启动环境/进程架构下可能得到不同文本。注册表视图（registry view）控制读哪一份注册表数据，环境块控制 `%NAME%` 替换成什么；切换 `KEY_WOW64_32KEY/64KEY` 不等于切换 Expand 的进程环境。`RegGetValueW` 的子键视图 flags 只改变子键的访问视图。[WOW64 环境规则][wow64]、[RegGetValueW][regget]

不能把“x64 程序通常得到某目录”提升为所有启动方式的绝对值：创建者可提供环境，进程也可改自己的环境。ARM64/x86 等组合需依照目标 Windows 的 WOW64 文档和测试判断。本报告的本机验证仅覆盖 x64，不把 x64 目录字面量规定为产品常量。[CreateProcessW][createprocess]、[SetEnvironmentVariableW][setvariable]

## 原始注册表数据与派生文本

**文档保证**：`RegGetValueW` 默认会展开 `REG_EXPAND_SZ`，`RRF_NOEXPAND` 禁用该自动展开；即便禁展开，字符串缺少末尾 NUL 时仍可能被补齐。它的缓冲区长度单位为字节，成功为 `ERROR_SUCCESS`，不足为 `ERROR_MORE_DATA`；失败时除 `RRF_ZEROONFAILURE` 明确清零外，缓冲内容未定义。[RegGetValueW][regget]

`RegQueryValueExW` 提供类型、数据和实际返回字节数，字符串不保证具有正确终止符；文档明确区分它与 `RegGetValueW` 的补终止符行为。[RegQueryValueExW][regquery]

**工程推论**：沿用保存原始类型/字节的读取路径，在独立缓冲区内构造可安全传给 W API 的文本。匹配用的展开结果是派生候选（derived candidate），不能覆盖原始值。没有终止符、嵌入 NUL、无效 UTF-16、奇数字节等异常的文本解释规则，应与已有文本读取契约协调；Expand API 本身不替 CLI 定义这些规则。`REG_MULTI_SZ` 若纳入新条件，先保留/解析元素边界，再按元素构造输入，避免遗漏首个 NUL 之后的元素。[LPCWSTR][datatypes]、[注册表字符串类型][types]

## 要承诺查询开始时的环境，还需做什么

以下是**工程推论和实现选项，不替产品选择规则**：

1. 明确捕获时点、进程身份、启动环境和架构，取得一次环境块后在本次查询内保持其内容不变。`GetEnvironmentStringsW` 取得当前进程块，必须只读并用 `FreeEnvironmentStringsW` 释放；Microsoft 第一方历史说明明确指出现代 A/W 版本返回快照。[GetEnvironmentStringsW][getstrings]、[Raymond Chen：GetEnvironmentStrings 的历史][snapshothistory]
2. **让实际展开读取这一份快照**。`ExpandEnvironmentStringsW` 不接受任意环境块参数，单纯先调用 GetEnvironmentStringsW 再直接调用 Expand 不足以实现这一点。可选方向包括：对拥有的快照实现确定的单遍替换器；或以快照显式创建、并约束其环境保持不变的原生辅助进程。后者涉及启动时架构调整，仍需验证有效环境与预期快照相符。也可约束整个进程环境在查询期间无写入，但只锁自己的包装器不能约束其他组件直接调用 SetEnvironmentVariableW。[ExpandEnvironmentStringsW][expand]、[CreateProcessW][createprocess]、[WOW64 环境调整][wow64]
3. 若自行展开，明确 `%...%` 的扫描规则、未配对 `%`、`%%`、替换值不重扫、Unicode 名称比较和空变量。官方仅说名称忽略大小写，不能未经核实就宣称 Unicode `to_lowercase` 或正则引擎的忽略大小写比较等同于 Windows 环境变量查找。本文的 ASCII 用例也不能证明完整 Unicode 等价性。[ExpandEnvironmentStringsW][expand]
4. 同一注册表值/同一 `REG_MULTI_SZ` 元素的展开候选应来自同一份原始读取与环境快照；如缓存，缓存键或生命周期必须绑定这份快照与转换规则。不能把捕获环境、读取注册表、匹配多个条件看成 Windows 已提供的整体事务。环境快照不会冻结实时注册表。
5. 将“资源不足/API 失败”与“展开成功但没有正则命中”分开交给查询层。是否报错、继续、退出码及诊断格式仍是产品规则。

## 本机 Win32 观察

通过一个独立的 `powershell.exe -NoLogo -NoProfile -NonInteractive -File ...` 子进程执行附录。宿主仅承载 C# P/Invoke，**没有使用 .NET 的 ExpandEnvironmentVariables 或 PowerShell 的变量展开替代 Win32 API**；所有测试输入均是普通字符串，未交给命令解释器执行。临时环境只由子进程的 `SetEnvironmentVariableW` 设置；注册表只读现存 `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\windir`，没有创建值、修改注册表或持久环境。

环境：x64；`RuntimeInformation.OSDescription` 报告 `Microsoft Windows 10.0.26300`；`kernelbase.dll` 文件版本 `10.0.26100.9974 (WinBuild.160101.0800)`；PowerShell `5.1.26100.9818`。以下仅是这一本机组合的观察，不能宣称全部 Windows 版本保证。

为便于阅读，表中的 `P_` 代表完整测试前缀 `REGSEARCH_PROBE_17_5D19_`。子进程设 `P_VALUE=Alpha`、`P_SECOND=Omega`、`P_NESTED=%P_SECOND%`、`P_SELF=%P_SELF%`、`P_CYCLEA=%P_CYCLEB%`、`P_CYCLEB=%P_CYCLEA%`、`P_SUFFIX=VALUE`；显式删除 `P_MISSING`，将 `P_EMPTY` 设为空串。

| 原始输入或步骤 | 一次原生调用的观察 |
| --- | --- |
| `%P_VALUE%`、相同名称全部小写 | 都得到 `Alpha`，返回 `6`。 |
| `%P_MISSING%` | 原样保留；非零成功返回。缺变量没有令 Expand 返回 API 失败。 |
| `%P_EMPTY%` | 空字符串，返回 `1`，含末尾 NUL。 |
| `%P_NESTED%` | 得到 `%P_SECOND%`，不再展开为 `Omega`。 |
| `%P_NESTED%\|%P_SECOND%` | 得到 `%P_SECOND%\|Omega`；原始输入的第二个引用正常展开，插入的第一个引用保留。 |
| `%P_SELF%` / `%P_CYCLEA%` | 分别得到 `%P_SELF%` / `%P_CYCLEB%`，没有递归循环。 |
| `%P_%P_SUFFIX%%` | 得到 `%P_VALUE%`，没有继续展开为 `Alpha`。这是嵌套百分号的一个观察，不能据此泛化完整语法。 |
| `%P_VALUE%%P_SECOND%` | `AlphaOmega`。 |
| `%P_VALUE:~1,2%` / `%P_VALUE:Alpha=Beta%` | 均保持原样。 |
| `%%`、单个 `%`、缺少尾 `%` 的引用 | 本机保持原样；附录保留完整用例。 |
| `A😀B` | 保留原串，返回 `5`，即四个 UTF-16 代码单元加 NUL。 |
| `Alpha` 的目标容量为 `0/1/5` | 均返回 `6`；不足缓冲区内容未用于匹配或展示。 |
| 同一目标容量为 `6/7` | 均成功返回 `6`，输出 `Alpha`。 |
| 先探测需要 `6`，再把 `P_VALUE` 改为 `Alpha-longer`，以容量 `6` 调用 | 返回 `13`，证明先测长度再取内容仍需处理容量变化。 |
| 捕获 `P_SNAPSHOT=before` 的块，再设进程变量为 `after` | 捕获块内仍为 `before`；之后的原生 Expand 返回 `after`。 |

只读注册表对照：

| API / flags | 返回码、类型与结果 |
| --- | --- |
| `RegQueryValueExW(windir)` | `0`，类型 `2`（`REG_EXPAND_SZ`），`26` 字节，`%SystemRoot%\0`。 |
| `RegGetValueW(RRF_RT_ANY)` | `0`，类型 `1`（`REG_SZ`），首个 NUL 前文本 `C:\WINDOWS`。本机 `pcbData` 为 `26`，该范围内 UTF-16 数据为 `C:\WINDOWS\0%\0`；保留此细节，不能把整个计数字节范围强行解释成单个无 NUL 文本。 |
| `RegGetValueW(RRF_RT_ANY \| RRF_NOEXPAND)` | `0`，类型 `2`，`26` 字节，`%SystemRoot%\0`。 |
| `RegGetValueW(RRF_RT_REG_EXPAND_SZ)` | `1630`，失败；未使用失败缓冲区。 |
| `RegGetValueW(RRF_RT_REG_EXPAND_SZ \| RRF_NOEXPAND)` | `0`，类型 `2`，未展开文本。 |

上面的类型转换、限制 flags 交互和返回缓冲细节作为**本机观察**记录；不借用 `SHRegGetValue` 的独立文档，把它们包装成 RegGetValueW 未明确给出的承诺。原始存储类型/字节应来自原始读取，这一实现边界不依赖上述细节是否在其他 Windows 版本相同。

本机 x64 的原生展开还观察到 `%PROCESSOR_ARCHITECTURE%=AMD64`、`%ProgramFiles%=C:\Program Files`、`%ProgramFiles(x86)%=C:\Program Files (x86)`、`%ProgramW6432%=C:\Program Files`；未定义的 `%PROCESSOR_ARCHITEW6432%` 保留。x86 子进程尝试受该宿主的脚本执行策略阻止，因此没有 x86 实测结论，也未修改该策略；位数边界以上面的 WOW64 第一方文档为依据。

## 仍需产品决定与实施验证的部分

- 新条件的名称、参数重复行为、如何进入组内 OR、正则大小写，以及是否适用于 `REG_SZ` / `REG_MULTI_SZ`；Windows 不规定 CLI 的条件代数。
- “一遍”的完整扫描语义，尤其未配对/连续百分号、动态名字、Unicode 名称比较，以及空变量和缺失变量的区别。
- 要承诺查询开始时的环境时，选择何种实现，并验证实际展开器确实只读那份快照。
- 字符串异常、资源上限、API 失败的查询结果与诊断策略；不要从未知变量原样保留推导出所有问题都应静默当作普通文本。
- ARM64、WOW64、不同启动器、其他用户环境源的实测覆盖。它们不会因选择了某个注册表视图而自动变得相同。

## 附录：完整本机探针

以下是本次最终执行的源码，便于复核结果；将其作为受控测试脚本在独立 PowerShell 子进程执行。它使用固定测试前缀，仅修改该子进程环境；退出即丢弃。注册表函数均为只读 API。

```powershell
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeEnvironmentProbe
{
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern uint ExpandEnvironmentStringsW(IntPtr source, IntPtr destination, uint size);
    [DllImport("kernel32.dll", ExactSpelling = true, CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetEnvironmentVariableW(string name, string value);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr GetEnvironmentStringsW();
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeEnvironmentStringsW(IntPtr block);
    [DllImport("advapi32.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int RegOpenKeyExW(IntPtr key, string subkey, uint options, uint access, out IntPtr result);
    [DllImport("advapi32.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int RegQueryValueExW(IntPtr key, string value, IntPtr reserved, out uint type, byte[] data, ref uint size);
    [DllImport("advapi32.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
    private static extern int RegGetValueW(IntPtr key, string subkey, string value, uint flags, out uint type, byte[] data, ref uint size);
    [DllImport("advapi32.dll", ExactSpelling = true)]
    private static extern int RegCloseKey(IntPtr key);

    private const string Prefix = "REGSEARCH_PROBE_17_5D19_";
    public static void Set(string suffix, string value)
    {
        if (!SetEnvironmentVariableW(Prefix + suffix, value))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    public static void Delete(string suffix)
    {
        if (!SetEnvironmentVariableW(Prefix + suffix, null))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }

    public static Dictionary<string, object> Expand(string input, uint capacity)
    {
        IntPtr source = Marshal.StringToHGlobalUni(input);
        IntPtr destination = capacity == 0 ? IntPtr.Zero : Marshal.AllocHGlobal(checked((int)capacity * 2));
        try
        {
            uint returned = ExpandEnvironmentStringsW(source, destination, capacity);
            int lastError = Marshal.GetLastWin32Error();
            var result = new Dictionary<string, object>();
            result["input"] = input;
            result["capacity_utf16"] = capacity;
            result["returned"] = returned;
            result["last_error_on_failure"] = returned == 0 ? (object)lastError : null;
            result["output"] = returned != 0 && returned <= capacity
                ? Marshal.PtrToStringUni(destination, checked((int)returned - 1)) : null;
            return result;
        }
        finally
        {
            Marshal.FreeHGlobal(source);
            if (destination != IntPtr.Zero) Marshal.FreeHGlobal(destination);
        }
    }

    public static Dictionary<string, object> Snapshot()
    {
        Set("SNAPSHOT", "before");
        IntPtr block = GetEnvironmentStringsW();
        if (block == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            Set("SNAPSHOT", "after");
            string wanted = Prefix + "SNAPSHOT=";
            string captured = null;
            IntPtr cursor = block;
            while (Marshal.ReadInt16(cursor) != 0)
            {
                string entry = Marshal.PtrToStringUni(cursor);
                if (entry.StartsWith(wanted, StringComparison.Ordinal))
                    captured = entry.Substring(wanted.Length);
                cursor = IntPtr.Add(cursor, (entry.Length + 1) * 2);
            }
            var result = new Dictionary<string, object>();
            result["captured_value"] = captured;
            result["later_native_expand"] = Expand("%" + Prefix + "SNAPSHOT%", 512);
            return result;
        }
        finally
        {
            if (!FreeEnvironmentStringsW(block))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    public static List<Dictionary<string, object>> RegistryReadOnly()
    {
        IntPtr key;
        int status = RegOpenKeyExW(new IntPtr(unchecked((int)0x80000002)),
            @"SYSTEM\CurrentControlSet\Control\Session Manager\Environment", 0, 1, out key);
        if (status != 0) throw new System.ComponentModel.Win32Exception(status);
        try
        {
            var results = new List<Dictionary<string, object>>();
            uint[] flags = { 0, 0x0000ffff, 0x1000ffff, 0x00000004, 0x10000004 };
            foreach (uint flag in flags)
            {
                byte[] data = new byte[4096];
                uint size = (uint)data.Length;
                uint type;
                status = flag == 0
                    ? RegQueryValueExW(key, "windir", IntPtr.Zero, out type, data, ref size)
                    : RegGetValueW(key, null, "windir", flag, out type, data, ref size);
                var result = new Dictionary<string, object>();
                result["api"] = flag == 0 ? "RegQueryValueExW" : "RegGetValueW";
                result["flags_hex"] = "0x" + flag.ToString("x8");
                result["status"] = status;
                result["type"] = status == 0 ? (object)type : null;
                result["bytes"] = status == 0 ? (object)size : null;
                result["utf16_including_nul"] = status == 0 ? Encoding.Unicode.GetString(data, 0, (int)size) : null;
                results.Add(result);
            }
            return results;
        }
        finally { RegCloseKey(key); }
    }

    public static string Reference(string suffix) { return "%" + Prefix + suffix + "%"; }
}
'@

[NativeEnvironmentProbe]::Set('VALUE', 'Alpha')
[NativeEnvironmentProbe]::Set('SECOND', 'Omega')
[NativeEnvironmentProbe]::Set('NESTED', [NativeEnvironmentProbe]::Reference('SECOND'))
[NativeEnvironmentProbe]::Set('SELF', [NativeEnvironmentProbe]::Reference('SELF'))
[NativeEnvironmentProbe]::Set('CYCLEA', [NativeEnvironmentProbe]::Reference('CYCLEB'))
[NativeEnvironmentProbe]::Set('CYCLEB', [NativeEnvironmentProbe]::Reference('CYCLEA'))
[NativeEnvironmentProbe]::Set('EMPTY', '')
[NativeEnvironmentProbe]::Delete('MISSING')
[NativeEnvironmentProbe]::Set('SUFFIX', 'VALUE')
$cases = @(
    'plain-text',
    [NativeEnvironmentProbe]::Reference('VALUE'),
    [NativeEnvironmentProbe]::Reference('VALUE').ToLowerInvariant(),
    [NativeEnvironmentProbe]::Reference('MISSING'),
    [NativeEnvironmentProbe]::Reference('NESTED'),
    ([NativeEnvironmentProbe]::Reference('NESTED') + '|' + [NativeEnvironmentProbe]::Reference('SECOND')),
    [NativeEnvironmentProbe]::Reference('SELF'),
    [NativeEnvironmentProbe]::Reference('CYCLEA'),
    [NativeEnvironmentProbe]::Reference('EMPTY'),
    '%REGSEARCH_PROBE_17_5D19_%REGSEARCH_PROBE_17_5D19_SUFFIX%%',
    ([NativeEnvironmentProbe]::Reference('VALUE') + [NativeEnvironmentProbe]::Reference('SECOND')),
    '%REGSEARCH_PROBE_17_5D19_VALUE:~1,2%',
    '%REGSEARCH_PROBE_17_5D19_VALUE:Alpha=Beta%',
    '%%',
    '%',
    'before%REGSEARCH_PROBE_17_5D19_VALUE',
    ('A' + [char]::ConvertFromUtf32(0x1f600) + 'B')
)
$results = foreach ($case in $cases) { [NativeEnvironmentProbe]::Expand($case, 512) }
$buffers = foreach ($capacity in @(0,1,5,6,7)) {
    [NativeEnvironmentProbe]::Expand([NativeEnvironmentProbe]::Reference('VALUE'), $capacity)
}
$needed = [NativeEnvironmentProbe]::Expand([NativeEnvironmentProbe]::Reference('VALUE'), 0)
[NativeEnvironmentProbe]::Set('VALUE', 'Alpha-longer')
$changedAfterSizing = [NativeEnvironmentProbe]::Expand([NativeEnvironmentProbe]::Reference('VALUE'), [uint32]$needed['returned'])
$standardVariables = foreach ($reference in @('%PROCESSOR_ARCHITECTURE%', '%PROCESSOR_ARCHITEW6432%', '%ProgramFiles%', '%ProgramFiles(x86)%', '%ProgramW6432%')) {
    [NativeEnvironmentProbe]::Expand($reference, 512)
}
[ordered]@{
    process_bits = [IntPtr]::Size * 8
    os = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    kernelbase_version = (Get-Item -LiteralPath ($env:windir + '\System32\kernelbase.dll')).VersionInfo.FileVersion
    powershell = $PSVersionTable.PSVersion.ToString()
    cases = @($results)
    buffers = @($buffers)
    changed_after_sizing = $changedAfterSizing
    snapshot = [NativeEnvironmentProbe]::Snapshot()
    standard_variables = @($standardVariables)
    registry_hklm_environment_windir = [NativeEnvironmentProbe]::RegistryReadOnly()
} | ConvertTo-Json -Depth 8
```

[expand]: https://learn.microsoft.com/en-us/windows/win32/api/processenv/nf-processenv-expandenvironmentstringsw
[getstrings]: https://learn.microsoft.com/en-us/windows/win32/api/processenv/nf-processenv-getenvironmentstringsw
[getvariable]: https://learn.microsoft.com/en-us/windows/win32/api/processenv/nf-processenv-getenvironmentvariablew
[setvariable]: https://learn.microsoft.com/en-us/windows/win32/api/processenv/nf-processenv-setenvironmentvariablew
[environment]: https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables
[userenvironment]: https://learn.microsoft.com/en-us/windows/win32/shell/user-environment-variables
[createprocess]: https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
[expanduser]: https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-expandenvironmentstringsforuserw
[createblock]: https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-createenvironmentblock
[wow64]: https://learn.microsoft.com/en-us/windows/win32/winprog64/wow64-implementation-details
[regget]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew
[regquery]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw
[types]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types
[datatypes]: https://learn.microsoft.com/en-us/windows/win32/winprog/windows-data-types
[wil]: https://github.com/microsoft/wil/blob/master/include/wil/win32_helpers.h
[buildorder]: https://devblogs.microsoft.com/oldnewthing/20231212-00/?p=109137
[snapshothistory]: https://devblogs.microsoft.com/oldnewthing/20130117-00/?p=5533
