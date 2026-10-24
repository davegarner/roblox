<#
.SYNOPSIS
    One-shot setup of a Windows 11 PC for Roblox game development with Claude Code.

.DESCRIPTION
    Installs the following, skipping anything already present (safe to re-run):

      Git for Windows        version control; also gives Claude Code its Bash tool
      Visual Studio Code     code editor, plus Roblox/Luau extensions and the Claude Code extension
      Roblox Studio          the Roblox engine and editor
      Node.js LTS            needed by many MCP servers and dev tools (leave out with -Skip Node)
      Claude Code            Anthropic's terminal coding agent (official native installer, auto-updates)
      Rokit                  toolchain manager for Roblox command-line tools
      Rojo, StyLua, Selene   file sync into Studio, code formatter, linter (installed through Rokit)
      Rojo Studio plugin     the Roblox Studio side of Rojo

    Then creates a first Rojo project under %USERPROFILE%\RobloxProjects containing:
      CLAUDE.md              tells Claude Code how the project is laid out and how to work in it
      JOURNAL.md             a learning log to fill in as you go
      selene.toml            lint config for Roblox
      .vscode\settings.json  format Luau on save
      rokit.toml             pinned tool versions for this project
      <name>.rbxlx           a built place file ready to open in Roblox Studio

    A full log of every run is written to %USERPROFILE%\roblox-dev-setup-logs\.

.PARAMETER ProjectName
    Folder name of the first game project. Default: my-first-game

.PARAMETER ProjectRoot
    Folder that holds all your projects. Default: %USERPROFILE%\RobloxProjects

.PARAMETER Skip
    Steps to leave out. One or more of:
    Git, VSCode, Studio, Node, Claude, Rokit, Tools, Extensions, Plugin, Project

.PARAMETER DryRun
    Show what would be installed or created without changing anything.

.EXAMPLE
    .\Setup-RobloxDev.ps1

.EXAMPLE
    .\Setup-RobloxDev.ps1 -DryRun

.EXAMPLE
    .\Setup-RobloxDev.ps1 -ProjectName obby-game -Skip Node

.NOTES
    Works in Windows PowerShell 5.1 (built into Windows) and PowerShell 7.
    Does not need to run as Administrator. Windows may show "Do you want to allow this app
    to make changes" prompts for Git and VS Code: click Yes.
    If Windows blocks scripts, double-click Run-Setup.cmd instead, or run:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-RobloxDev.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectName = 'my-first-game',
    [string]$ProjectRoot = (Join-Path $env:USERPROFILE 'RobloxProjects'),
    [string[]]$Skip = @(),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# -Skip accepts both "-Skip Node,Studio" (one string when launched with -File or from
