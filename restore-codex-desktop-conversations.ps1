param(
    [string]$CcSwitchPath,
    [string]$Provider,
    [switch]$AllProviders,
    [switch]$IncludeNonInteractive,
    [switch]$NoCcSwitch,
    [switch]$NoPrompt,
    [switch]$NoWaitForCodexExit,
    [switch]$KeepOriginalProvider,
    [switch]$NoPin,
    [switch]$DryRun,
    [string]$WorkspaceRoot = "D:\codex",
    [int]$SummaryChars = 110
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-CodexHome {
    if ($env:CODEX_HOME) {
        return $env:CODEX_HOME
    }
    return Join-Path $HOME ".codex"
}

function Get-CurrentProvider {
    param([string]$CodexHome)

    $configPath = Join-Path $CodexHome "config.toml"
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Codex config not found: $configPath"
    }

    $configText = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $match = [regex]::Match($configText, '(?m)^model_provider\s*=\s*"([^"]+)"')
    if (-not $match.Success) {
        throw "Could not read model_provider from $configPath"
    }
    return $match.Groups[1].Value
}

function Get-DefaultCcSwitchPath {
    $paths = @(
        (Join-Path $env:LOCALAPPDATA "Programs\CC Switch\cc-switch.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\CC Switch\CC Switch.exe"),
        (Join-Path $env:LOCALAPPDATA "cc-switch\cc-switch.exe"),
        (Join-Path $env:LOCALAPPDATA "cc-switch\CC Switch.exe"),
        (Join-Path $env:PROGRAMFILES "CC Switch\cc-switch.exe"),
        (Join-Path $env:PROGRAMFILES "CC Switch\CC Switch.exe"),
        (Join-Path ${env:PROGRAMFILES(X86)} "CC Switch\cc-switch.exe"),
        (Join-Path ${env:PROGRAMFILES(X86)} "CC Switch\CC Switch.exe")
    )

    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    $cmd = Get-Command "cc-switch.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    $cmd = Get-Command "CC Switch.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }
    return ""
}

function Read-CcSwitchPath {
    param(
        [string]$Current,
        [switch]$NoPrompt,
        [switch]$AllowMissing
    )

    $default = if ($Current) { $Current } else { Get-DefaultCcSwitchPath }
    if ($default) {
        Write-Host "Detected CC Switch path:"
        Write-Host "  $default"
        if ($NoPrompt) {
            return $default
        }
        $inputPath = Read-Host "Press Enter to use it, or paste cc-switch.exe path"
        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            return $default
        }
        $inputPath = $inputPath.Trim().Trim('"')
        if (-not (Test-Path -LiteralPath $inputPath)) {
            throw "CC Switch executable not found: $inputPath"
        }
        return $inputPath
    }

    if ($AllowMissing) {
        Write-Host "CC Switch path was not detected."
        return ""
    }
    if ($NoPrompt) {
        throw "CC Switch executable was not detected. Pass -CcSwitchPath or remove -NoPrompt."
    }
    $inputPath = (Read-Host "Paste cc-switch.exe path").Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $inputPath)) {
        throw "CC Switch executable not found: $inputPath"
    }
    return $inputPath
}

function ConvertTo-Snippet {
    param(
        [string]$Text,
        [int]$MaxLength
    )

    if (-not $Text) {
        return ""
    }
    $snippet = $Text -replace '(?s)<environment_context>.*?</environment_context>', ' '
    $snippet = $snippet -replace '(?s)<turn_aborted>.*?</turn_aborted>', ' '
    $snippet = $snippet -replace 'sk-[A-Za-z0-9_\-]{12,}', 'sk-***'
    $snippet = $snippet -replace 'tp-[A-Za-z0-9_\-]{12,}', 'tp-***'
    $snippet = $snippet -replace '(?i)(api[-_ ]?key\s*[=:]\s*)[A-Za-z0-9_\-]{12,}', '$1***'
    $snippet = $snippet -replace '\s+', ' '
    $snippet = $snippet.Trim()
    if ($snippet.Length -gt $MaxLength) {
        return $snippet.Substring(0, [Math]::Max(0, $MaxLength - 3)) + "..."
    }
    return $snippet
}

