# 工作流修改记录

本文档记录了 .github/workflows 目录下被修改过的工作流文件，在从上游 openclaw/openclaw 合并更新时需要保留这些修改。

## 修改过的工作流文件

### 1. auto-response.yml

**修改内容：**
- 移除了对官方 GitHub App 的依赖（app-id: 2729701, 2971289）
- 移除了对 `maintainer` 团队的引用
- 简化了自动回复逻辑，仅保留欢迎新 issue 的功能
- 移除了自动关闭 issue/PR 的复杂规则

**原因：**
- 官方 GitHub App 是 OpenClaw 官方私有应用，fork 仓库无法使用
- fork 仓库没有 `maintainer` 团队配置
- 简化的欢迎消息更适合 Termux fork 仓库

### 2. labeler.yml

**修改内容：**
- 移除了对官方 GitHub App 的依赖
- 移除了对 `maintainer` 团队的引用
- 移除了 `trusted-contributor` 和 `experienced-contributor` 标签逻辑
- 仅保留 PR 大小标签（size: XS/S/M/L/XL）的自动应用功能

**原因：**
- 官方 GitHub App 不可用于 fork 仓库
- 贡献者标签逻辑依赖于官方的团队和合并历史统计

### 3. ci.yml

**修改内容：**
- 将 `blacksmith-16vcpu-ubuntu-2404` 等特殊 runner 改为标准的 `ubuntu-latest`
- 移除了 macOS、Windows、Android 等平台的测试矩阵
- 移除了对内部 actions 的引用（如 `.github/actions/setup-node-env`）
- 使用标准的 actions 替代（actions/setup-node@v4, pnpm/action-setup@v4）
- 移除了 bun 运行时测试
- 移除了 secret scanning 和 zizmor 安全审计
- 添加了 Termux 专属的 `termux-build` 任务

**原因：**
- Blacksmith runner 是官方专用的付费 runner
- 内部 actions 在 fork 仓库中不存在
- Termux fork 主要关注 Linux/Android 平台
- 简化 CI 流程，加快反馈速度

### 4. docker-release.yml

**修改内容：**
- 将 `useblacksmith/*` actions 改为标准的 `docker/*` actions
- 将 `blacksmith-16vcpu-ubuntu-2404(-arm)` runner 改为 `ubuntu-latest`
- 使用 Docker Buildx 的标准缓存

**原因：**
- Blacksmith 专用 actions 在 fork 仓库中不可用
- 标准 Docker actions 功能相同且更通用

### 5. install-smoke.yml

**修改内容：**
- 将 `blacksmith-16vcpu-ubuntu-2404` runner 改为 `ubuntu-latest`
- 使用标准的 actions 替代内部 actions
- 移除了对官方安装脚本的测试
- 添加了 Termux 安装脚本的存在性检查

**原因：**
- 官方的 install.sh 测试不适用于 Termux fork
- Termux 有自己的安装脚本 Install_termux_cn.sh

## 未修改的文件

### workflow-sanity.yml

**状态：** 保留原样

**原因：** 这是一个通用的工作流检查工具，不依赖特定配置，可以直接使用。

## 新增的文件

### docs/WORKFLOW-MODIFICATIONS.md（本文件）

记录所有工作流修改，方便下次升级时参考。

### .github/workflows/cleanup.yml

自动清理超过 7 天的 artifacts 和 workflow runs，防止 GitHub Actions 存储超限。

**触发条件：**
- 每周日凌晨 3 点自动运行
- 或手动触发（workflow_dispatch）

**清理内容：**
- 超过 7 天的 artifacts
- 超过 7 天且已完成的 workflow runs

## 升级时的操作建议

当从上游 `openclaw/openclaw` 合并更新时：

1. **方案 A - 保留本地修改：**
   ```bash
   git merge upstream/main --no-commit
   # 对于上述工作流文件，使用 git checkout --ours 保留本地版本
   git checkout --ours .github/workflows/auto-response.yml
   git checkout --ours .github/workflows/labeler.yml
   git checkout --ours .github/workflows/ci.yml
   git checkout --ours .github/workflows/docker-release.yml
   git checkout --ours .github/workflows/install-smoke.yml
   git commit -m "Merge upstream main, preserve Termux workflow modifications"
   ```

2. **方案 B - 手动对比合并：**
   ```bash
   git merge upstream/main --no-commit
   # 仔细对比每个工作流文件的新变化
   # 手动将上游的新功能合并到本地修改版本中
   ```

## 检查清单

每次升级后，确认以下内容：

- [ ] `.github/workflows/auto-response.yml` 保留 Termux 简化版本
- [ ] `.github/workflows/labeler.yml` 保留简化的 PR 大小标签功能
- [ ] `.github/workflows/ci.yml` 保留标准 runner 和简化配置
- [ ] `.github/workflows/docker-release.yml` 保留标准 Docker actions
- [ ] `.github/workflows/install-smoke.yml` 保留 Termux 安装脚本检查
- [ ] CI 工作流能够正常运行
- [ ] Docker 构建能够正常执行

## 备注

- 如果上游工作流有重大改进（如新的安全检查、性能优化等），应该评估是否值得将改进应用到 Termux 版本
- 保持工作流的简洁性和可维护性是首要目标
