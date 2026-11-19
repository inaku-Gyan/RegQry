# Windows Registry

本上下文描述本机 Windows 注册表的搜索与查看。术语遵循 [Windows 注册表结构](https://learn.microsoft.com/en-us/windows/win32/sysinfo/structure-of-the-registry)；键与值是不同的对象。

## Language

**注册表键（Registry Key）**:
注册表树中的节点，可以包含子键和注册表值；键名不区分大小写。
_Avoid_: 注册表项（未说明指键还是值时）

**注册表值（Registry Value）**:
隶属于某个注册表键的数据条目，具有值名、类型和关联的数据。
_Avoid_: 键值（未区分注册表键与注册表值时）

**值名（Value Name）**:
注册表值在所属键中的名称，与该值保存的数据不同；值名不区分大小写。[Windows 值名规则](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regdeletevaluew)。
_Avoid_: 键名（指注册表值的名称时）

**值数据（Value Data）**:
注册表值中保存的内容，与该值的名称不同。
_Avoid_: 值（需要区分完整注册表值与其数据时）

**值类型（Value Type）**:
随注册表值保存、用于解释其数据的类型标识，以类型码区分。REG_NONE 是实际值的一种类型；不存在的值没有类型。
_Avoid_: 未设置（作为 REG_NONE 的同义词时）

**原始值数据（Raw Value Data）**:
注册表值实际保存的字节序列，保留存储编码、字节序及终止符，与解释后的文本、整数或字符串序列不同。
_Avoid_: 数据匹配文本、展开后的文本（用来指原始存储字节时）

**数据匹配文本（Data Matching Text）**:
注册表值按其类型解释后供文本检索使用的内容，例如保存的字符串、字符串序列中的元素或整数的十进制文本；其含义独立于终端排版。
_Avoid_: 原始字节、显示行（作为数据匹配文本的同义词时）

**展开后的文本（Expanded Text）**:
在给定环境中将环境变量引用替换后得到的派生文本；原始保存数据仍独立存在。
_Avoid_: 原始数据、持久化数据（用来指展开结果时）

**默认值（Default Value）**:
用空值名标识的注册表值，也称未命名值；它可以不存在，也不预设数据类型。
_Avoid_: 默认数据、默认类型

**默认值未设置（Unset Default Value）**:
键存在，但其空值名对应的注册表值不存在的状态；没有实际的值类型或数据。
_Avoid_: 空默认值、REG_NONE（用来表示默认值不存在时）

**逻辑空数据（Logically Empty Data）**:
已存在注册表值按其类型解释后没有内容，例如空字符串、空多字符串序列或空二进制数据；不等同于数值零或存储字节数为零。
_Avoid_: 未设置、零长度数据（未区分逻辑内容与存储长度时）

**零长度数据（Zero-length Data）**:
已存在注册表值的原始存储数据恰为零字节；与值不存在是不同状态。
_Avoid_: 未设置、空字符串（作为零长度数据的同义词时）

**注册表视图（Registry View）**:
Windows 对部分注册表路径提供的不同逻辑视图；同一路径在不同视图中可能指向不同数据。
_Avoid_: 程序位数（作为注册表视图的同义词时）

**注册表符号链接（Registry Symbolic Link）**:
指向另一注册表键的特殊注册表键。链接源和它指向的目标是不同的键。[Windows 符号链接键](https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regcreatekeyexw)。
_Avoid_: 预定义根别名、值数据中的路径（作为注册表符号链接的同义词时）

**搜索起点（Search Root）**:
用于界定一次注册表搜索遍历范围的键，可以是任意注册表键。
_Avoid_: 预定义根键、配置单元（Hive）（作为搜索起点的同义词时）
