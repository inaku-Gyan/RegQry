# 注册表能力与 CLI 功能设计依据

调查日期：2026-11-19。问题：面向“位置未知时搜索 → 检查 → 单目标编辑”的本机排查工具，Windows 注册表有哪些值得支持的能力，各自解决什么任务、承担什么语义成本？

本报告复用并核对已有接口调查，提供产品讨论的事实底稿，不选择 Rust 库、命令分组、参数或 TUI。既定范围是本机实时注册表、兼顾脚本和单目标创建/修改/删除；远程、离线 hive、批量替换/删除仍排除。以下**事实**来自 Microsoft 文档及官方源码；**推断**是证据所支持的产品影响；**建议**仅表示讨论优先级，均未被用户选定。除读取 `reg.exe /?` 帮助和可执行文件版本外，没有访问用户注册表、安装依赖或运行操作试验。

## 目标和数据：已核实事实

注册表键（Registry Key）是树节点，注册表值（Registry Value）属于键，包含独立的值名、类型、数据。键名不区分大小写且不能含 `\`，值名可以含 `\`，因此不能把末段路径一律当值名。空值名标识默认值（Default Value）：它可不存在，也可为任意类型；缺失、空字符串和零字节数据必须区分。[结构](https://learn.microsoft.com/en-us/windows/win32/sysinfo/structure-of-the-registry)、[默认值与读取](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw)、[值名大小写](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletevaluew)。

常见入口为 HKLM（机器）、HKCU（当前用户）、HKU（用户分支）、HKCC（当前硬件配置别名）及 HKCR。HKCU 映射 HKU 下的当前用户分支，HKCC 是 HKLM 中一条路径的别名；HKCR 则合并用户/机器 `Software\Classes`，用户设置优先，键与值的写入落点规则还不同。性能数据入口并非普通持久配置树。[预定义键](https://learn.microsoft.com/en-us/windows/win32/sysinfo/predefined-keys)、[HKCR 合并及写入](https://learn.microsoft.com/en-us/windows/win32/sysinfo/hkey-classes-root-key)。

注册表视图（Registry View）属于目标身份：WOW64 默认视图随进程架构变化，显式 32/64 位标志对共享键无效；完整枚举两视图要分两遍，后续子键操作继续携带同一视图。ARM 的 32 位视图还有架构差异，不应直接操作保留的 `Wow6432Node` 路径。[替代视图](https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view)。兼容性虚拟化还可能把旧程序的写入导向用户位置，它与 WOW64 是两种机制；64 位进程、带 `requestedExecutionLevel` 清单的进程禁用这种虚拟化。[虚拟化](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-virtualization)。

值的解释不等于原始保真（Raw Fidelity）。常见类型包括 SZ、未展开环境变量的 EXPAND_SZ、字符串序列 MULTI_SZ、DWORD/QWORD、BINARY/NONE；还有大端整数、LINK 等类型。字符串可能缺终止 NUL；便利读取 `RegGetValue` 会补终止符，默认还会展开环境变量。[类型](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types)、[读取转换](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetvaluew)。**建议：**检查同时保留类型码、字节长度及原始数据入口，再提供文本、整数、列表或十六进制解释；异常数据不能因显示转换而被静默改写。罕见类型可先讨论“可检查/原样保留”，无需等同承诺专用编辑器。

## 能力 → 任务 → 候选功能矩阵

候选列中的“核心”“附加”“专门管理”均为**建议，非首版决定**；边界列为事实，标出的“推断/待定”除外。

| 能力 | 用户任务 | 候选功能 | 重要边界 | 第一方来源 |
| --- | --- | --- | --- | --- |
| 精确定位 | 把命中交给脚本或稍后编辑 | 核心：保留根、键路径、视图、对象种类及独立值名 | HKCR/别名不一定是独立存储；空值名不能以展示标签替代身份 | [结构](https://learn.microsoft.com/en-us/windows/win32/sysinfo/structure-of-the-registry)、[HKCR](https://learn.microsoft.com/en-us/windows/win32/sysinfo/hkey-classes-root-key) |
| 枚举、键检查 | 看邻近配置、分支规模和最近变化 | 核心：直接子键/值列表；附加：键元数据详情 | 键可查询 class、子键/值计数、最大长度、安全描述符长度、最后写入时间；时间是键或其值变化的时间，不能当每个值的时间。安全描述符长度也不是 ACL 内容 | [键信息](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryinfokeyw) |
| 值检查 | 判断配置存在、类型是否正确、真实存储是什么 | 核心：存在性、类型、数据、完整数据读取 | 读取指定值需 `KEY_QUERY_VALUE`；缓冲区不足和对象缺失是不同状态；数据大小可能在两次调用间增长 | [读取](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw) |
| 搜索 | 只知道产品名、值名片段或旧路径 | 核心：分开选择键名、值名、值数据；指定子树和视图；讨论精确/大小写/类型过滤 | 文本解释、数值语义和字节序列匹配是不同需求；正则等匹配语言待定。`reg query` 已有递归、模式、键/数据域、精确/大小写、类型和视图筛选 | [reg query](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-query) |
| 创建键 | 按已知配置说明建立容器 | 核心：明确“新建”与“已存在”的结果 | `RegCreateKeyEx` 已存在则打开；可创建所有缺失中间键，新键起初无值、默认继承父 ACL。是否允许自动补父路径待定 | [创建](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcreatekeyexw) |
| 新增/修改值及类型 | 设置开关、修复错误类型或路径 | 核心：指定完整目标、类型及数据；区分新增与覆盖意图 | 常规 `RegSetValueEx` 同时接收类型、完整数据与字节长度；改类型走这一路径仍需提交数据，不提供自动转换承诺。不存在同名值时会新增 | [设置](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsetvalueexw) |
| 删除值、删除键 | 去掉明确的旧配置 | 核心：区分值删除和键删除；非空键策略待定 | 删值需 `KEY_SET_VALUE`；无子键的键仍可能有值，非递归删键会连其所有值删除；递归删树是另一操作。单个指定子树删除不等于搜索结果批量删除，但仍需明确范围 | [值删除](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletevaluew)、[键删除](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletekeyexw)、[递归](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletetreew) |
| 重命名 | 纠正键名或值名，同时保留内容 | 附加：分别讨论键与值重命名 | 键有 `RegRenameKey`，新名不得存在，句柄需 `KEY_WRITE`，另要求父键 `KEY_CREATE_SUB_KEY` 及整棵被改名子树的 DELETE；值重命名的已核实实现是组合操作，见下文 | [键重命名](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regrenamekey)、[值实现](https://github.com/PowerShell/PowerShell/blob/v7.5.4/src/System.Management.Automation/namespaces/RegistryProvider.cs#L2147) |
| 复制、移动 | 借用一个值，或建立配置试验副本 | 附加：单值复制与子树复制分开评估 | `RegCopyTree` 源需 `KEY_READ`、目标需 `KEY_CREATE_SUB_KEY`；目标为已打开的键，递归含值/子键并复制安全描述符。`reg copy` 可选择是否含子键；PowerShell 的目标已存在/不存在行为不同，复制子键还需 Recurse。移动若由复制再删除组成，影响源与目标 | [复制树](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcopytreew)、[reg copy](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-copy)、[PowerShell 目标](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_registry_provider?view=powershell-7.5#copying-registry-keys-and-values)、[递归范围](https://learn.microsoft.com/en-us/powershell/scripting/samples/working-with-registry-keys?view=powershell-7.5#copying-keys) |
| 文本导出/导入 | 分享配置、保存可审阅的配置片段 | 附加：只读导出可独立评估；导入需另审范围 | `reg export` 写 `.reg`，`import` 写入本机。文件可含多键/值乃至删除指令，因此导入不是一次单目标编辑，不能绕过已排除的批量删除；也不能由此承诺无损备份/权限恢复 | [export](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-export)、[import](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-import)、[官方删除指令示例](https://support.microsoft.com/en-us/servicing/os/windows-server/2020/08/kb914387-how-to-configure-daylight-saving-time-for-microsoft-windows-operating-systems) |
| 保存/恢复注册表文件 | 恢复整段配置或管理 hive 备份 | 专门管理：与普通编辑分开评估 | `RegSaveKeyEx` 需启用备份特权、只存非易失键，失败可留下损坏文件；恢复覆盖目标及后代，需备份和恢复特权，受打开句柄约束。系统状态备份应使用 VSS，不宜把它包装为单值撤销 | [保存](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsavekeyexw)、[恢复](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regrestorekeyw) |
| 比较 | 比较两个配置分支或不同视图 | 附加：只读差异、可供脚本判断的结果 | `reg compare` 已支持指定值、默认值及递归比较，返回码区分相同/差异/失败。**待定：**本工具比较原始类型/字节还是解释值，是否包括 ACL/class/时间 | [reg compare](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-compare) |
| 变更通知 | 观察应用何时重写已定位的配置 | 附加：对指定键/子树等待变化后复查 | 需 `KEY_NOTIFY`，可按子键名、值或安全变化通知；收到一次通知后须重新注册，不能检测 `RegRestoreKey` 造成的变化。返回事件不含旧新数据或写入者；**推断：**需另行读取/差分，不能声称完整审计日志 | [通知](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regnotifychangekeyvalue) |
| 权限查看/管理 | 解释访问拒绝，或修复授权 | 查看可作为附加诊断；修改所有者、ACL、继承/审计属专门管理 | 安全描述符属于键；读 owner/DACL 需 READ_CONTROL，SACL 还需相应系统访问及安全特权；写 DACL/owner 分别要求 WRITE_DAC/WRITE_OWNER。能读值不等于能读完整权限，更不等于可写 | [权限读取](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-reggetkeysecurity)、[安全信息权限](https://learn.microsoft.com/en-us/windows/win32/secauthz/security-information) |

## 容易误定的边界

**重命名、复制与原子性。** 公开 Win32 文档确认了键重命名；本次未找到具有同等契约的公开值重命名操作，不能据此断言所有 Windows 内部接口均不存在。可核实的是 PowerShell 7.5.4 `RenameProperty` 调用 `MoveProperty`：读取类型/数据，设置新名，再删除旧名；该版本键重命名也被实现为移动，而非调用 `RegRenameKey`。[官方源码](https://github.com/PowerShell/PowerShell/blob/v7.5.4/src/System.Management.Automation/namespaces/RegistryProvider.cs#L797)。**推断：**这些组合步骤有中间状态及部分完成风险；目标冲突、类型/字节保真、源变化和失败恢复必须单独规定。原生单次调用不能被推广为任意复制、移动或检查后写入的事务承诺；所查文档没有给出整个 CLI 多步流程的原子/回滚保证。[RegRenameKey](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regrenamekey)、[RegCopyTree](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcopytreew)。

**导入导出与备份恢复。** `.reg` 是配置交换路径；官方示例在恢复前额外加入删键指令再重建，说明普通重导入不能被当成“恢复到完全相同状态”的通用办法。[示例](https://support.microsoft.com/en-us/servicing/os/windows-server/2020/08/kb914387-how-to-configure-daylight-saving-time-for-microsoft-windows-operating-systems)。`reg export/import` 文档没有提供 ACL、键时间或异常数据往返保证；**推断：**不得把文本导出宣称为权限恢复或无损备份。[export](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-export)、[import](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-import)。本次没有找到可据以承诺这些保真性质的第一方格式契约，具体保留/丢失项目未实测。二进制保存/恢复另有文件格式、特权和覆盖语义；Microsoft 还明确不推荐用保存+恢复来复制子树，因为会影响句柄且不触发通知。[注册表文件](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-files)、[保存限制](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regsavekeyexw)。

**实时性、权限与成功含义。** 子键和值枚举顺序均未定义，Microsoft 要求枚举期间应用不应修改该键；各次读取仍可能失败或遇到数据增长。[键枚举](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regenumkeyexw)、[值枚举](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regenumvaluew)。打开键按其安全描述符检查所请求权限；枚举子键、读值、写值和创建子键是不同权限。[访问权](https://learn.microsoft.com/en-us/windows/win32/sysinfo/registry-key-security-and-access-rights)。**推断/建议：**实时搜索不能承诺全树一致快照；部分访问拒绝、对象消失、取消和“完整搜索但零命中”应可区分。命中到编辑之间可能变化，编辑前复核及覆盖冲突策略仍待定。写入后其他进程可见与立即落盘也不同；强制 flush 会阻塞整个 hive 的修改且成本高，不应由“成功”二字隐含保证。[落盘](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regflushkey)。

## 六个任务场景：建议如何评估功能

| 具体场景 | 需要的能力与建议优先级 |
| --- | --- |
| 只知道卸载软件的旧 exe 路径，位置未知 | 核心：限定候选根/子树搜索数据及名称，结果保留视图和独立值名；检查原始路径、类型、邻近值，再选择一个目标。EXPAND_SZ 是否按未展开文本或展开结果匹配需明确。 |
| 64 位检查工具读得到设置，32 位应用却行为不同 | 核心：显式定位/检查两个视图；比较可作为附加便利。HKCR 场景还应查看用户/机器来源，不能把不同命中简单当重复项。 |
| 支持文档要求在已知键下增加 DWORD 调试开关 | 核心：区分键不存在、值不存在、值已存在及类型不符；明确是否补父路径，再提交单个值的类型和完整数据、复读核对。 |
| 删除一个明确的旧值，让应用自行选择后续行为 | 核心：区分删值、写空数据和删键；删未命名值也需明确身份。若用户要清理一棵软件分支，再讨论单目标子树删除，不能默认从命中列表扩张删除范围。 |
| 升级前留下当前配置，或借用一个正常分支作对照 | 附加：只读导出、单值复制、比较各有独立价值。可审阅配置、原始值前态和 hive 备份是三种不同承诺；导入、递归复制或恢复会增加写入范围。 |
| 修改后设置很快被重写，或操作遭拒绝 | 核心先提供带目标/操作/错误的失败信息；附加通知与差分辅助观察时间，权限查看辅助解释授权。找出写入进程和修改 ACL 是进一步任务，不能由通知或一次读写失败直接推断。 |

这些场景说明“搜索、检查、编辑”不只是三个 API 包装：可复用的目标身份、类型/原始数据、范围和结果完整性贯穿全过程。**建议：**先由用户选择核心流程的完整度，再逐项评估附加能力；权限管理、备份恢复以及多目标导入需要独立理由。TUI 与命令语法继续后置。

## 已有工具覆盖及本项目可改善之处

`reg.exe` 已提供 query/add/delete/copy/compare/export/import/save/restore 等能力；其价值不是只有基础读写。[命令目录](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg)。PowerShell Registry Provider 则把键视为容器、值视为属性，可枚举、类型化读取/写入、创建、清除、删除、复制、移动、重命名，并可用 Get-Acl/Set-Acl 管理键的安全描述符；复杂筛选可用对象管道组合。[Provider](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_registry_provider?view=powershell-7.5)、[筛选](https://learn.microsoft.com/en-us/powershell/scripting/samples/working-with-registry-keys?view=powershell-7.5)、[Get-Acl](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-acl?view=powershell-7.5)、[Set-Acl](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-acl?view=powershell-7.6)。

**推断/建议：**本项目可改善的是未知位置排查时的连续工作流：明确搜索域，把命中稳定地转成检查/编辑目标，让类型与保真边界可见，提供便于脚本消费的输出和部分失败信息。这里没有性能基准或用户比较试验，不能宣称搜索更快、覆盖比现有工具更完整，或终端交互已经更好。

本机只读观察：`reg.exe` 文件版本 `10.0.26100.8457`；执行 `query /?`、`add /?`、`delete /?` 均成功，未指定任何注册表目标。帮助明确给出 `query /f … /v` 可只搜值名；query/add 的类型清单包含 QWORD，delete 帮助包含视图参数，而所查在线页面有遗漏或不同清单。[query 文档](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-query)、[add 文档](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-add)、[delete 文档](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-delete)。这只是本机帮助证据，不是 CRUD、匹配细节或跨版本支持试验。

## 尚未验证、留待人决定

没有验证：异常 UTF-16/缺终止符/未知类型的显示与写回；名称转义和原始数据搜索；HKCR、别名、符号链接及两视图/ARM 的实际落点；并发枚举与编辑冲突；复制目标冲突、ACL 保留及部分失败；重命名的并发可见性；`.reg` 与 hive 文件对元数据及异常字节的往返；通知合并/重注册行为。上述内容不应成为首版支持保证。

功能决定仍需用户参与：搜索域和匹配语义；键/值详情的深度、脚本输出与完整性状态；常见类型和 raw 支持边界；中间键创建、覆盖、非空键删除及并发复核；重命名、复制、比较、导出、通知、权限查看是否纳入；导入、权限管理和备份恢复是否另立范围。本研究没有替用户作这些选择。
