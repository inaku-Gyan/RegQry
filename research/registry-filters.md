# fd / ripgrep 筛选约定与注册表映射

调查日期：2026-11-19；范围为只读搜索、查看。事实来自 fd 在线 `master` 手册/源码及 ripgrep `15.2.0`；fd 遍历细节另核对 `v10.5.2`。这是线上版本观察，未安装工具、运行查询或访问用户注册表。下文的**建议**不锁定本项目旗标、默认搜索域或匹配语言。

## 已核实的工具约定

正则表达式（regular expression）、固定字符串（fixed string）、通配模式（glob）是不同匹配语言；“整个字段”与“字段中的子串”是另一条维度。

| 维度 | fd | ripgrep |
| --- | --- | --- |
| 默认匹配对象 | 递归匹配条目末段名称；默认正则子串匹配。`-p/--full-path` 改为完整绝对路径；`-a` 只改变输出路径。[README][fd-readme] | 默认对文件内容逐行作正则匹配，输出命中行；路径是候选文件的筛选条件。[Guide][rg-guide] |
| 字面与完整匹配 | `-F` 是字面子串；`--exact` 是整个名称的字面匹配，可与 `-p` 组合；`-g` 将主模式改为完整 glob。[CLI][fd-cli] | `-F` 是字面匹配，`-x` 要求整行匹配，单独 `-x` 仍可用正则，`-Fx` 才是整行字面匹配；`-g` 不改变内容模式。[参数定义][rg-flags] |
| 大小写 | 默认智能大小写（smart case）；`-i` 忽略、`-s` 敏感，互相覆盖时后者生效；主 glob 也受该选择影响。[CLI][fd-cli]、[匹配器][fd-patterns] | 默认敏感；`-i/-s/-S` 为忽略/敏感/智能，后者生效。`-S` 看 Unicode 字面字符：无字面字符的 `\w` 不算全小写。[参数定义][rg-flags] |
| 多模式 | 主模式加重复 `--and` 要全部命中；可用正则交替表达“或”。`-e` 是扩展名筛选，多个扩展名可取“或”。[匹配器][fd-patterns]、[README][fd-readme] | 重复 `-e` 或 `-f` 文件中的模式取“或”，匹配任一个即选中该行；使用 `-e/-f` 后，位置参数都是搜索路径。[参数定义][rg-flags] |
| 深度与类型 | `-d` 上限，另有 `--min-depth/--exact-depth`；`-t` 是文件/目录/链接等条目种类，多种类取“或”，empty/executable 是额外限定。[手册][fd-man] | `-d` 上限；起点深度 0，1 为直接子项。`-t/-T` 是纳入/排除文件类型，其实是名称 glob 集，不是 MIME 或文件/目录种类。[参数定义][rg-flags]、[类型源码][rg-types] |
| 大小与时间 | `-S`：`+N` 为 ≥N、`-N` 为 ≤N、无符号为恰好；区分十进制 `k` 与二进制 `ki`。重复大小条件全部满足；有修改时间新于/早于日期或相对时长的筛选。[手册][fd-man]、[测试][fd-tests] | `--max-filesize` 只给文件大小上限，重复时后者覆盖；所查参数表没有 fd 式原生修改时间上下限。[参数定义及测试][rg-flags] |

因此 `-g/-e/-t/-S` 均存在语义冲突，不能把两者称为同一套兼容接口。大小写也有两个层次：fd 的 `-i` 影响主 glob，但 `-E` 的排除匹配器独立构建、默认敏感；rg 的 `-i` 只管内容，不影响 `-g`，glob 要用 `--iglob` 或 `--glob-case-insensitive`。[fd 排除构建][fd-main]、[fd 遍历][fd-walk]、[rg glob 构建][rg-hiargs]。

## 组合、优先级与剪枝

**事实：**rg 多个正 `-g` 允许文件命中任一个；有正 include 后，未命中任何规则的文件被排除。`!` 前缀排除，同一路径命中多个规则时后写覆盖先写，例如 `-g '!*.toml' -g '*.toml'` 与反序结果不同。命令行 glob 高于 ignore 文件和类型筛选；这种优先级不表示可越过深度限制。[Guide][rg-guide]、[override 源码][rg-overrides]、[遍历器][rg-walk]。

**事实：**fd 的 `-E` 可重复排除文件/目录，并覆盖其他 ignore 逻辑；普通排除模式取并集，顺序不改变结果，不是 rg 正负 `-g` 列表。名称、扩展名、类型、大小和时间逐层通过才输出。名称未命中不会停止深入目录；`--prune` 则在命中并通过筛选后停止深入。[手册][fd-man]、[遍历器][fd-walk]。

两者默认跳过隐藏条目及 ignore 规则排除的路径，rg 还会避开二进制内容；这些依赖文件系统环境的默认筛选，不构成注册表里的天然对应物。[fd README][fd-readme]、[rg Guide][rg-guide]。

**事实：**两者排除目录都会令后代不被遍历；后代 include 不应被理解为自动恢复已剪掉的祖先。fd 默认只搜末段，模式遇不到路径分隔符；`-p` 正则直接面对路径字符串，`.` 不受路径层级限制。fd 主 glob 设置了分隔符边界：`*` 不跨分隔符，`**` 可表达多层。rg `-g` 用 gitignore 风格路径规则，与内容正则分开。[fd 遍历器][fd-walk]、[fd 匹配器][fd-patterns]、[globset 语法][globset]、[rg Guide][rg-guide]。

