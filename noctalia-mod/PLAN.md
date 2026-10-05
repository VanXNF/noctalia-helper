# Noctalia Mod：模块化脚本项目重构计划

> 这是后续分步实施的事实入口和会话交接文档。
> 当前只保存方案，不实现模块代码，不修改旧 Nyxuri 行为。

## 1. 当前调查结论

当前仓库的 Nyxuri 已经具备较完整的配置部署能力，但安装入口、配置部署、依赖管理、状态、预设、主题和运行时脚本仍由 Python 中央路由连接，模块之间存在跨域依赖。

已确认的现状：

- `install.sh` 负责引导、缓存仓库、网络镜像和进入 Python 引擎。
- `nyxuri/` 是当前主运行时，使用 Python 标准库实现。
- `configs/` 保存 niri、Noctalia、Fish、Kitty 等配置源码。
- `assets/` 保存壁纸、Fcitx5 等静态资产。
- 当前已有原子部署、`__custom__` 保留、manifest preserve、预设、零件、快照、回滚、卸载和状态账本能力。
- 当前存在两条需要保持区分的保留机制：
  - 路径名含 `__custom__` 的文件或目录自动保留。
  - manifest 中显式声明的 preserve 路径按名称保留。
- `.module.toml` 和 `.optional-apps.toml` 已经表达了一部分模块依赖和部署例外，但依赖 TOML 解析和中央 Python 逻辑。
- `cli.py`、`core.py`、`deploy`、`state`、`modules`、`deps`、`menus` 之间仍有较多跨域调用。
- Noctalia、niri 仍在多个位置作为默认或特殊对象出现。
- Noctalia、niri 运行时脚本仍会直接读取 `~/.config/niri`、`~/.config/noctalia`、`~/.local/state` 和 `~/.cache`。

调查时以当前源码行为为准，`llms-wiki/` 作为架构契约和设计决策参考。若源码与 Wiki 不一致，实施时必须先记录差异，再决定是否修正文档或保留兼容行为。

## 2. 总体目标与边界

新项目在当前仓库内与旧 Nyxuri 并行存在，项目目录固定为：

```text
noctalia-mod/
```

目标环境：

- CachyOS
- niri
- Noctalia V5

第一版使用 Bash 作为运行时，允许使用系统已有基础工具，不引入 Python 作为新项目运行时依赖。模块协议不把 niri 写死为唯一窗口管理器，但第一阶段只验证 CachyOS+niri+Noctalia V5。

第一阶段目标是完成安装与配置管理闭环：

- 安装入口。
- 模块发现和配置部署。
- 依赖检查与确认安装。
- 原子替换。
- `__custom__` 和 preserve 保留。
- 状态账本。
- 快照、回滚和卸载。
- 隔离环境测试和新旧行为对照。

第一阶段不替换 `install.sh`，不删除或重构旧 Nyxuri，不迁移旧 Nyxuri 状态。

## 3. 目标目录结构

最终目标结构如下：

```text
noctalia-mod/
├── bin/
│   └── noctalia-mod
├── lib/
│   ├── common.sh
│   ├── paths.sh
│   ├── lock.sh
│   ├── package-manager.sh
│   ├── state.sh
│   ├── snapshot.sh
│   ├── deploy.sh
│   └── module-loader.sh
├── modules/
│   ├── niri/
│   ├── noctalia/
│   ├── kitty/
│   ├── fish/
│   └── starship/
├── profiles/
├── tests/
├── PLAN.md
└── README.md
```

每个模块自包含：

```text
modules/<module>/
├── module.conf          # 模块元数据和依赖声明
├── files/               # 默认配置
├── presets/              # 官方预设，可为空
├── parts/                # 可插拔零件，可为空
├── hooks.sh             # 可选生命周期钩子
└── README.md
```

`noctalia-mod/` 内部的代码只通过窄接口通信。中央运行时负责生命周期、事务、状态和安全边界；模块负责自己的配置、依赖声明、例外和验证。

## 4. 模块协议

