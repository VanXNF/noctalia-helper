# Noctalia Mod：从 Nyxuri 重构出的独立子项目

> 事实入口与会话交接文档。只记录代码里真实存在的状态，不写"计划中已完成"。
> 状态标记：`已完成` / `进行中` / `待办`。缺陷用 `P0`/`P1`/`P2` 标优先级。
>
> **权威边界**：`noctalia-mod/` 内部文档是本子项目的唯一事实源。本仓库
> `llms-wiki/` 描述的是旧引擎 Nyxuri，不再同步子项目内容；旧引擎退役时
> 一并作废（见 §12）。
>
> **新会话先读 [§16 接手须知](#16-接手须知新会话先读)**
> —— 环境事实、当前工作区状态、下一步、待裁决清单、已知陷阱、
> 以及哪些结论只是推理而非实测，都在那一节。阶段 A 与阶段 B 已收口，
> 下一步是阶段 C。

## 0. 终极目标与定位

终极目标：把配置管理能力从现有 Nyxuri 引擎中重构出来，形成独立子项目
`noctalia-mod/`，逐步接管全部能力，最终成为唯一的配置管理实现。

**最终用途**：装完 CachyOS 之后，先引导用户装齐必要的软件和包，再引导用户快速
完成配置（niri + noctalia）。这条用途是硬约束，不是附属场景——它决定了能力
迁移的优先级和交互形态。

### 目标使用流程

两段式，各自独立、可重跑、可只跑其中一段：

```text
① deps   依赖引导   检查 → 列出缺什么 → 一次授权 → 装齐
② install 配置引导  预检清单 → 一次确认 → 原子部署 + reload
```

对应的命令：

```bash
noctalia-mod setup                     # 引导：一份清单、一次确认、两段跑完（核心集）
noctalia-mod setup --yes               # 同上，非交互
noctalia-mod setup --with fcitx5       # 顺带装一个模块声明过的可选程序
noctalia-mod deps                      # 只装依赖，不碰 ~/.config
noctalia-mod deps niri noctalia --yes  # 同上，非交互
noctalia-mod install niri noctalia     # 只铺配置
noctalia-mod install --yes             # 全量，非交互
```

设计要求：

- **两段之间没有隐式依赖**：`deps` 不写 `~/.config`；`install` 会把它预检清单里
  缺的包一并装掉，但一定先列出来、算在那一次确认里，不偷偷装。用户想先看清单再
  决定是常态，不能逼他一次做完。
- **`setup` 是引导入口，不是第三套实现**：它把两段合成一条路径——一份合并
  清单、一次确认、装包与部署依次跑完，两段本身仍各自可用。它默认只装核心集
  （niri + noctalia），无参数不等于"全都要"。
- **每段自己就是完整的**：`deps` 单独跑完系统就是"包齐了"的状态，`install`
  单独跑完配置就是"铺好了"的状态，重跑都收敛。
- **引导 = 集中决策，不是逐步盘问**：清单一次性摊开，确认一次，然后安静跑完。
  这和 AGENTS §6 的"非交互优先 + 部署前统一预检"是同一件事，不是相反的东西。
- **权限一次性取**：`deps` 在动手前统一 `sudo -v`，安装循环里不再打断。
- **AUR helper 前置确认**：先把 repo 包装到一半才发现没有 helper 是最糟的收场，
  所以顺序是"检查 helper → 取权限 → 装 repo → 装 AUR"。
- **niri + noctalia 是核心**：其余模块（kitty/fish/starship）是加固而非必需。
  但 niri 的配置会 spawn `kitty`、`nautilus` 等程序，这些由 §3 的程序自洽校验
  强制声明并进包清单，所以"核心"实际是"配置能真正跑起来的最小集合"，
  不能只按模块名划。

由此确定其余约束：

- **不能假设系统里已有任何配置**：全新机器上没有 `~/.config/niri`、没有
  用户目录结构、没有旧状态，一切都由本项目创建。
- **环境检查与依赖安装是一等公民**：缺什么要能在部署前说清楚并装掉，
  而不是让用户自己去补。
- **非交互路径必须可用**：初始化场景要能一路跑完，阻断式确认只能是例外。
- **可重复执行**：同一台机器上重跑必须收敛，不产生重复或残留。

由此确定三条基本路线：

- **渐进迁移，不推倒重来**：基座先跑通安装/部署/状态/快照闭环，其余能力
  按 §11 的顺序逐块搬过来。每一步新旧可并行，可回退。
- **子项目自包含**：代码、配置源、测试、文档都在 `noctalia-mod/` 内。
  迁移完成后整目录可独立检出使用（可提取为独立仓库）。
- **不背旧包袱**：不迁移 Nyxuri 的兼容别名（`nyxniri`）、历史墓碑清单和
  用户状态账本。新项目只认自己的状态。

目标环境：CachyOS + niri + Noctalia V5。运行时是 Bash，只用系统已有基础工具。
模块协议不把 niri 写死为唯一窗口管理器，但第一阶段只验证上面这组环境。

### 为什么是 Bash

不是因为"Python 有依赖"——恰恰相反，[install.sh](../install.sh) 已经把
`python3` 作为硬性前置，旧引擎是零 pip 依赖的纯标准库实现。选 Bash 的理由只有
一条：子项目要能被单独取走使用，且不引入新的运行时前提。

代价必须被承认：原子替换、状态账本、快照这三块最关键的代码会有两套独立实现。
因此它们必须有等价的行为契约和测试，不能靠"看起来一样"。基座收口（§11 阶段 A）
就是为这件事服务的。

## 1. 迁移期边界：所有权与漂移检测

迁移期内新旧两个管理器会写同一批 `~/.config` 路径。**这是当前最大的风险**，
必须显式处理，不能只靠目录级的"外部文件"提示。

问题：`noctalia-mod` 与 Nyxuri 各自持有 preset/part 状态。例如先跑
`nyxuri preset kitty transparent`，再跑 `noctalia-mod install kitty`，
`kitty.conf` 会被静默改回默认——两边都不知道对方动过什么。

设计决定（`已完成`）：

1. **所有权指纹**：每个模块部署成功后把管理内容的摘要写进自身 state 的
   `fingerprint`；`plan` 时重新计算并对比。
2. **漂移必现**：不一致时 pre-flight 打印 `drift\t<模块>\t<changed|missing>`，
   当作外部改动处理，绝不静默覆盖。
3. **只认自己的账本**：不读取、不迁移 Nyxuri 的 `state.json`、预设目录和快照索引。
4. **退出判据**：当 §11 阶段 A–G 的能力对等清单全部满足、且切换入口后，
   旧引擎转为只读回退路径，随后删除。切换前不新增对旧状态的依赖。

指纹刻意选轻：整个模块一个摘要，不做逐文件版本库。覆盖范围只包括"本项目会覆盖
的文件"，即排除 `__custom__` 与 `MODULE_PRESERVE`：

- 用户改 `__custom__` 是设计内行为，不该报漂移；
- 运行时被改写的文件（如 Noctalia 渲染的 `niri/colors.kdl`、被 `toggle-eyecare.sh`
  改指向的 `niri/effects.kdl`）必须声明为 preserve，声明了就不算漂移；
- 反过来说，**如果某个运行时写入者没被声明，报漂移就是对的**——它说明模块元数据
  漏了一个写入者，这比默默覆盖有价值。

已知取舍：摘要只能告诉你"这个模块变了"，说不出是哪个文件变的；要说清楚得把文件
清单也存进账本。权限位不进指纹（`apply_chmod_rules` 每次部署都会重新施加）。

## 2. 目标目录结构

```text
noctalia-mod/
├── bin/
│   └── noctalia-mod
├── lib/
│   ├── common.sh          # 基础原语、校验、日志
│   ├── paths.sh           # XDG 路径与目标路径安全检查
│   ├── lock.sh            # 项目级非阻塞锁
│   ├── package-manager.sh # 依赖探测与 argv 构造
│   ├── state.sh           # 状态账本
│   ├── snapshot.sh        # 快照、回滚、清理
│   ├── deploy.sh          # 暂存构建、原子替换、保留规则
│   ├── preset.sh          # 用户预设的存取与预设消失语义
│   ├── reference-check.sh # 引用与程序声明的静态自洽校验
│   └── module-loader.sh   # 模块元数据加载与校验
├── modules/
│   └── <module>/          # 见 §3
├── tests/                 # 子项目自带测试（自包含）
├── PLAN.md                # 本文档：方案与进度
└── README.md              # 使用说明
```

每个模块自包含：

```text
modules/<module>/
├── module.conf            # 模块元数据与依赖声明（Bash，被 source）
├── files/                 # 默认配置源
├── presets/               # 官方预设，可为空
├── parts/                 # 可插拔零件，可为空
└── README.md
```

**当前实际布局与目标的差异**（迁移中，不得当作已完成）：

| 目标 | 现状 |
|---|---|
| `tests/` 在子项目内 | `已完成`：`noctalia-mod/tests/`，自带 `utils.py`，不 import 旧引擎 |
| `profiles/` 可用 | 已判定**不需要**并删除空目录（§11 阶段 C）；用户预设按模块存放就够表达"哪个变体" |
| 各模块 `README.md` 描述协议与例外 | `已完成`：八个模块各自写了目标、包、preserve、零件与例外 |

## 3. 模块协议

`module.conf` 是 Bash 变量赋值，由引擎 source，不引入 TOML 解析器。变量：

| 变量 | 含义 |
|---|---|
| `MODULE_ID` | 模块 ID，必须与目录名一致 |
| `MODULE_TARGET` | 相对 `$XDG_CONFIG_HOME` 的目标路径（文件或目录） |
| `MODULE_FILES` | 默认配置源目录，默认 `files` |
| `MODULE_REPO_PACKAGES` | 官方仓库依赖 |
| `MODULE_AUR_PACKAGES` | AUR 依赖 |
| `MODULE_PRESERVE` | 按名保留的路径（运行时会话状态） |
| `MODULE_CHMOD` | 需要加执行位的相对 glob |
| `MODULE_RELOAD_COMMAND` | 部署后的 reload/reload 动作（argv 数组） |
| `MODULE_VALIDATE_PATHS` | 部署后必须存在的路径 |
| `MODULE_EXTERNAL_REFS` | 被引用但不由本项目提供的配置路径（运行时产出或外部提供），见下 |
| `MODULE_REQUIRED_COMMANDS` | 必需程序，写作 `命令:提供它的包`，见下 |
| `MODULE_OPTIONAL_COMMANDS` | 可选程序，写作 `命令` 或 `命令:包`；缺失只提示，`setup --with` 只认这里声明过的名字 |
| `MODULE_EXTERNAL_COMMANDS` | 基础系统自带的程序，声明出来给 spawn 检查一个落点 |
| `MODULE_PARTS` / `MODULE_PART_<SLOT>_TARGET` / `MODULE_PART_<SLOT>_DEFAULT` | 零件插槽声明 |

默认行为由目录约定驱动，`module.conf` 只声明例外。

模块必须遵守：

- 参数与返回码明确；失败向上传播，不吞错。
- 不直接改其他模块的状态；不绕过中央锁、快照和失败恢复。
- 不假设某个模块已安装，除非 §7 的依赖声明写明。
- 外部命令用参数列表调用，不拼接未校验的输入。
- **引用自洽（`已完成`，见 §10 已修复 P0-2）**：被部署配置引用到的
  `~/.config` 路径，必须在部署后真实存在——要么由某个已接入模块提供，要么在
  `MODULE_EXTERNAL_REFS` 里显式登记。没有第三条路。

### 引用自洽校验

`noctalia-mod check` 静态扫描所有模块源（`files/`、`presets/`、`parts/`），
提取两类引用后逐条核对部署集合：

1. 直接写死的配置路径：`~/.config/x`、`$HOME/.config/x`、`/home/user/.config/x`、
   `${XDG_CONFIG_HOME:-$HOME/.config}/x`。
2. 目录变量再拼文件名：`VAR="<配置根>/dir"` 之后出现 `"$VAR/file"`。

部署集合由"已接入模块实际会部署什么"算出：`files/` 全树 + 每个 preset 的稀疏
覆盖 + 各零件目标文件。判定规则：引用等于其中一项，或是其中某项的祖先目录，
即视为存在。

未解析的引用一律报错：`check` 返回非零，`install` 直接拒绝部署，`plan` 在预检里
打印 `unresolved-ref` 行。这样"配置引用了不存在的东西"在开发期就暴露，不会等到
用户装完才发现快捷键是坏的。

### 程序自洽校验

路径查完了还得查程序：配置里 `spawn` 的东西如果没人声明，`deps` 就会报"齐全"
而快捷键是坏的。规则同样是"要么声明，要么不许留"：

1. **静态**（`check`）：KDL 里 `spawn` / `spawn-at-startup` 的首个参数必须被
   声明为必需、可选或基础系统三者之一，否则报 `undeclared-command`。
2. **静态**（`check`）：必需程序的包必须出现在**本模块自己的**包清单里，否则报
   `unbound-command`。绑在同一个模块上有意为之——这样 `deps <module>` 是自足的，
   不会出现"装了 A 模块却依赖 B 模块的包"。
3. **运行时**（`deps`、`plan`、`setup`）：`command -v` 核对必需/可选程序是否真的在
   PATH 上，报 `missing-required` / `missing-optional`。只核对本次选定的模块——
   `deps niri` 不该去说 fish 的二进制在不在。`deps`/`setup` 装完还会再核一遍必需项，
   防止"包装了但命令还是没有"（包名对不上、二进制改名、PATH 未刷新）。
4. **加装**（`setup --with <程序>`）：只认模块声明过的可选程序，解析成包后并进
   同一条安装路径。命令行不能凭空指定包名，否则"谁 spawn 谁声明"的契约就能绕过。
   可选程序默认不装，只在这份清单里列出来。

运行时缺必需程序**不阻断** `install`/`setup`：那是这台机器的状态，不是仓库的
缺陷。仓库缺陷（未声明、未绑定）才阻断部署。

已知边界（校验器不覆盖，属于人工责任）：

- 只扫 KDL 的 `spawn`。shell 脚本里的调用（`wpctl`、`wlsunset`…）和 Python 里的
  `subprocess` 不会自动提取，靠人工写进 `MODULE_*_COMMANDS`。niri 模块的声明是
  人工审计后的结果（脚本里 `command -v` 守卫过的算可选）。
- 脚本里用自身位置拼出来的路径同样扫不到。`niri-scratch-toggle.sh` 用
  `$(dirname $BASH_SOURCE)/../../noctalia/tools/wallpaper-picker.py` 指向 noctalia
  模块，运行时正好落在 `~/.config/` 内、是对的，但换个 `MODULE_TARGET` 就会断——
  这类引用只能人工保证。
- 拼接、循环生成的路径。
- Python/其它语言里的 `os.path.join(A, B, C)` 形式。
- **用户预设不在扫描范围内**：`check` 只扫仓库里的模块源（`files/`、`presets/`、
  `parts/`）。用户预设是用户自己的内容，让仓库体检去为用户数据报错是错的取向；
  那里的悬空引用要等 `install` 部署时才暴露。
- **shipped 工具的运行时依赖是否已声明**：`MODULE_REPO_PACKAGES` 与工具实际
  import 之间没有自动校验。第一个实例是 noctalia 的 `import cairo`，需要
  `python-cairo`——迁移 tools 时才暴露出来（见 §10 已修复）。

**暂不实现**：`hooks.sh` 生命周期钩子。协议里保留这个概念，但引擎不实现、
模块不提供，直到真正需要（§11 阶段 D 重新评估）。

## 4. 配置层次与保留规则

四层模型不变，改为模块内部管理：

1. 默认配置：`modules/<module>/files/`
2. 官方 preset：`modules/<module>/presets/<name>/`（稀疏覆盖，未重写的文件从底版继承）
3. 用户 preset：`$XDG_CONFIG_HOME/noctalia-mod/presets/<module>/<name>/`
4. 用户自定义：目标路径中的 `__custom__` 文件或目录

preset 状态按模块保存（账本里的 `preset` 键）。第一阶段不做全局不可拆分的 preset；
`profiles/` 那一层跨模块组合已判定不需要，见 §11 阶段 C。

**用户预设归 config 不归 state**：它是用户手编、值得自己备份的内容，而 state 放的是
账本、快照、锁这类机器状态。路径与旧引擎的 `~/.config/nyxuri/presets/` 同构。

规则：

- **解析顺序官方优先**：同名时官方预设胜出（它是随仓库发布的契约），`preset save`
  直接拒绝占用官方名字，不给"永远不生效的同名目录"留活路。
- **`default` 是保留字**：它指随包发布的默认配置。`apply default` 是正经操作（把模块
  铺回默认），但 `save` / `edit` / `delete` 都不接受这个名字。
- **名字必须是标识符**（`[a-z0-9][a-z0-9-]*`），与模块 id、零件名同一套校验。
- **`save` 不带走 `__custom__`**：那是用户的实时覆盖，每次部署都会被重新继承回来，
  存进预设只会让人误以为它进了"版本"。软链按链接存（如 kitty 的 `current-theme.conf`）。
  覆盖同名用户预设前必须确认一次（`--yes` 跳过）——那是不可逆的用户内容。
- **官方预设不可 `edit` / `delete`**：它在仓库里，不在用户目录里。
- **预设目录本身不接受软链**：否则"预设"就能变成指向仓库外任意路径的跳板。
- **预检里显式暴露**：活跃 preset 消失时 `plan`/`setup` 打印
  `preset-missing\t<模块>\t<preset>\t<frozen|reset>`，不靠用户自己从账本里发现。

**活跃 preset 消失后的语义**（与旧引擎一致，都是刻意选择）：

| 情形 | 处理 | 为什么 |
|---|---|---|
| 目标还在 | **冻结**：跳过该模块的部署，账本不动，警告 | 绝不静默把用户的配置改回默认，那等于毁数据 |
| 目标也没了 | 回退 `default` 重铺，成功后才写账本 | 没有东西可丢；写状态放在部署之后，失败就什么都不留 |

冻结的模块**不写账本**：重算指纹会把漂移一起抹掉，等于替用户宣布"没变化"。

目标根目录默认 `~/.config/`（跟随 `XDG_CONFIG_HOME`）。状态目录：

```text
$XDG_STATE_HOME/noctalia-mod/         # 回退 $HOME/.local/state/noctalia-mod/
├── modules/<id>.state                # 模块账本
├── snapshots/<snapshot_id>/          # 快照
├── audit.log                         # 操作审计
└── lock                              # 项目锁
```

用户预设不在状态目录里，它是配置：

```text
$XDG_CONFIG_HOME/noctalia-mod/presets/<module>/<name>/
```

**暂存目录不在 cache**：原子替换要求同一文件系统，暂存目录建在目标父目录下的
隐藏临时目录（`.noctalia-mod.new.*` / `.noctalia-mod.old.*`），完成后就地清理。
`$XDG_CACHE_HOME/noctalia-mod/` 不是本管理器的临时目录，它是 Noctalia 渲染
Material You 色板的输出位置（见 noctalia 模块配置），子项目只是沿用这个位置。

部署时必须继续遵守：

- 不软链接写入 `~/.config`（`~/.config` 内部文件之间的运行时软链接不受此限，
  例如 niri 的 `effects.kdl`）。
- `__custom__` 文件和目录按名保留。
- `MODULE_PRESERVE` 声明的路径按名保留，软链接按链接保留（不解引用）。
- 回滚支持关闭 custom 继承，保证精确恢复。
- 所有目标路径经路径安全校验，禁止脱离配置根目录。
- **单文件型目标**（如 `starship.toml`）：不存在目录暂存，因此整个文件每次都被
  替换，也没有 `__custom__` 继承与 preserve 名单；`/home/user` 占位符替换只对
  暂存目录执行，单文件目标不参与。

## 5. 部署、状态与事务

一次部署的阶段：

1. 拒绝 root 运行。
2. 加载并校验目标模块。
3. 汇总环境信息（CachyOS 标记、niri / Noctalia 是否在 PATH）。
4. 汇总缺失依赖、将覆盖的路径、保留路径、reload 动作、漂移项（§1）。
5. 展示 pre-flight 清单。
6. 交互模式要求确认；只有显式 `--yes`/`--express` 或非交互显式传参才跳过。
7. 覆盖前创建当前配置快照。
8. 按模块构建暂存树并原子替换。
9. 执行权限规则、部署后校验、reload。
10. 成功后写入账本（含所有权指纹）。
11. 任一模块失败时，按部署前快照恢复已修改内容。

第 6 步确认之后、第 7 步快照之前，`install` 与 `setup` 还会按同一份预检清单把缺的
软件包装掉——就是 §7 那个依赖阶段本身。所以 `install` 单独跑也是完整的，不强制
先跑 `deps`；反过来 `deps` 单独跑也从不碰配置。

**环境检查语义（明确）**：第一阶段只提示，不阻断。目标环境之外的机器上装出来
的东西大概率不能用，但那是用户的选择；`plan` 会把缺失项列出来。若将来要阻断，
必须同时提供 `--force` 出口。

`setup` 走的是同一批阶段，只是把 3–11 步并为"一份合并清单 + 一次确认"，装包与
配置部署之间不再第二次打断。它不另开装包通道，也不另写一套部署逻辑。

冲突策略：预检列清单后确认覆盖。自己管过的可直接更新；来源不明（含 Nyxuri
部署的、或指纹漂移的）必须出现在清单里；非交互模式必须显式确认参数。

账本字段：

| 字段 | 说明 | 状态 |
|---|---|---|
| `enabled` | 是否已启用 | 已完成 |
| `preset` | 当前 preset | 已完成 |
| `target` | 目标相对路径 | 已完成 |
| `source_version` | 部署源版本 | 已完成 |
| `last_snapshot` | 部署前快照 ID | 已完成 |
| `custom_paths` | 保留的 `__custom__` 路径 | 已完成 |
| `preserve_paths` | 保留的 preserve 路径 | 已完成 |
| `last_result` | 最近一次部署结果 | 部分（只写成功） |
| `part.<slot>` | 各插槽当前零件 | 已完成 |
| `fingerprint` | 管理内容的摘要，用于漂移检测 | 已完成 |

另一份**项目级**账本 `$XDG_STATE_HOME/noctalia-mod/packages.tsv`：

| 字段 | 说明 | 状态 |
|---|---|---|
| `<包>` \t `<repo\|aur>` | 由本项目实际装下去的包 | 已完成 |

依赖包放在项目级而不是模块级：同一个包可能被多个模块声明，而且用户可能只跑了
`deps` 没跑 `install`——那时模块 state 还不该存在。只记"我们装的"，本来就在系统里
的包不进账本，否则将来的显式清理会去动用户自己装的东西。

状态写入必须经锁保护，并使用临时文件加原子替换，且是**合并写**：本次没提到的键
原样保留，已存在的键就地更新，新键追加到末尾。覆盖式重写会让新增字段被下一次
`install` 静默抹掉——账本字段只会越来越多，要求每次写都把整个 schema 记全不现实。

合并写的代价是陈旧键不再被自动清掉，所以"整族键"的清理要显式做：模块删掉一个
零件插槽时，`record_modules` 会先清掉 `part.*` 再写当前值（`state_module_unset_prefix`）。

## 6. 快照、回滚与卸载

### 快照与回滚

- 部署前自动快照；支持手动创建、列出、删除。
- 回滚前创建当前状态保护快照。
- 普通部署继承 `__custom__`；精确回滚不继承当前配置里的新 custom 内容。
- **清理保护（`已完成`）**：清理保留 = 全部受保护快照 + 最近的 N 个普通快照。
  受保护的是：刚建好的那个、每个模块账本里的 `last_snapshot`（uninstall 的恢复
  点）、最近一次滚回保护快照。保留排序按 `created_at`，不按 ID 字符串——ID 的
  时间戳只到秒、后缀随机，按 ID 排等于随机丢弃。
- 快照上限 30 个，指的是**普通**快照；受保护的不计名额，宁可多留几个也不删掉
  唯一的恢复点。
- 用户手动删掉某个恢复点时给出警告；卸载时如果恢复点已经不在，明确告知原文件
  无法恢复，不静默删除。

### 卸载

- 优先恢复最近一次部署前快照。
- 没有可用快照时，只移除账本记录的文件和目录；此时必须明确告知用户
  "原文件无法恢复"，因为那意味着回滚点已经丢了。
- 不删除 `__custom__` 内容和模块声明的 preserve 文件。
- 不删除系统软件包（避免删掉别人共用的依赖）。
- 结束后清理状态目录，保留审计信息。

## 7. 依赖管理

依赖由模块声明，由独立的 `deps` 阶段统一检查和执行。它不写 `~/.config`，
也不依赖 `install` 先跑过——这是 §0 两段式流程的第一段。`setup` 用的是同一个
依赖阶段，只是和配置部署合并成一次确认（见 §5）。

```bash
noctalia-mod deps [module ...] [--yes]
noctalia-mod setup [module ...] [--yes] [--with <程序> ...]
```

输出是一份清单，不是逐一提问：

```text
Noctalia Mod dependency pre-flight
environment	CachyOS detected
repo	niri noctalia python-gobject python-cairo gtk-layer-shell
aur	<空则不打这一行>
missing-repo	niri noctalia
missing-aur	<空则不打这一行>
aur-helper	paru
```

规则：

- 首选 CachyOS/Arch 官方仓库包；`MODULE_REPO_PACKAGES` 声明。
- 支持声明 AUR 包来源（`MODULE_AUR_PACKAGES`），但不自动安装或引导 AUR helper。
- 优先检测已存在的 `paru` 或 `yay`；没有可用 helper 时明确报告，不静默改系统。
- **执行顺序固定**：缺 AUR 包 → 先确认 helper → 无 helper 立即失败，不装任何
  repo 包 → 有 helper 则 `sudo -v` 一次性取权限 → 装 repo → 装 AUR。
- 全部已装时直接报"nothing to install"并成功返回，不取权限、不调包管理器。
- 交互模式确认一次，`--yes` 跳过；非交互且无 `--yes` 直接拒绝。
- 依赖检查、依赖安装、配置部署是三件独立的事，可以分开重试。
- `install_dependencies` 把实际装下去的包回报给调用方，由 CLI 写进
  `packages.tsv`；`deps` 与 `setup` 都会记账。默认不自动卸载，将来做显式清理时，
  只能处理"账本确认由本项目安装、且当前没有任何模块声明需要"的包。
- **可选程序默认不装**：`setup` 的清单里列成 `optional` 行，只有 `--with <程序>`
  点名的才进包清单。名字必须是模块声明过的可选程序；包在模块 AUR 清单里就按
  AUR 装，否则走官方仓库。

包清单不只来自"模块自己声明要什么"，也来自"配置里 spawn 了什么"：必需程序的
包必须写进同一模块的 `MODULE_REPO_PACKAGES`/`MODULE_AUR_PACKAGES`，所以
`deps niri` 会把 `kitty`、`nautilus`、`wireplumber`、`libnotify`、`python`、
`noctalia` 一起带上——这些正是 niri 默认配置直接 invoke 的程序。清单输出里的
`missing-required` / `missing-optional` 就是这个核对的结果，且只覆盖本次选定的
模块。

## 8. 已接入模块

`已完成`：niri、noctalia、kitty、fish、starship、fastfetch、xdg-desktop-portal、zed。

- **niri**：默认配置、`monitor.kdl` / `effects.kdl` / `colors.kdl` 等 preserve、
  `effects` 与 `glow` 两个零件插槽、脚本执行位、`niri msg` reload。随包提供
  初始 `effects.kdl -> effects_normal.kdl` 软链，保证全新安装时
  `config.kdl` 的 `include "effects.kdl"` 能解析；运行时脚本改指向后由 preserve 保留。
- **noctalia**：Noctalia V5 配置、模板源（模板由 Noctalia 自身渲染）、
  `tools/`（Orbit 启动器与 Wallpaper Picker 及其 Python 包）、`wallpaper-hook.sh`
  与 `mpv-hook.lua`。这些是配置里真实引用到的文件，随模块一起走。
- **kitty**：配置、`current-theme.conf` 运行时软链、预设 `transparent`、`pkill -SIGUSR1` reload。
- **fish**：配置目录、local PATH hook、补全。
- **starship**：单文件配置。
- **fastfetch**：`config.jsonc`；包、二进制、目录同名，无例外。配置本身不 spawn
  东西，但 `fastfetch` 仍声明为必需程序——否则 `deps` 会对着没人能读的配置报"齐全"。
- **xdg-desktop-portal**：`portals.conf` + `niri-portals.conf` 两份路由。配置里
  `[preferred]` 点名 gnome / gtk 两个后端与 gnome-keyring，所以这四个包都归本模块
  声明。portal 与后端都装在 `/usr/lib`、由 D-Bus 激活，因此**不**写
  `MODULE_REQUIRED_COMMANDS`（`command -v` 看不到它们，声明了就是永久假警报）。
- **zed**：`settings.json` + `keymap.json`。旧引擎把它同时登记在
  `.optional-apps.toml` 里（配置部署、包只进 optdepends）；新项目没有"可选软件"
  这一轴，所以 `zed` 是普通模块，`deps zed` 会装编辑器。代价见 §10。

## 9. 当前真实进度

### 已完成

- Bash 入口与模块加载器，八个模块接入。
- 操作：`list`、`check`、`setup`、`deps`、`plan`、`install`、
  `preset list|apply|save|edit|delete`、`part list|apply`、`snapshot`、`rollback`、
  `uninstall`、`status`。
- 用户预设：存在 `~/.config/noctalia-mod/presets/<模块>/<名字>/`，与官方预设同一套
  解析顺序（官方优先）；`save` 不带 `__custom__`、覆盖前确认、拒绝保留字与官方同名；
  `delete` / `edit` 只作用于用户预设。活跃预设消失时按 §4 的冻结/回退语义处理。
- 引导入口 `setup`：依赖与配置合成一份清单、一次确认、依次跑完，无参数时默认
  核心集（niri + noctalia）；`--with <程序>` 加装模块声明过的可选程序；跑完落
  一份收尾总结（装了什么、铺到哪、怎么退）。`setup` 可重复执行并收敛。
- 独立的 `deps` 依赖阶段：清单式预检、AUR helper 前置确认、`sudo -v` 一次性
  授权、repo/AUR 分批安装、已装齐时零操作返回、装后复核必需程序。
- pacman/AUR helper 的 argv 构造、pre-flight 清单、原子替换、失败恢复、
  项目锁、状态账本。
- 自动快照、手动快照、回滚、卸载恢复，`__custom__` 与 preserve 保留。
- 引用自洽校验（`check`）：配置路径 + 配置 spawn 的程序两个维度，并接入
  `plan`/`setup` 预检与 `install`/`setup` 门禁。
- 所有权指纹与 drift 检出；项目级依赖包账本。
- 行为测试 41 个用例，位于子项目内（`noctalia-mod/tests/`），可独立执行。
- 与旧引擎零耦合：不读旧状态、不依赖旧入口、不修改旧 `install.sh`。

### 未完成 / 不实

以下项目曾在本文档中被写成"已完成"，实际不成立，已订正：

- 测试**不在**子项目内，且 §13 的覆盖清单只满足约三分之一。
- `profiles/` 只有空目录，没有任何实现（现已判定不需要并删除，见 §11 阶段 C）。
- `hooks.sh` 在 §3 声明过，引擎里没有任何实现。
- 没有做过新旧部署结果的隔离 HOME 对照验收。
- 环境检查只打印信息，不阻断（现已明确为设计选择）。
- `$XDG_RUNTIME_DIR/noctalia-mod` 从未被使用，相关函数是死代码。
- **初始化从未在真实全新机器上验收过**：`setup` 只在隔离 HOME + 假命令下闭环，
  实机受 `sudo` 不可用限制（见 §16.1、§16.5）。

## 10. 已知缺陷与待办

按优先级排列。每项都要有能复现它的测试，测试通过才算关闭。

### 已修复

**P0-2 迁移后的悬空引用（已修复）**。niri 的 `Mod+W`、`Mod+A` 与 noctalia 的
`wallpaper_changed` hook 指向 `~/.config/noctalia/tools/*.py`、`wallpaper-hook.sh`
和 `mpv-hook.lua`，这些文件原先都不在模块里，全新装机后快捷键是坏的。

处理方式：按"配置引用了什么就带上什么"的原则，把 `tools/`（Orbit + Wallpaper
Picker 两个 Python 包）、`wallpaper-hook.sh`、`mpv-hook.lua` 一并纳入 noctalia
模块；迁移时清理了旧项目残留——`~/.cache/nyxuri` 系列路径改为
`~/.cache/noctalia-mod`，删掉 `NYXURI_*`/`NYXNIRI_*` 兼容脚手架与
`LEGACY_PALETTE_PATH` 回退，环境变量改名 `NOCTALIA_MOD_WALLPAPERS_DIR`。

同时按 §3 加了自动校验（`check` 命令 + `plan`/`install` 门禁），这类问题以后在
开发期就会被拦下。回归测试：
`test_noctalia_ships_every_tool_its_config_references`、
`test_reference_check_rejects_a_dangling_reference`、
`test_deploy_refuses_when_a_reference_is_dangling`。

**P1-1 所有权指纹未实现（已修复）**。原先 `plan` 判断 owner 只看自己的 state，
Nyxuri 或用户直接改过的目标挡不住被静默覆盖。

处理方式：`module_fingerprint` 对"本项目会覆盖的文件"（排除 `__custom__` 与
`MODULE_PRESERVE`）取内容摘要，部署成功后写入 state 的 `fingerprint`；`plan` 重新
计算并对比，不一致打印 `drift <模块> changed`，目标消失打印 `missing`。
回归测试：`test_drift_reports_only_files_the_project_would_overwrite`、
`test_drift_reports_a_target_that_disappeared`。

**P1-2 依赖包未记账（已修复）**。`record_modules` 从不记录装过什么包。

处理方式：`install_dependencies` 回报实际装下去的包（`PLAN_INSTALLED_REPO/AUR`），
CLI 写进项目级账本 `packages.tsv`（`包<TAB>来源`），`deps` 与 `install` 两条路径都记。
只记我们装的，本来就在系统里的包不进账本。回归测试：
`test_deps_records_only_what_it_installed`。

**P1-3 状态写入丢弃未列出的字段（已修复）**。`state_put_many` 原先每次重写整个
文件，只写传入的键，于是任何本次没提到的字段都会被下一次 `install` 静默抹掉——
新增 `owner`、`packages` 这类字段时必然踩到。

处理方式：改成合并写（未提到的键保留、已存在的键就地更新、新键追加），
`state_module_set` 改为复用同一条路径，去掉重复实现；因为合并写不再自动清陈旧键，
新增 `state_module_unset_prefix` 并在 `record_modules` 里显式清理 `part.*`。
回归测试：`test_state_merge_preserves_keys_the_write_does_not_mention`、
`test_state_put_many_updates_in_place_and_appends_new_keys`、
`test_reinstall_clears_a_part_key_the_module_no_longer_declares`。
这条也是 P1-2 的前置：账本从此可以安全地加字段，不会被下一次写入抹掉。

**P0-1 快照清理会删掉账本仍在引用的回滚点，卸载丢用户数据（已修复）**。
`snapshot_prune` 原先只保护刚创建的那一个快照，从不看模块账本里的
`last_snapshot`。实测：装 niri 后连续创建 34 个快照，安装前快照被清理，账本仍
指向它；此时 `uninstall` 找不到快照，退化到"只移除账本记录的文件"，用户原有的
`~/.config/niri/<file>` 直接消失且没有任何提示。

处理方式：保护集合改为"新快照 ∪ 所有模块 `last_snapshot` ∪ 最近一次
pre-rollback 保护快照"，且受保护的不占 30 个名额；保留排序从 ID 字符串改为
`created_at`（ID 的时间戳只到秒、后缀随机，原排序在同一秒内实际是随机的）；
`uninstall` 在恢复点缺失时明确警告原文件无法恢复；`snapshot delete` 删到恢复点时
也给出警告。回归测试：
`test_pruning_never_deletes_the_snapshot_uninstall_needs`（端到端复现原故障）、
`test_prune_orders_by_creation_time_not_by_snapshot_id`、
`test_prune_keeps_a_snapshot_referenced_by_module_state`、
`test_uninstall_says_so_when_the_recovery_point_is_gone`。

**P1-6 程序层依赖无人核对（已修复）**。`check` 原先只核对配置引用的**路径**，
不核对配置里 spawn 的**程序**。后果是按 §0 的流程只装 niri + noctalia，进桌面后
`Mod+Return`、`Mod+E`、音量键是坏的，而 `deps` 报告"依赖齐全"。

处理方式：模块新增 `MODULE_REQUIRED_COMMANDS`（`命令:包`）、
`MODULE_OPTIONAL_COMMANDS`、`MODULE_EXTERNAL_COMMANDS`；`check` 增加
`undeclared-command`（spawn 了但没声明）与 `unbound-command`（声明了但没人装）
两类拦截；`deps`/`plan` 增加 `missing-required` / `missing-optional` 运行时核对，
`deps` 装完再核一遍必需项。niri 模块按审计结果声明了 7 个必需程序、5 个可选程序、
4 个基础系统程序，并把 `kitty`/`nautilus`/`wireplumber`/`libnotify`/`python`/
`noctalia` 加进自己的包清单。回归测试：
`test_check_rejects_a_spawned_program_that_is_never_declared`、
`test_check_rejects_a_required_command_without_its_package`、
`test_declaring_program_and_package_satisfies_both_checks`、
`test_plan_reports_a_required_program_that_is_not_installed`、
`test_install_refuses_on_undeclared_spawned_program`。

**程序层运行时核对越出选定模块（已修复）**。`runtime_command_report` 原先固定遍历
全部模块，于是 `deps niri` / `plan niri` 会报出 `fish`、`starship` 的二进制在不在
——用户没问这两个模块，而 niri 自己 spawn 的 `kitty`/`wpctl` 本来就在 niri 的声明
里。这与 §3"`deps <module>` 自足"的说法直接矛盾，也让 `setup` 的核心集清单里混进
无关的 `missing-required` 行。

处理方式：报告改为只遍历调用方选定的模块，`plan`/`deps`/`setup` 各传自己的模块
列表；静态校验（`check` 的悬空引用与未声明程序）仍全仓库扫，那本来就该广。回归
测试：`test_runtime_report_is_scoped_to_the_selected_modules`。

**P1-4 全新安装缺 `effects.kdl`（已修复）**。niri 的 `config.kdl` 是
`include "effects.kdl"`（非 optional），而模块原先只有 `effects_normal.kdl` /
`effects_eyecare.kdl`；`effects.kdl` 靠 `toggle-eyecare.sh` 运行时创建，可那个脚本
自己是 `spawn-at-startup`——要先成功加载配置才会被拉起。现在模块随包提供初始
软链，并把 `effects.kdl` 加进 `MODULE_VALIDATE_PATHS`。回归测试：
`test_fresh_install_ships_effects_symlink_and_keeps_runtime_state`
（同时断言运行时改指向后重部署仍被 preserve 保留）。

**依赖缺口：`python-cairo`（已修复）**。迁移 `tools/` 后才发现
`orbit/renderer.py` 有 `import cairo`，而旧清单与模块都只声明了 `python-gobject`
与 `gtk-layer-shell`。全新系统上会直接 import 失败。已补进
`MODULE_REPO_PACKAGES`。这类"shipped 工具的 import 与依赖声明不一致"目前没有
自动校验，见 §3 已知边界。

### 待办（余项）

#### P1-5 全新系统上的壁纸目录

noctalia 配置把 `wallpaper.directory` / `video_directory` 指向
`$HOME/图片/Wallpapers`（`/home/user` 占位符在部署时替换）。全新 CachyOS 上这个
目录很可能不存在，而本阶段不接管壁纸管理（§11 阶段 D）。需要在阶段 B 的初始化
验收里确认 Noctalia 在目录缺失时的行为，再决定是随模块创建空目录、换默认路径，
还是提前做壁纸迁移。

#### P2 其它

- **迁移取舍：`zed` 与 portal 后端的包不再是"可选"**。旧引擎把 zed 登记在
  `.optional-apps.toml`（包只进 optdepends），portal 后端则完全没人声明。新项目没有
  "可选软件"这一轴，模块要么声明包要么不声明，所以 `deps --yes` / `install --yes`
  会把 zed 编辑器与两个 portal 后端一起装上。走 §0 的 `setup` 引导路径不受影响
  （默认只有 niri + noctalia）。想恢复"配置在、包不在"的状态，就得显式把包从模块
  清单里拿掉，但那样 `check` 的模块自足契约也就断了。

- **待验证**：Noctalia 的内置 kitty 模板是否会写进 `~/.config/kitty/`。如果会，
  被写到的文件必须声明为 preserve，否则每次 `plan` 都会误报 drift。目前没有证据，
  不凭猜测改声明——阶段 B 的初始化验收会暴露它（`plan` 出现 drift 即为信号）。

- `colors.kdl` 被列为 preserve，但没有任何 niri 配置文件 include 它（Noctalia 渲染
  产出，保留本身无害，但值得确认它到底该不该存在）。
- `snapshot_restore` 逐模块恢复，中途失败不回滚已恢复的模块；回滚目前不是事务。
- 迁移过来的 `wallpaper_picker/config.py` 里有个仓库相对回退路径
  （`../../../..//Wallpapers`），在新目录结构下已经指不到东西；属于阶段 D 壁纸
  迁移时一并清理的死代码。

## 11. 后续迁移顺序

每一阶段独立验收，验收通过才进入下一阶段。顺序按 §0 的最终用途（全新 CachyOS
初始化）排：初始化跑不通的能力优先，锦上添花的往后放。

### 阶段 A：基座收口（已完成）

- 缺陷清单里的 P0/P1 已全部关闭（见 §10 已修复）。
- 测试迁入 `noctalia-mod/tests/`，自带临时 HOME 工具，子项目可独立跑通（§13）。
- §13 覆盖清单里原本 `⬜/部分` 的项已补：并发锁、root 拒绝、环境检测输出、
  卸载对 preserve 的保留、模块元数据校验。
- 文档与代码对齐：本文档状态、`README.md`、各模块 `README.md`。

基座完成的判据（`plan`/`deps`/`install`/`snapshot`/`rollback`/`uninstall` 在隔离
HOME 下闭环、`check` 全绿、34 个测试通过、无 P0/P1 未关闭）都已满足。

仍留在清单上的两项不是缺陷，而是明确的选择：

- shipped 工具的 import 与依赖声明一致 —— 目前靠人工审计，见 §3 已知边界。
- 全新系统初始化闭环 —— 属于阶段 B。

### 阶段 B：全新系统初始化闭环（已完成）

这一阶段直接服务 §0 的目标使用流程，优先级高于功能广度。

- `deps` 阶段本身（`已完成`）：清单式预检、AUR 前置确认、`sudo -v`、分批安装。
- 依赖面铺全（`已完成`）：程序层依赖已接上 §3 的程序自洽校验，并收口到选定模块。
- **`setup` 引导入口（已完成）**：依赖与配置合成一份清单、一次确认、依次跑完；
  默认核心集 = niri + noctalia（niri 配置实际 spawn 的程序由 niri 自己的包清单
  带上）。`--with <程序>` 加装模块声明过的可选程序，默认不装。
- **非交互初始化路径（已完成）**：`setup --yes` 从零到配置就位一遍跑完，中途不打断。
- **幂等复跑（已完成）**：重复执行不产生重复配置、不残留暂存目录、账本不重复。
- **收尾总结（已完成）**：跑完打印装了什么、铺到哪、下一步与退路。
- **环境检查语义定稿（已完成）**：目标环境缺失只提示；仓库缺陷（悬空引用、未声明
  程序）阻断部署；运行时缺必需程序只警告，因为那是这台机器的状态（§5）。
- **初始化验收（部分）**：隔离 HOME + 假命令下端到端跑通（见 §13 隔离验收）；
  **真实全新机器上的验收仍未做**，`sudo` 不可用，见 §16.5。

阶段 B 拍板结果（原"待定交互决策"）：

- `install` 不带参数仍是全部五个模块，不改默认值；`setup` 自己定义核心集。
- 可选程序在清单里列出，默认不装，用 `--with <程序>` 加装。
- `nautilus` 保持必需项，因为 `Mod+E` 是随包发布的默认绑定。
- `setup` 跑完落一份收尾总结。
- 假定用户已经装好 niri 与 noctalia 再跑本工具；因此 `reload` 失败仍然导致回滚
  （既有契约不变，`test_nested_custom_entries_and_exact_reload_failure_restore`
  锁的就是它）。在没有运行中会话的 TTY 里跑 `setup` 会把刚铺的配置回滚掉——
  这是已知约束，不是待修缺陷。

### 阶段 C：内容侧补齐（已完成）

- **迁移剩余配置（已完成）**：fastfetch、xdg-desktop-portal、zed 三个模块接入，
  连同前面五个共八个。迁移时按既有约定改写：项目名 `Nyxuri` → `Noctalia Mod`、
  运行时标识 `nyxuri` → `noctalia-mod`、去行尾空格；旧引擎的 `.module.toml`
  不随模块走（那是给旧引擎读的，不是配置）。
  - portal 模块按配置点名的后端补齐四个包（见 §8），这是与旧引擎的有意差异。
  - zed 从"可选软件"变成普通模块，代价记在 §10 P2。
- **用户预设（已完成）**：`preset save` / `edit` / `delete`，加 `list` 显示
  来源与当前活跃项。存储位置、解析顺序、保留字、覆盖确认、活跃预设消失后的
  冻结/回退语义都在 §4。比旧引擎多做的两处：覆盖同名用户预设前确认一次；
  预检里直接打印 `preset-missing` 行。
- **kitty/niri 的预设与零件对等（已完成，实为早已满足）**：对照旧引擎的
  `configs/kitty/__presets__/transparent/` 与 `configs/niri/__presets__/`（后者只有
  `effects`/`glow` 两个零件源目录，没有官方预设），新项目的 `presets/` 与 `parts/`
  已逐一对上，无需补内容。
- **`profiles/` 去留（已完成）**：结论是**不需要**，空目录已删。理由：用户预设按模块
  存放就已经能表达"某个模块的哪个变体"，再叠一层跨模块组合是空概念；真需要"一次切
  多个模块"时，`setup <模块...>` 加各自 `preset apply` 已经够用。

### 阶段 D：运行时能力（下一步）

- 模板渲染与主题同步（旧引擎的 `theme` 与 `_phase_render_templates`）。
- 壁纸部署与 managed 账本，并收掉 §10 P1-5 与 P2 里的壁纸相关死代码。
- 决定 `shell-action.sh` / `session-shell.sh` 的最终形态：新项目已去掉自研 shell
  路由，只留 Noctalia；本阶段确认这是最终决定，而不是临时缺口。
- 重新评估 `hooks.sh` 是否需要（若模板渲染确实需要，就在这一阶段实现）。

### 阶段 E：运维与自更新

- `update`：拉取新版本 + 重新部署（新旧引擎共存期先不做自动状态迁移）。
- `doctor` 体检与 `bug` 诊断导出。
- `clean` 缓存清理（`-n` 预览）。
- 沙箱部署测试入口（等价 `install.sh test`）。
- 快照/回滚做成事务（P2 最后一条）。

### 阶段 F：系统级可选模块

- fcitx5（含"部署素材"与"设为默认"解耦）
- greeter、fisher、gtktheme
- 统一 `install|status|uninstall` 三件套契约。

### 阶段 G：发布与替换

- 打包：PKGBUILD 与依赖聚合。
- 切换入口：让 `install.sh` 指向子项目。
- 旧引擎退役：转为只读回退路径，随后删除，并作废 `llms-wiki/`。

### 明确不迁移

- `nyxniri` 兼容别名与 `NYXNIRI_*` 环境变量（新项目无历史包袱）。
- Nyxuri 的 `NYXURI_*` 运行时环境变量与 `LEGACY_*` 回退分支（迁移 tools 时已删）。
- 用户状态账本与迁移墓碑清单。
- 自研桌面外壳路由（旧引擎的 `shell get|set`）。新项目只支持 Noctalia。

## 12. 文档与变更记录约定

- **文档权威在子项目内**：`PLAN.md`（方案与进度）、`README.md`（用法）、
  各模块 `README.md`（协议与例外）。代码改动必须同步这里。
- **不更新 `llms-wiki/`**：那是旧引擎的文档。迁移期内它描述的能力会逐渐转移到
  子项目，出现不一致时以子项目文档和当前代码为准。旧引擎退役时整体作废。
- **变更记录后置**：子项目在没有被真实用户使用之前，不写用户可见的 changelog。
  迁移期不往仓库根 `CHANGELOG.md` 添加子项目条目——那条记录对用户不可感知
  （入口未接入，也不在 PATH 上）。子项目被实际使用（阶段 G 切换入口）后，
  在子项目内建自己的 changelog。

## 13. 测试与验收

测试用 Python 标准库（`unittest`），不引入 Bats 等新依赖，全部在临时 HOME 与假
外部命令环境中运行，禁止触碰真实 `~/.config`。测试属于子项目：

```bash
python3 -m unittest discover -s noctalia-mod/tests -q
python3 noctalia-mod/tests/test_noctalia_mod.py -q   # 直接执行同样可以
```

`noctalia-mod/tests/utils.py` 只提供临时 HOME，不 import 旧引擎——子项目要能单独
取走。作为分离的代价，仓库根的 `discover -s tests` 不再覆盖子项目。

覆盖清单（`✅` 已有，`⬜` 待补）：

| 覆盖点 | 状态 |
|---|---|
| 模块发现与元数据校验（id 不匹配、越界目标、非法包/命令/零件） | ✅ |
| 依赖检查与包管理器 argv 形状（repo + AUR） | ✅ |
| `deps` 独立阶段：清单、拒绝、幂等、不碰 `~/.config` | ✅ |
| AUR helper 前置确认（无 helper 不装 repo 包） | ✅ |
| 程序层核对：未声明 / 未绑定被拒，绑定后通过 | ✅ |
| 程序层核对：运行时 missing-required / missing-optional 报告 | ✅ |
| 程序层核对：报告只覆盖选定的模块 | ✅ |
| `setup` 引导：默认核心集、一份合并清单、装包先于部署 | ✅ |
| `setup` 引导：非交互无 `--yes` 拒绝且不写入 | ✅ |
| `setup` 引导：幂等复跑（树不变、无暂存残留、账本不重复） | ✅ |
| `setup --with`：可选程序默认不装、点名后进 argv、未声明被拒 | ✅ |
| pre-flight 清单生成 | 部分 |
| 用户拒绝确认时不发生写入 | ✅ |
| 文件与目录原子替换 | ✅ |
| `__custom__` 文件、目录、嵌套路径保留 | ✅ |
| preserve 路径保留（含软链接按链接保留） | 部分 |
| preset 切换（官方） | ✅ |
| 用户预设：save 不带 `__custom__`、软链按链接存 | ✅ |
| 用户预设：保留字 / 官方同名 / 非法名被拒 | ✅ |
| 用户预设：覆盖同名前必须确认 | ✅ |
| 用户预设：delete / edit 只动用户预设、清理空目录 | ✅ |
| 用户预设：单文件目标（starship）存取往返 | ✅ |
| 预设消失：目标还在→冻结且不动账本；目标没了→回退 default | ✅ |
| 预设清单区分来源与当前活跃项 | ✅ |
| 迁移内容无旧引擎残留（`.module.toml`、项目名） | ✅ |
| portal 模块按配置点名安装后端 | ✅ |
| 零件选择与恢复 | ✅ |
| 快照创建与回滚 | ✅ |
| 快照清理：按创建时间保留 | ✅ |
| 快照清理：受保护恢复点不被删 | ✅ |
| 恢复点丢失时卸载给出警告 | ✅ |
| 部署中途失败的自动恢复 | ✅ |
| 并发锁（持锁时拒绝且不写入） | ✅ |
| 状态原子写入与合并写入（未提及的键保留、陈旧 part 键清理） | ✅ |
| 卸载不删 custom / preserve 内容（含无快照回退路径） | ✅ |
| root 拒绝（uid 守卫） | ✅ |
| `--yes` / express 模式行为 | 部分 |
| reload 命令 argv 形状 | ✅ |
| 环境检测输出（marker 两分支、程序缺失提示） | ✅ |
| 引用自洽校验（悬空引用被拒） | ✅ |
| 安装后 niri 能加载配置（`effects.kdl` 存在且可解析） | ✅ |
| 运行时软链状态跨重部署保留 | ✅ |
| shipped 工具的 import 与依赖声明一致 | 人工审计（无自动校验，见 §3 边界） |
| 全新系统初始化闭环（§11 阶段 B） | 隔离 HOME 闭环 ✅；真实机器 ⬜ |
| 所有权指纹与 drift 检出（managed 改动、目标消失） | ✅ |
| drift 不误报 `__custom__` / preserve / 运行时软链改动 | ✅ |
| 依赖包记账（只记我们装的、不重复） | ✅ |

每步实现后至少运行（全部零网络秒级）：

```bash
# 语法：必须逐个文件跑。`bash -n a b c` 只检查 a，b/c 会被当成位置参数静默忽略。
find noctalia-mod -type f \( -name '*.sh' -o -name 'noctalia-mod' \) -print0 |
    xargs -0 -n1 bash -n

# 随包发布的 Python 工具也要过语法，否则要到用户点开 Orbit / 壁纸选择器才发现。
# pyc 必须重定向出仓库：__pycache__ 落在 files/ 里会被一起拷进 ~/.config。
PYTHONPYCACHEPREFIX=${TMPDIR:-/tmp}/noctalia-mod-pycache \
    python3 -m compileall -q noctalia-mod/modules/noctalia/files/tools

# 静态分析：-x 必须带，否则 source 进来的 lib 根本不参与分析。
# 用 find 收集，不要手写 glob —— 漏掉 modules/noctalia/files/wallpaper-hook.sh
# 这种不在 scripts/ 下的脚本是很容易发生的事。
mapfile -t shells < <(find noctalia-mod -type f -name '*.sh' | sort)
shellcheck -x noctalia-mod/bin/noctalia-mod "${shells[@]}"

python3 -m unittest discover -s noctalia-mod/tests -q
noctalia-mod/bin/noctalia-mod check
```

三个坑，都是踩过的：

1. **`bash -n` 只看第一个文件。** 多文件写法下其余参数变成位置参数，语法错误不会
   被发现，命令还会返回 0。必须逐个跑。
2. **`shellcheck` 不带 `-x` 等于半盲。** 这个 CLI 的核心逻辑全在被 source 的
   `lib/*.sh` 里，不带 `-x` 就只检查入口那一个文件，lib 里的问题一个都看不到。
   入口里的 `source` 需要 `# shellcheck source-path=SCRIPTDIR` 才能被正确解析。
3. **注释不要以 `shellcheck` 开头。** 任何 `# shellcheck ...` 开头的行都会被当成
   指令解析，写中文说明时踩过一次，直接报 SC1072 语法错误。

`shellcheck` 已装在 `~/.local/bin/shellcheck`（官方静态二进制 v0.11.0，容器里 sudo
无法提权，所以没走 pacman）。子项目、`install.sh` 与旧项目的 shell 脚本当前都是
零告警。

> 仓库根 `AGENTS.md` §3 里的 `bash -n install.sh configs/noctalia/*.sh ...` 是同一个
> 坑：那条命令实际只检查了 `install.sh`。已在会话里报告，未擅自改动该文件。

隔离验收（假命令置于 PATH 前，`HOME` 与 XDG 指向临时树）：

```bash
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod list
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod check
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod setup --yes
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod deps niri noctalia --yes
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod plan niri noctalia
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod install niri noctalia --yes
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod snapshot
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod rollback
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod uninstall niri noctalia --yes
```

注意这些命令需要 PATH 上能有 `pacman`、`sudo` 之类；本机实测时用假命令目录放在
PATH 前面（见 §16.5 的做法），否则 `setup --yes` 会真的去装包。

## 14. 会话执行约束

1. 先读 **§16 接手须知**（环境事实、工作区状态、陷阱、待裁决），再读对应模块
   README，然后动手。
2. 修改前检查 `git status`（当前工作区是脏的，见 §16.3）。
3. 对路径、状态、部署、保留规则有疑问时，全仓库检索引用后再下结论。
4. 每步保持新旧引擎可并行运行，不修改旧 `install.sh`（阶段 G 之前）。
5. 每个模块独立测试，不依赖其他模块的隐式副作用。
6. 不使用软链接写入 `~/.config`（运行时内部软链除外）。
7. 不在安装循环里加无必要的阻断式确认。
8. 破坏性操作前统一生成清单并确认。
9. 代码改动必须同步本文档与对应模块文档，不允许代码先行、文档滞后。
10. 不主动提交 Git commit。
11. 不新增调试输出、注释掉的代码、未完成的 TODO。
12. 不新增模块，除非 §11 的对应阶段已启动。
13. 每次改动后跑 §16.2 的门禁三连，别只跑其中一条——语法/静态分析/行为测试
    各挡一类问题，只跑一条会漏。

## 15. 默认假设

- 子项目目录 `noctalia-mod/`，入口 `noctalia-mod/bin/noctalia-mod`。
- 第一阶段锁定 CachyOS + niri + Noctalia V5，保留扩展接口。
- 不兼容旧引擎状态，只识别目标文件并提示冲突与漂移。
- 保留"默认配置 / 官方预设 / `__custom__`"三层模型。
- 依赖由中央流程统一检查，确认后安装。
- `setup` 是引导入口，默认只装核心集（niri + noctalia）；无参数不等于全量。
- 假定用户已经装好 niri 与 noctalia 再跑本工具。
- 卸载默认不删除系统软件包。
- Bash 负责运行时，Python 标准库负责测试。
- 本文档是方案与交接文档，不是运行时配置，不得部署到 `~/.config`。

## 16. 接手须知（新会话先读）

### 16.1 环境事实（实测）

| 项 | 值 |
|---|---|
| 本机 | CachyOS Linux，`x86_64`，**就是目标环境** |
| 工作目录 | `/home/victorxu/Projects/workspace/noctalia-helper` |
| 用户 | uid 1000（`victorxu`），非 root |
| `sudo` | **不可用**：容器设了 no-new-privileges，`sudo -v` 直接失败 |
| `pacman` / `paru` | 都在，但因为上一条，装包路径无法实测 |
| 网络 | 通（GitHub 与 Arch 镜像均可达） |
| `shellcheck` | `~/.local/bin/shellcheck`，v0.11.0 官方静态二进制；`~/.local/bin` 在默认 PATH 上 |
| 沙箱 | 工作区之外只读；写 `~/.local/bin` 之类需要一次提权 |

`shellcheck` 是后补装的（pacman 不可用，走官方 tar.xz 静态二进制），子项目、
`install.sh` 与旧项目的 shell 脚本当前都是零告警。

### 16.2 门禁三连（每条都实测过，照抄即可）

```bash
cd /home/victorxu/Projects/workspace/noctalia-helper

# 1. 语法：shell 必须逐个文件跑（见 §16.4 陷阱一），随包 Python 工具一起过
find noctalia-mod -type f \( -name '*.sh' -o -name 'noctalia-mod' \) -print0 |
    xargs -0 -n1 bash -n
PYTHONPYCACHEPREFIX=${TMPDIR:-/tmp}/noctalia-mod-pycache \
    python3 -m compileall -q noctalia-mod/modules/noctalia/files/tools

# 2. 静态分析：-x 必须带（见 §16.4 陷阱二）
mapfile -t shells < <(find noctalia-mod -type f -name '*.sh' | sort)
shellcheck -x noctalia-mod/bin/noctalia-mod "${shells[@]}"

# 3. 行为测试 + 仓库引用自洽
python3 -m unittest discover -s noctalia-mod/tests -q
noctalia-mod/bin/noctalia-mod check
```

当前基线：语法 17 个入口全过、shellcheck 零告警、53 个测试 OK、`check` 全绿。
仓库根 `discover -s tests` 也能过，但**不再覆盖子项目**（测试已迁入，见 §13）。

### 16.3 当前工作区状态

- 所有改动**均未提交**。用户明确要求不主动 commit。
- `git status` 会显示 `RM tests/test_noctalia_mod.py -> noctalia-mod/tests/test_noctalia_mod.py`
  —— 重命名由 `git mv` 完成，因此**已暂存**，其余改动未暂存。这不是异常。
- 未跟踪的新文件：`lib/reference-check.sh`、`tests/utils.py`、
  `modules/niri/files/effects.kdl`（软链）、`modules/noctalia/files/{mpv-hook.lua,
  wallpaper-hook.sh,tools/}`。
- 仓库根 `CHANGELOG.md` 的 `noctalia-mod` 条目已被移除，理由见 §12。

### 16.4 已知陷阱（都踩过）

1. **`bash -n a b c` 只检查 `a`**，其余参数变成位置参数、静默忽略且返回 0。
   实测：语法错误的第二个文件用旧写法 exit 0，逐个跑 exit 123。必须逐个跑。
2. **`shellcheck` 不带 `-x` 等于半盲**：核心逻辑都在被 source 的 `lib/*.sh` 里。
   入口需要 `# shellcheck source-path=SCRIPTDIR` 才能解析这些 `source`。
3. **注释不要以字面 `shellcheck` 开头**：任何 `# shellcheck ...` 行都会被当成指令，
   写中文说明时会直接报 SC1072。措辞要避开这个前缀。
4. **假命令必须同时正确响应查询与安装**：给 `pacman` 写测试替身时只处理 `-Q`
   会让 `-S` 也失败，结果测的是替身而不是被测代码。
5. **`state_root()` 会自加 `noctalia-mod`**：lib 级测试里设置 `XDG_STATE_HOME`
   时要给它的父目录，否则 prune 之类会跑在空目录上、测试变成假通过。
6. **仓库根 `AGENTS.md` §3 的 `bash -n install.sh configs/.../*.sh` 是同一个坑**
   （只检查了 `install.sh`）。**没有擅自改动该文件**，等用户裁决。

### 16.5 哪些是实测，哪些还只是推理

写结论前先看这张表，别把推理当既成事实。

**实测过**：门禁三连、53 个测试、`check` 全绿、`deps → install → plan → uninstall`
在假命令 + 临时 HOME 下闭环、`setup --yes` 从零到配置就位并幂等复跑（树不变、无
暂存残留、账本不重复）、`setup --with` 的 argv 形状与未声明名字被拒、`plan niri` /
`deps niri` 不再报别的模块的程序、drift 的四种情形（受管改动报、`__custom__`/preserve/
运行时软链不报、重部署清零、目标消失报 missing）、P0-1 的端到端复现、AUR helper
前置确认的顺序契约、并发锁拒绝、以 `command -v` 为准的运行时程序核对（本机实测：必需程序全部就位，可选只缺 `ddcutil`）。

**未实测（只有推理或设计）**：

- 真实机器上的 `deps`/`install`/`setup` 从未跑过——`sudo` 不可用，安装路径只能用
  假命令验证。所以"全新机器上能进桌面、快捷键可用、Noctalia 正常渲染"这句结论
  **还没有依据**，§11 阶段 B 的初始化验收只完成到隔离 HOME 这一层。
- 在 niri 会话之外（TTY）跑 `setup` 会怎样：按现有契约，`niri msg action
  reload-config` 失败会导致部署回滚。这是从代码推出的结论，未在 TTY 上实测。
- niri 是否真的会因为缺 `effects.kdl` 而拒绝加载配置：未验证。修复是防御性的
  （随包提供软链），无害但理由未经实机确认。
- Noctalia 是否把它渲染的 kitty 主题写进 `~/.config/kitty/`：未知。如果会，被写到的
  文件必须声明 preserve，否则 `plan` 会误报 drift。见 §10 P2。
- §3 的程序层声明（`MODULE_REQUIRED_COMMANDS` 等）是逐脚本人工审计的结果，
  不是自动推导出来的。
- shipped 工具的 `import` 与 `MODULE_REPO_PACKAGES` 是否一致，没有自动校验
  （见 §3 边界）；`python-cairo` 那次是人工发现的。

### 16.6 下一步与待裁决

阶段 A（基座收口）、阶段 B（全新系统初始化闭环的代码部分）与阶段 C（内容侧补齐）
**已完成**，见 §11。下一步是**阶段 D：运行时能力**——模板渲染与主题同步、壁纸部署
与 managed 账本，并收掉 §10 P1-5 与 P2 里的壁纸死代码。

阶段 B 已拍板的四项（`install` 默认值、可选程序交互形态、`nautilus` 定位、收尾
总结）记在 §11，别再翻案。仍然开着的：

1. 仓库根 `AGENTS.md` §3 的 `bash -n` 多文件写法要不要一并修掉？（见 §16.4 陷阱一）
2. 真实机器上的初始化验收什么时候做、在什么环境下做？（容器里 `sudo` 不可用，
   见 §16.1）这一项不解决，"全新系统能进桌面"就一直是推理。
3. §10 P1-5（壁纸目录缺失时 Noctalia 的行为）要在阶段 D 之前有个结论。