**事实：**fd 未给模式或普通空模式会列举候选条目；`--exact ''` 不采用“空模式匹配全部”的捷径。fd 没有 rg 式 `-v` 主模式反选接口。rg 空模式匹配所有输入行；`-v` 反选的是行，不是“整文件没有命中”，后者另有 `--files-without-match`。空的模式文件又表示零个模式，区别于包含空行的模式文件。[fd 匹配器][fd-patterns]、[fd CLI][fd-cli]、[rg 参数定义][rg-flags]、[模式收集][rg-hiargs]。

## 可迁移原则及必须重定义之处

**建议：**借鉴“短查询 + 独立筛选”的可组合体验，先分别定义遍历范围、匹配字段、匹配语言、字面/整字段、大小写及元数据条件。每种重复参数要声明是“或”“且”还是后者覆盖；把排除结果与剪掉子树分开。是否采用 rg 的有序覆盖、fd 的默认 smart case，仍是产品选择，不能由“像 fd/rg”自动推出。

| 注册表事实 | 对 filter 契约的影响（推断，待决定） |
| --- | --- |
| 注册表键（Registry Key）和值（Registry Value）是不同对象；值名可含 `\`；键名禁止 `\`，但可含实际的 `/` 字符。[结构][registry-structure] | 分开键名、键路径、值名、值数据；不能把原生路径全换成 `/` 后当作无歧义路径，也不可把值名拼成末段路径。glob 分隔符、转义及路径正则的被匹配字符串须定义；对象种类与 `REG_SZ/DWORD` 等值类型不同。 |
| 默认值（Default Value）的真实值名是空串，可不存在。[读取接口][registry-value] | 未给模式、空模式、精确空值名、零字节数据需要不同语义；展示用的“默认”标签不能进入身份匹配。 |
| 类型、原始字节长度属于值；最后写入时间属于键，包含其值的变化。[读取接口][registry-value]、[键信息][registry-key-info] | 明确 size 是存储字节数，不是显示字符数或子树大小；时间筛值时是否沿用所属键时间须显式决定，不能声称值有独立修改时间。 |
| 注册表视图（Registry View）及根键别名/合并入口影响身份。[视图][registry-view]、[预定义根][registry-roots] | 路径匹配前需定义别名规范化及视图范围；深度按搜索起点到键的边数还是再加值一层，不能直接照搬文件树。 |

数据搜索还需明确：原始字节（raw bytes）、未展开文本、数值解释、多字符串各元素是否属于同一字段，以及“任一字段命中”与“所有条件在同一条目满足”的关系。**建议：**反选只作用于已选匹配谓词，不隐含翻转范围、权限失败或未读数据；这属于注册表产品语义，不是已有工具的兼容事实。

## 用于后续讨论的查询场景

- 已知值名 `InstallPath`：在限定子树与视图内精确匹配值名，再查看数据；与路径包含 `InstallPath` 区分。
- 只知道旧路径 `C:\Tools\old.exe`：固定字符串搜值数据，限定字符串类型；决定是否搜索展开后的 `EXPAND_SZ`。
- 查某产品分支内 1–4 KiB 的二进制值：类型与两条大小条件取“且”，排除一个缓存子树；查看时保留所属键和独立值名。
- 找最近一天变过的键、或只找默认值：前者用键时间，后者用精确空值名；两者都不等同“空模式列举全部”。

这些是评审用意图，不是本项目最终命令示例。未实测 Windows shell 转义、名称异常编码或性能；未设计写入、重命名和 TUI。

[fd-readme]: https://github.com/sharkdp/fd#matching-the-full-path
[fd-cli]: https://github.com/sharkdp/fd/blob/master/src/cli.rs
[fd-patterns]: https://github.com/sharkdp/fd/blob/master/src/patterns.rs
[fd-main]: https://github.com/sharkdp/fd/blob/master/src/main.rs
[fd-man]: https://github.com/sharkdp/fd/blob/master/doc/fd.1
[fd-tests]: https://github.com/sharkdp/fd/blob/master/tests/tests.rs
[fd-walk]: https://github.com/sharkdp/fd/blob/v10.5.2/src/walk.rs
[rg-guide]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/GUIDE.md
[rg-flags]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/core/flags/defs.rs
[rg-types]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/ignore/src/types.rs
[rg-overrides]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/ignore/src/overrides.rs
[rg-hiargs]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/core/flags/hiargs.rs
[rg-walk]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/ignore/src/walk.rs
[globset]: https://github.com/BurntSushi/ripgrep/blob/15.2.0/crates/globset/src/lib.rs#L60
[registry-structure]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/structure-of-the-registry
[registry-value]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryvalueexw
[registry-key-info]: https://learn.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regqueryinfokeyw
[registry-view]: https://learn.microsoft.com/en-us/windows/win32/winprog64/accessing-an-alternate-registry-view
[registry-roots]: https://learn.microsoft.com/en-us/windows/win32/sysinfo/predefined-keys
