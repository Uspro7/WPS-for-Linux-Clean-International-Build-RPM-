# 构建与测试

## 环境要求

当前构建和验收环境为 Fedora 44 x86_64。需要 Bash、Python 3、RPM 构建工具，以及常见 GNU 命令行工具。

```bash
sudo dnf install git rpm-build rpm cpio wget curl unzip python3 fontconfig
```

脚本检查 `rpmbuild`、`rpm`、`rpm2cpio`、`cpio`、`wget`、`curl`、`unzip`、`sha256sum` 和 `python3`。字体测试还需要 `fc-scan`。不需要安装系统 Qt 开发包，真实翻译检查使用 WPS 包内自带的 Qt 运行库。

构建时使用普通用户，不要以 root 执行整个构建脚本。首次运行需要联网，下载、解包和重打包会占用数 GB 空间。

## 构建入口

在仓库根目录运行：

```bash
./build-rpm.sh
```

脚本按自身所在目录定位工作区，不要求固定的绝对路径。生成的安装包在 `build/dist/`。

## 本次发行使用的输入

| 类型 | 文件 |
| --- | --- |
| 官方国际版底包 | `wps-office-11.1.0.11723.XA-1.x86_64.rpm` |
| 官方中文资源包 | `wps-office-12.1.2.28080.AK.preread.sw.Personal-1-765475.x86_64.rpm` |
| 符号字体归档 | `wps_symbol_fonts.zip` |

国际版底包决定程序及 RPM 的主版本，中文包只提供语言资源和模板，不替换国际版核心程序。

字体归档来自 `Rongronggg9/wps-fonts` 的 `publish` 发行版，脚本固定检查以下 SHA-256：

```text
01e965dc81167ae816b3bbd7076986bf2fb64a2c456a077df677f8882dabcbe2
```

当前脚本没有为两个官方 RPM 固定 SHA-256，不应将字体校验描述为全链路供应链校验。请从官方来源取得输入文件，并自行保存其校验值。

## 来源解析和缓存

1. 优先查找 `build/raw/` 中的国际版 `wps-office-*.XA-*.x86_64.rpm`。
2. 优先查找同目录中的中文资源包 `wps-office-*.Personal-*.x86_64.rpm`。
3. 找不到国际版缓存时，下载脚本指定的 `11.1.0.11723.XA` 官方 RPM。
4. 找不到中文包缓存时，尝试解析官方中文下载页；解析失败则使用脚本内的固定备用地址。
5. 缺少字体归档时下载，并核对固定哈希。

同类源包存在多个文件时，脚本按文件名排序取第一个，不会自动选择最高版本。要构建指定组合，建议每类只保留一个源包。

已存在且非空的解包目录会被复用。**更换任一官方 RPM 后，必须先删除旧解包缓存**：

```bash
rm -rf build/extracted
./build-rpm.sh
```

这只删除项目的构建缓存，不操作系统安装目录。已有下载文件也会被复用，下载中断产生的残缺 RPM 应删除后重新下载。

## 构建目录

```text
build/
├── raw/                 下载的原始 RPM、字体归档
├── extracted/
│   ├── int_base/         国际版解包结果
│   └── chn_l10n/         中文语言资源及模板
├── repack/               已完成定制的文件树
├── rpmbuild/             临时 SPEC、SOURCES、BUILDROOT 等
└── dist/                 最终发行 RPM
```

每次定制都会重新生成 `build/repack/` 和 `build/rpmbuild/`；构建成功复制产物前，会清理 `build/dist/` 中旧的 RPM。不要在这些目录存放需要保留的手工修改。

## 流水线

```text
依赖检查 -> 解析来源 -> 下载缺失文件 -> 读取 RPM 元数据
         -> 解包 -> 注入中文及兼容索引 -> 清理组件
         -> 安装字体、调整启动器 -> 生成 SPEC -> rpmbuild
```

RPM 使用 `4.linuxwps%{?dist}` 发行号，发行版后缀由构建环境的 RPM 宏决定；Fedora 44 下生成 `.fc44`。载荷采用 zstd 压缩。RPM 包名仍为 `wps-office`，不会与同路径的官方包隔离安装。

## 快速验证

语法和纯源码测试可以先运行：

```bash
bash -n build-rpm.sh
sh -n src/wps-locale.sh
python3 -m unittest discover -s tests -p test_qm_compat.py -v
git diff --check
```

完整构建后运行：

```bash
python3 -m unittest discover -s tests -v
rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' build/dist/*.rpm
rpm -Uvh --test --replacepkgs --notriggers build/dist/*.rpm
```

最后一条仅做安装事务测试，不会安装；依赖检查结果取决于当前系统。部分 payload 测试在缺少 `build/repack/` 时会跳过，纯源码测试通过不能替代最终 RPM 验收。

测试覆盖 QM 原始消息保留、上下文区分、多行 XML 翻译键、语言配置幂等性、六种字体、独立 PDF 移除，以及包内真实 Qt 的工具栏翻译查询。完整验收还需打开三个编辑器检查实际界面，不应仅以语言文件存在作为汉化成功依据。