每个模块必须能够声明：

- 模块 ID。
- 目标配置路径。
- 适用环境或前置条件。
- 官方仓库依赖和可选 AUR 依赖。
- 默认配置源目录。
- 官方 preset。
- 可选 parts。
- 需要保留的路径。
- 需要设置执行权限的路径。
- 部署前检查。
- 部署后 reload 或验证动作。
- 卸载清理规则。
- 模块状态摘要。

默认行为由目录约定驱动，`module.conf` 只声明例外，例如：

- 目标路径。
- 包管理器依赖。
- `preserve` 路径。
- `chmod` 路径。
- preset 和 part 入口。
- reload 命令或验证命令。

第一版不继续让 Bash 解析完整 TOML。现有 `.module.toml` 的信息在迁移时转换为新模块协议，避免引入额外解析器和运行时依赖。

模块 hook 必须满足：

- 使用明确的参数和返回码。
- 不直接修改其他模块的状态。
- 不绕过中央锁、快照和错误传播。
- 不假设某个模块一定已经安装，除非协议显式声明依赖。
- 外部命令使用参数列表调用，不拼接未经校验的用户输入。

## 5. 配置层次与保留规则

保留三层模型，但改为模块内部管理：

1. 默认配置：`modules/<module>/files/`。
2. 官方 preset：`modules/<module>/presets/<name>/`。
3. 用户自定义：目标路径中的 `__custom__` 文件或目录。

preset 状态按模块保存。第一阶段不要求所有模块共享一个不可拆分的全局 preset。未来可通过 `profiles/` 组合多个模块 preset，但不在第一阶段实现复杂桌面级 profile。

目标路径默认仍为：

```text
$HOME/.config/
```

状态目录使用：

```text
$XDG_STATE_HOME/noctalia-mod/
```

未设置 `XDG_STATE_HOME` 时回退到：

```text
$HOME/.local/state/noctalia-mod/
```

缓存和运行时临时目录分别使用：

```text
$XDG_CACHE_HOME/noctalia-mod/
$XDG_RUNTIME_DIR/noctalia-mod/
```

部署时必须继续遵守：

- 不使用软链接写入 `~/.config`。
- `__custom__` 文件和目录按名保留。
- manifest preserve 文件按名保留。
- 回滚时支持关闭 custom 继承，以保证精确恢复。
- 所有目标路径必须经过路径安全校验，禁止脱离目标配置根目录。

## 6. 部署、状态与事务

一次部署按以下阶段执行：

1. 拒绝 root 运行。
2. 加载并校验目标模块。
3. 检查 CachyOS、niri、Noctalia V5 相关环境。
4. 汇总缺失依赖、将要覆盖的路径、保留路径和 reload 动作。
5. 展示 pre-flight 清单。
6. 交互模式要求确认；只有显式 `--yes` 或 express 模式才跳过确认。
7. 在覆盖前创建当前配置快照。
8. 按模块执行原子替换。
9. 执行模块验证和 reload。
10. 成功后写入部署账本。
11. 任一模块失败时，根据部署前快照恢复已修改内容。

默认冲突策略为“预检列清单后确认覆盖”：

- 新项目自己的历史部署可直接更新。
- 其他来源的目标文件必须显示在清单中。
- 非交互模式必须显式传入确认参数。
- 无法判断来源时按外部文件处理，不静默覆盖。

状态账本至少记录：

- 已启用模块。
- 每个模块当前 preset。
- 实际部署路径。
- 部署源版本。
- 部署前快照位置。
- 由本项目安装过的依赖包。
- 仍存在的 preserve 和 custom 路径。
- 最近一次部署结果。

状态写入必须经过锁保护，并使用临时文件加原子替换。

## 7. 快照、回滚与卸载

### 快照和回滚

第一阶段保留完整快照能力：

- 部署前自动生成快照。
- 支持手动创建、列出和删除快照。
- 回滚前创建当前状态保护快照。
- 普通部署继承 `__custom__`。
- 精确回滚不继承当前配置中的新 custom 内容。
- 快照清理不能删除当前回滚目标或保护快照。

