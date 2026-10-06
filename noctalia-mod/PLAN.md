# Noctalia Mod：从 Nyxuri 重构出的独立子项目

> 事实入口与会话交接文档。只记录代码里真实存在的状态，不写"计划中已完成"。
> 状态标记：`已完成` / `进行中` / `待办`。缺陷用 `P0`/`P1`/`P2` 标优先级。
>
> **权威边界**：`noctalia-mod/` 内部文档是本子项目的唯一事实源。本仓库
> `llms-wiki/` 描述的是旧引擎 Nyxuri，本子项目不维护它、也不接管它
> （阶段 G 已取消，见 §11、§12）。
>
> **新会话先读 [§16 接手须知](#16-接手须知新会话先读)**
> —— 环境事实、工作区与 Git 状态、下一步、待裁决清单、已知陷阱、
> 以及哪些结论只是推理而非实测，都在那一节。阶段 A–E 已收口，
> 下一步是阶段 F（系统级可选模块）。

## 0. 终极目标与定位

终极目标：把配置管理能力从现有 Nyxuri 引擎中重构出来，形成独立项目
`noctalia-mod/`，它有自己的入口、模块、测试和文档，能整目录取走独立使用。
不接管旧入口，也不要求旧引擎退役（阶段 G 取消，见 §11）。

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
noctalia-mod install --yes             # 全部配置模块，非交互
noctalia-mod install fcitx5            # 系统级模块：写 ~/.local/share、配输入法
noctalia-mod install greeter           # 系统级模块 + 需要 root：接管登录界面
noctalia-mod action fcitx5 activate    # 只把皮肤设为当前主题
```

**系统级模块永远要点名**（§3）：不带参数的 `plan`/`deps`/`install` 只覆盖配置模块，
`setup` 无参数仍是核心集。

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
  现在整目录就能独立检出使用（可提取为独立仓库）。
- **不背旧包袱**：不迁移 Nyxuri 的兼容别名（`nyxniri`）、历史墓碑清单和
  用户状态账本。新项目只认自己的状态。
- **不接管旧入口**：两边各自是一条完整的路径，谁都不需要对方退役
  （阶段 G 取消，见 §11）。

目标环境：CachyOS + niri + Noctalia V5。运行时是 Bash，只用系统已有基础工具。
模块协议不把 niri 写死为唯一窗口管理器，但第一阶段只验证上面这组环境。

### 为什么是 Bash

不是因为"Python 有依赖"——恰恰相反，[install.sh](../install.sh) 已经把
`python3` 作为硬性前置，旧引擎是零 pip 依赖的纯标准库实现。选 Bash 的理由只有
一条：子项目要能被单独取走使用，且不引入新的运行时前提。

代价必须被承认：原子替换、状态账本、快照这三块最关键的代码会有两套独立实现。
因此它们必须有等价的行为契约和测试，不能靠"看起来一样"。基座收口（§11 阶段 A）
就是为这件事服务的。

## 1. 与旧引擎的边界：所有权与漂移检测

只要 Nyxuri 还在这台机器上服役，两个管理器就会写同一批 `~/.config` 路径。
**这是当前最大的风险**，必须显式处理，不能只靠目录级的"外部文件"提示。

问题：`noctalia-mod` 与 Nyxuri 各自持有 preset/part 状态。例如先跑
`nyxuri preset kitty transparent`，再跑 `noctalia-mod install kitty`，
`kitty.conf` 会被静默改回默认——两边都不知道对方动过什么。

设计决定（`已完成`）：

1. **所有权指纹**：每个模块部署成功后把管理内容的摘要写进自身 state 的
   `fingerprint`；`plan` 时重新计算并对比。
2. **漂移必现**：不一致时 pre-flight 打印 `drift\t<模块>\t<changed|missing>`，
   当作外部改动处理，绝不静默覆盖。
3. **只认自己的账本**：不读取、不迁移 Nyxuri 的 `state.json`、预设目录和快照索引。
4. **边界不靠退役来收口**：本条的风险在两边都活着的时候就存在，处理办法就是上面
   三条——指纹、漂移必现、不读旧状态。旧引擎退不退役是仓库根的决定，不是本子项目
   的前置条件（阶段 G 取消，见 §11）。

指纹刻意选轻：整个模块一个摘要，不做逐文件版本库。覆盖范围只包括"本项目会覆盖
的文件"，即排除 `__custom__`、`MODULE_PRESERVE` 与 `MODULE_RUNTIME_WRITES`：

- 用户改 `__custom__` 是设计内行为，不该报漂移；
- 运行时被改写、且**我们不再拥有**的文件（如 Noctalia 渲染的 `niri/colors.kdl`、
  被 `toggle-eyecare.sh` 改指向的 `niri/effects.kdl`）声明为 `MODULE_PRESERVE`：
  部署时不覆盖，指纹也不看；
- 运行时被改写、但**我们仍然拥有**的文件（Noctalia 会就地重写 `kitty.conf`、
  `kitty/themes/noctalia.conf`、`starship.toml`）声明为 `MODULE_RUNTIME_WRITES`：
  照旧被部署覆盖，只是不进指纹。**这两件事必须分开**——用 preserve 顶替会让模块
  再也更新不了自己的文件（§10 P1-9）；
- 反过来说，**如果某个运行时写入者两条声明都没有，报漂移就是对的**——它说明模块
  元数据漏了一个写入者，这比默默覆盖有价值。

单文件型目标没有子路径可写，所以用**目标文件名本身**放进 `MODULE_RUNTIME_WRITES`
表示"这个文件会被运行时改写"（starship 就是这种）。

已知取舍：摘要只能告诉你"这个模块变了"，说不出是哪个文件变的；要说清楚得把文件
清单也存进账本。权限位不进指纹（`apply_chmod_rules` 每次部署都会重新施加）。
被声明成运行时写入的文件放弃了漂移检测——这是有意的：对它们报漂移只会训练用户忽略
漂移报告。

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
│   ├── system.sh          # 系统级模块的动作契约与 root/systemd 原语
│   ├── network.sh         # 受校验的下载（多镜像 + sha256）
│   ├── preset.sh          # 用户预设的存取与预设消失语义
│   ├── theme.sh           # GTK 深浅同步（Noctalia 不做的那一半）
│   ├── wallpaper.sh       # 壁纸部署与 managed 账本
│   ├── reference-check.sh # 引用与程序声明的静态自洽校验
│   ├── module-loader.sh   # 模块元数据加载与校验
│   ├── doctor.sh          # 体检与 bug 诊断导出
│   ├── clean.sh           # 暂存残渣清理与快照清理预览
│   ├── sandbox.sh         # 沙箱部署测试（test）
│   └── update.sh          # git 拉取与换进程重新部署
├── modules/
│   └── <module>/          # 见 §3
├── assets/
│   ├── wallpapers/        # 离线壁纸（随子项目走，便于整目录独立取走）
│   └── fcitx5/            # NyxMellow 输入法皮肤素材
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

系统级模块（`MODULE_KIND='system'`，见 §3）把 `files/`/`presets/`/`parts/` 换成动作脚本：

```text
modules/<module>/
├── module.conf            # 同样的元数据，另加 MODULE_KIND 与动作声明
├── actions/
│   ├── install.sh         # 装
│   ├── status.sh          # 查（只读，健康退 0）
│   ├── uninstall.sh       # 卸
│   └── <extra>.sh         # MODULE_SYSTEM_EXTRA_ACTIONS 声明的额外动作
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
| `MODULE_KIND` | `config`（默认，一棵目标树）或 `system`（自带动作脚本），见下 |
| `MODULE_TARGET` | 相对 `$XDG_CONFIG_HOME` 的目标路径（文件或目录）；`system` 模块必须留空 |
| `MODULE_FILES` | 默认配置源目录，默认 `files` |
| `MODULE_REPO_PACKAGES` | 官方仓库依赖 |
| `MODULE_AUR_PACKAGES` | AUR 依赖 |
| `MODULE_PRESERVE` | 按名保留的路径（部署时不覆盖，原样继承实机版本） |
| `MODULE_RUNTIME_WRITES` | 运行时也会改写、但模块仍然拥有并覆盖的路径（只影响指纹，不影响覆盖），见 §1 |
| `MODULE_CHMOD` | 需要加执行位的相对 glob |
| `MODULE_RELOAD_COMMAND` | 部署后的 reload/reload 动作（argv 数组） |
| `MODULE_VALIDATE_PATHS` | 部署后必须存在的路径；`system` 模块里写绝对路径 |
| `MODULE_EXTERNAL_REFS` | 被引用但不由本项目提供的配置路径（运行时产出或外部提供），见下 |
| `MODULE_REQUIRED_COMMANDS` | 必需程序，写作 `命令:提供它的包`，见下 |
| `MODULE_OPTIONAL_COMMANDS` | 可选程序，写作 `命令` 或 `命令:包`；缺失只提示，`setup --with` 只认这里声明过的名字 |
| `MODULE_EXTERNAL_COMMANDS` | 基础系统自带的程序，声明出来给 spawn 检查一个落点 |
| `MODULE_PARTS` / `MODULE_PART_<SLOT>_TARGET` / `MODULE_PART_<SLOT>_DEFAULT` | 零件插槽声明 |

`system` 模块专属：

| 变量 | 含义 |
|---|---|
| `MODULE_SYSTEM_EXTRA_ACTIONS` | 三件套之外的额外动作名（如 fcitx5 的 `deploy`/`activate`/`rime`） |
| `MODULE_SYSTEM_PATHS` | 动作会碰的绝对路径，预检清单里逐条列出来 |
| `MODULE_SYSTEM_SERVICES` | 会 enable 的 systemd 单元，预检里列出来 |
| `MODULE_SYSTEM_PRIVILEGED` | `yes` 表示动作需要 root，引擎在动手前统一取一次权限 |

默认行为由目录约定驱动，`module.conf` 只声明例外。

模块必须遵守：

- 参数与返回码明确；失败向上传播，不吞错。
- 不直接改其他模块的状态；不绕过中央锁、快照和失败恢复。
- 不假设某个模块已安装，除非 §7 的依赖声明写明。
- 外部命令用参数列表调用，不拼接未校验的输入。
- **引用自洽（`已完成`，见 §10 已修复 P0-2）**：被部署配置引用到的
  `~/.config` 路径，必须在部署后真实存在——要么由某个已接入模块提供，要么在
  `MODULE_EXTERNAL_REFS` 里显式登记。没有第三条路。

### 系统级模块（`MODULE_KIND='system'`）

配置模块的模型是"一棵树换一棵树"：目标在配置根内、先暂存再原子替换、失败整棵回滚。
有一类事情没有这个形状——写 `/etc`、enable systemd 单元、用 fish 装插件、把素材放进
`~/.local/share`。硬塞进"目标目录"只会得到一个假装原子的东西，所以它们换一套契约：
**模块自带动作脚本，引擎负责预检、调用、记账。**

```text
modules/<id>/actions/install.sh    装：把这件事做完
modules/<id>/actions/status.sh     查：只读探测，健康退 0、不健康非 0
modules/<id>/actions/uninstall.sh  卸：还原
modules/<id>/actions/<extra>.sh    MODULE_SYSTEM_EXTRA_ACTIONS 声明的额外动作
```

- **动作是独立进程**：引擎用 `bash <脚本>` 调它，通过环境传 `NOCTALIA_MOD_ROOT`、
  `NOCTALIA_MOD_ID`、`NOCTALIA_MOD_ACTION`；脚本自己 source `lib/*.sh`，用的是同一套
  原语。引擎不替它做原子替换，也**不替它回滚**——系统级动作没有"换回去"这一说，
  备份与还原是动作自己的责任（旧引擎也是这么分的）。
- **包由引擎装**：`MODULE_REPO_PACKAGES` / `MODULE_AUR_PACKAGES` 照旧声明，`deps` /
  `install` / `setup` 走同一条安装通道；动作只做系统配置，缺了包就报错退出。这样
  "装包一次授权"仍然成立。
- **权限一次取**：`MODULE_SYSTEM_PRIVILEGED='yes'` 的模块，引擎在动手前统一 `sudo -v`，
  预检里打一行 `privilege <模块> sudo`。动作中途再弹提示是不允许的。
- **预检是声明出来的，不是从脚本里猜的**：`MODULE_SYSTEM_PATHS` 与
  `MODULE_SYSTEM_SERVICES` 决定用户看到的那一次确认值。已知取舍：这两项是文档性的
  （引擎不核对脚本实际写了什么），`MODULE_VALIDATE_PATHS`（绝对路径）才是硬校验。
- **永远不被隐式选中**：不带参数的 `plan` / `deps` / `install` 只覆盖配置模块。
  系统级模块必须点名——写 `/etc`、切换显示管理器的事不该由"我什么都没写"触发。
- **账本只记四件事**：`kind=system`、`enabled`、`source_version`、`last_result`。
  没有目标树，所以没有 `target` / `preset` / `fingerprint` / `part.*`；快照里也不会
  出现系统模块（`snapshot_create` 直接跳过它）。
- **额外动作要点名**：`noctalia-mod action <模块> <动作>`，动作必须在
  `MODULE_SYSTEM_EXTRA_ACTIONS` 里声明过、模块必须已装（`status` 除外）。
  这条和 `--with` 只认声明过的可选程序是同一条规矩：命令行不能凭空指定动作。
- **不带配置根内的目标树**，因此 `MODULE_PRESERVE` / `MODULE_RUNTIME_WRITES` /
  `MODULE_CHMOD` / `MODULE_EXTERNAL_REFS` / `MODULE_PARTS` 在系统级模块里一律非法——
  留着只会让人以为它们生效了。

**它替代了旧引擎的 `post_install = "模块:函数"`**。旧引擎在 `.optional-apps.toml` 里写
`post_install = "fcitx:setup_rime_ice"`，装完 `fcitx5-rime` 再反射调用一个函数；新项目
没有这条缝，也不需要：**声明那个包的模块自己就是那个钩子**——`MODULE_AUR_PACKAGES` 里的
`rime-ice-git` 属于 fcitx5 模块，`install fcitx5` 自然就把方案配好了。

**跨模块写别人配置文件是不允许的**。旧引擎的 `fcitx_register_templates()` 会往 noctalia
的配置里追加模板节；新项目把那份注册放回 noctalia 模块自己的配置，并给它加
`requires_path`——Noctalia 在路径不存在时跳过这条模板，于是它天生是惰性的：
没装皮肤不报错，卸了皮肤也不会留下指向空路径的注册。

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
  import 之间没有静态校验。第一个实例是 noctalia 的 `import cairo`，需要
  `python-cairo`——迁移 tools 时才暴露出来（见 §10 已修复）。阶段 E 起 `doctor`
  会真去 import 一次（`gi` / `cairo` / `GtkLayerShell`），缺了就会在体检里报出来；
  但那是运行时探测，不是静态推导，覆盖不到将来新引入的 import。

**没有 `hooks.sh`**（阶段 D 复评后关闭）：模块侧的收尾动作由
`MODULE_RELOAD_COMMAND` 承担，运行时写入的文件由 `MODULE_PRESERVE` 声明，引擎级的全局
步骤（路径改写、GTK 深浅同步）属于引擎自己。旧引擎里唯一像"模块钩子"的东西是
`.module.toml` 的 `post_install = "模块:函数"`（fcitx5-rime 在用）——阶段 F 的答案是
"不需要这条缝"：系统级模块的三件套加上"谁声明包谁负责配好"已经覆盖了它，见上面
「系统级模块」。

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

**部署期占位符**（只在暂存树上替换，所以单文件型目标不参与）：

| 占位符 | 替换成 | 例子 |
|---|---|---|
| `/home/user` | 真实 `$HOME` | `input_path = "/home/user/.config/..."` |
| `@XDG_PICTURES@` | XDG 图片目录（`xdg-user-dir PICTURES`，答不出来才回退 `$HOME/Pictures`） | `directory = "@XDG_PICTURES@/Wallpapers"` |

`@XDG_PICTURES@` 是阶段 D 加的（§10 P1-7）：旧引擎在部署后原地改写 noctalia 的
`directory` / `video_directory` 与 niri 的 `screenshot-path`，新项目原来只做 `/home/user`
替换，于是把仓库源里写死的中文 locale 路径 `$HOME/图片/Wallpapers` 原样铺下去。
占位符比"部署后按文件名正则改写"干净：引擎不需要知道哪个模块的哪个键要改。

**注释里不要写占位符字面量**——替换会连注释一起改，留下一句读不通的话。

**壁纸不在 `~/.config` 里**，所以它不归任何模块（模块目标必须是配置根内的相对路径），
是引擎自己的步骤：

- 目标目录：`<XDG 图片目录>/Wallpapers`
- 账本：`<壁纸目录>/.noctalia-mod-managed`，一行一个顶层名字（本项目放进去的东西）
- 同步：no-clobber（同名文件已存在就跳过，用户的版本优先），但仍记进账本
- 清理：`wallpapers remove` 只删账本里的条目；账本里出现越界路径（`..`、带分隔符）
  就拒绝执行并**留在账本里**，不静默遗忘
- 只有 `setup`（从零到桌面）会顺手部署壁纸；`install` 的契约是"只动 `~/.config`"
- 远程壁纸包下载不迁

**GTK 深浅同步**（`theme sync`，§10 P1-8）也是引擎步骤：Noctalia 跟着模式设
`color-scheme`，但既不设 `gtk-theme` 也不写 `gtk-{3,4}.0/settings.ini`，而 Brave
一类应用的冷启动就读后者。`install` / `setup` 的收尾各跑一次，失败只警告——配置已经
铺好了，不该因为 `gsettings` 或会话不可用就把一次成功的部署弄成失败。模式切换时的实时
同步（旧引擎的 `theme_mode_changed` hook）**仍然没接**：它要指向一个能执行
`theme sync` 的命令，而这个项目没有二进制在 PATH 上（阶段 G 已取消，不做入口替换）。
这是一条待裁决项，理由与可选做法记在 §16.6。

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

**系统级模块在这条线上的位置**：确认之后先取权限（需要 root 的话），然后装包，再
**先配置后系统动作**——配置能整棵退回快照，系统动作退不了，所以配置放前面，系统动作
失败时至少配置不会停在半新半旧。系统动作自己的备份与回滚由动作负责（§3）。一次
`install` 里没有任何配置模块时（例如只装 `fcitx5`），不创建快照：空快照只会给
`snapshot list` 添噪音。

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

系统级模块只写其中四个（`kind=system`、`enabled`、`source_version`、`last_result`）：
没有目标树，就没有 `target`／`preset`／`last_snapshot`／`custom_paths`／
`preserve_paths`／`fingerprint`／`part.*` 可写（见 §3）。

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
- **恢复是事务（`已完成`，阶段 E）**：`snapshot_restore` 在动手前先给"将要恢复的那些
  模块"存一份 `pre-restore` 保护快照，任何一步失败就用它把已经改过的模块放回去。没有
  这一步，恢复失败的收场是"一半新一半旧"，而账本还指着原来那个快照。保护快照的 ID
  写在 `SNAPSHOT_LAST_GUARD` 里，`rollback` 会把它作为"撤销这次恢复"的退路打出来。
  保护快照创建时会把**正在恢复的那个快照**钉进 prune 的保护集合
  （`SNAPSHOT_PROTECT_EXTRA`）——它可能已经排在第 30 名之外，不钉住就会在应用之前被
  自己的 prune 吃掉。
- `uninstall` 走不带事务包装的 `snapshot_apply`：它逐模块恢复，而单个模块的替换本身
  就是原子的，不可能出现"半个模块"；为每个模块留一份保护快照只会把列表塞满噪音。
- 普通部署继承 `__custom__`；精确回滚不继承当前配置里的新 custom 内容。
- **清理保护（`已完成`）**：清理保留 = 全部受保护快照 + 最近的 N 个普通快照。
  受保护的是：刚建好的那个、每个模块账本里的 `last_snapshot`（uninstall 的恢复
  点）、最近一次恢复保护快照。保留排序按 `created_at`，不按 ID 字符串——ID 的
  时间戳只到秒、后缀随机，按 ID 排等于随机丢弃。
  删与预览问的是同一个清单（`snapshot_prune_candidates`），`clean -n --snapshots`
  看到的和真删的一模一样。
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
- **已知取舍（待裁决，见 §10 P2）**：模块账本只存一个 `last_snapshot`，每次部署都会
  覆盖它。所以"装过一次再装一次，然后卸载"的收场是恢复到第二次部署前的样子（也就是
  配置还在），而不是清空。旧引擎同样取 `backups[0]`，行为一致。

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

`已完成`（配置模块八个）：niri、noctalia、kitty、fish、starship、fastfetch、
xdg-desktop-portal、zed。

`已完成`（系统级模块三个，§3）：fcitx5、fisher、greeter。

- **niri**：默认配置、`monitor.kdl` / `effects.kdl` / `colors.kdl` 等 preserve、
  `effects` 与 `glow` 两个零件插槽、脚本执行位、`niri msg` reload。随包提供
  初始 `effects.kdl -> effects_normal.kdl` 软链，保证全新安装时
  `config.kdl` 的 `include "effects.kdl"` 能解析；运行时脚本改指向后由 preserve 保留。
- **noctalia**：Noctalia V5 配置、模板源（模板由 Noctalia 自身渲染）、
  `tools/`（Orbit 启动器与 Wallpaper Picker 及其 Python 包）、`wallpaper-hook.sh`
  与 `mpv-hook.lua`。这些是配置里真实引用到的文件，随模块一起走。
  另外带 `theme.templates.user.nyxmellow_*` 三节，用 `requires_path` 挂在 fcitx5
  模块的素材上（见 §3）：注册随配置发布，没装皮肤时 Noctalia 自己跳过。
- **kitty**：配置、`current-theme.conf` 运行时软链、预设 `transparent`、`pkill -SIGUSR1` reload。
- **fish**：配置目录、local PATH hook、补全、`fish_plugins` 锁文件。因为目录部署是
  整棵树替换，本模块还 preserve `functions/` 与 fisher 装的四个文件，并把
  `fish_plugins` 声明成运行时写入——否则下一次 `install fish` 会把插件删掉（§3）。
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
- **fcitx5**：NyxMellow 皮肤素材（`assets/fcitx5/`，原子替换进
  `~/.local/share/fcitx5/themes/nyxmellow/templates/`）+ 雾凇拼音 + 设为默认，三件事
  拆成 `deploy` / `rime` / `activate` 三个动作，`install` 依次跑完。包需要 AUR
  （`rime-ice-git`）。全部在 `$HOME` 内，不需要 root。
- **fisher**：按固定 commit + sha256 取 fisher 引导脚本（三个镜像依次回退），装三个
  钉住的插件，并把自己写进去的文件记进 `$XDG_STATE_HOME/noctalia-mod/fisher.owned`。
  锁文件不是本模块钉住的那份就拒绝；已经有 fisher 但没有我们的账本也拒绝（不接管
  别人装的东西）。卸载只删账本里、且在白名单内的文件。
- **greeter**：`greetd`（仓库）+ `noctalia-greeter`（AUR），写
  `/etc/greetd/config.toml`、polkit 规则、`/var/lib/noctalia-greeter`，并切换
  显示管理器（记下原来那个，失败就放回去）。唯一需要 root 的模块，也是唯一**必须
  点名**才动系统的模块。详细契约见模块 README。

## 9. 当前真实进度

### 已完成

- Bash 入口与模块加载器，十一个模块接入（八个配置模块 + 三个系统级模块）。
- 操作：`list`、`check`、`setup`、`deps`、`plan`、`install`、`preset list|apply|save|edit|delete`、
  `part list|apply`、`action <模块> <动作>`、`snapshot`、`rollback`、`uninstall`、
  `status`、`theme sync|status`、`wallpapers deploy|status|remove`、`update`、`doctor`、
  `bug`、`clean`、`test`。
- 用户预设：存在 `~/.config/noctalia-mod/presets/<模块>/<名字>/`，与官方预设同一套
  解析顺序（官方优先）；`save` 不带 `__custom__`、覆盖前确认、拒绝保留字与官方同名；
  `delete` / `edit` 只作用于用户预设。活跃预设消失时按 §4 的冻结/回退语义处理。
- 阶段 D 的调研与止血：查清旧引擎的壁纸能力（部署 + managed 账本 + 部署期改写
  路径），并清掉 `wallpaper_picker/config.py` 里那条仓库相对回退路径——它在任何布局下
  都指不到东西（零行为变更，旧引擎那份源不动）。查出的路径回归记为 §10 P1-7。
- `shell-action.sh` / `session-shell.sh` 定稿为只留 Noctalia（§11 阶段 D），与旧引擎
  逐行对照确认只少了自研外壳路由。
- 部署期占位符：`/home/user` 与 `@XDG_PICTURES@`（§4），后者覆盖 noctalia 的
  `directory` / `video_directory` 与 niri 的 `screenshot-path`。
- `theme sync` / `theme status`：Noctalia 不做的另一半 GTK 深浅同步（写
  `gtk-{3,4}.0/settings.ini` 与 `gsettings gtk-theme`），`install`/`setup` 收尾各跑一次。
- `wallpapers deploy|status|remove`：离线包 no-clobber 同步 + `.noctalia-mod-managed`
  账本，清理只删账本内的条目；`setup` 顺手部署，`install` 不碰 `~/.config` 之外。
- 模块协议新增 `MODULE_RUNTIME_WRITES`：运行时也会改写、但模块仍然拥有的文件
  不进指纹（kitty 的两个文件、starship 的单文件目标）。
- 引导入口 `setup`：依赖与配置合成一份清单、一次确认、依次跑完，无参数时默认
  核心集（niri + noctalia）；`--with <程序>` 加装模块声明过的可选程序；跑完落
  一份收尾总结（装了什么、铺到哪、怎么退）。`setup` 可重复执行并收敛。
- 独立的 `deps` 依赖阶段：清单式预检、AUR helper 前置确认、`sudo -v` 一次性
  授权、repo/AUR 分批安装、已装齐时零操作返回、装后复核必需程序。
- pacman/AUR helper 的 argv 构造、pre-flight 清单、原子替换、失败恢复、
  项目锁、状态账本。
- 自动快照、手动快照、回滚、卸载恢复，`__custom__` 与 preserve 保留；恢复是事务
  （阶段 E）。
- 引用自洽校验（`check`）：配置路径 + 配置 spawn 的程序两个维度，并接入
  `plan`/`setup` 预检与 `install`/`setup` 门禁。
- 所有权指纹与 drift 检出；项目级依赖包账本。
- 运维与自更新（阶段 E）：`doctor` 体检（TSV 输出、有 fail 才非零退出）、`bug`
  诊断导出、`clean` 只清自己的暂存残渣并可选清理快照、`test` 沙箱部署闭环、
  `update` 拉取后换进程重新部署。四条的边界都写在 §11 阶段 E。
- 系统级可选模块（阶段 F）：`MODULE_KIND='system'` + `actions/*.sh` 三件套契约
  （§3），`lib/system.sh`（root/systemd/INI 原语）、`lib/network.sh`（多镜像 +
  sha256 校验的下载）；fcitx5、fisher、greeter 三个模块接入；
  `noctalia-mod action <模块> <动作>` 跑额外动作；`status` / `doctor` 走模块自己的
  status 动作；不带参数的 `plan`/`deps`/`install` 只覆盖配置模块。
- 行为测试 96 个用例，位于子项目内（`noctalia-mod/tests/`），可独立执行。
- 与旧引擎零耦合：不读旧状态、不依赖旧入口、不修改旧 `install.sh`。子项目是
  独立项目，不接管旧入口（§11 阶段 G 已取消）。

### 未完成 / 不实

以下项目曾在本文档中被写成"已完成"，实际不成立，已订正：

- 测试**不在**子项目内，且 §13 的覆盖清单只满足约三分之一。
- `profiles/` 只有空目录，没有任何实现（现已判定不需要并删除，见 §11 阶段 C）。
- `hooks.sh` 在 §3 声明过，引擎里没有任何实现。
- 没有做过新旧部署结果的隔离 HOME 对照验收。
- 环境检查只打印信息，不阻断（现已明确为设计选择）。
- `$XDG_RUNTIME_DIR/noctalia-mod` 从未被使用，相关函数是死代码。
- **模式切换时的实时主题同步仍未接**：`theme sync` 只在部署收尾跑，Noctalia 自己切
  深浅时不会通知本项目（§4、§16.6）。
- **初始化从未在真实全新机器上验收过**：`setup` 只在隔离 HOME + 假命令下闭环，
  实机验收要用户自己跑（agent 侧 `sudo` 不可用，见 §16.1、§16.5）。阶段 E 的 `test`
  也没有改变这一点——它同样不装真包、不进真会话。

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

**P1-7 迁移丢掉了壁纸路径的部署期改写（已修复）**。旧引擎每次部署都会把已落地的
`noctalia-config.toml` 里 `directory` / `video_directory` 与 niri 的 `screenshot-path`
改写成 `$(xdg-user-dir PICTURES)` 基准（`nyxuri/deploy/templates.py:26-47`）。新项目只做
`/home/user` → `$HOME` 替换，于是把仓库源里写死的 `/home/user/图片/Wallpapers` 原样铺成
`$HOME/图片/Wallpapers`——`图片` 是中文 locale 的 XDG 名字，英文 locale 下不存在。

**实测**：隔离 HOME 里 `install noctalia --yes` 落地的是 `$HOME/图片/Wallpapers`；本机
`xdg-user-dir PICTURES` = `~/Pictures`、`~/图片` 不存在；而旧引擎部署在本机的真实配置
指向 `~/Pictures/Wallpapers`，用户的 21 张壁纸与 `video/` 就在那里。后果不是报错而是
**静默吞掉**：Noctalia 只在 `directory` 为空串时才回退 XDG Pictures，非空但无效的值原样
生效，扫描器遇到不存在的目录只缓存一个空结果（依据是上游 `wallpaper_paths.cpp` /
`wallpaper_scanner.cpp` 与官方文档；仓库内 `noctalia-llm-docs/` 没有覆盖这条，属外部证据）。

处理方式：部署引擎加了第二个占位符 `@XDG_PICTURES@`，三处路径改用它（§4），引擎因此
不需要知道哪个模块的哪个键要改；`pictures_dir()` 在 `xdg-user-dir` 答不出来时才回退
`$HOME/Pictures`（与旧引擎一致）。回归测试：
`test_xdg_pictures_placeholder_follows_the_users_pictures_dir`、
`test_xdg_pictures_falls_back_when_the_tool_cannot_answer`。

**P1-8 GTK 深浅同步没人做了（已修复）**。旧引擎的 `theme` 命令
（`nyxuri/theme.py:67-109`）在每次部署收尾与模式切换时做两件 Noctalia 不做的事：写
`gtk-{3,4}.0/settings.ini` 的 `gtk-application-prefer-dark-theme` / `gtk-theme-name`，
以及 `gsettings set … gtk-theme adw-gtk3(-dark)`。Noctalia 只设 `color-scheme`
（二进制里有 `gsettings set … color-scheme`，实测该键跟着模式走），既没有 `adw-gtk3`
也没有 `gtk-application-prefer-dark-theme` 任何字符串；它的内置 gtk 模板写的是
`gtk-{3,4}.0/noctalia.css`（一行 `@import` 策略），而当前 `builtin_ids` 不含 gtk3/gtk4，
所以那条路也没在跑。

**实测**：`noctalia msg theme-mode-get` = `light`、`gsettings color-scheme` =
`prefer-light`，但 `gsettings gtk-theme` = `adw-gtk3-dark`、`settings.ini` 仍是
`gtk-application-prefer-dark-theme = true`——三处不同步。`configs/noctalia/README.md`
记过这个键是 Brave/Chromium 冷启动判深浅的硬依赖，不能不管。

处理方式：新增 `lib/theme.sh` 与 `theme sync` / `theme status` 两个动作，`install` 与
`setup` 的收尾各调一次，失败只警告（配置已经铺好了，不该因为 `gsettings` 或会话不可用
把一次成功的部署弄成失败）。旧引擎的模式解析保留（部署时没有别的办法知道当前深浅），
flock 防抖去掉——新架构没有 CLI + hook 双触发。模式切换时的实时同步仍然没接：
hook 要指向一个能执行 `theme sync` 的命令，而本项目没有二进制在 PATH 上（§16.6 第 5 条）。
回归测试：`test_theme_sync_follows_the_current_mode`、
`test_theme_sync_preserves_unrelated_settings_ini_content`、
`test_theme_status_reports_what_is_expected`、
`test_deploy_syncs_the_theme_without_failing_the_install`。

**P1-9 Noctalia 会反向改写我们"拥有"的文件（已修复）**。Noctalia 的内置模板带
`post_hook`，会就地改写仓库部署下去的文件：`kitty/kitty.conf`（删掉
`# BEGIN_KITTY_THEME … # END_KITTY_THEME` 整块——仓库的 `include current-theme.conf`
就在块里——并在文末补 `include themes/noctalia.conf`）、`kitty/themes/noctalia.conf`
（按当前壁纸调色板整体重写）、`starship.toml`（重写 palette 块）。三个都实测过：实机
`kitty.conf` 42 行无块，仓库版 45 行含块；主题文件与 starship 的调色板都是当前浅色值。

后果是漂移必然常报。按 §1 的设计这**不是误报**——它正确地指出"漏声明了一个运行时写入
者"；但照 §1 的老办法把 `kitty.conf` 声明成 preserve 会走向另一个极端：preserve 会把
实机版本原样拷回暂存树，模块从此再也更新不了自己的 `kitty.conf`。

处理方式：把绑在一个概念里的两件事拆开，新增 `MODULE_RUNTIME_WRITES`（§1、§4）——
照旧覆盖更新，只是不进指纹。kitty 声明 `kitty.conf` 与 `themes/noctalia.conf`，starship
是单文件目标，用文件名本身声明。代价写进了 §1：这些文件放弃了漂移检测，这是有意的，
对它们报漂移只会训练用户忽略漂移报告。

顺带结掉两条：§10 P1-5（全新系统上的壁纸目录）由本条的路径修正 + `wallpapers deploy`
的 `mkdir` 一起解决——目录现在一定会被创建，Noctalia 缺目录时只显示空面板、不崩溃
（外部证据），所以不再需要"换默认路径"或"提前做壁纸迁移"；P2 里"`colors.kdl` 没有任何
niri 配置 include 它"的说法也不准确——`modules/niri/parts/glow/glow-material-you.kdl`
里有 `include optional=true "colors.kdl"`，只是默认零件是 `default` 所以看不到。

回归测试：`test_runtime_written_files_do_not_report_drift`、
`test_runtime_written_files_are_still_overwritten_by_a_deploy`；
壁纸一侧：`test_wallpaper_deploy_records_only_what_it_placed`、
`test_wallpapers_remove_keeps_user_files_and_refuses_unsafe_entries`、
`test_setup_deploys_wallpapers_but_install_does_not`。

**回滚不是事务（已修复，阶段 E）**。`snapshot_restore` 原先逐模块恢复，中途失败就
直接返回：已经恢复的模块留在新状态、没恢复的留在旧状态，而账本还指着原来那个快照。
模块再多一个，这个中间态就没人说得清。

处理方式：`snapshot_restore` 变成事务包装——先给"将要恢复的那些模块"存一份 `pre-restore`
保护快照，失败就用它把已改的模块放回去；原来的逐模块循环拆成内部原语 `snapshot_apply`
（`uninstall` 仍用它：单模块替换本身原子，不需要也不该为每个模块留一份保护快照）。
保护快照创建时会 prune，所以正在恢复的那个快照被 `SNAPSHOT_PROTECT_EXTRA` 钉住，
否则它可能在第 30 名之外被自己的 prune 删掉。回归测试：`test_rollback_is_a_transaction`
（快照里一个模块的副本故意弄坏，验证另一个模块被放回去、保护快照存在）。

顺带统一了两处：`snapshot_prune` 与 `clean -n --snapshots` 现在共用
`snapshot_prune_candidates`，"预览的"和"真删的"是同一个清单；保护快照的类型名从
`pre-rollback` 改为 `pre-restore`——现在建它的不只 `rollback`，安装/部署失败的自动
恢复也走同一条路，`snapshot_protected_ids` 保护的仍是"最近一个"。

### 待办（余项）

#### P2 其它

- **迁移取舍：`zed` 与 portal 后端的包不再是"可选"**。旧引擎把 zed 登记在
  `.optional-apps.toml`（包只进 optdepends），portal 后端则完全没人声明。新项目没有
  "可选软件"这一轴，模块要么声明包要么不声明，所以 `deps --yes` / `install --yes`
  会把 zed 编辑器与两个 portal 后端一起装上。走 §0 的 `setup` 引导路径不受影响
  （默认只有 niri + noctalia）。想恢复"配置在、包不在"的状态，就得显式把包从模块
  清单里拿掉，但那样 `check` 的模块自足契约也就断了。

- ~~待验证：Noctalia 的内置 kitty 模板是否会写进 `~/.config/kitty/`~~ → **已结案：
  会写，而且不止 kitty**，实测见 §10 P1-9。

- **重装之后卸载不删配置（未改，待裁决）**。模块账本只存一个 `last_snapshot`，
  每次部署都覆盖它，而 `uninstall` 恢复的就是它。**实测**：连续两次
  `install niri --yes` 之后跑 `uninstall niri --yes`，`~/.config/niri` 还在——因为
  最近一次"部署前快照"就是第二次部署前的样子（配置已经铺好）。旧引擎取
  `backups[0]`，行为一致，所以这不是迁移引入的回归。要改成"卸载恢复第一次部署前的
  状态"，得在账本里多存一个 `first_snapshot`（或按模块记录首次部署时间），属于
  schema 变更。阶段 E 没有动它：`test` 沙箱的卸载断言只验账本被清空，文件语义留给
  这次裁决。

- **`clean` 不碰系统级缓存（有意，待裁决）**。旧引擎的 `clean` 会清 pacman 包缓存、
  vacuum journal、删孤立包、跑 TRIM，还要提权；新项目的 `clean` 只管自己的暂存残渣
  与快照。理由：那些是操作系统维护，不是配置管理器的领地，而需要 root 的万金油命令
  和"非交互优先 + 只动自己的东西"是冲突的。要保留这套能力的话，更适合做成一份显式的
  系统维护清单（阶段 F 的系统级模块就是它的落点），而不是塞回 `clean`。

- **系统级动作失败不能自动回滚（有意）**。配置模块有部署前快照，系统级模块没有——
  写 `/etc`、enable 单元这些事没有"换回去"的原子操作。所以契约是：动作自己负责备份与
  还原（greeter 就是这么写的），引擎在一份 `install` 里只能把配置那半边退回快照。
  一次 `install greeter niri` 里 greeter 失败，niri 会被退回去，而 greeter 自己半路
  改掉的东西只能靠它自己的回滚逻辑（它也确实实现了）。这条写进 §3，不是待修项。

- **fish 与 fisher 的 preserve 清单是手工维护的（有意，有漂移风险）**。`install fish`
  是整棵树替换，所以 fisher 装进去的文件必须在 `fish` 模块的 `MODULE_PRESERVE` 里
  逐个声明（`functions/` 整目录 + 四个文件）。fisher 上游哪天多写一个文件，那次部署
  还是会把它删掉——这是"两套机制不合并"的直接后果（§3），代价换来的是安装结果可预测。
  同理 `fisher` 模块的 `MODULE_FISHER_MANAGED_FILES` 白名单也是手抄的：它决定卸载能删
  什么，宁可少删也不能多删。

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
  **真实全新机器上的验收仍未做**（agent 侧 `sudo` 不可用，见 §16.5）。

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

### 阶段 D：运行时能力（已完成）

先从两个只读调研收口（哪些是实测、哪些是推断见 §16.5），再按结论动手：

- **模板渲染：不做（关闭）。** `templates/*` 里的 `{{ }}` 由 Noctalia 自己的
  TemplateEngine 按 `[theme.templates.user.*]` 的 `input_path` → `output_path` 渲染
  （本机产物里 `{{` 计数为 0，颜色跟着当前壁纸）。旧引擎的 `_phase_render_templates`
  **从来不是模板引擎**，只是部署后对已落地文件做文本替换。`module.conf` 里"gtk.css 由
  Noctalia 运行时渲染"的声明成立，新项目只负责把模板源铺进去。
- **`hooks.sh`：不做（关闭）。** 没有"渲染后钩子"这种东西要模块提供；真正缺的两件事
  （GTK 深浅同步、XDG 路径改写）是引擎的全局职责，写成模块钩子只会让每个模块重复一遍。
  模块自己的收尾动作已经由 `MODULE_RELOAD_COMMAND` 覆盖。§3 里那条空转了两轮的概念
  已删除；阶段 F 的 fcitx5 若需要"部署后设为默认"，届时单独设计。
- **`shell-action.sh` / `session-shell.sh` 定稿**：只留 Noctalia 是最终决定。与旧引擎
  逐行对照，两个脚本唯一少掉的就是自研外壳路由（读 `state.json` 的 `active_shell` /
  `custom_shell_bin`、`NYXURI_CUSTOM_SHELL_BIN` 回退、启动失败时的 notify-send 兜底）；
  会话 scope 清理与动作分发表逐字一致。`shell-action.sh` 保留为薄分发表：它的价值是让
  niri 键位不直接依赖 Noctalia 子命令的拼写，而不是"可切换外壳"。
- **不需要补**：Kvantum INI 与 `layout-{dark,light}.kdl` 切换（旧引擎的 Python 引擎本来
  就没做，只在已死的 `theme-sync.sh` 里）、fish `fish_variables`（没有这个文件）、
  `theme` 命令的 flock 防抖（新架构没有 CLI + hook 双触发）。
- **补齐三处实测缺口**：§10 P1-7（`@XDG_PICTURES@` 占位符，覆盖 wallpaper /
  video_directory / niri screenshot-path）、P1-8（`lib/theme.sh` + `theme sync`，写
  `gtk-{3,4}.0/settings.ini` 与 `gsettings gtk-theme`，`install`/`setup` 收尾各调一次）、
  P1-9（新增 `MODULE_RUNTIME_WRITES`，把"运行时写入"与"不要覆盖"拆开，kitty 与 starship
  的漂移不再常报）。
- **壁纸**：`lib/wallpaper.sh` + `wallpapers deploy|status|remove`，离线包
  no-clobber 同步 + `<壁纸目录>/.noctalia-mod-managed` 账本 + 只删账本内条目。离线包随
  子项目走（`assets/wallpapers/`，1 张图），远程壁纸包下载不迁——旧引擎也只把它做成
  显式可选。只有 `setup` 会顺手部署壁纸，`install` 的契约仍是"只动 `~/.config`"。
- **P2 里的壁纸死代码已清**：`wallpaper_picker/config.py` 那条仓库相对回退路径在任何
  布局下都指不到东西，零行为变更地删掉（旧引擎那份源不动，那是另一棵树的事）。

仍然留着的取舍：`video_directory` 与 `mpvpaper` 插件在装着的 noctalia 5.2.1 上是惰性的
（二进制里没有这两个字符串，也没有 plugins 目录），所以不为它写特殊逻辑，但也不删——
升级后会生效。

### 阶段 E：运维与自更新（已完成）

- **`update`（已完成）**：`git pull --ff-only` + 换进程重新部署账本里的模块。四条
  边界都被测试钉住：不是 git 检出就拒绝；改了已跟踪文件就拒绝（未跟踪文件不拦）；
  非交互又没有 `--yes` 时**先拒绝、再拉取**（不留"拉了但没铺"的中间态）；拉完必须
  `exec` 一个新进程，因为 lib 只在入口启动时 source 过一次。网络参数带显式超时
  （`http.lowSpeedLimit/lowSpeedTime/connectTimeout`）。**不做状态迁移**：账本 schema
  是自包含的，没有按版本号走的迁移链可言（旧引擎那套 `migrations` 是给跨版本升级的）。
- **`doctor` 体检（已完成）**：TSV 输出 `<状态>\t<领域>\t<说明>`，状态是
  `ok|warn|fail|info`。十项检查：环境、仓库自洽（复用 `check` 的三个函数）、模块账本
  与指纹、执行位、必需/可选程序、状态目录与暂存残渣、GTK 深浅、壁纸、随包 Python
  工具的 import（就是 §3 那条"人工审计"的自动版）、磁盘空间。退出码只在有 `fail`
  时非零——"没装这个程序"是 `warn`（那描述的是机器，不是仓库），"装着的模块目标没了"
  才是 `fail`。
- **`bug` 诊断导出（已完成）**：把体检、部署账本、包账本、快照列表、审计尾部收进
  一份 Markdown，落在 `$XDG_STATE_HOME/noctalia-mod/bug-report-<时间戳>.md`。只读本项目
  自己的状态与几个基础命令，不收集系统日志。
- **`clean`（已完成，范围有意收窄）**：清的是本项目唯一会留下的垃圾——部署中断留下的
  暂存树（名字精确匹配 `.<目标>.noctalia-mod.{new,old,build,uninstall}.<随机后缀>`，
  路径必须在配置根内，软链一律跳过）。`-n` 预览与实删共用同一个清单；
  `--snapshots` 顺带做一次快照清理（受保护的点绝不删）。**不碰 pacman 缓存、journal、
  TRIM、孤立包**：那些要 root、属于操作系统维护，理由与去留见 §10 P2。
- **沙箱部署测试 `test`（已完成）**：在临时 HOME + 命令替身（`pacman` 一律答"已装"，
  于是不装包、不提权）里跑真入口：`setup --yes` → 校验模块目标与 `MODULE_VALIDATE_PATHS`
  → 再跑一遍必须得到同一棵树、不留暂存残渣 → `plan` 不许报漂移 → `uninstall` 必须清空
  账本。失败时保留沙箱目录并打印日志尾部。它等价于 `install.sh test`，但更严：那条
  命令只是"在当前环境重铺一次"，这条自带隔离与收敛断言，且不会碰到真实 `~/.config`。
- **快照/回滚做成事务（已完成）**：见 §6 与 §10 已修复。

### 阶段 F：系统级可选模块（已完成）

这一阶段要解决的是"配置树之外的动作"：写 `/etc`、enable systemd 单元、用 fish 装插件、
把素材放进 `~/.local/share`。硬塞进"目标目录"只会得到一个假装原子的东西，所以先定契约
（§3「系统级模块」），再按它接模块：

- **契约（已完成）**：`MODULE_KIND='system'` + `modules/<id>/actions/{install,status,uninstall}.sh`，
  额外动作由 `MODULE_SYSTEM_EXTRA_ACTIONS` 声明、用 `noctalia-mod action <模块> <动作>` 跑。
  预检清单由 `MODULE_SYSTEM_PATHS` / `MODULE_SYSTEM_SERVICES` 声明；需要 root 的模块
  （`MODULE_SYSTEM_PRIVILEGED='yes'`）在动手前统一取一次权限。引擎不替动作回滚——备份与
  还原是动作自己的责任（系统级动作没有"换回去"这一说），引擎能做的是把配置那半边的
  事务照旧做完，并在系统动作失败时把它退掉（§5）。
- **`post_install = "模块:函数"` 的重新设计（已完成）**：不复活这条缝。声明那个包的系统级
  模块自己就是钩子——`rime-ice-git` 属于 fcitx5 模块，`install fcitx5` 自然就把雾凇拼音
  配好；旧引擎的 `setup_rime_ice` 在 `install` 动作里有了落点（§3）。
- **fcitx5（已完成）**：素材、雾凇拼音、"设为默认"三件事拆成三个动作，`install` 依次跑完；
  `deploy` 只铺素材、不动当前主题。素材随子项目走（`assets/fcitx5/`）。
  **旧引擎的模板注册不再由本模块改写 noctalia 的配置**：那三节回到 noctalia 模块自己的
  `noctalia-config.toml`，带 `requires_path`，没装皮肤时 Noctalia 自己跳过。
- **fisher（已完成）**：固定 commit + sha256 + 三镜像回退的引导下载，所有权账本
  `fisher.owned`（装到一半也记账，重试安全），锁文件对不上就拒绝，别人装的 fisher 不接管。
- **greeter（已完成）**：唯一的 root 模块。写 `/etc/greetd/config.toml`、polkit 规则、
  `/var/lib/noctalia-greeter`，切换显示管理器并记下原来那个（失败放回去），卸载关掉 greetd、
  把上一个 enable 回来、按备份还原文件。session 命令必须通过可信路径检查（root 拥有、
  落在 `/usr/bin` 或 `/usr/local/bin`、祖先目录不可被组/其他写）。
  与旧引擎的一处有意差别：记录文件里没有上一个显示管理器时照样关掉 greetd——旧引擎在这个
  情况下拒绝卸载，用户会被卡住。
- **gtktheme（已完成，判定为不需要独立模块）**：旧引擎那个模块只做三件事——注册模板、
  催渲染、清掉旧版 `gtk-dark.css` 软链。注册本来就随配置发布而不是它装的：旧树里那两节
  在 `configs/noctalia/noctalia-config.toml:233-241`，新树里在
  `noctalia-mod/modules/noctalia/files/noctalia-config.toml`；剩下两件是引擎级的 GTK 收尾，
  和写 `settings.ini` 属同一类，所以收进 `theme_clean_legacy_overrides` 与
  `theme_trigger_render`，由 `install`/`setup` 的收尾调用。为两个命令再建一个模块，正是
  这个项目已经砍掉两次的"空转概念"（`hooks.sh`、`profiles/`，见阶段 D 与阶段 C）。
- **`update` 与系统级模块（已完成）**：`update` 重铺账本里的配置模块与**不需要 root** 的
  系统级模块（fcitx5、fisher），需要 root 的那个（greeter）只打印"要显式重跑"。更新代码
  不该顺手改掉这台机器下次开机登录的样子。

### 阶段 G：已取消（重构后的项目是独立项目，不接管旧项目）

原计划是"打包 + 让 `install.sh` 指向子项目 + 退役旧引擎"。**取消**：`noctalia-mod/`
是一个能整目录取走的独立项目，自己的入口是 `bin/noctalia-mod`，不需要替换旧入口，
也不需要等旧引擎退役。由此：

- 打包（PKGBUILD、依赖聚合）不属于本子项目的交付；真要打包，那是"独立项目的发布
  方式"，届时单独设计，和旧引擎的去留无关。
- 仓库根的 `install.sh`、`nyxuri/`、`configs/`、`assets/` 不归本子项目管，也不为了
  子项目好过而改动（§14）。
- `llms-wiki/` 继续是旧引擎的文档，本子项目不维护它（§12）。旧树哪天退役是仓库根的
  决定，不是本子项目的前置条件。

### 明确不迁移

- `nyxniri` 兼容别名与 `NYXNIRI_*` 环境变量（新项目无历史包袱）。
- Nyxuri 的 `NYXURI_*` 运行时环境变量与 `LEGACY_*` 回退分支（迁移 tools 时已删）。
- 用户状态账本与迁移墓碑清单。
- 自研桌面外壳路由（旧引擎的 `shell get|set`）。新项目只支持 Noctalia。
- 旧入口的接管与旧引擎的退役（阶段 G 取消，见上）。

## 12. 文档与变更记录约定

- **文档权威在子项目内**：`PLAN.md`（方案与进度）、`README.md`（用法）、
  各模块 `README.md`（协议与例外）。代码改动必须同步这里。
- **不更新 `llms-wiki/`**：那是旧引擎的文档，本子项目不维护它（阶段 G 取消后旧引擎
  不会被子项目取代，两份文档各自描述各自的树）。出现不一致时以子项目文档和当前代码
  为准。
- **变更记录后置**：子项目在没有被真实用户使用之前，不写用户可见的 changelog。
  也不往仓库根 `CHANGELOG.md` 添加子项目条目——那条记录对用户不可感知（入口是
  `bin/noctalia-mod`，不在 PATH 上，也没有自己的发布）。等它真的被日常使用，再在
  子项目内建自己的 changelog。

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
| shipped 工具的 import 与依赖声明一致 | ✅ 由 `doctor` 真去 import 一次（§11 阶段 E） |
| 全新系统初始化闭环（§11 阶段 B） | 隔离 HOME 闭环 ✅；真实机器 ⬜ |
| 所有权指纹与 drift 检出（managed 改动、目标消失） | ✅ |
| drift 不误报 `__custom__` / preserve / 运行时软链改动 | ✅ |
| 依赖包记账（只记我们装的、不重复） | ✅ |
| 部署期占位符：`@XDG_PICTURES@` 跟随 XDG、答不出来才回退 | ✅ |
| GTK 深浅同步：settings.ini 两键、gsettings 两键、非相关键不被破坏 | ✅ |
| 部署收尾做主题同步，且 gsettings 坏了不让部署失败 | ✅ |
| 壁纸：离线包 no-clobber、账本只记我们放的项、幂等 | ✅ |
| 壁纸清理：只删账本条目、拒绝越界路径且不遗忘 | ✅ |
| `install` 不碰 `~/.config` 之外，`setup` 才部署壁纸 | ✅ |
| 运行时写入的文件不报漂移，但仍被部署覆盖 | ✅ |
| `MODULE_RUNTIME_WRITES` 越界路径被元数据校验拒 | ✅ |
| `doctor`：健康时退出 0、目标消失时 fail 且退出 1 | ✅ |
| `doctor`：报出 drift 与暂存残渣 | ✅ |
| `bug`：报告含账本、包账本与体检输出 | ✅ |
| `clean`：只删自己命名的暂存项，`-n` 不删任何东西 | ✅ |
| `clean --snapshots`：预览与实删同一清单，普通 `clean` 不动快照 | ✅ |
| `test`：沙箱闭环、不碰调用者 HOME、成功即清理 | ✅ |
| `test`：仓库坏掉时失败并保留沙箱目录 | ✅ |
| `update`：拉取后换进程重铺新代码、账本版本更新 | ✅ |
| `update`：脏树 / 非 git 检出 / 非交互无 `--yes` 被拒且不动仓库 | ✅ |
| `update`：git argv 形状（超时参数、`--ff-only`、未跟踪文件不拦） | ✅ |
| 回滚是事务：中途失败放回已恢复的模块，并留 `pre-restore` 保护快照 | ✅ |
| 系统级模块：元数据校验（目标、相对路径、越界、未知 kind、权限标记、缺动作） | ✅ |
| 系统级模块：不带参数的 `plan`/`deps`/`install` 不隐式选中它们 | ✅ |
| 系统级模块：预检列出会写的路径、会 enable 的单元、要不要 root | ✅ |
| 系统级模块：账本只写 kind/enabled/source_version/last_result，不写目标与指纹 | ✅ |
| 系统级模块：动作失败时配置那半边退回快照、不写账本 | ✅ |
| 系统级模块：需要 root 的在动手前统一 `sudo -v` | ✅ |
| `action`：未声明 / 非系统模块 / 未安装 / 重复顶层命令都被拒 | ✅ |
| `preset` 与 `part` 拒绝系统级模块 | ✅ |
| `status <模块>` 跑它自己的 status 动作并沿用退出码 | ✅ |
| `doctor` 用系统模块的 status 动作判断健康 | ✅ |
| fcitx5：素材 + 雾凇拼音 + 设为默认，卸载只还原自己改过的值 | ✅ |
| fcitx5：`deploy` 不动当前主题选择、`rime` 退路不覆盖用户的 `user.yaml` | ✅ |
| fisher：锁文件被改过就拒绝、不接管别人装的 fisher | ✅ |
| fisher：装到一半失败仍记账（`complete=0`）、重试收敛、卸载只删自己的文件 | ✅ |
| 下载校验：sha256 不符不留文件、多镜像 argv 带显式超时 | ✅ |
| greeter：接管登录界面并在卸载时放回原来的显示管理器 | ✅ |
| greeter：enable greetd 失败时放回上一个显示管理器并回滚文件 | ✅ |
| greeter：不可信的 session 路径在任何特权操作之前被拒 | ✅ |
| 沙箱 `test` 只跑核心集（niri + noctalia），系统级模块不走它 | ✅（有意：`test` 是"全新机器核心闭环"的替身） |

每步实现后至少运行（全部零网络秒级）：

```bash
# 语法：必须逐个文件跑。`bash -n a b c` 只检查 a，b/c 会被当成位置参数静默忽略。
find noctalia-mod -type f \( -name '*.sh' -o -name 'noctalia-mod' \) -print0 |
    xargs -0 -n1 bash -n

# 随包发布的 Python 工具也要过语法，否则要到用户点开 Orbit / 壁纸选择器才发现。
# pyc 必须重定向出仓库：__pycache__ 落在 files/ 里会被一起拷进 ~/.config。
PYTHONPYCACHEPREFIX=${TMPDIR:-/tmp}/noctalia-mod-pycache \
    python3 -m compileall -q noctalia-mod/modules/noctalia/files/tools

# 随包发布的 fish 配置同样过语法：一个语法错误就让交互 shell 起不来。
# 需要 fish 已安装——fish 模块本来就在装它。
find noctalia-mod/modules/fish -type f -name '*.fish' -print0 |
    xargs -0 -n1 fish -n

# 静态分析：-x 必须带，否则 source 进来的 lib 根本不参与分析。
# 用 find 收集，不要手写 glob —— 漏掉 modules/noctalia/files/wallpaper-hook.sh
# 这种不在 scripts/ 下的脚本是很容易发生的事。
mapfile -t shells < <(find noctalia-mod -type f -name '*.sh' | sort)
shellcheck -x noctalia-mod/bin/noctalia-mod "${shells[@]}"

python3 -m unittest discover -s noctalia-mod/tests -q
noctalia-mod/bin/noctalia-mod check
noctalia-mod/bin/noctalia-mod test        # 自带隔离，跑完整闭环（阶段 E）
```

三个坑，都是踩过的：

1. **`bash -n` 只看第一个文件。** 多文件写法下其余参数变成位置参数，语法错误不会
   被发现，命令还会返回 0。必须逐个跑。
2. **`shellcheck` 不带 `-x` 等于半盲。** 这个 CLI 的核心逻辑全在被 source 的
   `lib/*.sh` 里，不带 `-x` 就只检查入口那一个文件，lib 里的问题一个都看不到。
   入口里的 `source` 需要 `# shellcheck source-path=SCRIPTDIR` 才能被正确解析。
3. **注释不要以 `shellcheck` 开头。** 任何 `# shellcheck ...` 开头的行都会被当成
   指令解析，写中文说明时踩过一次，直接报 SC1072 语法错误。

`shellcheck` 现在是 pacman 装的那份（`/usr/bin/shellcheck`，包版本 `0.11.0-150`）；
此前临时装在 `~/.local/bin` 的静态二进制已由用户移除，不再依赖它。子项目（22 个
`*.sh` + 入口）、`install.sh` 与旧项目的 8 个 `configs/**/*.sh` 在这份包版本上复核过，
**零告警**。

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
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod theme status
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod wallpapers status
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod doctor
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod bug
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod clean -n
noctalia-mod/bin/noctalia-mod test          # 自己造临时 HOME 与命令替身，不需要外面套 HOME
```

注意这些命令需要 PATH 上能有 `pacman`、`sudo`、`xdg-user-dir`、`gsettings` 之类；
本机实测时用假命令目录放在 PATH 前面（见 §16.5 的做法），否则 `setup --yes` 会真的去
装包、`theme sync` 会真的动你当前的 gsettings。`theme sync` 与 `wallpapers deploy`
是两条**会改到 `~/.config` 之外**的命令，在真机上跑之前先想清楚。`doctor`、`bug`、
`clean -n` 与 `update --no-deploy` 都是只读的（`bug` 只往状态目录写一份报告）。

## 14. 会话执行约束

1. 先读 **§16 接手须知**（环境事实、工作区状态、陷阱、待裁决），再读对应模块
   README，然后动手。
2. 修改前检查 `git status` 与 §16.3 的工作区状态；有未提交改动先问用户，别在脏树上动工。
3. 对路径、状态、部署、保留规则有疑问时，全仓库检索引用后再下结论。
4. 旧引擎与旧入口不归本子项目管：不为了子项目好过而改 `install.sh`、`nyxuri/`、
   `configs/`、`assets/`（阶段 G 已取消，见 §11）。
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
| `sudo` | **agent 的工具沙箱里不可用**：设了 no-new-privileges，`sudo -v` 直接失败。用户自己的 shell 不受这条限制（`shellcheck` 就是他自己 `pacman -S` 装的），所以本机装包路径由用户实测，不由 agent 实测 |
| `pacman` / `paru` | 都在。agent 侧因为上一条无法走安装路径（`deps`/`setup` 只能用假命令验证） |
| 网络 | 通（GitHub 与 Arch 镜像均可达） |
| `shellcheck` | pacman 装的 `/usr/bin/shellcheck`（`shellcheck 0.11.0-150`）。早先临时用的 `~/.local/bin` 静态二进制已被移除，现在走包管理 |
| `fish` | 4.9.3，在 PATH 上（fish 模块本来就要装它），所以 `fish -n` 能进语法门禁 |
| `xdg-user-dir` / `timeout` / `gsettings` | 都在 PATH 上。前两个被 `@XDG_PICTURES@` 与各处的超时用到，`gsettings` 被 `theme sync` 用到 |
| Git 身份 | `victor xu <vanxnf@gmail.com>`（全局已配好；此前几个提交的身份是后改的，见 §16.3） |
| 远端 | `git@github.com:VanXNF/noctalia-helper.git`，当前分支 `refactor/v3` |
| **SSH 是坏的** | `/etc/ssh/ssh_config.d/20-systemd-ssh-proxy.conf` 的符号链接目标属主成了 `nobody:nobody`，OpenSSH 的属主检查直接拒绝读配置，任何 ssh 连接都起不来。绕法：`GIT_SSH_COMMAND='ssh -F /dev/null -o ConnectTimeout=15 -o BatchMode=yes' git push …`。**没有**改那个系统文件（属于系统，不是本仓库的事） |
| 沙箱 | 工作区之外只读；写 `~/.local/bin` 之类需要一次提权 |

`shellcheck` 的运行前提是它在 PATH 上（包装的 `/usr/bin/shellcheck` 满足）；这条
命令不参与任何构建，所以缺了只是门禁少一条，不影响项目本身。

### 16.2 门禁三连（每条都实测过，照抄即可）

```bash
cd /home/victorxu/Projects/workspace/noctalia-helper

# 1. 语法：shell 必须逐个文件跑（见 §16.4 陷阱一），随包 Python 工具一起过
find noctalia-mod -type f \( -name '*.sh' -o -name 'noctalia-mod' \) -print0 |
    xargs -0 -n1 bash -n
PYTHONPYCACHEPREFIX=${TMPDIR:-/tmp}/noctalia-mod-pycache \
    python3 -m compileall -q noctalia-mod/modules/noctalia/files/tools
find noctalia-mod/modules/fish -type f -name '*.fish' -print0 |
    xargs -0 -n1 fish -n

# 2. 静态分析：-x 必须带（见 §16.4 陷阱二）
mapfile -t shells < <(find noctalia-mod -type f -name '*.sh' | sort)
shellcheck -x noctalia-mod/bin/noctalia-mod "${shells[@]}"

# 3. 行为测试 + 仓库引用自洽 + 沙箱闭环
python3 -m unittest discover -s noctalia-mod/tests -q
noctalia-mod/bin/noctalia-mod check
noctalia-mod/bin/noctalia-mod test
```

当前基线：语法 39 个 shell 文件 + 随包 Python 工具 + 4 个 fish 文件全过、shellcheck
零告警、96 个测试 OK、`check` 全绿、`test` 闭环。
仓库根 `discover -s tests` 也能过，但**不再覆盖子项目**（测试已迁入，见 §13）。

### 16.3 当前工作区与 Git 状态

- 分支 `refactor/v3`，本地 HEAD 是 `2bdab64`（阶段 E：运维与自更新），阶段 A–E 已提交。
- **阶段 F 的改动在工作区里、还没提交**：新增 `lib/{system,network}.sh`、
  `modules/{fcitx5,fisher,greeter}/`、`assets/fcitx5/`；改了 `bin/noctalia-mod`、
  `lib/{common,module-loader,deploy,snapshot,reference-check,doctor,update,theme,sandbox}.sh`、
  noctalia 的 `noctalia-config.toml`、fish 的 `module.conf`、测试与文档。
  要提交的话按 §5 的 changelog 规矩（子项目现在**不写**用户可见 changelog，见 §12）。
- 推远端记得 §16.1 那条 SSH 绕法（`ssh_config.d` 的属主检查坏了，任何 ssh 都起不来）。
- **子项目是独立项目，不接管旧入口**（阶段 G 已取消，见 §11）：
  - `install.sh`、`nyxuri/`、`configs/`、`assets/` 仍在旧引擎名下服役，本子项目
    不为了自己好过去改它们；
  - 子项目里那份 `assets/wallpapers/lawson_fuji.webp`、`assets/fcitx5/` 与仓库根那两份
    是重复的，各自随各自的树走，不是待清理的残留；
  - 仓库根 `CHANGELOG.md` 里子项目的条目已经撤掉，理由见 §12。
- 仓库根 `discover -s tests`（旧引擎 471 个用例）现在是绿的；子项目的测试**不在**
  那条发现路径里，要单独跑（见 §16.2）。

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
   （只检查了 `install.sh`）。**没有擅自改动那一行**，等用户裁决（AGENTS §4 的占位符
   那行倒是按阶段 D 的决定加了 `@XDG_PICTURES@`）。
7. **注释里不要写占位符字面量**：`/home/user` 与 `@XDG_PICTURES@` 是全局文本替换，
   注释里写了会连注释一起被替换成一句读不通的话（真踩过，`noctalia-config.toml`
   里那条说明现在刻意不写占位符本身）。
8. **删掉测试替身 ≠ 测回退**：PATH 后面还压着真的命令。想测"`xdg-user-dir` 答不出来
   就回退"，得让替身 `exit 1`，而不是把替身删掉——真 `xdg-user-dir` 在没有
   `user-dirs.dirs` 时会按 XDG 规定答 `$HOME`，于是断言会以看上去毫不相干的方式失败。
9. **`compileall` 会把 `__pycache__` 写进 `files/`，然后被一起部署进 `~/.config`**。
   跑随包 Python 的语法门禁必须带 `PYTHONPYCACHEPREFIX`（见 §16.2 第一条命令），
   跑完顺手确认 `find noctalia-mod/modules -name __pycache__` 是空的。
10. **`find … -type d` 不跟软链**：预设/目录清单用的是它，所以软链目录既不会被列出
   也不会被解析（这是想要的行为，见 §4"预设目录本身不接受软链"）。
11. **`((${#arr[@]})) && printf …` 作函数最后一句会返回 1**，`set -e` 下把调用方带崩。
   本项目里所有"打印行"的小函数都在末尾补 `return 0`，新加同类函数照做。
12. **单引号里的反引号会被 shellcheck 报 SC2016（info）**：Markdown 代码围栏写
   `printf '```\n'` 就会踩到，零告警基线立刻被打破。要字面量就加
   `# shellcheck disable=SC2016`（它作用到下一个函数整块）并写清为什么；
   "整段内容是给别的进程的 shell 代码"那种（`test` 的命令替身）更适合用 quoted
   heredoc，那里不报。
13. **命令替换里写全局变量会丢**：`SNAPSHOT_LAST_GUARD` 由 `snapshot_restore` 写，
   调用方要读它就不能写成 `x=$(snapshot_restore …)`——那是子 shell，赋值出不来。
14. **`git status --porcelain` 默认把未跟踪文件算进"脏"**：拿它挡更新会把一个路过的
   临时文件变成永久拦路虎，要带 `--untracked-files=no` 才是"改过已跟踪文件"。
15. **`# shellcheck source-path=` 指令必须写在文件最上面**（shebang 之后、任何注释之前）。
   写在中间时它只对紧跟着的那一条 `source` 生效，同一个文件里后面的 `source` 会被报成
   SC1091——而零告警基线会因为 info 级提示破掉。`source-path=SCRIPTDIR/../../..` 这类
   相对路径是"给 shellcheck 找文件用"的，路径拼法要按它算，不是按脚本里的变量算。
16. **`(($#)) && printf …` 放在 `{ … } > file` 里也一样会返回 1**（PLAN 陷阱 11 的变体）。
   fisher 的所有权账本在"一个文件都还没装"时正好是空列表，于是写入被判成失败、整个动作
   退出 1。复合块里要判断有没有参数，用 `if`，不要用 `&&`。
17. **假命令只挡了 pacman、没挡 paru，测试会真的去编译 AUR 包**。`install fcitx5 --yes`
   里 `rime-ice-git` 是 AUR，`package_aur_helper` 找的是 PATH 上真实的 `paru`——一次
   真实 clone + 构建，整套测试从 100 秒涨到 576 秒，还会因为构建失败而红。假命令目录里
   必须有 `paru`/`yay`（放在单独一层，好让"没有 helper"的用例自己拼 PATH）。

### 16.5 哪些是实测，哪些还只是推理

写结论前先看这张表，别把推理当既成事实。

**实测过**：

- 门禁三连（含随包 Python 与 fish 的语法）、96 个测试、`check` 全绿、`test` 闭环。
- 旧引擎的 471 个用例仍绿（`discover -s tests`）。
- `deps → install → plan → snapshot → rollback → uninstall` 在假命令 + 临时 HOME 下闭环。
- `setup --yes` 从零到配置就位并幂等复跑（树不变、无暂存残留、账本不重复）；
  `setup --with` 的 argv 形状与未声明名字被拒。
- `plan niri` / `deps niri` 不再报别的模块的程序（§10 收口）。
- drift 的四种情形（受管改动报、`__custom__` / preserve / 运行时软链不报、重部署清零、
  目标消失报 missing）；新增：声明成 `MODULE_RUNTIME_WRITES` 的文件改写后不报漂移，
  且下一次部署仍会把它覆盖回仓库版本。
- 用户预设全路径：save 不带 `__custom__`、软链按链接存、保留字/官方同名/非法名被拒、
  覆盖前确认、delete/edit 只动用户预设、单文件目标往返、活跃预设消失后的冻结与回退。
- **阶段 D 的三处缺口都在实机文件上验过**：新项目部署出的壁纸路径是
  `$HOME/图片/Wallpapers`，而本机 `xdg-user-dir PICTURES` = `~/Pictures`、`~/图片`
  不存在（§10 P1-7）；模式已是 `light` 但 `gsettings gtk-theme` 与
  `gtk-3.0/settings.ini` 仍是 dark（§10 P1-8）；Noctalia 会删掉 `kitty.conf` 的
  `BEGIN_KITTY_THEME` 块并把调色板写进 `kitty.conf` / `themes/noctalia.conf` /
  `starship.toml`（§10 P1-9，逐文件 `diff` 过）；旧引擎部署出的 `directory` 是
  `/home/victorxu/Pictures/Wallpapers`（证明旧引擎的改写确实在跑）。
- 修好之后的行为也验过：隔离 HOME 里 `@XDG_PICTURES@` 跟着假的 `xdg-user-dir` 走、
  `theme sync` 写出的两键与 `gsettings` 调用正确、壁纸 no-clobber 幂等、
  `wallpapers remove` 只删账本条目、手写的越界账本条目被拒且 `/etc/passwd` 完好。
- P0-1 的端到端复现、AUR helper 前置确认的顺序契约、并发锁拒绝、以 `command -v`
  为准的运行时程序核对（本机实测：必需程序全部就位，可选只缺 `ddcutil`）。
- **阶段 E 的五条都在隔离环境里跑过**：`doctor` 在健康树上退出 0、删掉部署目标后
  报 `fail` 且退出 1、手改受管文件与造一个暂存残渣都会被点名；`bug` 写出的报告含
  账本、包账本、体检输出与审计尾部（本机实跑并读过一遍内容）；`clean` 的 `-n` 与
  实删只动名字精确匹配的暂存项、放过只长得像的名字与用户文件；`test` 在沙箱里
  走完 setup → 复跑同树 → plan 无漂移 → uninstall 清账本，且不碰调用者 HOME；
  `update` 在本地 bare 远端上实跑过四条路径（脏树拒绝且 HEAD 不动、非交互无
  `--yes` 先拒绝后不拉、`--no-deploy` 只拉不铺、`--yes` 换进程把新代码铺出来并
  更新账本版本）。
- **回滚事务的失败路径是实测的**：故意弄坏快照里一个模块的副本，验证另一个模块
  被放回原样、`pre-restore` 保护快照存在、退出码非零（`test_rollback_is_a_transaction`）。
- **重装后卸载不删配置是实测的**（§10 P2）：连跑两次 `install niri --yes` 再
  `uninstall niri --yes`，`~/.config/niri` 仍在——恢复点是"第二次部署前"的样子。
- **阶段 F 的行为在隔离环境里验过**（`noctalia-mod/tests/`，96 个用例里的新一批）：
  fcitx5 从素材铺到雾凇拼音到设为默认、卸载只还原自己改过的两个值且删除自己建的文件；
  `action fcitx5 deploy` 不动当前主题；fisher 的锁文件拒绝、外来 fisher 拒绝、
  装到一半仍记账并可重试、卸载只删白名单内的自有文件；下载校验失败不留文件、curl 的
  argv 带 `--connect-timeout`/`--max-time`；greeter 在补丁过的项目副本 + 假 systemctl
  上走完"接管 sddm → 重装不动显示管理器 → 卸载放回 sddm"，以及 enable greetd 失败时
  放回上一个显示管理器并回滚文件；系统级模块的元数据校验、隐式选中被排除、账本字段、
  失败时配置退回快照、需要 root 时先 `sudo -v`、`action`/`preset`/`part` 的拒绝路径。
- **假命令必须挡住真实的 AUR helper 这条也是实测的**：不挡的时候
  `install fcitx5 --yes` 会真的让 `paru` 去 clone + 构建 `rime-ice-git`（§16.4 陷阱 17），
  顺带得到一条外部事实：本机那份 PKGBUILD 现在构建不过（`melt_eng.*.bin` 缺失）。

**未实测（只有推理或设计）**：

- **greeter 的特权编排没有在真实系统上跑过**：隔离测试用的是项目副本 + 假
  `systemctl`，把 `/etc/greetd` 等路径重定向进沙箱，并把可信路径检查换成替身
  （替身存在的原因：本机 `/usr/bin` 的属主被映射成 `nobody`，真实的检查在这里永远
  拒绝）。所以"在真机上接管登录界面、失败时放回 sddm"仍然是推理；可信检查本身
  （拒绝用户可写路径与带 shell 元字符的路径）是真代码验过的。
- **fcitx5 的素材与雾凇拼音没在真机上装过**：`rime-ice-git` 是 AUR 包，本机构建失败
  （上游 PKGBUILD 与源码树不同步），所以"皮肤在真 fcitx5 里长什么样、雾凇拼音能不能
  打字"没有依据。
- **fisher 没在真实网络上跑过**：sha256 与镜像顺序按旧引擎那套写的，测试里 curl 是
  替身；真实 GitHub / jsDelivr / gh-proxy 的可达性与内容没有验过。
- **Noctalia 的 `requires_path` 行为只有文档依据**：`05_THEMING_PALETTES_AND_TEMPLATES.md`
  写着 "Skip template if path does not exist"，据此把 nyxmellow 的三节注册放进了
  noctalia 模块的配置。没有在真会话里验过"没装 fcitx5 时这三节真的被跳过"。

- 真实机器上的 `deps`/`install`/`setup` 从未由 agent 跑过——agent 侧 `sudo` 不可用，
  安装路径只能用假命令验证（用户自己可以装包：`shellcheck` 就是他 `pacman -S` 装的）。所以"全新机器上能进桌面、快捷键可用、Noctalia 正常渲染"这句结论
  **还没有依据**，§11 阶段 B 的初始化验收只完成到隔离 HOME 这一层。
- **Noctalia v5.2.1 是否真会在目录缺失时静默空面板**：依据是官方文档 + 上游源码 +
  本机二进制字符串，**没有在真机 niri 会话里实跑**（调研是只读约束）。这条支撑着
  §10 P1-7 的后果判断。
- **"哪些文件会被 Noctalia 就地改写"是逐文件 diff 出来的，不是 Noctalia 的契约**：本机
  确认了 `kitty.conf` / `kitty/themes/noctalia.conf` / `starship.toml` 三处，并据此写了
  `MODULE_RUNTIME_WRITES`。Noctalia 升级后若多写一个文件，`plan` 会重新报漂移——那正是
  §1 想要的信号，但别把这三条声明当成永久契约。另外**没有在实机上跑过 `plan kitty`**
  （本机的新项目从未部署过、状态目录里没有指纹记录；要跑就得先 `install`，那会覆盖作者
  真实的 `~/.config`），"声明了就不报"只在隔离 HOME 的测试里验过。
- 在 niri 会话之外（TTY）跑 `setup` 会怎样：按现有契约，`niri msg action
  reload-config` 失败会导致部署回滚。这是从代码推出的结论，未在 TTY 上实测。
- niri 是否真的会因为缺 `effects.kdl` 而拒绝加载配置：未验证。修复是防御性的
  （随包提供软链），无害但理由未经实机确认。
- **`theme sync` 在真实 Noctalia 会话里的效果**：只验到"它写对了
  `settings.ini` 与 `gsettings`"，没验"GTK 应用真的跟着变了深浅"，也没验模式切换后
  Noctalia 自己会不会顺手把 `color-scheme` 之外的东西也改掉。
- **`@XDG_PICTURES@` 在真实用户目录下的取值**：隔离测试用的是假 `xdg-user-dir`；
  本机真实值是 `~/Pictures`，但中文 locale 机器、或 `user-dirs.dirs` 缺失（真
  `xdg-user-dir` 会答 `$HOME`）这两种形态都没在真机上跑过部署。
- 壁纸的实际观感（Noctalia 面板能不能看到离线那张）没验：那要在真会话里点开面板。
- §3 的程序层声明（`MODULE_REQUIRED_COMMANDS` 等）是逐脚本人工审计的结果，
  不是自动推导出来的。
- shipped 工具的 `import` 与 `MODULE_REPO_PACKAGES` 是否一致：`doctor` 会真去 import
  一次，但那条探测只在**当前解释器**上回答"能不能 import"，不检查声明的包名对不对，
  也不覆盖将来新引入的 import（见 §3 边界）；`python-cairo` 那次仍是人工发现的。
- **`update` 没在真实远端上跑过**：所有验证都用本地 bare 仓库（`git pull` 的协议路径
  一样，但认证、镜像、慢链路没验）。本机 ssh 也是坏的（§16.1），所以 https/ssh 两种
  远端都只是"参数按旧引擎那套写的"。
- **`doctor` 的几项判断是启发式的**：`gsettings` 拿不到值时报 `warn`（不算 `fail`）、
  磁盘阈值写死 10 GiB、`XDG_CURRENT_DESKTOP` 用子串匹配 `niri`；这些都不是契约。
- **`clean` 的暂存命名匹配靠正则**：`.<名字>.noctalia-mod.{new,old,build,uninstall}.<6+ 位>`。
  如果将来 `deploy.sh` 起了新的暂存前缀而没同步这个正则，残渣就会留在盘上（不会误删，
  只是清不掉）。

### 16.6 下一步与待裁决

**阶段 A（基座收口）、B（全新系统初始化闭环的代码部分）、C（内容侧补齐）、
D（运行时能力）、E（运维与自更新）、F（系统级可选模块）都已完成**，逐阶段的交付与
理由见 §11。**阶段 G 已取消**：重构后的项目是独立项目，不接管旧入口，也不需要旧引擎
退役（§11 阶段 G）。

§11 里排的迁移顺序到此走完。**没有既定的下一阶段**——剩下的都是下面这几件要用户
拍板的事，再加上"在真机上用一遍"这条验收。

已拍板的决定散在 §11 各阶段末尾，**别再翻案**；阶段 D 的四项（占位符修法、主题同步
触发时机、运行时写入的建模、壁纸范围）连同实测证据在 §10 P1-7…P1-9 有完整说明，
阶段 E 的五项（`doctor` 的退出码语义与检查面、`bug` 只收自己的状态、`clean` 只清自己
的残渣、`test` 的沙箱边界、`update` 不做状态迁移）在 §11 阶段 E，阶段 F 的六项
（动作契约、`post_install` 的替代、fcitx5、fisher、greeter、gtktheme 判定）在
§11 阶段 F。

要用户拍板的几项，不要自己动：

1. 仓库根 `AGENTS.md` §3 的 `bash -n install.sh configs/.../*.sh` 多文件写法（只检查了
   第一个文件）。要不要一并修掉？见 §16.4 陷阱一。
2. **真实机器上的初始化验收**什么时候做、在什么环境下做？agent 侧 `sudo` 不可用
   （§16.1），所以"全新系统能进桌面、快捷键可用、Noctalia 正常渲染"至今仍是推理。
   阶段 E 的 `test` 解决不了这一条——它不装真包、不进真会话；阶段 F 的 greeter 同理，
   它的特权编排只在补丁过的项目副本 + 假 systemctl 上验过（§16.5）。
3. **重装之后卸载不删配置**（§10 P2）：要不要在账本里多存一个 `first_snapshot`，
   让 `uninstall` 恢复"本项目第一次动它之前"的状态？
4. **`clean` 的系统级缓存清理要不要保留**（§10 P2）：旧引擎那套 pacman/journal/TRIM
   现在没有对应物。阶段 F 建了系统级模块这套机制，要做的话现在有落点了（一个
   `maintenance` 模块），但它是操作系统维护而不是配置管理，仍然待裁决。
5. **模式切换时的实时主题同步怎么接**（§4）：它要指向一个能执行 `theme sync` 的命令，
   而现在这个项目没有二进制在 PATH 上。可选做法：(a) 随 noctalia 模块提供一个
   `theme-sync.sh`，它找 PATH 上的 `noctalia-mod`，找不到就静默退出（等于在没上 PATH
   的机器上不生效）；(b) 干脆不接，靠每次部署收尾同步；(c) 先把 `bin/` 放进 PATH
   这件事定下来再接 hook——那已经是"发布方式"，不属于子项目内部。
6. **要不要在真机上装 fcitx5 模块**（§16.5）：它的 AUR 依赖 `rime-ice-git` 在本机
   构建失败过（`melt_eng.*.bin` 缺失，`install` 报错退出），那是**上游 PKGBUILD 与当前
   源码树不同步**，不是本模块的缺陷；但 agent 侧无法确认修好没有。装之前先自己
   `paru -S rime-ice-git` 试一次。

开工前的固定动作：`git status` 看树、按 §16.2 跑门禁三连建基线、读本节的
§16.1–§16.5，然后才动手。

开工前的固定动作：`git status` 看树、按 §16.2 跑门禁三连建基线、读本节的
§16.1–§16.5，然后才动手。