# Run-Setup.cmd) and "-Skip Node,Studio" as a real array (when called from PowerShell).
$AllSteps = @('Git', 'VSCode', 'Studio', 'Node', 'Claude', 'Rokit', 'Tools', 'Extensions', 'Plugin', 'Project')
$Skip = @($Skip | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
$unknownSteps = @($Skip | Where-Object { $AllSteps -notcontains $_ })
if ($unknownSteps.Count -gt 0) {
    Write-Host "Unknown -Skip value(s): $($unknownSteps -join ', ')" -ForegroundColor Red
    Write-Host "Valid values: $($AllSteps -join ', ')"
    exit 2
}
# Windows PowerShell 5.1 can default to old TLS; GitHub and claude.ai require TLS 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$ClaudeInstallUrl = 'https://claude.ai/install.ps1'
$RokitInstallUrl  = 'https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1'

# Command-line tools installed through Rokit. Spec is the GitHub owner/repo.
$RokitTools = @(
    @{ Cmd = 'rojo';   Spec = 'rojo-rbx/rojo';        Friendly = 'Rojo (syncs your files into Roblox Studio)' },
    @{ Cmd = 'stylua'; Spec = 'JohnnyMorganz/StyLua'; Friendly = 'StyLua (code formatter)' },
    @{ Cmd = 'selene'; Spec = 'Kampfkarren/selene';   Friendly = 'Selene (linter)' }
)

$VsCodeExtensions = @(
    @{ Id = 'anthropic.claude-code';     Why = 'Claude Code panel inside VS Code' },
    @{ Id = 'JohnnyMorganz.luau-lsp';    Why = 'Luau autocomplete, type checking, Roblox API docs' },
    @{ Id = 'evaera.vscode-rojo';        Why = 'Rojo controls inside VS Code' },
    @{ Id = 'JohnnyMorganz.stylua';      Why = 'Format Luau code on save' },
    @{ Id = 'Kampfkarren.selene-vscode'; Why = 'Lint warnings shown inline' },
    @{ Id = 'filiptibell.roblox-ui';     Why = 'Explorer-style tree view of your Rojo project' }
)

# ---------------------------------------------------------------------------
# Output and bookkeeping helpers
# ---------------------------------------------------------------------------
$script:Results = New-Object System.Collections.Generic.List[object]

function Write-Step([string]$Title) { Write-Host ''; Write-Host "==> $Title" -ForegroundColor Cyan }
function Write-Info([string]$Msg)   { Write-Host "    $Msg" }
function Write-Ok([string]$Msg)     { Write-Host "    [OK]   $Msg" -ForegroundColor Green }
function Write-Warn2([string]$Msg)  { Write-Host "    [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail([string]$Msg)   { Write-Host "    [FAIL] $Msg" -ForegroundColor Red }

function Add-Result([string]$Step, [string]$Status, [string]$Detail) {
    $script:Results.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail })
}

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# Runs a native executable, captures stdout+stderr as text plus the exit code, and
# never throws on stderr output. (Windows PowerShell 5.1 would otherwise turn stderr
# lines into terminating errors while $ErrorActionPreference is 'Stop'.)
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $code; Output = (@($lines) -join "`n") }
}

function Get-OutputTail([string]$Text, [int]$Lines = 6) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $all = $Text.Split([char[]]@("`r", "`n"), [StringSplitOptions]::RemoveEmptyEntries)
    return ((@($all) | Select-Object -Last $Lines) -join "`n    ")
}

# Installers add themselves to the registry PATH, but this process keeps its old copy.
# Rebuild PATH from the registry plus the known per-user install folders.
function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $known = @(
        (Join-Path $env:USERPROFILE '.local\bin'),                        # Claude Code native install
        (Join-Path $env:USERPROFILE '.rokit\bin'),                        # Rokit + Rojo/StyLua/Selene
        (Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin'),   # VS Code (per-user install)
        (Join-Path $env:ProgramFiles 'Microsoft VS Code\bin'),            # VS Code (all-users install)
        (Join-Path $env:ProgramFiles 'Git\cmd')                           # Git for Windows
    ) | Where-Object { Test-Path $_ }
    # The filter drops null/empty entries only; a PATH entry is never "0" or "false".
    $env:Path = (@($machine, $user) + @($known) | Where-Object { -not [string]::IsNullOrEmpty($_) }) -join ';'
}

