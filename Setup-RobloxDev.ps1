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
      uv + graphify          Python tool runner and the /graphify Claude Code skill: a knowledge
                             graph of your project that Claude queries instead of re-reading files

    Then creates a first Rojo project under %USERPROFILE%\RobloxProjects containing:
      CLAUDE.md              tells Claude Code how the project is laid out and how to work in it
      JOURNAL.md             a learning log to fill in as you go
      .claude\skills\journal example project skill: type /journal to write today's JOURNAL.md entry
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
    Git, VSCode, Studio, Node, Claude, Rokit, Tools, Extensions, Plugin, Skills, Project

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
$AllSteps = @('Git', 'VSCode', 'Studio', 'Node', 'Claude', 'Rokit', 'Tools', 'Extensions', 'Plugin', 'Skills', 'Project')
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
$UvInstallUrl     = 'https://astral.sh/uv/install.ps1'
$RokitReleaseApi  = 'https://api.github.com/repos/rojo-rbx/rokit/releases/latest'
# Roblox's own "latest" Studio installer: the same file winget's Roblox.RobloxStudio entry points at.
$StudioInstallerUrl = 'https://setup.rbxcdn.com/RobloxStudioInstaller.exe'
# winget exit code 0x8A150011: the downloaded installer does not match the hash in winget's catalog.
$WingetHashMismatch = -1978335215
# Where `graphify install --platform windows` writes the Claude Code skill.
$GraphifySkillFile = Join-Path $env:USERPROFILE '.claude\skills\graphify\SKILL.md'
# Python for graphify. Its tree-sitter dependency only ships prebuilt Windows wheels for released
# Python versions up to a point; left to itself uv picks the newest Python and then tries to
# compile tree-sitter, which needs Microsoft's C++ Build Tools.
$GraphifyPython = '3.13'

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
# Console output
# ---------------------------------------------------------------------------
# This file is plain ASCII, which Windows PowerShell 5.1 reads correctly without a byte-order
# mark, so the box-drawing and marker glyphs are built from their code points. All of them are
# in the classic console character set (CP437), so every console font draws them.
$Glyph = @{
    H    = [string][char]0x2500; V    = [string][char]0x2502   # light line, horizontal / vertical
    TL   = [string][char]0x250C; BL   = [string][char]0x2514   # light corners, left side
    DH   = [string][char]0x2550; DV   = [string][char]0x2551   # double line, horizontal / vertical
    DTL  = [string][char]0x2554; DTR  = [string][char]0x2557   # double corners, top
    DBL  = [string][char]0x255A; DBR  = [string][char]0x255D   # double corners, bottom
    DLT  = [string][char]0x2560; DRT  = [string][char]0x2563   # double tees, left / right
    Ok   = [string][char]0x221A                                # square root sign, reads as a tick
    Bad  = [string][char]0x00D7                                # multiplication sign
    Dot  = [string][char]0x2022                                # bullet
    Skip = [string][char]0x00BB                                # double angle quote, "moved past"
    Play = [string][char]0x25BA                                # right-pointing pointer
}

# Rules and boxes are drawn to the console width, within limits. Non-console hosts throw here.
$script:Width = 80
try { $script:Width = [Math]::Max(64, [Math]::Min(100, $Host.UI.RawUI.WindowSize.Width - 1)) } catch { }

$script:Results   = New-Object System.Collections.Generic.List[object]
$script:Started   = Get-Date
$script:StepIndex = 0
$script:StepTotal = 0   # set once $Skip is known

# A line of output is a list of pieces; a piece is @('text', 'Colour') or a plain string.
# A list with a single piece needs the unary comma, @(, @('text', 'Colour')): in PowerShell
# @( <array> ) is that same array, not an array holding it.
#
# Colour goes to the console through the Console API and the plain text of each finished line
# goes to the log file. Start-Transcript is not used: Windows PowerShell 5.1 would log every
# coloured piece on a line of its own.
$script:IsConsole = ($Host.Name -eq 'ConsoleHost')
$script:DefaultColour = if ($script:IsConsole) { [Console]::ForegroundColor } else { 'Gray' }
$script:Log = $null
function Write-Parts([object[]]$Parts) {
    $plain = New-Object System.Text.StringBuilder
    foreach ($p in $Parts) {
        if ($p -is [array]) { $text = "$($p[0])"; $colour = "$($p[1])" } else { $text = "$p"; $colour = '' }
        $null = $plain.Append($text)
        if ($script:IsConsole) {
            if ($colour) { [Console]::ForegroundColor = $colour }
            [Console]::Write($text)
            if ($colour) { [Console]::ForegroundColor = $script:DefaultColour }
        }
        elseif ($colour) { Write-Host $text -NoNewline -ForegroundColor $colour }
        else { Write-Host $text -NoNewline }
    }
    if ($script:IsConsole) { [Console]::WriteLine() } else { Write-Host '' }
    if ($script:Log) { $script:Log.WriteLine($plain.ToString().TrimEnd()) }
}
# For the log file only (run header and footer).
function Write-LogOnly([string]$Text) {
    if ($script:Log) { $script:Log.WriteLine($Text) }
}

