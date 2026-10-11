# 安装及故障排查

## 1. 确认安装的是本项目发行包

```bash
rpm -q wps-office
command -v wps wpset wpswpp
```

本次发行预期为 `wps-office-11.1.0.11723.XA-4.linuxwps.fc44.x86_64`。若仍是较低发行号，请先保存文档、退出所有 WPS 窗口，再安装新包。不要让旧进程继续使用已经被替换的资源文件。

遇到包冲突时先确认已有软件的来源和路径。Flatpak、手动解压版或其他重打包版本可能有独立桌面入口；安装 RPM 不会自动移除它们。不要直接使用 `rpm --force` 或批量删除不明目录。

## 2. 启动页中文，编辑器工具栏仍是英文

这个症状通常不能仅靠修改语言选项解决。本发行版同时包含中文资源、兼容翻译索引和语言启动脚本。

先确认安装版本，并从终端用 `wps`、`wpset`、`wpswpp` 启动，而不是直接运行 `/opt` 下的内部二进制。检查配置：

```bash
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
grep -A8 '^\[6\.0\]' "$config_root/Kingsoft/Office.conf"
```

应有 `languages=zh_CN`。不要只验证启动页，要分别新建文字、表格和演示文档，查看“开始、插入”等工具栏。若使用的是自行构建的新版本，请运行完整测试并记录底包及语言包版本。

启动器会重新选择中文，手工把这个键改成英文不会持久生效。

## 3. 提示缺少 Symbol、Wingdings 等字体

先关闭 WPS，再刷新并检查字体：

```bash
fc-cache -f
fc-list : family | grep -Ei 'Symbol|Wingdings|Webdings|MT Extra'
rpm -ql wps-office | grep '/usr/share/fonts/wps-office/'
```

预期包含 Symbol、Wingdings、Wingdings 2、Wingdings 3、Webdings、MT Extra。若字体文件缺失，请确认没有安装旧发行包，或检查：

```bash
rpm -V wps-office
```

六种符号字体用于解决对应警告，不涵盖文档中的全部字体。宋体、微软雅黑等其他字体缺失仍可能导致排版变化。

## 4. Wayland 下不能输入中文

本项目包含 Fcitx5 环境变量兼容脚本，但系统仍需自行安装和配置 Fcitx5，并运行 XWayland。

```bash
printf '%s\n' "$XDG_SESSION_TYPE" "$QT_IM_MODULE" "$XMODIFIERS"
```

请从项目提供的三个启动命令进入。如果其他应用也不能输入中文，应先处理系统输入法配置；本项目脚本不会启动输入法服务。提交问题时附上桌面环境、会话类型和上述环境变量，不要附带完整环境或凭证。

## 5. 为什么没有 WPS PDF

这是预期行为：项目不安装独立 PDF 应用及其桌面入口。查看 PDF 请使用其他阅读器；文字、表格和演示的导出 PDF 功能仍保留相关库支持。不要为了清理独立程序而手工删除所有 `*pdf*.so` 文件。

## 6. 安装提示没有签名或依赖不满足

本项目 RPM 未签名。先通过同一发行版提供的 `SHA256SUMS` 检查文件完整性，再决定是否信任该发布来源；校验值不替代签名。若本机强制要求本地包签名，可按组织策略自行签名，不建议关闭全局签名校验。

Fedora 以外的系统没有经过本次验收。遇到依赖或 ABI 问题时，不要使用 `--nodeps` 强行安装，应在目标系统上自行构建并验证，或使用已验证环境。

## 7. 配置备份与卸载

首次修改已有语言配置时的备份位于：

```text
${XDG_CONFIG_HOME:-$HOME/.config}/Kingsoft/Office.conf.linuxwps-backup
```

需要恢复时先保存文档并退出所有 WPS，再备份当前配置并还原所需内容。只要仍使用本项目启动器，下次启动仍会重新设置中文。

```bash
sudo dnf remove wps-office
```

卸载不会主动删除用户文档和用户配置。不要为了卸载软件而删除整个 `~/Documents` 或整个 `~/.config/Kingsoft`。

## 反馈问题

请提供发行包文件名、发行版和桌面环境、会话类型、复现步骤及必要截图。请先去除文档内容、账号、令牌等个人信息。
