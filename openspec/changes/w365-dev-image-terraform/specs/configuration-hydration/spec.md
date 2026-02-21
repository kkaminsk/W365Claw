## ADDED Requirements

### Requirement: Claude Code enterprise managed settings
The system SHALL deploy a Claude Code managed-settings.json to `C:\ProgramData\ClaudeCode\` with autoUpdatesChannel=stable and permissions.defaultMode=allow.

#### Scenario: Managed settings file created
- **WHEN** Phase 4 configuration runs
- **THEN** `C:\ProgramData\ClaudeCode\managed-settings.json` SHALL exist with the specified JSON content

### Requirement: OpenClaw configuration template
The system SHALL create an OpenClaw template configuration at `C:\ProgramData\OpenClaw\template-config.json` with the default model, gateway port, and workspace path.

#### Scenario: Template config created
- **WHEN** Phase 4 configuration runs
- **THEN** `C:\ProgramData\OpenClaw\template-config.json` SHALL contain the model, gateway mode/port, and web channel settings

### Requirement: Active Setup first-login hydration
The system SHALL register a Windows Active Setup component that copies the OpenClaw template configuration to each user's `~/.openclaw/openclaw.json` on first login, creating the workspace directory.

#### Scenario: Active Setup registry key registered
- **WHEN** Phase 4 completes
- **THEN** `HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\OpenClaw-ConfigHydration` SHALL exist with a StubPath pointing to the hydration script

#### Scenario: Config hydrated on user login
- **WHEN** a new user logs into the Cloud PC for the first time
- **THEN** `~/.openclaw/openclaw.json` SHALL be created from the template and `~/Documents/OpenClawWorkspace` SHALL exist

### Requirement: Teams VDI optimisation
The system SHALL set the `IsWVDEnvironment` registry key to enable Teams media optimisation for Windows 365.

#### Scenario: Teams registry key set
- **WHEN** Phase 4 runs
- **THEN** `HKLM:\SOFTWARE\Microsoft\Teams\IsWVDEnvironment` SHALL be set to DWORD 1

### Requirement: Image cleanup
The system SHALL clean temp files, Windows Update cache, npm cache, and run DISM component store cleanup before image capture.

#### Scenario: Cleanup reduces image size
- **WHEN** Phase 4 cleanup runs
- **THEN** temp files, SoftwareDistribution downloads, and npm cache SHALL be removed, and DISM `/StartComponentCleanup /ResetBase` SHALL execute