function Get-MessageText {
    param([object]$Content)

    $parts = foreach ($part in $Content) {
        if ($part.type -eq "input_text" -and $part.text) {
            [string]$part.text
        }
        elseif ($part.text) {
            [string]$part.text
        }
    }
    return ($parts -join " ")
}

function Get-SessionInfo {
    param([System.IO.FileInfo]$File)

    if (-not $IncludeNonInteractive -and $File.Name -match 'exec|review') {
        return $null
    }

    $idMatch = [regex]::Match($File.BaseName, '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$')
    if (-not $idMatch.Success) {
        return $null
    }

    $id = $idMatch.Groups[1].Value
    $provider = ""
    $source = "vscode"
    $cwd = ""
    $cliVersion = ""
    $model = ""
    $reasoningEffort = ""
    $sandboxPolicy = '{"type":"danger-full-access"}'
    $approvalMode = "never"
    $threadName = ""
    $firstUserMessage = ""
    $recentUserMessages = New-Object System.Collections.Generic.List[string]
    $firstTimestamp = ""
    $lastTimestamp = ""

    foreach ($line in Get-Content -LiteralPath $File.FullName -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $item = $line | ConvertFrom-Json
        }
        catch {
            continue
        }

        if (-not $firstTimestamp -and $item.timestamp) {
            $firstTimestamp = [string]$item.timestamp
        }
        if ($item.timestamp) {
            $lastTimestamp = [string]$item.timestamp
        }

        if ($item.type -eq "session_meta" -and $item.payload) {
            if ($item.payload.id) { $id = [string]$item.payload.id }
            if ($item.payload.model_provider) { $provider = [string]$item.payload.model_provider }
            if ($item.payload.source) { $source = [string]$item.payload.source }
            if ($item.payload.cwd) { $cwd = [string]$item.payload.cwd }
            if ($item.payload.cli_version) { $cliVersion = [string]$item.payload.cli_version }
        }
        elseif ($item.type -eq "turn_context" -and $item.payload) {
            if ($item.payload.model) { $model = [string]$item.payload.model }
            if ($item.payload.effort) { $reasoningEffort = [string]$item.payload.effort }
            if ($item.payload.approval_policy) { $approvalMode = [string]$item.payload.approval_policy }
            if ($item.payload.sandbox_policy) { $sandboxPolicy = $item.payload.sandbox_policy | ConvertTo-Json -Compress -Depth 20 }
        }
        elseif ($item.type -eq "event_msg" -and $item.payload.type -eq "thread_name_updated" -and $item.payload.thread_name) {
            $threadName = [string]$item.payload.thread_name
        }
        elseif ($item.type -eq "response_item" -and $item.payload.type -eq "message" -and $item.payload.role -eq "user" -and $item.payload.content) {
            $msg = ConvertTo-Snippet -Text (Get-MessageText -Content $item.payload.content) -MaxLength 300
            if ($msg) {
                if (-not $firstUserMessage) { $firstUserMessage = $msg }
                $recentUserMessages.Add($msg)
            }
        }
    }

    if (-not $firstTimestamp) { $firstTimestamp = $File.CreationTimeUtc.ToString("o") }
    if (-not $lastTimestamp) { $lastTimestamp = $File.LastWriteTimeUtc.ToString("o") }
    if (-not $cwd) { $cwd = $WorkspaceRoot }

    $title = ConvertTo-Snippet -Text $threadName -MaxLength 120
    if (-not $title) { $title = ConvertTo-Snippet -Text $firstUserMessage -MaxLength 120 }
    if (-not $title) { $title = $id }

    $summary = ""
    if ($recentUserMessages.Count -gt 0) {
        $summary = ConvertTo-Snippet -Text (@($recentUserMessages | Select-Object -Last 2) -join " | ") -MaxLength $SummaryChars
    }

    [pscustomobject]@{
        Id = $id
        Provider = $provider
        Source = $source
        Cwd = $cwd
        CodexCwd = if ($cwd.StartsWith("\\?\")) { $cwd } else { "\\?\$cwd" }
        Title = $title
        Summary = $summary
        File = $File.FullName
        UpdatedAt = $File.LastWriteTime
        CreatedAtSeconds = [DateTimeOffset]::Parse($firstTimestamp).ToUnixTimeSeconds()
        UpdatedAtSeconds = [DateTimeOffset]::Parse($lastTimestamp).ToUnixTimeSeconds()
        CreatedAtMs = [DateTimeOffset]::Parse($firstTimestamp).ToUnixTimeMilliseconds()
        UpdatedAtMs = [DateTimeOffset]::Parse($lastTimestamp).ToUnixTimeMilliseconds()
        CliVersion = $cliVersion
        FirstUserMessage = $firstUserMessage
        Model = $model
        ReasoningEffort = $reasoningEffort
        SandboxPolicy = $sandboxPolicy
        ApprovalMode = $approvalMode
    }
}

function Backup-File {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        $backup = "$Path.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $backup -Force
        Write-Host "Backup: $backup"
    }
}