# Visible length of a list of pieces, for padding.
function Get-PartsLength([object[]]$Parts) {
    $n = 0
    foreach ($p in $Parts) { if ($p -is [array]) { $n += "$($p[0])".Length } else { $n += "$p".Length } }
    return $n
}

# Shortens a path to fit, keeping both ends: C:\Users\dav...\my-first-game
function Format-Fit([string]$Text, [int]$Max) {
    if ($Text.Length -le $Max) { return $Text }
    if ($Max -lt 8) { return $Text.Substring(0, [Math]::Max(0, $Max)) }
    $head = [int][Math]::Floor(($Max - 3) / 2)
    $tail = $Max - 3 - $head
    return $Text.Substring(0, $head) + '...' + $Text.Substring($Text.Length - $tail)
}
# Shortens a sentence to fit, keeping the start: Luau autocomplete, type chec...
function Format-Clip([string]$Text, [int]$Max) {
    if ($Text.Length -le $Max) { return $Text }
    if ($Max -lt 4) { return $Text.Substring(0, [Math]::Max(0, $Max)) }
    return $Text.Substring(0, $Max - 3) + '...'
}
# Wraps a sentence at spaces so it fits the width; a single over-long word is cut.
function Split-Wrapped([string]$Text, [int]$Max) {
    if ($Text.Length -le $Max) { return , $Text }
    $lines = @()
    $line = ''
    foreach ($word in ($Text -split ' ')) {
        if ($line.Length -eq 0) { $line = $word }
        elseif (($line.Length + 1 + $word.Length) -le $Max) { $line += ' ' + $word }
        else { $lines += $line; $line = $word }
        while ($line.Length -gt $Max) { $lines += $line.Substring(0, $Max); $line = $line.Substring($Max) }
    }
    if ($line.Length -gt 0) { $lines += $line }
    return $lines
}

# Double-lined box, full width: edges ('top', 'middle', 'bottom') and padded rows.
function Write-BoxEdge([string]$Kind, [string]$Border) {
    $inner = $Glyph.DH * ($script:Width - 2)
    $line = switch ($Kind) {
        'top'    { "$($Glyph.DTL)$inner$($Glyph.DTR)" }
        'middle' { "$($Glyph.DLT)$inner$($Glyph.DRT)" }
        'bottom' { "$($Glyph.DBL)$inner$($Glyph.DBR)" }
    }
    Write-Parts @(, @($line, $Border))
}
function Write-BoxRow([object[]]$Parts, [string]$Border) {
    $inner = $script:Width - 4
    $over = (Get-PartsLength $Parts) - $inner
    if ($over -gt 0) {
        # Too long for the box: clip the last piece rather than break the right edge.
        $last = $Parts[-1]
        if ($last -is [array]) { $Parts[-1] = @((Format-Clip $last[0] ($last[0].Length - $over)), $last[1]) }
        else { $Parts[-1] = Format-Clip "$last" ("$last".Length - $over) }
    }
    $pad = $inner - (Get-PartsLength $Parts)
    # Note the extra parentheses: in PowerShell the comma binds tighter than +.
    Write-Parts (@(, @("$($Glyph.DV)  ", $Border)) + $Parts + @(, @(((' ' * $pad) + " $($Glyph.DV)"), $Border)))
}

# Section header: a light rule with the title set into it, and an optional grey "why" line.
#   +- 3/12 Roblox Studio ----------------------------------------
#   |   The Roblox game engine and editor
function Write-Section([object[]]$TitleParts, [string]$Why = '') {
    $lead = @(, @("$($Glyph.TL)$($Glyph.H) ", 'DarkCyan')) + $TitleParts
    $fill = [Math]::Max(0, $script:Width - (Get-PartsLength $lead) - 1)
    Write-Parts @()
    Write-Parts ($lead + @(, @((' ' + ($Glyph.H * $fill)), 'DarkCyan')))
    if ($Why) { Write-Body ' ' 'DarkGray' $Why 'DarkGray' }
}
function Write-Step([string]$Title, [string]$Why = '') {
    $script:StepIndex++
    Write-Section @( @("$($script:StepIndex)/$($script:StepTotal)", 'DarkCyan'), @(" $Title", 'White') ) $Why
}