# Adds a folder to the persistent per-user PATH if it is not there yet. Returns $true if added.
function Add-UserPath([string]$Dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if (-not [string]::IsNullOrEmpty($user)) {
        $parts = @($user.Split(';', [StringSplitOptions]::RemoveEmptyEntries))
    }
    if ($parts -contains $Dir) { return $false }   # -contains is case-insensitive
    [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
    return $true
}

# ---------------------------------------------------------------------------
# winget helpers
# ---------------------------------------------------------------------------
function Test-WingetInstalled([string]$Id) {
    $r = Invoke-Native 'winget' @('list', '--id', $Id, '--exact', '--accept-source-agreements')
    # Installed: exit 0 and the Id appears in the table.
    # Missing:   non-zero exit and "No installed package found matching input criteria."
    return (($r.ExitCode -eq 0) -and ("$($r.Output)" -like "*$Id*"))
}

function Install-WingetPackage([string]$Id, [string]$Friendly) {
    if (Test-WingetInstalled $Id) {
        Write-Ok "$Friendly is already installed"
        Add-Result $Friendly 'present' $Id
        return $true
    }
    if ($DryRun) {
        Write-Info "DRY RUN: winget install --id $Id --exact --silent"
        Add-Result $Friendly 'dry-run' "winget install $Id"
        return $true
    }
    Write-Info "Installing $Friendly with winget (a Windows permission prompt may appear: click Yes) ..."
    $r = Invoke-Native 'winget' @(
        'install', '--id', $Id, '--exact', '--silent',
        '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity'
    )
    if (($r.ExitCode -eq 0) -or (Test-WingetInstalled $Id)) {
        Write-Ok "$Friendly installed"
        Add-Result $Friendly 'installed' $Id
        return $true
    }
    Write-Fail "$Friendly did not install (winget exit code $($r.ExitCode))"
    Write-Info (Get-OutputTail $r.Output)
    Add-Result $Friendly 'FAILED' "winget exit $($r.ExitCode), see log"
    return $false
}

# Runs an official "irm <url> | iex" installer in a child PowerShell so that a `cd` or
# `exit` inside the installer cannot derail this script.
function Invoke-RemoteInstaller([string]$Url, [string]$Friendly) {
    $psExe = (Get-Process -Id $PID).Path
    Write-Info "Running the official $Friendly installer from $Url ..."
    $r = Invoke-Native $psExe @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command',
        "Invoke-RestMethod '$Url' | Invoke-Expression"
    )
    if ($r.ExitCode -ne 0) {
        Write-Warn2 "$Friendly installer exited with code $($r.ExitCode)"
        Write-Info (Get-OutputTail $r.Output)
    }
    return $r
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
$exitCode = 0
$logDir  = Join-Path $env:USERPROFILE 'roblox-dev-setup-logs'
$logFile = Join-Path $logDir ('setup-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$transcriptStarted = $false
try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Start-Transcript -Path $logFile -Append | Out-Null
    $transcriptStarted = $true
}
catch {
    Write-Warn2 "Could not start a log file ($($_.Exception.Message)). Continuing without one."
}

# $Skip lists things NOT to do. Turn it into positive "do this" flags so every
# branch below reads as what it does.
$Do = @{}
foreach ($step in $AllSteps) {
    $Do[$step] = -not ($Skip -contains $step)
}

Write-Host ''
Write-Host '  Roblox + Claude Code development setup' -ForegroundColor Magenta
Write-Host '  ======================================' -ForegroundColor Magenta
if ($DryRun) { Write-Host '  DRY RUN: nothing will be installed or written.' -ForegroundColor Yellow }
if ($Skip.Count -gt 0) { Write-Host "  Skipping: $($Skip -join ', ')" -ForegroundColor Yellow }
Write-Host "  Log: $logFile"

$projectPath = Join-Path $ProjectRoot $ProjectName

try {
    # -----------------------------------------------------------------------
    Write-Step 'Preflight checks'
    # -----------------------------------------------------------------------
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    Write-Info "$($os.Caption) (build $build), PowerShell $($PSVersionTable.PSVersion)"
    if ($build -lt 17763) {
        throw 'Windows 10 version 1809 (build 17763) or newer is required.'
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warn2 'Running as Administrator. Not needed; per-user tools will install into this account.'
    }

    if (-not (Test-Command winget)) {
        Write-Fail 'winget (Windows Package Manager) was not found.'
        Write-Info 'Open the Microsoft Store, search for "App Installer", click Update or Install, then run this again.'
        Write-Info 'Store link: ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1'
        throw 'winget is missing'
    }
    Write-Ok "winget $((Invoke-Native 'winget' @('--version')).Output.Trim())"

    try {
        $null = Invoke-WebRequest -Uri 'https://github.com' -Method Head -UseBasicParsing -TimeoutSec 20
        Write-Ok 'Internet connection works'
    }
    catch {
        Write-Fail "Cannot reach github.com: $($_.Exception.Message)"
        if (-not $DryRun) { throw 'No internet connection' }
    }

    # -----------------------------------------------------------------------
    # Core applications via winget
    # -----------------------------------------------------------------------
    if ($Do.Git) {
        Write-Step 'Git for Windows (version control; Claude Code uses its Bash shell)'
        $null = Install-WingetPackage 'Git.Git' 'Git for Windows'
    }
    if ($Do.VSCode) {
        Write-Step 'Visual Studio Code (code editor)'
        $null = Install-WingetPackage 'Microsoft.VisualStudioCode' 'Visual Studio Code'
    }
    if ($Do.Studio) {
        Write-Step 'Roblox Studio (the Roblox game editor)'
        Write-Info 'Studio may open itself when the install finishes. You can close it for now.'
        $null = Install-WingetPackage 'Roblox.RobloxStudio' 'Roblox Studio'
    }
    if ($Do.Node) {
        Write-Step 'Node.js LTS (used by many MCP servers and developer tools)'
        $null = Install-WingetPackage 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    }
    Update-SessionPath

    # -----------------------------------------------------------------------
    if ($Do.Claude) {
        Write-Step 'Claude Code (Anthropic terminal coding agent)'
        if (Test-Command claude) {
            $v = (Invoke-Native 'claude' @('--version')).Output.Trim()
            Write-Ok "Claude Code is already installed ($v)"
            Add-Result 'Claude Code' 'present' $v
        }
        elseif ($DryRun) {
            Write-Info "DRY RUN: irm $ClaudeInstallUrl | iex   (fallback: winget install Anthropic.ClaudeCode)"
            Add-Result 'Claude Code' 'dry-run' 'native installer'
        }
        else {
            $null = Invoke-RemoteInstaller $ClaudeInstallUrl 'Claude Code'
            # The native installer puts claude.exe in %USERPROFILE%\.local\bin and sometimes
            # leaves that folder off PATH. Make sure it is on the user PATH.
            $claudeBin = Join-Path $env:USERPROFILE '.local\bin'
            if (Test-Path (Join-Path $claudeBin 'claude.exe')) {
                if (Add-UserPath $claudeBin) { Write-Info "Added $claudeBin to your PATH" }
            }
            Update-SessionPath
            if (-not (Test-Command claude)) {
                Write-Warn2 'Native installer did not produce a working "claude" command. Trying winget ...'
                $null = Install-WingetPackage 'Anthropic.ClaudeCode' 'Claude Code (winget)'
                Update-SessionPath
            }
            if (Test-Command claude) {
                $v = (Invoke-Native 'claude' @('--version')).Output.Trim()
                Write-Ok "Claude Code installed ($v)"
                Add-Result 'Claude Code' 'installed' $v
            }
            else {
                Write-Fail 'Claude Code is not on PATH. Open a NEW terminal and run: claude --version'
                Add-Result 'Claude Code' 'FAILED' 'not found on PATH after install'
            }
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Rokit) {
        Write-Step 'Rokit (installs and pins Roblox command-line tools)'
        if (Test-Command rokit) {
            Write-Ok "Rokit is already installed ($((Invoke-Native 'rokit' @('--version')).Output.Trim()))"
            Add-Result 'Rokit' 'present' ''
        }
        elseif ($DryRun) {
            Write-Info "DRY RUN: irm $RokitInstallUrl | iex"
            Add-Result 'Rokit' 'dry-run' 'install.ps1'
        }
        else {
            $null = Invoke-RemoteInstaller $RokitInstallUrl 'Rokit'
            Update-SessionPath
            if (Test-Command rokit) {
                Write-Ok "Rokit installed ($((Invoke-Native 'rokit' @('--version')).Output.Trim()))"
                Add-Result 'Rokit' 'installed' ''
            }
            else {
                Write-Fail 'Rokit is not on PATH. Expected %USERPROFILE%\.rokit\bin\rokit.exe'
                Add-Result 'Rokit' 'FAILED' 'not found after install'
            }
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Tools) {
        Write-Step 'Rojo, StyLua, Selene (rokit add --global)'
        $canInstallTools = $DryRun -or (Test-Command rokit)
        if ($canInstallTools) {
            foreach ($t in $RokitTools) {
                if (Test-Command $t.Cmd) {
                    Write-Ok "$($t.Friendly) already installed"
                    Add-Result $t.Cmd 'present' $t.Spec
                    continue
                }
                if ($DryRun) {
                    Write-Info "DRY RUN: rokit add --global $($t.Spec)"
                    Add-Result $t.Cmd 'dry-run' $t.Spec
                    continue
                }
                Write-Info "rokit add --global $($t.Spec) ..."
                $r = Invoke-Native 'rokit' @('add', '--global', $t.Spec)
                Update-SessionPath
                if (Test-Command $t.Cmd) {
                    Write-Ok "$($t.Friendly) installed"
                    Add-Result $t.Cmd 'installed' $t.Spec
                }
                else {
                    Write-Fail "$($t.Friendly) failed (rokit exit $($r.ExitCode))"
                    Write-Info (Get-OutputTail $r.Output)
                    Add-Result $t.Cmd 'FAILED' "rokit exit $($r.ExitCode)"
                }
            }
        }
        else {
            Write-Warn2 'Rokit is not available, so these tools cannot be installed. Fix Rokit first, then re-run.'
            Add-Result 'Rojo/StyLua/Selene' 'SKIPPED' 'rokit missing'
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Extensions) {
        Write-Step 'VS Code extensions'
        Update-SessionPath
        $canInstallExtensions = $DryRun -or (Test-Command code)
        if ($canInstallExtensions) {
            $installedExts = @()
            if (Test-Command code) {
                $raw = (Invoke-Native 'code' @('--list-extensions')).Output
                if (-not [string]::IsNullOrEmpty($raw)) {
                    $installedExts = @($raw.Split([char[]]@("`r", "`n"), [StringSplitOptions]::RemoveEmptyEntries))
                }
            }
            foreach ($e in $VsCodeExtensions) {
                if ($installedExts -contains $e.Id) {
                    Write-Ok "$($e.Id) already installed"
                    Add-Result $e.Id 'present' $e.Why
                    continue
                }
                if ($DryRun) {
                    Write-Info "DRY RUN: code --install-extension $($e.Id)   ($($e.Why))"
                    Add-Result $e.Id 'dry-run' $e.Why
                    continue
                }
                $r = Invoke-Native 'code' @('--install-extension', $e.Id, '--force')
                if ($r.ExitCode -eq 0) {
                    Write-Ok "$($e.Id) installed ($($e.Why))"
                    Add-Result $e.Id 'installed' $e.Why
                }
                else {
                    Write-Fail "$($e.Id) failed (code exit $($r.ExitCode))"
                    Write-Info (Get-OutputTail $r.Output)
                    Add-Result $e.Id 'FAILED' "code exit $($r.ExitCode)"
                }
            }
        }
        else {
            Write-Warn2 'The "code" command is not available yet. Open a NEW terminal and re-run this script; everything already installed is skipped.'
            Add-Result 'VS Code extensions' 'SKIPPED' 'code command not found'
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Plugin) {
        Write-Step 'Rojo plugin for Roblox Studio'
        if ($DryRun) {
            Write-Info 'DRY RUN: rojo plugin install'
            Add-Result 'Rojo Studio plugin' 'dry-run' ''
        }
        elseif (Test-Command rojo) {
            $r = Invoke-Native 'rojo' @('plugin', 'install')
            if ($r.ExitCode -eq 0) {
                Write-Ok 'Rojo plugin installed into the Roblox Studio plugins folder'
                Add-Result 'Rojo Studio plugin' 'installed' ''
            }
            else {
                Write-Fail "rojo plugin install failed (exit $($r.ExitCode))"
                Write-Info (Get-OutputTail $r.Output)
                Add-Result 'Rojo Studio plugin' 'FAILED' "exit $($r.ExitCode)"
            }
        }
        else {
            Write-Warn2 'Rojo is not available; plugin not installed. Re-run after Rojo installs.'
            Add-Result 'Rojo Studio plugin' 'SKIPPED' 'rojo missing'
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Project) {
        Write-Step "First project: $projectPath"
        if (Test-Path $projectPath) {
            Write-Ok 'Project folder already exists; leaving it untouched'
            Add-Result 'Project' 'present' $projectPath
        }
        elseif ($DryRun) {
            Write-Info "DRY RUN: rojo init `"$projectPath`"; copy templates\CLAUDE.md + JOURNAL.md; write selene.toml + .vscode\settings.json; rokit init + add tools; rojo build; git commit"
            $templateDir = Join-Path $PSScriptRoot 'templates'
            foreach ($name in 'CLAUDE.md', 'JOURNAL.md') {
                if (Test-Path (Join-Path $templateDir $name)) { Write-Ok "template found: templates\$name" }
                else { Write-Warn2 "template missing: templates\$name (project would be created without it)" }
            }
            Add-Result 'Project' 'dry-run' $projectPath
        }
        elseif (-not (Test-Command rojo)) {
            Write-Warn2 'Rojo is not available; project not created. Re-run after Rojo installs.'
            Add-Result 'Project' 'SKIPPED' 'rojo missing'
        }
        else {
            New-Item -ItemType Directory -Path $ProjectRoot -Force | Out-Null
            $r = Invoke-Native 'rojo' @('init', $projectPath)
            if (($r.ExitCode -ne 0) -or (-not (Test-Path (Join-Path $projectPath 'default.project.json')))) {
                Write-Fail "rojo init failed (exit $($r.ExitCode))"
                Write-Info (Get-OutputTail $r.Output)
                Add-Result 'Project' 'FAILED' 'rojo init'
            }
            else {
                Write-Ok 'rojo init created default.project.json and src\ (client, server, shared)'

                # Project templates shipped next to this script. {{PROJECT_NAME}} is replaced.
                $templateDir = Join-Path $PSScriptRoot 'templates'
                foreach ($name in 'CLAUDE.md', 'JOURNAL.md') {
                    $src = Join-Path $templateDir $name
                    if (Test-Path $src) {
                        $text = (Get-Content -Path $src -Raw).Replace('{{PROJECT_NAME}}', $ProjectName)
                        Set-Content -Path (Join-Path $projectPath $name) -Value $text -Encoding UTF8
                        Write-Ok "Added $name"
                    }
                    else {
                        Write-Warn2 "Template not found, skipped: $src"
                    }
                }

                # Selene needs to know this is Roblox code.
                Set-Content -Path (Join-Path $projectPath 'selene.toml') -Value 'std = "roblox"' -Encoding Ascii
                # VS Code: format Luau with StyLua on save.
                $vscodeDir = Join-Path $projectPath '.vscode'
                New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null
                $settings = @'
{
    "editor.formatOnSave": true,
    "[luau]": {
        "editor.defaultFormatter": "JohnnyMorganz.stylua"
    },
    "[lua]": {
        "editor.defaultFormatter": "JohnnyMorganz.stylua"
    }
}
'@
                Set-Content -Path (Join-Path $vscodeDir 'settings.json') -Value $settings -Encoding Ascii
                Write-Ok 'Added selene.toml and .vscode\settings.json'

                Push-Location $projectPath
                try {
                    # Pin tool versions for this project (rokit.toml) so it builds the same later.
                    if (Test-Command rokit) {
                        $null = Invoke-Native 'rokit' @('init')
                        foreach ($t in $RokitTools) { $null = Invoke-Native 'rokit' @('add', $t.Spec) }
                        if (Test-Path 'rokit.toml') { Write-Ok 'Added rokit.toml with pinned Rojo/StyLua/Selene versions' }
                    }

                    # Build the first place file so Studio has something to open.
                    $placeFile = "$ProjectName.rbxlx"
                    $rb = Invoke-Native 'rojo' @('build', '-o', $placeFile)
                    if (($rb.ExitCode -eq 0) -and (Test-Path $placeFile)) {
                        Write-Ok "Built $placeFile (open this in Roblox Studio)"
                    }
                    else {
                        Write-Warn2 "rojo build failed (exit $($rb.ExitCode)). Run it yourself later: rojo build -o $placeFile"
                    }

                    # First commit. rojo init already ran `git init` when git was available.
                    if (Test-Command git) {
                        if (-not (Test-Path '.git')) { $null = Invoke-Native 'git' @('init') }
                        $gitName  = (Invoke-Native 'git' @('config', '--global', 'user.name')).Output.Trim()
                        $gitEmail = (Invoke-Native 'git' @('config', '--global', 'user.email')).Output.Trim()
                        $hasIdentity = (-not [string]::IsNullOrEmpty($gitName)) -and (-not [string]::IsNullOrEmpty($gitEmail))
                        if ($hasIdentity) {
                            $null = Invoke-Native 'git' @('add', '-A')
                            $gc = Invoke-Native 'git' @('commit', '-q', '-m', 'Initial Rojo project scaffold')
                            if ($gc.ExitCode -eq 0) { Write-Ok 'Created the first git commit' }
                            else { Write-Warn2 "git commit failed: $(Get-OutputTail $gc.Output 2)" }
                        }
                        else {
                            Write-Warn2 'Git does not know your name and email yet, so no commit was made. Run these once, then commit:'
                            Write-Info 'git config --global user.name "Your Name"'
                            Write-Info 'git config --global user.email "you@example.com"'
                            Write-Info "cd `"$projectPath`"; git add -A; git commit -m `"Initial project`""
                        }
                    }
                }
                finally {
                    Pop-Location
                }
                Add-Result 'Project' 'created' $projectPath
            }
        }
    }
}
catch {
    Write-Host ''
    Write-Fail "Setup stopped: $($_.Exception.Message)"
    Add-Result 'Setup' 'STOPPED' $_.Exception.Message
    $exitCode = 1
}

# ---------------------------------------------------------------------------
Write-Step 'Summary'
# ---------------------------------------------------------------------------
$script:Results | Format-Table -AutoSize -Property Step, Status, Detail | Out-String -Width 200 | Write-Host

$failed = @($script:Results | Where-Object { $_.Status -in 'FAILED', 'STOPPED' })
if ($failed.Count -gt 0) {
    Write-Warn2 "$($failed.Count) step(s) failed. Fix the cause (see messages above and the log), then re-run this script; completed steps are skipped."
    $exitCode = 1
}
else {
    Write-Ok 'All steps completed.'
}

Write-Host ''
Write-Host '  What to do next' -ForegroundColor Magenta
Write-Host '  ---------------' -ForegroundColor Magenta
Write-Host '  1. Open Roblox Studio from the Start menu and log in (a free Roblox account is enough).'
Write-Host '  2. Open a NEW terminal window so the PATH changes apply: Start menu > "Terminal".'
Write-Host '  3. Run:   claude        then follow the browser login. Claude Code needs a Claude Pro or Max subscription.'
Write-Host "  4. Run:   cd `"$projectPath`""
Write-Host '            rojo serve    and leave it running.'
Write-Host "  5. In Studio: File > Open from File > $projectPath\$ProjectName.rbxlx"
Write-Host '     then Plugins tab > Rojo > Connect.'
Write-Host '  6. In a second terminal in the project folder run:   claude'
Write-Host '     and ask: "Read CLAUDE.md and explain how this project is set up."'
Write-Host '  7. In Studio press Play (F5). View > Output should show "Hello world, from server!".'
Write-Host ''
Write-Host "  Full log: $logFile"
Write-Host ''

if ($transcriptStarted) { Stop-Transcript | Out-Null }
exit $exitCode