function Update-RolloutProvider {
    param(
        [string]$Path,
        [string]$Provider
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    foreach ($line in [System.IO.File]::ReadLines($Path, [System.Text.Encoding]::UTF8)) {
        if (-not $changed -and -not [string]::IsNullOrWhiteSpace($line)) {
            try {
                $item = $line | ConvertFrom-Json
                if ($item.type -eq "session_meta" -and $item.payload) {
                    $prop = $item.payload.PSObject.Properties["model_provider"]
                    if ($prop) {
                        $prop.Value = $Provider
                    }
                    else {
                        $item.payload | Add-Member -NotePropertyName "model_provider" -NotePropertyValue $Provider
                    }
                    $lines.Add(($item | ConvertTo-Json -Compress -Depth 100))
                    $changed = $true
                    continue
                }
            }
            catch {
            }
        }
        $lines.Add($line)
    }

    if ($changed) {
        Backup-File -Path $Path
        [System.IO.File]::WriteAllLines($Path, [string[]]$lines, [System.Text.UTF8Encoding]::new($false))
    }
    return $changed
}

function ConvertTo-SqlLiteral {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return "NULL" }
    return "'" + ($Text -replace "'", "''") + "'"
}

function ConvertTo-SqlNullableLiteral {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "NULL" }
    return ConvertTo-SqlLiteral -Text $Text
}

function Set-JsonProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    $existing = $Object.PSObject.Properties[$Name]
    if ($existing) {
        $existing.Value = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-JsonArray {
    param(
        [object]$Object,
        [string]$Name
    )

    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop -or $null -eq $prop.Value) {
        return @()
    }
    if ($prop.Value -is [System.Array]) {
        return @($prop.Value)
    }
    return @($prop.Value)
}

function Set-JsonArray {
    param(
        [object]$Object,
        [string]$Name,
        [object[]]$Values
    )

    Set-JsonProperty -Object $Object -Name $Name -Value @($Values)
}

function Ensure-ObjectProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    $prop = $Object.PSObject.Properties[$Name]
    if (-not $prop -or $null -eq $prop.Value) {
        $value = [pscustomobject]@{}
        Set-JsonProperty -Object $Object -Name $Name -Value $value
        return $value
    }
    return $prop.Value
}

function Add-Unique {
    param(
        [object[]]$Values,
        [string[]]$ToAdd
    )

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($value in $Values) {
        if ($null -ne $value -and -not $list.Contains([string]$value)) {
            $list.Add([string]$value)
        }
    }
    foreach ($value in $ToAdd) {
        if ($value -and -not $list.Contains($value)) {
            $list.Add($value)
        }
    }
    return @($list)
}

function Remove-Values {
    param(
        [object[]]$Values,
        [string[]]$ToRemove
    )

    $remove = @{}
    foreach ($value in $ToRemove) { $remove[$value] = $true }
    $result = foreach ($value in $Values) {
        if ($null -ne $value -and -not $remove.ContainsKey([string]$value)) {
            [string]$value
        }
    }
    return @($result)
}

function Wait-CodexDesktopExit {
    param([switch]$NoPrompt)

    $processes = @(Get-Process -Name Codex -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return
    }

    Write-Host ""
    Write-Host "Codex Desktop is still running:"
    $processes | Select-Object Id, ProcessName, MainWindowTitle | Format-Table -AutoSize
    Write-Host "Fully quit Codex Desktop now. Use the window close button and also quit it from the tray if needed."
    Write-Host "This script will continue only after Codex.exe has exited, so desktop state will not be overwritten."

    if (-not $NoPrompt) {
        Read-Host "After quitting Codex Desktop, press Enter to start waiting"
    }

    while (@(Get-Process -Name Codex -ErrorAction SilentlyContinue).Count -gt 0) {
        Write-Host "Waiting for Codex Desktop to exit..."
        Start-Sleep -Seconds 2
    }

    Write-Host "Codex Desktop has exited. Continuing repair."
}

