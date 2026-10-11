# 发行流程

本项目将脚本、测试和文档提交到 Git，将二进制 RPM 作为 GitHub Release 资产上传。`build/`、官方原始 RPM、字体归档及临时配置不进入源码提交。

## 1. 确定版本

当前版本对应关系：

```text
Git tag:     v11.1.0.11723.XA-4
RPM Version: 11.1.0.11723.XA
RPM Release: 4.linuxwps.fc44
RPM Arch:    x86_64
```

更新 `build-rpm.sh` 的发行号、README、更新记录和对应发行说明，记录实际使用的国际版及中文资源包。不同构建环境的 `%{?dist}` 后缀可能不同。

## 2. 构建与必要验收

```bash
./build-rpm.sh
bash -n build-rpm.sh
sh -n src/wps-locale.sh
python3 -m unittest discover -s tests -v
git diff --check
rpm -Uvh --test --replacepkgs --notriggers build/dist/*.rpm
```

确认完整测试没有因缺少 staging 被跳过。用测试用户或隔离的测试配置打开文字、表格、演示，核对实际中文工具栏、符号字体，以及独立 PDF 入口移除情况；不要干扰已有用户文档或结束无关进程。

## 3. 生成校验文件

在 `build/dist/` 内为本次发行的明确文件名生成校验值，避免混入旧 RPM：

```bash
cd build/dist
sha256sum wps-office-11.1.0.11723.XA-4.linuxwps.fc44.x86_64.rpm > SHA256SUMS
sha256sum -c SHA256SUMS
```

提交前检查暂存区，确保没有原始安装包、凭证、用户配置和临时日志。保留上游来源说明和提交历史。

## 4. 推送与发布

推送对应提交后，创建指向该提交的 tag 和 GitHub Release。以安装了 GitHub CLI 且已登录为例，在仓库根目录执行：

```bash
git tag -a v11.1.0.11723.XA-4 -m 'WPS Linux international clean RPM release 4'
git push origin main
git push origin v11.1.0.11723.XA-4

gh release create v11.1.0.11723.XA-4 \
  --repo Uspro7/WPS-for-Linux-Clean-International-Build-RPM- \
  --verify-tag \
  --title 'WPS Office 11.1.0.11723.XA · 精简中文版 RPM r4' \
  --notes-file docs/releases/v11.1.0.11723.XA-4.md \
  build/dist/wps-office-11.1.0.11723.XA-4.linuxwps.fc44.x86_64.rpm \
  build/dist/SHA256SUMS
```

GitHub CLI 不是构建依赖，也可以通过 GitHub 网页或 API 完成发布。上传期间可先保持 Release 为草稿，待两个资产完整上传后再公开。

## 5. 发布后核对

确认 tag 指向预期提交，Release 已公开且至少包含：

- 对应版本的 `.x86_64.rpm`；
- `SHA256SUMS`。

检查 GitHub 返回的资产大小和上传状态；若返回 SHA-256 digest，应与本地值一致。不要只创建没有资产的 Release，也不要把没有做过的运行时安全或兼容性检查写进发行说明。

上游历史 DEB 工作流已存放在 `docs/legacy/repack.yml.example`，当前没有自动定时构建或自动发布任务。