### 卸载

卸载默认只移除新项目实际管理的配置：

- 优先恢复最近一次部署前快照。
- 没有可用快照时，只移除账本记录的文件和目录。
- 不删除 `__custom__` 内容。
- 不删除模块声明的外部 preserve 文件。
- 不删除系统软件包。
- 成功后清理状态目录，保留必要的审计信息。

系统软件包不自动卸载，避免删除其他程序共用的依赖。未来若增加显式清理包功能，只能处理账本确认由本项目安装且未被其他模块使用的包。

## 8. 依赖管理

依赖由模块声明，由中央流程统一检查和执行：

- 首选 CachyOS/Arch 官方仓库包。
- 支持声明 AUR 包来源，但不自动安装或引导 AUR helper。
- 优先检测已存在的 `paru` 或 `yay`。
- 没有可用 helper 时明确报告，不静默改变系统。
- 安装前统一汇总依赖并确认。
- 依赖安装失败时不开始配置覆盖。
- 依赖检查、安装和配置部署分为独立阶段，便于重试。

## 9. 第一批模块

第一阶段只迁移以下五个核心模块：

- `niri`
- `noctalia`
- `kitty`
- `fish`
- `starship`

迁移重点：

- niri：默认配置、monitor preserve、effects/glow parts、脚本权限和安全部署。
- noctalia：Noctalia V5 配置和必要模板，不迁移主题同步、壁纸 hook 或运行时工具。
- kitty：配置和必要 reload。
- fish：配置目录和自定义文件保留。
- starship：单文件配置和最小状态处理。

后续再按同一协议迁移 `fastfetch`、`xdg-desktop-portal`、`zed` 等模块。

## 10. 与旧 Nyxuri 的关系

新旧项目并行存在：

- 不修改现有 `install.sh`。
- 不让旧入口自动切换到 `noctalia-mod`。
- 不读取或迁移 `~/.config/nyxuri` 中的 active preset、快照索引和账本。
- 现有 `~/.config/niri`、`~/.config/noctalia` 可以被识别为外部配置并在 pre-flight 中提示冲突。
- 新项目稳定前，旧 Nyxuri 继续作为行为参考和回退路径。
- 新旧部署结果在隔离 HOME 中对照验收后，再决定是否增加 opt-in 接入。

## 11. 暂不实现的内容

第一阶段明确不实现：

- 主题同步。
- 壁纸管理。
- mpvpaper、Wallpaper Picker、Orbit 等运行时工具。
- niri 快捷键和 scratchpad 行为重构。
- Noctalia IPC/CLI 封装。
- Fcitx5、greeter、GTK 主题迁移。
- Python 与 Bash 混合运行时。
- 旧 Nyxuri 状态迁移。
- 自动安装 AUR helper。
- 系统软件包自动卸载。
- 跨发行版兼容承诺。
- 通过新项目直接替换旧 `install.sh`。

这些能力只在模块协议中预留生命周期和能力声明，不在第一阶段创建实际实现。

## 12. 分步实施顺序

### 第 0 步：骨架与契约

- 创建 `noctalia-mod/bin/`、`lib/`、`modules/`、`profiles/`、`tests/`。
- 实现 CLI 参数解析、路径计算、root 检查、锁和统一错误码。
- 定义模块加载和元数据校验。
- 先建立隔离测试框架，再写部署逻辑。

### 第 1 步：部署核心

- 实现 pre-flight 计划生成。
- 实现目标路径安全检查。
- 实现文件和目录原子替换。
- 实现 `__custom__` 与 preserve 保留。
- 实现部署事务和失败恢复。

### 第 2 步：状态与快照

- 实现状态账本。
- 实现自动快照、手动快照、回滚和快照清理。
- 实现模块级 preset 状态。
- 实现卸载和配置恢复。

### 第 3 步：依赖流程