function Select-Provider {
    param(
        [object[]]$Sessions,
        [string]$CurrentProvider
    )

    $groups = @($Sessions |
        Group-Object Provider |
        Sort-Object -Property @{ Expression = { if ($_.Name -eq $CurrentProvider) { 0 } else { 1 } } }, @{ Expression = "Count"; Descending = $true }, @{ Expression = "Name" })

    if ($groups.Count -eq 0) {
        throw "No local Codex sessions were found."
    }

    Write-Host ""
    Write-Host "Select the original API/provider to restore."
    Write-Host "Tip: choose the provider used by the old conversations. For your recent old conversations, that is usually 'yuan'."
    for ($i = 0; $i -lt $groups.Count; $i++) {
        $label = if ([string]::IsNullOrWhiteSpace($groups[$i].Name)) { "<unknown>" } else { $groups[$i].Name }
        $currentMark = if ($groups[$i].Name -eq $CurrentProvider) { " current" } else { "" }
        Write-Host ("  {0}. {1} ({2} session(s)){3}" -f ($i + 1), $label, $groups[$i].Count, $currentMark)
    }
    Write-Host ("  {0}. All providers ({1} session(s))" -f ($groups.Count + 1), $Sessions.Count)

    while ($true) {
        $choice = (Read-Host "Enter a number").Trim()
        $choiceNumber = 0
        if ([int]::TryParse($choice, [ref]$choiceNumber)) {
            if ($choiceNumber -ge 1 -and $choiceNumber -le $groups.Count) {
                return [pscustomobject]@{
                    Provider = [string]$groups[$choiceNumber - 1].Name
                    AllProviders = $false
                }
            }
            if ($choiceNumber -eq ($groups.Count + 1)) {
                return [pscustomobject]@{
                    Provider = ""
                    AllProviders = $true
                }
            }
        }
        Write-Host "Please enter a number from 1 to $($groups.Count + 1)."
    }
}

$codexHome = Get-CodexHome
$sessionRoot = Join-Path $codexHome "sessions"
$indexPath = Join-Path $codexHome "session_index.jsonl"
$stateDb = Join-Path $codexHome "state_5.sqlite"
$globalStatePath = Join-Path $codexHome ".codex-global-state.json"
$workspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')

if (-not (Test-Path -LiteralPath $sessionRoot)) {
    throw "Codex sessions folder not found: $sessionRoot"
}

$originalProvider = Get-CurrentProvider -CodexHome $codexHome
$ccSwitchExe = if ($NoCcSwitch) {
    Read-CcSwitchPath -Current $CcSwitchPath -NoPrompt -AllowMissing
}
else {
    Read-CcSwitchPath -Current $CcSwitchPath -NoPrompt:($NoPrompt -or $DryRun) -AllowMissing:$DryRun
}

$allSessions = @(Get-ChildItem -LiteralPath $sessionRoot -Recurse -File -Filter "rollout-*.jsonl" |
    ForEach-Object { Get-SessionInfo -File $_ } |
    Where-Object { $_ } |
    Sort-Object UpdatedAt)

if (-not $Provider -and -not $AllProviders) {
    $providerChoice = Select-Provider -Sessions $allSessions -CurrentProvider $originalProvider
    if ($providerChoice.AllProviders) {
        $AllProviders = $true
    }
    else {
        $Provider = $providerChoice.Provider
    }
}

$targetProvider = if ($Provider) { $Provider } else { $originalProvider }

$selectedSessions = if ($AllProviders) {
    @($allSessions)
}
else {
    @($allSessions | Where-Object { $_.Provider -eq $targetProvider })
}

if ($selectedSessions.Count -eq 0) {
    throw "No Codex sessions found for provider '$targetProvider'. Use -AllProviders or pass -Provider with the old provider name."
}

