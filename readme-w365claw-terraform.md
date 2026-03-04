# W365Claw

使用 Terraform 和 Azure VM Image Builder 自动构建 Windows 365 开发者镜像。生成预装完整开发工具链的 Azure Compute Gallery 镜像，可直接用于 Windows 365 Cloud PC 预配。

AI 代理（OpenClaw、Claude Code、Codex CLI）通过 Intune 在用户上下文中**于预配后交付** —— 不嵌入镜像。镜像负责运行时、开发工具、企业策略和配置模板。

## 配套书籍

本仓库是 **[使用 Windows 365 部署 OpenClaw：自定义镜像工程与部署实践指南](https://github.com/kkaminsk/W365ClawBook)**（作者：Kevin Kaminski，Windows 365 方向 Microsoft MVP）的配套代码。该书涵盖完整的端到端架构、安全模型、构建流水线和运维手册。下载 [PDF](https://raw.githubusercontent.com/kkaminsk/W365ClawBook/main/W365Claw.pdf)。

## 镜像内容

| 类别 | 组件 |
|---|---|
| **运行时** | Node.js 24.x、Python 3.14.x、PowerShell 7.4.x |
| **开发工具** | VS Code（系统安装）、Git 2.53.x、GitHub Desktop、Azure CLI 2.83.x |
| **企业配置** | Claude Code managed-settings.json、OpenClaw 通过 Active Setup 进行配置注入、VS Code 右键菜单集成 |
| **安全** | SBOM 生成、SHA-256 安装包校验、固定软件版本 |

## 预配后交付内容（通过 Intune）

| 组件 | 机制 |
|---|---|
| **OpenClaw** | Intune Win32 应用（按用户，`npm install -g openclaw`） |
| **Claude Code** | Intune Win32 应用（按用户，`npm install -g @anthropic-ai/claude-code`） |
| **OpenAI Codex CLI** | Intune Win32 应用（按用户） |
| **OpenSpec** | Intune Win32 应用（按用户） |
| **API 密钥** | Intune 脚本（用户上下文环境变量） |
| **VS Code 扩展** | Intune 脚本（GitHub Copilot 等） |
| **代理技能 / MCP 配置** | 通过 Active Setup 从 ProgramData 模板注入 |

## 架构

```
W365Claw/
├── terraform/
│   ├── main.tf                          # 根模块 - 编排 gallery、identity、image-builder
│   ├── variables.tf                     # 所有可配置输入及默认值
│   ├── outputs.tf                       # Gallery ID、构建日志信息、后续步骤指南
│   ├── versions.tf                      # Provider 要求（azurerm、azapi、time）
│   ├── terraform.tfvars                 # 环境特定值（已加入 git-ignore）
│   └── modules/
│       ├── gallery/                     # Azure Compute Gallery + 兼容 W365 的镜像定义
│       ├── identity/                    # 用户分配的托管标识 + 最小权限 RBAC
│       └── image-builder/               # AIB 模板及分阶段内联 PowerShell 自定义器
├── scripts/
│   ├── Initialize-BuildWorkstation.ps1  # 先决条件检查与安装程序
│   ├── Initialize-TerraformVars.ps1     # 从租户上下文生成 terraform.tfvars
│   └── Teardown-BuildResources.ps1      # 定向拆除（保留 Gallery 资源）
├── openspec/
│   └── changes/                         # OpenSpec 提案：设计、规范与任务追踪
├── CLAUDE.md                            # Claude Code 项目上下文
├── ConfigurationSpecification.md        # 完整配置规范
├── TerraformApplicationSpecification.md # Terraform HCL 规范与运维手册
├── TerraformAudit.md                    # 工程审计发现与修复状态
└── supply-chain-integrity.md            # SBOM 与供应链文档
```

## 先决条件

- Terraform >= 1.5
- Azure CLI >= 2.60
- Git >= 2.40
- Az PowerShell 模块 >= 12.0（用于构建后验证）
- Azure 订阅需注册以下资源提供程序：
  - `Microsoft.Compute`
  - `Microsoft.VirtualMachineImages`
  - `Microsoft.Network`
  - `Microsoft.ManagedIdentity`

## 快速入门

运行先决条件脚本自动检查并安装所有依赖：

```powershell
# 交互模式 - 每次安装前提示确认
.\scripts\Initialize-BuildWorkstation.ps1

# 非交互模式 - 无需确认直接安装
.\scripts\Initialize-BuildWorkstation.ps1 -Force
```

从租户上下文生成 `terraform.tfvars`：

```powershell
.\scripts\Initialize-TerraformVars.ps1
```

脚本会检查所有先决条件、安装缺失项（通过 winget）、登录 Azure、注册资源提供程序并运行 `terraform init`。详见 [ConfigurationSpecification.md](ConfigurationSpecification.md)。

## 快速开始

```powershell
Set-Location terraform

# 初始化
terraform init

# 计划
terraform plan -var-file="terraform.tfvars" -out tfplan

# 应用（部署基础设施 + 触发镜像构建）
terraform apply tfplan

# 构建完成并验证镜像后，拆除构建资源
# 注意：请勿运行 `terraform destroy` - Gallery 资源设有 prevent_destroy = true。
# 请使用定向拆除脚本：
..\scripts\Teardown-BuildResources.ps1
```

## 版本升级

```powershell
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=true'

# 试点验证通过后，推广为最新版本
terraform apply `
  -var='image_version=1.1.0' `
  -var='exclude_from_latest=false'
```

## 验证镜像

```powershell
Get-AzGalleryImageVersion `
  -ResourceGroupName "rg-w365-images" `
  -GalleryName "acgW365Dev" `
  -GalleryImageDefinitionName "W365-W11-25H2-ENU" |
  Format-Table Name, ProvisioningState, PublishingProfile
```

## Windows 365 合规性

镜像定义包含 Windows 365 ACG 导入所需的所有功能标志：

| 功能 | 值 |
|---------|-------|
| 受信任的启动 | 已启用 |
| 休眠 | 已启用 |
| NVMe 磁盘控制器 | 已启用 |
| 加速网络 | 已启用 |
| Hyper-V 代次 | V2 |
| 架构 | x64 |
| 操作系统状态 | 通用化 |

## 文档

- **[ConfigurationSpecification.md](ConfigurationSpecification.md)** — 完整配置规范及构建工作站设置
- **[TerraformApplicationSpecification.md](TerraformApplicationSpecification.md)** — 完整 Terraform HCL 规范、运维手册及安全注意事项
- **[TerraformAudit.md](TerraformAudit.md)** — 工程审计发现与修复状态
- **[supply-chain-integrity.md](supply-chain-integrity.md)** — SBOM 生成与供应链文档
- **[W365ClawBook](https://github.com/kkaminsk/W365ClawBook)** — 配套书籍，包含完整架构、安全模型与运维指南

## 成本

构建期基础设施（标识、AIB 模板、构建虚拟机）可在构建后移除。Gallery 和镜像版本受 `prevent_destroy` 保护，持久保留用于 Windows 365 预配。

**工作流：** `terraform apply` → 等待构建（约 75-120 分钟）→ 验证 → `.\scripts\Teardown-BuildResources.ps1`

## 许可证

参见 [LICENSE](LICENSE)。