- 实现依赖检查。
- 实现统一依赖确认。
- 实现 pacman 和已存在 AUR helper 的参数构造。
- 记录由本项目安装的依赖，但默认不自动卸载。

### 第 4 步：迁移 niri 和 noctalia

- 先迁移 niri，覆盖 preserve、parts、权限和回滚。
- 再迁移 Noctalia V5 配置。
- 对照现有 Nyxuri 在隔离 HOME 中的部署结果。

### 第 5 步：迁移 Kitty、Fish、Starship

- 按相同协议接入三个基础模块。
- 验证单模块安装、组合安装、独立卸载和部分失败恢复。

### 第 6 步：对照验收和文档同步

- 汇总新旧行为差异。
- 确认没有依赖、路径、状态和卸载残留。
- 更新对应 `llms-wiki/` 页面和 `llms-wiki/llms.txt` 索引。
- 不在没有验收前修改旧入口。

## 13. 测试与验收标准

新项目使用标准库测试驱动，不新增 Bats 等运行时依赖。所有测试使用临时 HOME 和假的外部命令环境，不能污染真实 `~/.config`。

必须覆盖：

- 模块发现和元数据校验。
- 依赖检查和包管理器参数形状。
- pre-flight 清单生成。
- 用户拒绝确认时不发生写入。
- 文件和目录原子替换。
- `__custom__` 文件、目录和嵌套路径保留。
- manifest preserve 路径保留。
- preset 切换。
- parts 选择和恢复。
- 快照创建、清理、保护和回滚。
- 部署中途失败后的自动恢复。
- 并发锁和状态原子写入。
- 卸载不删除 custom/preserve 内容。
- root 拒绝。
- `--yes`/express 模式行为。
- reload 命令参数列表形状。
- CachyOS+niri+Noctalia 环境检测。

每一步实现后至少运行：

```bash
python3 -m compileall -q nyxuri
python3 -m unittest discover -s tests -q
bash -n install.sh noctalia-mod/bin/noctalia-mod noctalia-mod/lib/*.sh noctalia-mod/modules/*/*.sh
shellcheck install.sh noctalia-mod/bin/noctalia-mod noctalia-mod/lib/*.sh noctalia-mod/modules/*/*.sh
```

新项目自身至少应支持以下隔离验收命令：

```bash
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod list
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod plan niri noctalia
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod install niri noctalia --yes
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod snapshot
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod rollback
HOME=$(mktemp -d) noctalia-mod/bin/noctalia-mod uninstall niri noctalia
```

## 14. 后续会话执行约束

后续开始实现时必须：

1. 先读取本文件和相关 `llms-wiki/` 页面。
2. 修改前检查 `git status`。
3. 对路径、状态、部署、manifest 和模块行为有疑问时，全仓库检索引用。
4. 不把旧 Nyxuri 的实现直接复制为新项目中央核心。
5. 每一步保持新旧项目可并行运行。
6. 每个模块独立测试，不依赖其他模块的隐式副作用。
7. 不使用软链接写入 `~/.config`。
8. 不在安装循环中增加无必要的阻断式确认。
9. 破坏性操作前统一生成清单并确认。
10. 涉及架构、部署、状态、模块、manifest 或 CLI 的代码变更，必须同步核验并更新 `llms-wiki/`。
11. 不主动提交 Git commit。
12. 不新增调试输出、注释掉的代码或未完成的 TODO。

## 15. 当前默认假设

- 新项目目录为 `noctalia-mod/`。
- 新项目入口为 `noctalia-mod/bin/noctalia-mod`。
- 第一阶段锁定 CachyOS，但保留未来扩展接口。
- 不兼容旧 Nyxuri 状态，只安全识别和提示目标文件冲突。
- 保留默认配置、官方 preset、`__custom__` 三层模型。
- 依赖由中央流程统一检查，并在确认后安装。
- 卸载默认不删除系统软件包。
- Bash 负责新项目运行时，标准库测试负责行为验证。
- 本文件是方案和会话交接文档，不是运行时配置，不应被部署到 `~/.config`。