Write-Host ""
Write-Host "Codex home:        $codexHome"
Write-Host "Workspace root:    $workspaceRoot"
Write-Host "Provider now:      $originalProvider"
if (-not $AllProviders) { Write-Host "Provider filter:   $targetProvider" }
Write-Host ""
Write-Host "Sessions that will be restored into Codex Desktop:"
$selectedSessions | Sort-Object UpdatedAt -Descending | Select-Object Id, Provider, UpdatedAt, Title, Summary | Format-Table -Wrap -AutoSize
Write-Host "Total selected sessions: $($selectedSessions.Count)"
Write-Host "Total local rollout sessions: $($allSessions.Count)"

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run only. Nothing was changed."
    exit 0
}

if (-not $NoCcSwitch) {
    Write-Host ""
    Write-Host "Opening CC Switch:"
    Write-Host "  $ccSwitchExe"
    Start-Process -FilePath $ccSwitchExe | Out-Null
    if (-not $NoPrompt) {
        Write-Host ""
        Read-Host "Switch API/provider in CC Switch, then press Enter to repair desktop visibility"
    }
}

if (-not $NoWaitForCodexExit) {
    Wait-CodexDesktopExit -NoPrompt:$NoPrompt
}
elseif (Get-Process -Name Codex -ErrorAction SilentlyContinue) {
    Write-Host ""
    Write-Host "Warning: Codex Desktop is running and may overwrite .codex-global-state.json after this script writes it."
}

$resumeProvider = Get-CurrentProvider -CodexHome $codexHome

Write-Host ""
Write-Host "Repairing session_index.jsonl..."
Backup-File -Path $indexPath
$indexLines = foreach ($session in ($allSessions | Sort-Object UpdatedAtMs, Id)) {
    [pscustomobject]@{
        id = $session.Id
        thread_name = $session.Title
        updated_at = [DateTimeOffset]::FromUnixTimeMilliseconds($session.UpdatedAtMs).UtcDateTime.ToString("o")
    } | ConvertTo-Json -Compress
}
[System.IO.File]::WriteAllLines($indexPath, [string[]]$indexLines, [System.Text.UTF8Encoding]::new($false))
Write-Host "  session_index.jsonl lines: $($indexLines.Count)"