# Body lines sit under the header, behind the rail:   |   v  message
# Long lines wrap to the console width; the mark goes on the first line only.
function Write-Body([string]$Mark, [string]$MarkColour, [string]$Msg, [string]$Colour) {
    if ([string]::IsNullOrWhiteSpace($Msg)) { return }
    $first = $true
    foreach ($raw in ($Msg -split "`r?`n")) {
        foreach ($line in (Split-Wrapped $raw.TrimEnd() ($script:Width - 6))) {
            $m = if ($first) { $Mark } else { ' ' }
            Write-Parts @( @("$($Glyph.V) ", 'DarkCyan'), @(" $m  ", $MarkColour), @($line, $Colour) )
            $first = $false
        }
    }
}
function Write-Info([string]$Msg) {
    if ($Msg -like 'DRY RUN: *') { Write-Body $Glyph.Dot 'Cyan' $Msg.Substring(9) 'DarkCyan' }
    else { Write-Body ' ' 'Gray' $Msg 'Gray' }
}
function Write-Ok([string]$Msg)    { Write-Body $Glyph.Ok  'Green'  $Msg 'White' }
function Write-Warn2([string]$Msg) { Write-Body '!'        'Yellow' $Msg 'Yellow' }
function Write-Fail([string]$Msg)  { Write-Body $Glyph.Bad 'Red'    $Msg 'Red' }

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
        # A blank stderr line arrives as an ErrorRecord whose text is "System.Management.Automation.RemoteException".
        $lines = & $Exe @Arguments 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $code; Output = (@($lines) -join "`n") }
}

# Last few lines of a command's output, without winget's spinner (- \ | /) and
# progress-bar ("1024 KB / 13.1 MB") lines.
function Get-OutputTail([string]$Text, [int]$Lines = 6) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $all = $Text.Split([char[]]@("`r", "`n"), [StringSplitOptions]::RemoveEmptyEntries) | Where-Object {
        ($_ -notmatch '^[\s\-\\|/]*$') -and ($_ -notmatch '(\d+%|[\d.]+ [KMG]?B / [\d.]+ [KMG]?B)\s*$')
    }
    return ((@($all) | Select-Object -Last $Lines) -join "`n")
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

