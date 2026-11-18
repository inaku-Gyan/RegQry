# 字面命名候选的公开记录与命令重名

核查日期：2026-11-19，Asia/Shanghai（UTC+08:00）；本轮查询约 06:25–06:31。
范围：本机 Windows 注册表搜索 / 查看 CLI；首版只读，未来轻量编辑不影响本次事实核查。
候选保持展示名 / CLI / Cargo 包同一拼写，仅大小写不同；补查 RegSift 后不再扩池。
本文不决定最终名称，也不证明任何名称可独占使用。

## 结果概览

| 展示名 / CLI / 包名 | 精确重名或占用 | 近似名与证据边界 |
| --- | --- | --- |
| RegGrep / reggrep / reggrep | **已有同名 Windows 注册表搜索、替换工具**；未核实其 CLI 入口。 | 作者在 Vector 的软件说明与作者目录相互对应。[作者软件说明](https://www.vector.co.jp/soft/win95/util/se063279.html)、[作者目录](https://www.vector.co.jp/vpack/browse/person/an012967.html) |
| RegRep / regrep / regrep | **已有精确同名 CLI**；另有 Windows 注册表复制代理 RegRep。 | `regrepl.exe` 是近似名的 Windows 注册表替换 GUI，不能混称为精确 `regrep`。[CLI README](https://github.com/markuslaker/regrep)、[厂商代理文档](https://docs.infoscale.com/us/en/infoscale/product-guides/windows/cluster-server-bundled-agents-reference-guide-wind/9-0/vcs-infrastructure-and-support-agents/registry-replication-regrep-agent.html)、[regrepl README](https://github.com/LTRData/regrepl) |
| RegFind / regfind / regfind | **已有精确同名 Windows CLI**；Microsoft Resource Kit 也曾使用此名。 | MOBZystems 的同名程序搜索文件；Resource Kit 的同名程序搜索、替换注册表。历史 Microsoft 原文仅从第三方存档读到。[厂商说明](https://www.mobzystems.com/tools/regfind/)、[KB 原文存档](https://jeffpar.github.io/kbarchive/kb/146/Q146303/) |
| RegLook / reglook / reglook | 历史分发方帖子使用 **Reglook** 名称；未取得原包、作者说明或准确可执行名。 | **RegLookup / reglookup** 已是同领域注册表文件读取工具；它是近似名，不能说成精确 `reglook`。[历史分发帖](https://www.bleepingcomputer.com/forums/t/5218/ie-home-page-problems-please-help/)、[RegLookup 上游](https://projects.sentinelchicken.org/reglookup/)、[发行版手册](https://manpages.debian.org/unstable/reglookup/reglookup.1.en.html) |
| RegLoc / regloc / regloc | **crates.io 已有精确包记录**，版本 `0.0.0`。 | 本轮未证实精确同名 CLI；已有包的描述明确称为 RLPS 项目保留名称，参考实现为 `r14n`。[精确 API](https://crates.io/api/v1/crates/regloc) |
| RegQry / regqry / regqry | 本轮**未证实强同名 CLI 或 Windows 注册表专用工具**。 | Windows 自带的是两词命令 `reg query`，不是单词 `regqry`；下表 API / 搜索结果也不能证明可发布或已预留。[Microsoft 命令文档](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-query) |
| RegSift / regsift / regsift | 本轮**未证实同名 CLI 或 Windows 注册表专用工具**。 | 包 API 与 GitHub 名称检索结果见下表；不代表全网唯一。 |

## crates.io 精确记录

以下是未认证的第一方 HTTPS API 请求；时间均为本地 UTC+08:00。

| 包名与查询来源 | HTTP 状态 | 查询时间 | 读到的公开记录 |
| --- | --- | --- | --- |
| [`reggrep`](https://crates.io/api/v1/crates/reggrep) | 404 | 06:26:34 | 当时未见公开记录 |
| [`regrep`](https://crates.io/api/v1/crates/regrep) | 404 | 06:26:36 | 当时未见公开记录 |
| [`regfind`](https://crates.io/api/v1/crates/regfind) | 404 | 06:26:37 | 当时未见公开记录 |
| [`reglook`](https://crates.io/api/v1/crates/reglook) | 404 | 06:26:38 | 当时未见公开记录 |
| [`regloc`](https://crates.io/api/v1/crates/regloc) | **200** | 06:26:39 | `name=regloc`，`max_version=0.0.0`，仓库为 `squillo/r14n` |
| [`regqry`](https://crates.io/api/v1/crates/regqry) | 404 | 06:26:40 | 当时未见公开记录 |
| [`regsift`](https://crates.io/api/v1/crates/regsift) | 404 | 06:29:06 | 当时未见公开记录 |

404 只表示该次公开查询没有找到记录；不能保证发布会被接受，不能排除保留名，也不构成预留。
`regloc` 的保留描述是该包维护者的自述；**HTTP 200 和已有包记录**才是其名称已被占用的直接证据。
Cargo 的[官方名称规则](https://doc.rust-lang.org/cargo/reference/registry-index.html#name-restrictions)将大小写，以及 `-` / `_` 差异纳入重名检测；改展示大小写不能消除这些精确重名。

## 同名工具的事实与限制

### RegGrep

- [作者在 Vector 的说明](https://www.vector.co.jp/soft/win95/util/se063279.html)以第一人称介绍 RegGrep：搜索注册表，也可替换 `REG_SZ` / `REG_EXPAND_SZ` 的字符串内容；可搜索键，且明确不替换名称。
- 页面标注作者岩田欣一、运行环境 Windows NT / 98 / 95；[作者目录](https://www.vector.co.jp/vpack/browse/person/an012967.html)也列出该软件。因此已经确认的是同领域**展示名**碰撞。
- 未下载或运行其程序，未确认是否有 CLI、是否以 `reggrep.exe` 为入口，也未验证它在现代 Windows 上的兼容性。

### RegRep

- [markuslaker/regrep README](https://github.com/markuslaker/regrep)称其为 Perl 5 grep 实现，并明确要求运行 `regrep` 查看参数；这是精确**命令名**碰撞，领域是文本搜索。
- [InfoScale 厂商文档](https://docs.infoscale.com/us/en/infoscale/product-guides/windows/cluster-server-bundled-agents-reference-guide-wind/9-0/vcs-infrastructure-and-support-agents/registry-replication-regrep-agent.html)将 RegRep 定义为 Registry Replication agent，用于监测指定注册表键并同步集群节点的注册表；不能据此说存在 `regrep` 搜索 CLI。
- [LTRData/regrepl README](https://github.com/LTRData/regrepl)明确 `regrepl.exe` 是递归替换注册表值数据的 Windows GUI；这是同领域**近似名**，比 `regrep` 多一个 `l`。

### RegFind

- [MOBZystems 自身文档](https://www.mobzystems.com/tools/regfind/)称 RegFind 为 Windows 命令行文件 / 目录正则表达式搜索工具，直接示范 `RegFind /?` 与文件搜索调用；这是独立于 Microsoft Resource Kit 的精确 CLI 重名。
- Microsoft 的 [Q146303 原文存档](https://jeffpar.github.io/kbarchive/kb/146/Q146303/)保留 NT 4.0 Resource Kit RegFind 的注册表搜索、替换说明及 `REGFIND` 语法；[KB290396 原文存档](https://mskb.pkisolutions.com/kb/290396)另外明确 `Regfind.exe` 来自 NT Server 或 Windows 2000 Server Resource Kit。
- 两篇历史原文的当前载体均为**第三方镜像**，不是 Microsoft 现行托管页。原站 `support.microsoft.com/en-us/help/146303` 与 `/290396` 本轮在 06:30:13 / 06:30:15 均返回 404；未验证旧二进制或现代系统支持状态。

### RegLook 与 RegLookup

- [BleepingComputer 原站帖子](https://www.bleepingcomputer.com/forums/t/5218/ie-home-page-problems-please-help/)中，管理员 Grinler 于 2004-11-21 以 Reglook 名称提供其站点分发链接；后续用户贴出的程序日志列出 Windows 注册表键、值名和数据类型。
- 这是历史分发方原帖及使用者原始日志，**不是作者 README 或已验证的二进制命令名**；不能仅凭它确认 `reglook.exe` 的准确入口。
- 旧分发页 `https://www.bleepingcomputer.com/files/reglook.php` 与尝试的 `/download/reglook/` 本轮 06:29:09 均为 HTTP 403，未继续下载或执行程序；精确同名工具的实现细节仍未证实。
- [RegLookup 上游首页](https://projects.sentinelchicken.org/reglookup/)明确项目直接分析 Windows NT 注册表文件，提供命令行工具；[Debian 随包手册](https://manpages.debian.org/unstable/reglookup/reglookup.1.en.html)给出 `reglookup [options] registry-file`，读取文件并输出 CSV 风格结果。
- RegLookup 是分析注册表文件的工具，不能描述为 Windows 自带命令；与 RegLook 的关系是同领域**近似名称**，未发现两者存在项目关联的证据。

### RegQry 与 RegSift

- 本轮对这两个精确拼写的有限公开项目检索，尚未取得两者强同名 CLI / 注册表工具的第一方正面证据。
- Microsoft 的 [`reg query`](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/reg-query)确有注册表递归查询、匹配筛选功能；其实际命令拼写是 `reg` 加子命令 `query`，不能算作精确 `regqry` 占用。
- 这两项保留“未证实”状态，不将搜索无结果表述为名称已可用；不因未见强碰撞而替用户作最终命名决定。

## GitHub 查询记录

第一方公开仓库搜索 API 均为 HTTP 200、`incomplete_results=false`；每次请求 `per_page=100`。
下列总数是 `候选 in:name` 的所有名称匹配，**不是精确同名仓库数量**；只核对精确名字、明显近似名字及可读项目资料，没有逐仓审计源码。

| 查询 | 查询时间 | 返回总数 |
| --- | --- | --- |
| [`reggrep in:name`](https://api.github.com/search/repositories?q=reggrep%20in%3Aname&per_page=100) | 06:27:51 | 0 |
| [`regrep in:name`](https://api.github.com/search/repositories?q=regrep%20in%3Aname&per_page=100) | 06:27:52 | 87 |
| [`regfind in:name`](https://api.github.com/search/repositories?q=regfind%20in%3Aname&per_page=100) | 06:27:56 | 6 |
| [`reglook in:name`](https://api.github.com/search/repositories?q=reglook%20in%3Aname&per_page=100) | 06:27:57 | 12 |
| [`regloc in:name`](https://api.github.com/search/repositories?q=regloc%20in%3Aname&per_page=100) | 06:27:58 | 11 |
| [`regqry in:name`](https://api.github.com/search/repositories?q=regqry%20in%3Aname&per_page=100) | 06:28:00 | 0 |
| [`regsift in:name`](https://api.github.com/search/repositories?q=regsift%20in%3Aname&per_page=100) | 06:29:07 | 0 |

例如 `reglook` 返回了 `jasonholloway125/RegLook`、`cockpitdotrun/reglook`、`ripungit/REGLOOK` 等精确仓库名，但 API 描述为空；仅凭仓库名不能断言它们是 CLI 或注册表工具。
该例来源为上表 `reglook` API；本轮未确认这些仓库的功能，也未将它们作为已确认的命令重名。

## 本机 PowerShell 无 profile 枚举

两个独立进程均用 `-NoLogo -NoProfile -NonInteractive`，只读取命令 / 别名元数据，未执行候选程序。

| 进程 | 查询时间 | 检查名称 | `Get-Command -All` | `Get-Alias` |
| --- | --- | --- | --- | --- |
| Windows PowerShell 5.1.26100.9818 / Desktop | 06:29:30 | `reggrep,regrep,regfind,reglook,regloc,regqry,regsift` | 0 匹配 | 0 匹配 |
| PowerShell 7.7.0 / Core | 06:28:35 | 同上 | 0 匹配 | 0 匹配 |

枚举主体如下；另外输出进程版本与 UTC 时间。原始结果是这次本地观察，无需通过外部网页推断。

```powershell
$names = 'reggrep','regrep','regfind','reglook','regloc','regqry','regsift'
Get-Command -Name $names -All -ErrorAction SilentlyContinue |
    Select-Object Name,CommandType,Source,Definition
Get-Alias -Name $names -ErrorAction SilentlyContinue |
    Select-Object Name,Definition
```

5.1 入口为 `C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`。
7 的已发现入口为 `C:\Users\inaku\AppData\Local\Microsoft\WindowsApps\Microsoft.PowerShell_8wekyb3d8bbwe\pwsh.exe`，经正常审批后运行成功；未确认包内部路径，没有更改执行策略。
Microsoft 的[命令优先级说明](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_command_precedence)说明 `-All` 的用途；[大小写说明](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_case-sensitivity)明确命令 / 别名查找不区分大小写。
因此这些本地零匹配只覆盖当时进程的发现范围、PATH 和会话，不覆盖其他机器、用户 profile、额外模块或未来安装的软件。

## 查询边界

- 初始受限网络请求未连通，**没有记作 404**；上面的 crates.io / GitHub 状态来自获正常审批后成功联网的只读请求。
- 部分网页通过搜索服务的原站索引可读，但直接抓取失败：RegLookup 首页直接请求出现 TLS 错误；这不代表项目不存在，也未采用关闭证书验证等绕过办法。
- RegFind 历史 Microsoft 文档的第三方镜像载体、RegLook 原分发 403、无描述同名仓库的未确认功能，均按上述限制保留，不能升级为已核实作者 / 可执行文件结论。
- 未穷尽私有仓库、所有软件包生态、企业名称、域名或商标；不是法律审查或全网唯一性证明。正式发布前应重新核查所选包名和入口。
- 未注册 / 发布 crate、占名、安装或运行候选程序、读取凭据、修改仓库名称；最终名称仍由用户选择。