Write-Host "Repairing state_5.sqlite threads table..."
if (-not (Test-Path -LiteralPath $stateDb)) {
    throw "Codex state database not found: $stateDb"
}
Backup-File -Path $stateDb
$dbIds = @(sqlite3 $stateDb "select id from threads;")
$missingThreads = @($allSessions | Where-Object { $_.Id -notin $dbIds })
if ($missingThreads.Count -gt 0) {
    $insertSqlPath = Join-Path $env:TEMP "codex-backfill-threads-$(Get-Date -Format 'yyyyMMddHHmmss').sql"
    $sqlLines = New-Object System.Collections.Generic.List[string]
    $sqlLines.Add("BEGIN;")
    foreach ($session in $missingThreads) {
        $sqlLines.Add(@"
INSERT OR IGNORE INTO threads (
    id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
    sandbox_policy, approval_mode, tokens_used, has_user_event, archived,
    cli_version, first_user_message, memory_mode, model, reasoning_effort,
    created_at_ms, updated_at_ms
) VALUES (
    $(ConvertTo-SqlLiteral -Text $session.Id),
    $(ConvertTo-SqlLiteral -Text $session.File),
    $($session.CreatedAtSeconds),
    $($session.UpdatedAtSeconds),
    $(ConvertTo-SqlLiteral -Text $session.Source),
    $(ConvertTo-SqlLiteral -Text $session.Provider),
    $(ConvertTo-SqlLiteral -Text $session.CodexCwd),
    $(ConvertTo-SqlLiteral -Text $session.Title),
    $(ConvertTo-SqlLiteral -Text $session.SandboxPolicy),
    $(ConvertTo-SqlLiteral -Text $session.ApprovalMode),
    0,
    0,
    0,
    $(ConvertTo-SqlLiteral -Text $session.CliVersion),
    $(ConvertTo-SqlLiteral -Text $session.FirstUserMessage),
    'enabled',
    $(ConvertTo-SqlNullableLiteral -Text $session.Model),
    $(ConvertTo-SqlNullableLiteral -Text $session.ReasoningEffort),
    $($session.CreatedAtMs),
    $($session.UpdatedAtMs)
);
"@)
    }
    $sqlLines.Add("COMMIT;")
    [System.IO.File]::WriteAllLines($insertSqlPath, [string[]]$sqlLines, [System.Text.UTF8Encoding]::new($false))
    sqlite3 $stateDb ".read '$insertSqlPath'"
    Write-Host "  inserted missing threads: $($missingThreads.Count)"
}
else {
    Write-Host "  inserted missing threads: 0"
}

$selectedIds = @($selectedSessions | Sort-Object UpdatedAt -Descending | ForEach-Object { $_.Id })
$selectedIdsSql = ($selectedIds | ForEach-Object { ConvertTo-SqlLiteral -Text $_ }) -join ","
if ($selectedIdsSql) {
    $providerSql = if ($KeepOriginalProvider) { "" } else { ", model_provider = $(ConvertTo-SqlLiteral -Text $resumeProvider)" }
    sqlite3 $stateDb "update threads set archived = 0, archived_at = NULL, has_user_event = 1, cwd = '$(($("\\?\$workspaceRoot") -replace "'", "''"))'$providerSql where id in ($selectedIdsSql);"
}
Write-Host "  marked selected threads visible: $($selectedIds.Count)"
if (-not $KeepOriginalProvider) {
    Write-Host "  updated selected threads to current provider: $resumeProvider"
    $changedRollouts = 0
    foreach ($session in $selectedSessions) {
        if (Update-RolloutProvider -Path $session.File -Provider $resumeProvider) {
            $changedRollouts++
        }
    }
    Write-Host "  updated selected rollout metadata provider: $changedRollouts"
}

Write-Host "Repairing Codex Desktop global state..."
if (-not (Test-Path -LiteralPath $globalStatePath)) {
    [System.IO.File]::WriteAllText($globalStatePath, "{}", [System.Text.UTF8Encoding]::new($false))
}
Backup-File -Path $globalStatePath
$globalState = Get-Content -LiteralPath $globalStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $globalState) { $globalState = [pscustomobject]@{} }

Set-JsonArray -Object $globalState -Name "project-order" -Values (Add-Unique -Values (Get-JsonArray -Object $globalState -Name "project-order") -ToAdd @($workspaceRoot))
Set-JsonArray -Object $globalState -Name "active-workspace-roots" -Values (Add-Unique -Values (Get-JsonArray -Object $globalState -Name "active-workspace-roots") -ToAdd @($workspaceRoot))

$hints = Ensure-ObjectProperty -Object $globalState -Name "thread-workspace-root-hints"
foreach ($session in $selectedSessions) {
    Set-JsonProperty -Object $hints -Name $session.Id -Value $workspaceRoot
}

$projectless = Remove-Values -Values (Get-JsonArray -Object $globalState -Name "projectless-thread-ids") -ToRemove $selectedIds
Set-JsonArray -Object $globalState -Name "projectless-thread-ids" -Values $projectless

if (-not $NoPin) {
    Set-JsonArray -Object $globalState -Name "pinned-thread-ids" -Values (Add-Unique -Values (Get-JsonArray -Object $globalState -Name "pinned-thread-ids") -ToAdd $selectedIds)
}

$persisted = Ensure-ObjectProperty -Object $globalState -Name "electron-persisted-atom-state"
$collapsed = Ensure-ObjectProperty -Object $persisted -Name "sidebar-collapsed-sections-v1"
Set-JsonProperty -Object $collapsed -Name "pinned" -Value $false
Set-JsonProperty -Object $collapsed -Name "threads" -Value $false
Set-JsonProperty -Object $collapsed -Name "chats" -Value $false

$json = $globalState | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($globalStatePath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "  mapped selected threads to project: $workspaceRoot"
if (-not $NoPin) { Write-Host "  pinned selected threads: $($selectedIds.Count)" }

Write-Host ""
Write-Host "Provider before CC Switch: $originalProvider"
Write-Host "Provider now:              $resumeProvider"
Write-Host ""
Write-Host "Done. Reopen Codex Desktop. The restored sessions should appear in Pinned and under project '$workspaceRoot'."
