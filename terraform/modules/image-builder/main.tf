# ── Build timestamp (stored in state, avoids perpetual diff from timestamp()) ──
resource "time_static" "build_time" {}

locals {
  # Build a unique template name per version to allow parallel builds
  template_name = "aib-w365-dev-ai-${replace(var.image_version, ".", "-")}"

  # End-of-life date: 90 days from build (uses time_static to avoid perpetual diff)
  end_of_life_date = timeadd(time_static.build_time.rfc3339, "2160h") # 90 days × 24 hours

  # ── Inline PowerShell Scripts ──
  # All scripts are embedded directly in the AIB template as inline
  # PowerShell customizers. No storage account is required.

  customizers = [
    # ── Phase 1: Core Runtimes (Node.js, Python, PowerShell 7) ──
    {
      type        = "PowerShell"
      name        = "InstallCoreRuntimes"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"
        $ProgressPreference = "SilentlyContinue"

        function Update-SessionEnvironment {
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"
            Write-Host "[PATH] Session environment refreshed"
        }

        function Get-InstallerWithRetry {
            param([string]$Uri, [string]$OutFile, [int]$MaxRetries = 3)
            for ($i = 1; $i -le $MaxRetries; $i++) {
                try {
                    Write-Host "[DOWNLOAD] Attempt $i of $MaxRetries : $Uri"
                    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
                    return
                } catch {
                    if ($i -eq $MaxRetries) { throw }
                    Write-Host "[DOWNLOAD] Attempt $i failed, retrying in 10 seconds..."
                    Start-Sleep -Seconds 10
                }
            }
        }

        function Test-InstallerHash {
            param([string]$FilePath, [string]$ExpectedHash)
            if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
                Write-Host "[INTEGRITY] No SHA256 provided for $(Split-Path $FilePath -Leaf) - skipping verification"
                return
            }
            $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
            if ($actual -ne $ExpectedHash.ToUpper()) {
                Write-Error "[INTEGRITY] SHA256 MISMATCH for $(Split-Path $FilePath -Leaf)! Expected: $ExpectedHash Got: $actual"
                exit 1
            }
            Write-Host "[INTEGRITY] SHA256 verified for $(Split-Path $FilePath -Leaf)"
        }

        # === NODE.JS ===
        $NodeVersion = "${var.node_version}"
        $NodeMsiUrl = "https://nodejs.org/dist/$NodeVersion/node-$NodeVersion-x64.msi"
        $NodeInstaller = "$env:TEMP\node-$NodeVersion-x64.msi"

        Write-Host "=== Installing Node.js $NodeVersion ==="
        Get-InstallerWithRetry -Uri $NodeMsiUrl -OutFile $NodeInstaller
        Test-InstallerHash -FilePath $NodeInstaller -ExpectedHash "${var.node_sha256}"

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$NodeInstaller`" /qn /norestart ALLUSERS=1 ADDLOCAL=ALL" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Node.js installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Node.js: $(node --version)"
        Write-Host "[VERIFY] npm: $(npm --version)"

        # === PYTHON ===
        $PythonVersion = "${var.python_version}"
        $PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"
        $PythonInstaller = "$env:TEMP\python-$PythonVersion-amd64.exe"

        Write-Host "=== Installing Python $PythonVersion ==="
        Get-InstallerWithRetry -Uri $PythonUrl -OutFile $PythonInstaller
        Test-InstallerHash -FilePath $PythonInstaller -ExpectedHash "${var.python_sha256}"

        $proc = Start-Process -FilePath $PythonInstaller `
            -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 Include_test=0 Include_launcher=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Python installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Python: $(python --version)"
        python -m pip install --upgrade pip --quiet
        Write-Host "[VERIFY] pip: $(python -m pip --version)"

        # === POWERSHELL 7 ===
        Write-Host "=== Installing PowerShell 7 ==="
        $PwshVersion = "${var.pwsh_version}"
        $PwshUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/PowerShell-$PwshVersion-win-x64.msi"
        $PwshInstaller = "$env:TEMP\PowerShell-7-x64.msi"
        Get-InstallerWithRetry -Uri $PwshUrl -OutFile $PwshInstaller
        Test-InstallerHash -FilePath $PwshInstaller -ExpectedHash "${var.pwsh_sha256}"

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$PwshInstaller`" /qn /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=0 REGISTER_MANIFEST=1 USE_MU=0 ENABLE_MU=0 ADD_PATH=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "PowerShell 7 installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] PowerShell 7 installed"

        # === CLEANUP ===
        Remove-Item -Path $NodeInstaller, $PythonInstaller, $PwshInstaller -Force -ErrorAction SilentlyContinue
        Write-Host "=== Phase 1 Complete: Runtimes installed ==="
        exit 0
        PWSH
      ]
    },
    # ── Restart after runtime installation ──
    {
      type                = "WindowsRestart"
      restartCommand      = "shutdown /r /f /t 5 /c \"Restart after runtime installation\""
      restartTimeout      = "10m"
      restartCheckCommand = "powershell -command \"node --version; python --version\""
    },
    # ── Phase 2: Developer Tools (VS Code, Git, GitHub Desktop) ──
    {
      type        = "PowerShell"
      name        = "InstallDevTools"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"
        $ProgressPreference = "SilentlyContinue"

        function Update-SessionEnvironment {
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"
        }

        function Get-InstallerWithRetry {
            param([string]$Uri, [string]$OutFile, [int]$MaxRetries = 3)
            for ($i = 1; $i -le $MaxRetries; $i++) {
                try { Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing; return }
                catch { if ($i -eq $MaxRetries) { throw }; Start-Sleep -Seconds 10 }
            }
        }

        function Test-InstallerHash {
            param([string]$FilePath, [string]$ExpectedHash)
            if ([string]::IsNullOrWhiteSpace($ExpectedHash)) {
                Write-Host "[INTEGRITY] No SHA256 provided for $(Split-Path $FilePath -Leaf) - skipping verification"
                return
            }
            $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
            if ($actual -ne $ExpectedHash.ToUpper()) {
                Write-Error "[INTEGRITY] SHA256 MISMATCH for $(Split-Path $FilePath -Leaf)! Expected: $ExpectedHash Got: $actual"
                exit 1
            }
            Write-Host "[INTEGRITY] SHA256 verified for $(Split-Path $FilePath -Leaf)"
        }

        # === VISUAL STUDIO CODE ===
        Write-Host "=== Installing Visual Studio Code (System) ==="
        $VSCodeUrl = "https://update.code.visualstudio.com/latest/win32-x64/stable"
        $VSCodeInstaller = "$env:TEMP\VSCodeSetup-x64.exe"
        Get-InstallerWithRetry -Uri $VSCodeUrl -OutFile $VSCodeInstaller

        $proc = Start-Process -FilePath $VSCodeInstaller `
            -ArgumentList "/VERYSILENT /NORESTART /MERGETASKS=`"!runcode,addcontextmenufiles,addcontextmenufolders,addtopath`"" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "VS Code installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] VS Code installed to: C:\Program Files\Microsoft VS Code"

        # === GIT FOR WINDOWS ===
        Write-Host "=== Installing Git for Windows ==="
        $GitVersion = "${var.git_version}"
        $GitUrl = "https://github.com/git-for-windows/git/releases/download/v$${GitVersion}.windows.1/Git-$${GitVersion}-64-bit.exe"
        $GitInstaller = "$env:TEMP\Git-$${GitVersion}-64-bit.exe"
        Get-InstallerWithRetry -Uri $GitUrl -OutFile $GitInstaller
        Test-InstallerHash -FilePath $GitInstaller -ExpectedHash "${var.git_sha256}"

        $proc = Start-Process -FilePath $GitInstaller `
            -ArgumentList "/VERYSILENT /NORESTART /PathOption=Cmd /NoAutoCrlf /SetupType=default" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Git installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Git: $(git --version)"

        # === GITHUB DESKTOP ===
        Write-Host "=== Installing GitHub Desktop (Machine-Wide Provisioner) ==="
        $GHDesktopUrl = "https://central.github.com/deployments/desktop/desktop/latest/GitHubDesktopSetup-x64.msi"
        $GHDesktopInstaller = "$env:TEMP\GitHubDesktop-x64.msi"
        Get-InstallerWithRetry -Uri $GHDesktopUrl -OutFile $GHDesktopInstaller

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$GHDesktopInstaller`" /qn /norestart ALLUSERS=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "GitHub Desktop installation failed ($($proc.ExitCode))"; exit 1 }
        Write-Host "[VERIFY] GitHub Desktop provisioner installed"

        # === AZURE CLI ===
        $AzCliVersion = "${var.azure_cli_version}"
        Write-Host "=== Installing Azure CLI $AzCliVersion ==="
        $AzCliUrl = "https://azcliprod.blob.core.windows.net/msi/azure-cli-$AzCliVersion-x64.msi"
        $AzCliInstaller = "$env:TEMP\azure-cli-$AzCliVersion-x64.msi"
        Get-InstallerWithRetry -Uri $AzCliUrl -OutFile $AzCliInstaller
        Test-InstallerHash -FilePath $AzCliInstaller -ExpectedHash "${var.azure_cli_sha256}"

        $proc = Start-Process -FilePath "msiexec.exe" `
            -ArgumentList "/i `"$AzCliInstaller`" /qn /norestart ALLUSERS=1" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) { Write-Error "Azure CLI installation failed ($($proc.ExitCode))"; exit 1 }
        Update-SessionEnvironment
        Write-Host "[VERIFY] Azure CLI: $(az --version | Select-Object -First 1)"

        # === GITHUB COPILOT (VS Code Extension) ===
        Write-Host "=== Installing GitHub Copilot VS Code Extension ==="
        $codeBin = "C:\Program Files\Microsoft VS Code\bin\code.cmd"
        if (Test-Path $codeBin) {
            & $codeBin --install-extension GitHub.copilot --force | Write-Host
            & $codeBin --install-extension GitHub.copilot-chat --force | Write-Host
            Write-Host "[VERIFY] GitHub Copilot extensions installed"
        } else {
            Write-Error "VS Code not found at expected path - cannot install Copilot extension"
            exit 1
        }

        # === CLEANUP ===
        Remove-Item -Path $VSCodeInstaller, $GitInstaller, $GHDesktopInstaller, $AzCliInstaller -Force -ErrorAction SilentlyContinue

        # === NPM GLOBAL PACKAGE INVENTORY ===
        Write-Host "=== Listing global npm packages ==="
        # Ensure SYSTEM profile npm directory exists (npm list -g fails without it)
        $npmDir = "$env:APPDATA\npm"
        if (-not (Test-Path $npmDir)) { New-Item -ItemType Directory -Path $npmDir -Force | Out-Null }
        npm list -g --depth=0 | Write-Host
        Write-Host "[SECURITY] Global package inventory logged (npm audit does not support --global)"

        # === SBOM GENERATION ===
        Write-Host "=== Generating Software Bill of Materials (SBOM) ==="
        $sbomDir = "C:\ProgramData\ImageBuild"
        New-Item -ItemType Directory -Path $sbomDir -Force | Out-Null

        $globalPackages = npm list -g --json 2>$null
        Set-Content -Path "$sbomDir\sbom-npm-global.json" -Value $globalPackages -Encoding UTF8
        Write-Host "[SBOM] npm global packages: $sbomDir\sbom-npm-global.json"

        # Record installed software versions
        $softwareManifest = @{
            buildDate       = (Get-Date -Format "yyyy-MM-dd'T'HH:mm:ss'Z'")
            nodeVersion     = (node --version).ToString()
            npmVersion      = (npm --version).ToString()
            pythonVersion   = (python --version).ToString()
            gitVersion      = (git --version).ToString()
            pwshVersion     = (pwsh --version).ToString()
            azCliVersion    = ((az version | ConvertFrom-Json).'azure-cli')
        } | ConvertTo-Json -Depth 3
        Set-Content -Path "$sbomDir\sbom-software-manifest.json" -Value $softwareManifest -Encoding UTF8
        Write-Host "[SBOM] Software manifest: $sbomDir\sbom-software-manifest.json"

        Write-Host "=== Phase 2 Complete: Developer tools installed ==="
        exit 0
        PWSH
      ]
    },
    # ── Phase 3: Configuration & Policy ──
    {
      type        = "PowerShell"
      name        = "ConfigureAgents"
      runElevated = true
      runAsSystem = true
      inline = [
        <<-PWSH
        $ErrorActionPreference = "Stop"

        # === CLAUDE CODE: Enterprise Managed Settings ===
        Write-Host "=== Configuring Claude Code enterprise policy ==="
        $claudeConfigDir = "C:\ProgramData\ClaudeCode"
        New-Item -ItemType Directory -Path $claudeConfigDir -Force | Out-Null

        $managedSettings = @{
            autoUpdatesChannel = "stable"
            permissions = @{
                defaultMode = "allowWithPermission"
            }
        } | ConvertTo-Json -Depth 5

        $managedSettingsPath = "$claudeConfigDir\managed-settings.json"
        Set-Content -Path $managedSettingsPath -Value $managedSettings -Encoding UTF8
        Write-Host "[CONFIG] Claude Code managed settings: $managedSettingsPath"

        # === OPENCLAW: Configuration Template ===
        Write-Host "=== Creating OpenClaw configuration template ==="
        $openclawTemplateDir = "C:\ProgramData\OpenClaw"
        New-Item -ItemType Directory -Path $openclawTemplateDir -Force | Out-Null

        $openclawConfig = @{
            agent = @{
                model = "${var.openclaw_default_model}"
                defaults = @{
                    workspace = "~/Documents/OpenClawWorkspace"
                }
            }
            gateway = @{
                mode = "local"
                port = ${var.openclaw_gateway_port}
            }
            channels = @{
                web = @{ enabled = $true }
            }
        } | ConvertTo-Json -Depth 5

        $templatePath = "$openclawTemplateDir\template-config.json"
        Set-Content -Path $templatePath -Value $openclawConfig -Encoding UTF8
        Write-Host "[CONFIG] OpenClaw template: $templatePath"

        # === CURATED AGENT SKILLS ===
        $skillsRepoUrl = "${var.skills_repo_url}"
        $skillsDir = "C:\ProgramData\OpenClaw\skills"
        if ($skillsRepoUrl -ne "") {
            Write-Host "=== Cloning curated agent skills ==="
            New-Item -ItemType Directory -Path $skillsDir -Force | Out-Null
            git clone --depth 1 $skillsRepoUrl "$skillsDir\approved" | Write-Host
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Skills clone failed - skills will need to be installed post-provisioning"
            } else {
                $skillCount = (Get-ChildItem -Path "$skillsDir\approved" -Filter "SKILL.md" -Recurse).Count
                Write-Host "[CONFIG] Curated skills cloned: $skillCount skills found"
            }
        } else {
            Write-Host "[SKIP] No skills repository configured"
        }

        # === MCP SERVER CONFIGURATION TEMPLATE ===
        Write-Host "=== Creating MCP server configuration template ==="
        $mcpConfigDir = "C:\ProgramData\OpenClaw\mcp"
        New-Item -ItemType Directory -Path $mcpConfigDir -Force | Out-Null

        # Template with placeholder API keys - real keys delivered via Intune env vars
        $mcpConfig = @{
            servers = @{
                "microsoft-docs" = @{
                    transport = "http"
                    url       = "https://learn.microsoft.com/api/mcp"
                }
                "perplexity" = @{
                    transport = "stdio"
                    command   = "npx"
                    args      = @("-y", "@perplexity-ai/mcp-server")
                    env       = @{
                        PERPLEXITY_API_KEY = "__PERPLEXITY_API_KEY__"
                    }
                }
            }
        } | ConvertTo-Json -Depth 5

        Set-Content -Path "$mcpConfigDir\mcporter.json" -Value $mcpConfig -Encoding UTF8
        Write-Host "[CONFIG] MCP server config template: $mcpConfigDir\mcporter.json"

        # === ACTIVE SETUP: First-Login Configuration Hydration ===
        Write-Host "=== Registering Active Setup for first-login hydration ==="

        # Hydration script OVERWRITES existing config to ensure consistency
        $hydrationScript = @'
$openclawDir = "$env:USERPROFILE\.openclaw"
$configFile = "$openclawDir\openclaw.json"
$templateFile = "C:\ProgramData\OpenClaw\template-config.json"

if (Test-Path $templateFile) {
    New-Item -ItemType Directory -Path $openclawDir -Force | Out-Null
    $workspaceDir = "$env:USERPROFILE\Documents\OpenClawWorkspace"
    New-Item -ItemType Directory -Path $workspaceDir -Force | Out-Null
    Copy-Item -Path $templateFile -Destination $configFile -Force
}

# Hydrate curated agent skills
$skillsSource = "C:\ProgramData\OpenClaw\skills"
$skillsDest = "$env:USERPROFILE\.agents\skills"
if (Test-Path $skillsSource) {
    New-Item -ItemType Directory -Path $skillsDest -Force | Out-Null
    Copy-Item -Path "$skillsSource\*" -Destination $skillsDest -Recurse -Force
}

# Hydrate MCP server configuration
$mcpSource = "C:\ProgramData\OpenClaw\mcp\mcporter.json"
$mcpDest = "$openclawDir\workspace\config"
if (Test-Path $mcpSource) {
    New-Item -ItemType Directory -Path $mcpDest -Force | Out-Null
    Copy-Item -Path $mcpSource -Destination "$mcpDest\mcporter.json" -Force
}
'@

        $hydrationScriptPath = "$openclawTemplateDir\hydrate-config.ps1"
        Set-Content -Path $hydrationScriptPath -Value $hydrationScript -Encoding UTF8

        # Register via Active Setup
        $activeSetupKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\OpenClaw-ConfigHydration"
        New-Item -Path $activeSetupKey -Force | Out-Null
        Set-ItemProperty -Path $activeSetupKey -Name "(Default)" -Value "OpenClaw Configuration Hydration"
        Set-ItemProperty -Path $activeSetupKey -Name "StubPath" -Value "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$hydrationScriptPath`""
        Set-ItemProperty -Path $activeSetupKey -Name "Version" -Value "1,0,0,0"
        Write-Host "[CONFIG] Active Setup registered: OpenClaw-ConfigHydration"

        # === TEAMS OPTIMISATION PREREQUISITES ===
        Write-Host "=== Setting Teams optimisation prerequisites ==="
        $teamsRegPath = "HKLM:\SOFTWARE\Microsoft\Teams"
        if (-not (Test-Path $teamsRegPath)) {
            New-Item -Path $teamsRegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $teamsRegPath -Name "IsWVDEnvironment" -Value 1 -Type DWord -Force
        Write-Host "[CONFIG] Teams IsWVDEnvironment = 1"

        # === IMAGE CLEANUP & OPTIMISATION ===
        Write-Host "=== Cleaning up image ==="
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        npm cache clean --force | Out-Null

        Write-Host "[CLEANUP] Running DISM component store cleanup..."
        Start-Process -FilePath "dism.exe" `
            -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" `
            -Wait -NoNewWindow

        Write-Host "=== Phase 4 Complete: Configuration and cleanup done ==="
        exit 0
        PWSH
      ]
    },
    # ── Windows Update ──
    {
      type           = "WindowsUpdate"
      searchCriteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*Preview*'",
        "include:$true"
      ]
      updateLimit = 40
    },
    # ── Final Restart ──
    {
      type           = "WindowsRestart"
      restartTimeout = "10m"
    }
  ]

  # Distributor: publish to Azure Compute Gallery
  distribute = [
    {
      type              = "SharedImage"
      galleryImageId    = var.image_definition_id
      runOutputName     = "w365-dev-ai-${var.image_version}"
      excludeFromLatest = var.exclude_from_latest
      targetRegions = [
        {
          name               = var.location
          replicaCount       = var.replica_count
          storageAccountType = "Standard_LRS"
        }
      ]
      versioning = {
        scheme = "Latest"
        major  = tonumber(split(".", var.image_version)[0])
      }
    }
  ]

  # Build VM profile
  vm_profile = {
    vmSize       = var.build_vm_size
    osDiskSizeGB = var.os_disk_size_gb
  }
}

# ── AIB Image Template ──
resource "azapi_resource" "image_template" {
  type      = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  name      = local.template_name
  location  = var.location
  parent_id = var.resource_group_id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.managed_identity_id]
  }

  tags = var.tags

  body = {
    properties = {
      buildTimeoutInMinutes = var.build_timeout_minutes

      source = {
        type      = "PlatformImage"
        publisher = var.source_image_publisher
        offer     = var.source_image_offer
        sku       = var.source_image_sku
        version   = var.source_image_version
      }

      customize = local.customizers

      distribute = local.distribute

      vmProfile = local.vm_profile
    }
  }
}

# ── Trigger the Build ──
resource "azapi_resource_action" "run_build" {
  type        = "Microsoft.VirtualMachineImages/imageTemplates@2024-02-01"
  resource_id = azapi_resource.image_template.id
  action      = "run"

  depends_on = [azapi_resource.image_template]

  timeouts {
    create = "${var.build_timeout_minutes + 30}m"
  }
}
