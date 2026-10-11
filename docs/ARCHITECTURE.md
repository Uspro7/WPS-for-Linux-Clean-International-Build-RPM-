# 项目结构与定制原理

## 主要文件

| 文件 | 职责 |
| --- | --- |
| `build-rpm.sh` | 下载、解包、定制文件树和生成原生 RPM |
| `src/wps_qm_compat.py` | 为官方中文 QM 添加国际版可使用的兼容翻译索引 |
| `src/wps-locale.sh` | 启动时设置当前用户的 WPS 界面语言 |
| `src/fcitx5xwayland.sh` | Wayland 会话下的输入法环境变量兼容处理 |
| `tests/test_qm_compat.py` | QM 兼容转换的单元测试 |
| `tests/test_rpm_customizations.py` | 配置、字体、组件清理和真实翻译回归检查 |
| `tests/qt_translation_probe.py` | 在独立进程中调用包内 Qt 翻译接口 |
| `repack.sh`、`.source.lock` | 保留的上游历史 DEB 流程，不参与当前 RPM 构建 |
| `docs/legacy/repack.yml.example` | 上游旧工作流参考，不是活动 GitHub Actions 工作流 |

## 国际版核心与中文资源

定制文件树以官方国际版 RPM 为底包，保留它自己的 `default/en_US` 皮肤和核心资源，仅加入中文 `zh_CN` 资源，并使用中文包中的模板。不会将整套中文版本的核心程序覆盖到国际版。

### 本项目新增实现与来源

跨版本 QM 兼容转换器及配套的真实 Qt 查询测试由本项目新增，不是继承的上游重打包功能。上游提供中文资源替换等基础流程；本项目进一步解决国际版核心与新版中文 QM 的索引兼容问题，使三个编辑器的主要工具栏能够使用中文。

实现集中在 `src/wps_qm_compat.py`，测试位于 `tests/test_qm_compat.py` 和 `tests/qt_translation_probe.py`，并由 `tests/test_rpm_customizations.py` 对实际构建载荷进行回归检查。中文译文主要来自官方语言包，只有少量兼容词条另行补充；转换逻辑及验证机制与译文资源的来源应明确区分。

### 为什么只复制语言包还不够

当前国际版底包的编辑器会使用不带消歧义参数的 Qt 翻译查询。所用新版中文语言包中，许多词条按 `source + context` 计算索引，而国际版查询的索引方式与之不同。因此，即使中文 QM 文件存在、启动页也是中文，编辑器里的 Home、Insert 等工具栏仍可能回退英文。

兼容脚本按以下方式补充索引：

1. 从国际版原始英文 QM 收集真实的上下文、源文和消歧义键。
2. 从 UI 的 `.kui/.kuip` XML 收集工具栏和对话框使用的源文；多行按钮同时收集保留换行和空格正规化的形式。
3. 保留中文 QM 的原始消息和索引，追加适合国际版查询方式的条目。
4. 新增条目显式记录上下文、源文和消歧义信息，避免相同哈希或相同英文在不同上下文中的误匹配。
5. 跨上下文复用译文仅限同一源文的已知官方译文一致时；少量旧版或改名词条使用明确的兼容译文。

该处理不修改 WPS 闭源程序二进制。测试直接调用底包的 `libQt5CoreKso.so.5`，验证真实查询能返回“开始、插入、粘贴、字体”等中文以及“格式刷、页眉页脚”等多行按钮译文。

## 当前用户语言配置

三个启动器均加载 `wps-locale.sh`，在以下位置写入配置：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/Kingsoft/Office.conf
```

目标键为：

```ini
[6.0]
languages=zh_CN
```

脚本保留其他设置，已正确设置时不重复写入。首次修改已有配置时创建 `Office.conf.linuxwps-backup`，并为 WPS 进程导出 `LANGUAGE=zh_CN:zh`。这一设计会在每次正常启动时重新选择中文，不提供持久切换英文的启动模式。

## 静态清理范围

主要删除对象包括：

- 官方 `INSTALL` 目录及原包安装钩子。
- `wpscloudsvr`、`wpsd` 服务程序。
- 已知的 `cloudpushsdk`、`kappcenter`、`kcloudfiledialog`、`kclouddocs`、`qing`、`jsapi` 插件目录。
- `ksowebstartup*`、推广桌面入口、更新定时任务及 WPS 自动启动项。
- 金山私有菜单和 `ksoqing` 协议入口。
- 独立 `wpspdf` 程序、启动命令和 PDF 桌面入口。

普通文档 MIME 关联仍然保留。部分名字带有云端或 PDF 字样的共享库是主程序的直接链接依赖，不一概删除，以免破坏启动或导出功能。独立 PDF 应用被移除不等于删除所有 PDF 功能。

这是按已知路径和入口进行的静态处理，不是网络沙箱，也没有阻断所有联网调用。需要严格离线边界的环境，应额外使用系统级网络隔离，并自行验证运行行为。

## 字体与桌面集成

六种符号字体安装在 `/usr/share/fonts/wps-office/`。安装及卸载脚本刷新 fontconfig、图标、桌面应用和 MIME 缓存；不通过隐藏提示来规避缺字体问题。字体集合并不等同于完整的 Windows / Office 字库，文档使用的其他字体仍需用户自行安装。

表格和演示命令分别改名为 `wpset`、`wpswpp`，对应桌面启动项同步更新。输入法脚本在 Wayland 会话中整理 `GTK_IM_MODULE`、`QT_IM_MODULE`、`SDL_IM_MODULE` 和 `XMODIFIERS`，不安装或启动输入法服务，也不将 WPS 改造成原生 Wayland 应用。

## 维护边界

更新底包或中文资源后，需要重新运行兼容转换、真实 Qt 回归测试和三个编辑器的 GUI 检查。不能假设新版语言包必然兼容，也不能只改版本号后沿用本次发行的验证结论。