# $HashMismatchFallback (optional) installs the package another way when winget's catalog
# entry is out of date. It returns $true if that worked.
function Install-WingetPackage([string]$Id, [string]$Friendly, [scriptblock]$HashMismatchFallback = $null) {
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
    if (($r.ExitCode -eq $WingetHashMismatch) -and $HashMismatchFallback) {
        Write-Warn2 "winget's record of the $Friendly installer is out of date (installer hash does not match). Trying the vendor's own download ..."
        if (& $HashMismatchFallback) {
            Write-Ok "$Friendly installed"
            Add-Result $Friendly 'installed' 'direct download (winget catalog out of date)'
            return $true
        }
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
# Installers that do not go through winget or an install.ps1
# ---------------------------------------------------------------------------
# Studio installs per user under %LOCALAPPDATA%\Roblox\Versions\<version>\ and registers an
# uninstall entry in HKCU. winget does not always recognise a Studio it did not install itself.
function Test-RobloxStudioInstalled {
    $versions = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
    if (Get-ChildItem -Path $versions -Filter 'RobloxStudioBeta.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) {
        return $true
    }
    $entries = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue
    return [bool]($entries | Where-Object { $_.DisplayName -like 'Roblox Studio*' })
}

# winget's Roblox Studio entry points at Roblox's unversioned "latest" installer, so its recorded
# hash goes stale every time Roblox updates that file. Download the same file, and check that it
# carries Roblox's code signature instead.
function Install-RobloxStudioDirect {
    $ProgressPreference = 'SilentlyContinue'   # the 5.1 progress bar makes downloads very slow
    $dir = Join-Path $env:TEMP ('roblox-studio-' + [guid]::NewGuid().ToString('N'))
    $exe = Join-Path $dir 'RobloxStudioInstaller.exe'
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Info "Downloading $StudioInstallerUrl ..."
        Invoke-WebRequest -Uri $StudioInstallerUrl -OutFile $exe -UseBasicParsing
        $sig = Get-AuthenticodeSignature -FilePath $exe
        if (($sig.Status -ne 'Valid') -or ($sig.SignerCertificate.Subject -notlike 'CN=Roblox Corporation,*')) {
            Write-Info "Not running it: the download is not validly signed by Roblox Corporation (signature: $($sig.Status))."
            return $false
        }
        Write-Info 'Signed by Roblox Corporation. Running the installer; it shows its own progress window ...'
        # Wait for the installer process only. It starts Studio when it finishes, and this
        # script should carry on while Studio is open.
        $p = Start-Process -FilePath $exe -PassThru
        if (-not $p.WaitForExit(20 * 60 * 1000)) {
            Write-Info 'The Studio installer is still running after 20 minutes. Let it finish, then re-run this script.'
            return $false
        }
        return (Test-RobloxStudioInstalled)
    }
    catch {
        Write-Info "Direct download failed: $($_.Exception.Message)"
        return $false
    }
    finally {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Same steps as Rokit's own install.ps1 (download the latest release, run `rokit self-install`),
# but keeps self-install's output and exit code, which install.ps1 throws away.
function Install-Rokit {
    $ProgressPreference = 'SilentlyContinue'
    $dir = Join-Path $env:TEMP ('rokit-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Info "Looking up the latest Rokit release ($RokitReleaseApi) ..."
        $release = Invoke-RestMethod -Uri $RokitReleaseApi -Headers @{ 'X-GitHub-Api-Version' = '2022-11-28' }
        # Rokit's install.ps1 also uses the x86_64 build on every PC; Windows on Arm runs it emulated.
        $asset = @($release.assets | Where-Object { $_.name -like 'rokit-*-windows-x86_64.zip' }) | Select-Object -First 1
        if (-not $asset) {
            Write-Info "Rokit release $($release.tag_name) has no windows-x86_64 download."
            return
        }
        Write-Info "Downloading $($asset.name) ..."
        $zip = Join-Path $dir $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $dir -Force
        $exe = Get-ChildItem -Path $dir -Filter 'rokit.exe' -Recurse | Select-Object -First 1
        if (-not $exe) {
            Write-Info "rokit.exe was not inside $($asset.name)."
            return
        }
        Write-Info 'rokit self-install ...'
        $r = Invoke-Native $exe.FullName @('self-install')
        if ($r.ExitCode -ne 0) { Write-Warn2 "rokit self-install exited with code $($r.ExitCode)" }
        Write-Info (Get-OutputTail $r.Output)
    }
    catch {
        Write-Warn2 "Rokit download failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
$exitCode = 0
$logDir  = Join-Path $env:USERPROFILE 'roblox-dev-setup-logs'
$logFile = Join-Path $logDir ('setup-{0}.log' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    # UTF-8 with a byte-order mark, so Notepad shows the box-drawing characters correctly.
    $script:Log = New-Object System.IO.StreamWriter($logFile, $true, (New-Object System.Text.UTF8Encoding($true)))
    $script:Log.AutoFlush = $true
    Write-LogOnly 'Roblox + Claude Code setup'
    Write-LogOnly "Started    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-LogOnly "User       $env:USERDOMAIN\$env:USERNAME on $env:COMPUTERNAME"
    Write-LogOnly "Script     $PSCommandPath"
    Write-LogOnly "Options    ProjectName=$ProjectName  ProjectRoot=$ProjectRoot  Skip=$($Skip -join ',')  DryRun=$DryRun"
    Write-LogOnly "PowerShell $($PSVersionTable.PSVersion)  host $($Host.Name)"
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

$script:StepTotal = 1 + @($AllSteps | Where-Object { $Do[$_] }).Count   # preflight + enabled steps
$projectPath = Join-Path $ProjectRoot $ProjectName

# Title banner.
$inner = $script:Width - 4
Write-Parts @()
Write-BoxEdge 'top' 'Magenta'
Write-BoxRow @( @("$($Glyph.Play)  ", 'Magenta'), @('ROBLOX', 'Red'), @('  +  ', 'DarkGray'), @('CLAUDE CODE', 'DarkYellow') ) 'Magenta'
Write-BoxRow @(, @('   Developer setup for Windows', 'Gray')) 'Magenta'
Write-BoxEdge 'middle' 'Magenta'
Write-BoxRow @( @('Project   ', 'DarkGray'), @((Format-Fit $projectPath ($inner - 10)), 'White') ) 'Magenta'
Write-BoxRow @( @('Log       ', 'DarkGray'), @((Format-Fit $logFile ($inner - 10)), 'Gray') ) 'Magenta'
if ($Skip.Count -gt 0) {
    Write-BoxRow @( @('Skipping  ', 'DarkGray'), @((Format-Fit ($Skip -join ', ') ($inner - 10)), 'Yellow') ) 'Magenta'
}
if ($DryRun) {
    Write-BoxRow @( @('Mode      ', 'DarkGray'), @('DRY RUN: nothing will be installed or written', 'Yellow') ) 'Magenta'
}
Write-BoxRow @(, @("$($script:StepTotal) steps. Safe to run again: anything already installed is skipped.", 'DarkGray')) 'Magenta'
Write-BoxEdge 'bottom' 'Magenta'

try {
    # -----------------------------------------------------------------------
    Write-Step 'Preflight checks' 'Windows version, winget and internet access'
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
        Write-Step 'Git for Windows' 'Version control. Claude Code also uses its Bash shell.'
        $null = Install-WingetPackage 'Git.Git' 'Git for Windows'
    }
    if ($Do.VSCode) {
        Write-Step 'Visual Studio Code' 'The code editor'
        $null = Install-WingetPackage 'Microsoft.VisualStudioCode' 'Visual Studio Code'
    }
    if ($Do.Studio) {
        Write-Step 'Roblox Studio' 'The Roblox game engine and editor'
        if (Test-RobloxStudioInstalled) {
            Write-Ok 'Roblox Studio is already installed'
            Add-Result 'Roblox Studio' 'present' 'Roblox.RobloxStudio'
        }
        else {
            Write-Info 'Studio may open itself when the install finishes. You can close it for now.'
            $null = Install-WingetPackage 'Roblox.RobloxStudio' 'Roblox Studio' { Install-RobloxStudioDirect }
        }
    }
    if ($Do.Node) {
        Write-Step 'Node.js LTS' 'Used by many MCP servers and developer tools'
        $null = Install-WingetPackage 'OpenJS.NodeJS.LTS' 'Node.js LTS'
    }
    Update-SessionPath

    # -----------------------------------------------------------------------
    if ($Do.Claude) {
        Write-Step 'Claude Code' "Anthropic's terminal coding agent"
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
        Write-Step 'Rokit' 'Installs and version-pins the Roblox command-line tools'
        if (Test-Command rokit) {
            Write-Ok "Rokit is already installed ($((Invoke-Native 'rokit' @('--version')).Output.Trim()))"
            Add-Result 'Rokit' 'present' ''
        }
        elseif ($DryRun) {
            Write-Info 'DRY RUN: download the latest Rokit release from GitHub; rokit self-install'
            Add-Result 'Rokit' 'dry-run' 'rokit self-install'
        }
        else {
            Install-Rokit
            # self-install normally adds this folder to PATH itself; make sure.
            $rokitBin = Join-Path $env:USERPROFILE '.rokit\bin'
            if (Test-Path (Join-Path $rokitBin 'rokit.exe')) {
                if (Add-UserPath $rokitBin) { Write-Info "Added $rokitBin to your PATH" }
            }
            Update-SessionPath
            if (Test-Command rokit) {
                Write-Ok "Rokit installed ($((Invoke-Native 'rokit' @('--version')).Output.Trim()))"
                Add-Result 'Rokit' 'installed' ''
            }
            else {
                Write-Fail "Rokit did not install: $rokitBin\rokit.exe is missing. See the messages above."
                Add-Result 'Rokit' 'FAILED' 'rokit.exe missing after self-install'
            }
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Tools) {
        Write-Step 'Rojo, StyLua, Selene' 'File sync into Studio, code formatter, linter (rokit add --global)'
        $canInstallTools = $DryRun -or (Test-Command rokit)
        if ($canInstallTools) {
            foreach ($t in $RokitTools) {
                if (Test-Command $t.Cmd) {
                    Write-Ok "$($t.Friendly) already installed"
                    Add-Result $t.Cmd 'present' $t.Spec
                    continue
                }
                if ($DryRun) {
                    Write-Info "DRY RUN: rokit trust $($t.Spec); rokit add --global $($t.Spec)"
                    Add-Result $t.Cmd 'dry-run' $t.Spec
                    continue
                }
                Write-Info "rokit add --global $($t.Spec) ..."
                # Rokit asks "Trust and install ...?" the first time it sees a tool, and fails
                # instead when it cannot ask (its output is captured here). This script chose these
                # tools, so trust them up front: the same as answering yes. Trust is per user, so it
                # also covers the project's `rokit add` below.
                $null = Invoke-Native 'rokit' @('trust', $t.Spec)
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
        Write-Step 'VS Code extensions' 'Claude Code, Luau language support, Rojo, StyLua, Selene, roblox-ui'
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
        Write-Step 'Rojo plugin for Roblox Studio' 'The Studio side of the file sync'
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
    if ($Do.Skills) {
        Write-Step 'Claude Code skill: graphify' 'A knowledge graph of your project, so Claude does not re-read every file'
        # uv tools (graphify) go in %USERPROFILE%\.local\bin, the folder Claude Code uses too.
        $uvBin = Join-Path $env:USERPROFILE '.local\bin'
        if (Test-Command uv) {
            Write-Ok "uv is already installed ($((Invoke-Native 'uv' @('--version')).Output.Trim()))"
            Add-Result 'uv (Python tool runner)' 'present' ''
        }
        elseif ($DryRun) {
            Write-Info "DRY RUN: irm $UvInstallUrl | iex   (fallback: winget install astral-sh.uv)"
            Add-Result 'uv (Python tool runner)' 'dry-run' 'official installer'
        }
        else {
            # Astral's installer puts uv.exe in .local\bin (next to claude.exe) and tells Windows
            # that PATH changed, so new terminals find it.
            $null = Invoke-RemoteInstaller $UvInstallUrl 'uv'
            if (Test-Path (Join-Path $uvBin 'uv.exe')) {
                if (Add-UserPath $uvBin) { Write-Info "Added $uvBin to your PATH" }
            }
            Update-SessionPath
            if (Test-Command uv) {
                Write-Ok "uv installed ($((Invoke-Native 'uv' @('--version')).Output.Trim()))"
                Add-Result 'uv (Python tool runner)' 'installed' $uvBin
            }
            else {
                Write-Warn2 'The uv installer did not produce a working "uv" command. Trying winget ...'
                $null = Install-WingetPackage 'astral-sh.uv' 'uv (Python tool runner)'
                Update-SessionPath
            }
        }
        $canInstallGraphify = $DryRun -or (Test-Command uv)
        if ($canInstallGraphify) {
            if (Test-Path $GraphifySkillFile) {
                Write-Ok "graphify skill already installed ($GraphifySkillFile)"
                Add-Result 'graphify' 'present' $GraphifySkillFile
            }
            elseif ($DryRun) {
                Write-Info "DRY RUN: uv tool install --python $GraphifyPython graphifyy; graphify install --platform windows"
                Add-Result 'graphify' 'dry-run' 'uv tool install graphifyy'
            }
            else {
                # PyPI name is graphifyy (two y); the command is graphify. uv downloads that Python itself if needed.
                Write-Info "uv tool install --python $GraphifyPython graphifyy ... (first run may also download Python; a few minutes)"
                $r = Invoke-Native 'uv' @('tool', 'install', '--python', $GraphifyPython, 'graphifyy')
                # uv puts tool executables in %USERPROFILE%\.local\bin; make sure that is on the user PATH.
                if (Test-Path (Join-Path $uvBin 'graphify.exe')) {
                    if (Add-UserPath $uvBin) { Write-Info "Added $uvBin to your PATH" }
                }
                Update-SessionPath
                if (Test-Command graphify) {
                    $gi = Invoke-Native 'graphify' @('install', '--platform', 'windows')
                    if (($gi.ExitCode -eq 0) -and (Test-Path $GraphifySkillFile)) {
                        Write-Ok 'graphify skill installed for Claude Code (type /graphify inside claude)'
                        Add-Result 'graphify' 'installed' $GraphifySkillFile
                    }
                    else {
                        Write-Fail "graphify install --platform windows failed (exit $($gi.ExitCode))"
                        Write-Info (Get-OutputTail $gi.Output)
                        Add-Result 'graphify' 'FAILED' "graphify install exit $($gi.ExitCode)"
                    }
                }
                else {
                    Write-Fail "uv tool install graphifyy did not produce a graphify command (uv exit $($r.ExitCode))"
                    Write-Info (Get-OutputTail $r.Output)
                    Add-Result 'graphify' 'FAILED' "uv exit $($r.ExitCode)"
                }
            }
        }
        else {
            Write-Warn2 'uv is not available, so graphify was not installed. Re-run after uv installs.'
            Add-Result 'graphify' 'SKIPPED' 'uv missing'
        }
    }

    # -----------------------------------------------------------------------
    if ($Do.Project) {
        Write-Step 'First project' $projectPath
        if (Test-Path $projectPath) {
            Write-Ok 'Project folder already exists; leaving it untouched'
            Add-Result 'Project' 'present' $projectPath
        }
        elseif ($DryRun) {
            Write-Info "DRY RUN: rojo init `"$projectPath`"; copy templates\CLAUDE.md + JOURNAL.md + skills\journal; write selene.toml + .vscode\settings.json; rokit init + add tools; rojo build; git commit"
            $templateDir = Join-Path $PSScriptRoot 'templates'
            foreach ($name in 'CLAUDE.md', 'JOURNAL.md', 'skills\journal\SKILL.md') {
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

                # Example project-level skill: /journal drafts today's JOURNAL.md entry.
                $skillSrc = Join-Path $templateDir 'skills\journal\SKILL.md'
                if (Test-Path $skillSrc) {
                    $skillDir = Join-Path $projectPath '.claude\skills\journal'
                    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
                    Copy-Item -Path $skillSrc -Destination (Join-Path $skillDir 'SKILL.md') -Force
                    Write-Ok 'Added .claude\skills\journal\SKILL.md (type /journal inside claude)'
                }
                else {
                    Write-Warn2 "Template not found, skipped: $skillSrc"
                }

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
    Write-Parts @()
    Write-Fail "Setup stopped: $($_.Exception.Message)"
    Add-Result 'Setup' 'STOPPED' $_.Exception.Message
    $exitCode = 1
}

# ---------------------------------------------------------------------------
# Summary: one row per result, then a verdict box
# ---------------------------------------------------------------------------
Write-Section @(, @('Summary', 'Magenta'))

# How each result status is shown: mark, colour, label.
$statusStyle = @{
    installed = @($Glyph.Ok,   'Green',     'installed')
    created   = @($Glyph.Ok,   'Green',     'created')
    present   = @($Glyph.Ok,   'DarkGreen', 'already there')
    'dry-run' = @($Glyph.Dot,  'Cyan',      'dry run')
    SKIPPED   = @($Glyph.Skip, 'Yellow',    'skipped')
    FAILED    = @($Glyph.Bad,  'Red',       'FAILED')
    STOPPED   = @($Glyph.Bad,  'Red',       'STOPPED')
}
$stepWidth = 4
foreach ($r in $script:Results) { $stepWidth = [Math]::Max($stepWidth, $r.Step.Length) }
$stepWidth   = [Math]::Min($stepWidth, 28)
$detailWidth = [Math]::Max(10, $script:Width - $stepWidth - 23)
foreach ($r in $script:Results) {
    $s = $statusStyle[$r.Status]
    if (-not $s) { $s = @($Glyph.Dot, 'Gray', $r.Status) }
    Write-Parts @(
        @("$($Glyph.V)  ", 'DarkCyan'),
        @($s[0], $s[1]),
        @(('  ' + (Format-Clip $r.Step $stepWidth).PadRight($stepWidth) + '  '), 'White'),
        @($s[2].PadRight(15), $s[1]),
        @((Format-Clip "$($r.Detail)" $detailWidth), 'DarkGray')
    )
}

# Totals line: "12 items in 4m 07s:  9 installed . 2 already there . 1 FAILED"
$failed  = @($script:Results | Where-Object { $_.Status -in 'FAILED', 'STOPPED' })
$elapsed = (Get-Date) - $script:Started
$elapsedText = if ($elapsed.TotalMinutes -ge 1) { '{0}m {1:d2}s' -f [int][Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds }
               else { '{0}s' -f [int]$elapsed.TotalSeconds }
$totals = @(, @("$($Glyph.BL)$($Glyph.H)$($Glyph.H) ", 'DarkCyan')) + @(, @("$($script:Results.Count) items in $elapsedText", 'Gray'))
$sep = ':  '
foreach ($status in 'installed', 'created', 'present', 'dry-run', 'SKIPPED', 'FAILED', 'STOPPED') {
    $n = @($script:Results | Where-Object { $_.Status -eq $status }).Count
    if ($n -eq 0) { continue }
    $s = $statusStyle[$status]
    $totals += , @($sep, 'DarkGray')
    $totals += , @("$n $($s[2])", $s[1])
    $sep = "  $($Glyph.Dot)  "
}
Write-Parts $totals

Write-Parts @()
if ($failed.Count -gt 0) {
    $names = ($failed | ForEach-Object { $_.Step }) -join ', '
    Write-BoxEdge 'top' 'Yellow'
    Write-BoxRow @( @("$($Glyph.Bad)  ", 'Red'), @("$($failed.Count) step(s) need attention:  ", 'Yellow'), @($names, 'White') ) 'Yellow'
    Write-BoxRow @(, @('   Fix the cause shown in red above, then run this again.', 'Gray')) 'Yellow'
    Write-BoxRow @(, @('   Steps that finished are skipped.', 'Gray')) 'Yellow'
    Write-BoxEdge 'bottom' 'Yellow'
    $exitCode = 1
}
elseif ($DryRun) {
    Write-BoxEdge 'top' 'Cyan'
    Write-BoxRow @( @("$($Glyph.Dot)  ", 'Cyan'), @('Dry run complete.  ', 'White'), @('Nothing was installed or written.', 'Gray') ) 'Cyan'
    Write-BoxEdge 'bottom' 'Cyan'
}
else {
    Write-BoxEdge 'top' 'Green'
    Write-BoxRow @( @("$($Glyph.Ok)  ", 'Green'), @('All set!  ', 'White'), @('Everything is installed and your first project is ready.', 'Gray') ) 'Green'
    Write-BoxEdge 'bottom' 'Green'
}

# ---------------------------------------------------------------------------
# What to do next
# ---------------------------------------------------------------------------
function Write-Next([int]$Number, [string]$Text) {
    $lead = "  $Number".PadLeft(4) + '  '
    foreach ($line in (Split-Wrapped $Text ($script:Width - 6))) {
        Write-Parts @( @($lead, 'Cyan'), @($line, 'Gray') )
        $lead = '      '
    }
}
function Write-NextNote([string]$Text) {
    foreach ($line in (Split-Wrapped $Text ($script:Width - 6))) {
        Write-Parts @( '      ', @($line, 'DarkGray') )
    }
}
function Write-NextCmd([string]$Command, [string]$Note = '') {
    $parts = @( '      ', @("$($Glyph.Play) ", 'DarkCyan'), @($Command, 'White') )
    if ($Note) { $parts += , @("   $Note", 'DarkGray') }
    Write-Parts $parts
}

Write-Section @(, @('What to do next', 'Magenta'))
if ($failed.Count -gt 0) {
    Write-Warn2 'First fix the failed steps and run this script again. Steps 4 to 8 need Rojo and the project folder.'
}
Write-Parts @()
Write-Next 1 'Open Roblox Studio from the Start menu and log in.'
Write-NextNote 'A free Roblox account is enough.'
Write-Next 2 'Open a NEW terminal window so the PATH changes apply: Start menu > Terminal.'
Write-NextNote 'Using the terminal inside VS Code? Quit VS Code completely and reopen it.'
Write-NextNote 'Still "not recognized"? Sign out of Windows and back in.'
Write-Next 3 'Log in to Claude Code. It needs a Claude Pro or Max subscription.'
Write-NextCmd 'claude' 'then follow the browser login'
Write-Next 4 'Start the file sync and leave it running.'
Write-NextCmd "cd `"$projectPath`""
Write-NextCmd 'rojo serve'
Write-Next 5 "In Studio: File > Open from File > $ProjectName.rbxlx (in the project folder), then Plugins tab > Rojo > Connect."
Write-Next 6 'In a second terminal, in the project folder, start Claude and ask it about the project.'
Write-NextCmd 'claude' 'then ask: "Read CLAUDE.md and explain how this project is set up."'
Write-Next 7 'Press Play (F5) in Studio. View > Output should show "Hello world, from server!".'
Write-Next 8 'Once the project has a few scripts, build its knowledge graph inside claude and ask questions through it.'
Write-NextCmd '/graphify .'
Write-NextCmd '/graphify query "how does scoring work"'
Write-Next 9 'End every session by writing up what you learned.'
Write-NextCmd '/journal'
Write-Parts @()
Write-Parts @( @('  Full log  ', 'DarkGray'), @($logFile, 'Gray') )
Write-Parts @()

if ($script:Log) {
    Write-LogOnly "Finished   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  exit code $exitCode"
    $script:Log.Close()
}
exit $exitCode
