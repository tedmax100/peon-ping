# peon-ping adapter for Google Antigravity CLI (Windows)
# Translates Antigravity lifecycle hooks into peon.ps1 stdin JSON

param(
    [string]$EventType = ""
)

$ErrorActionPreference = "SilentlyContinue"

$PeonDir = if ($env:CLAUDE_PEON_DIR) { $env:CLAUDE_PEON_DIR }
           else { Join-Path $env:USERPROFILE ".claude\hooks\peon-ping" }

$PeonScript = Join-Path $PeonDir "peon.ps1"

# Read JSON from stdin
$inputJson = $null
try {
    if ([Console]::IsInputRedirected) {
        $stream = [Console]::OpenStandardInput()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $raw = $reader.ReadToEnd()
        $reader.Close()
        if ($raw) { $inputJson = $raw | ConvertFrom-Json }
    }
} catch {}
if (-not $inputJson) { $inputJson = [PSCustomObject]@{} }

$event = if ($EventType) { $EventType } else { $inputJson.hookEventName }
$isPreTool = ($event -eq "PreToolUse")

if (Test-Path $PeonScript) {
    $convId = if ($inputJson.conversationId) { [string]$inputJson.conversationId } else { "$PID" }
    $sid = "antigravity-" + ($convId.Substring(0, [Math]::Min(8, $convId.Length)))
    $cwd = if ($inputJson.cwd) { [string]$inputJson.cwd } else { $PWD.Path }

    $mapped = $null
    $errorText = ""
    $toolName = ""

    switch ($event) {
        "SessionStart"   { $mapped = "SessionStart" }
        "PreInvocation"  { $mapped = "UserPromptSubmit" }
        "Stop"           { $mapped = "Stop" }
        "PostToolUse"    {
            if ($inputJson.error) {
                $mapped = "PostToolUseFailure"
                $errorText = [string]$inputJson.error
                $toolName = if ($inputJson.toolCall -and $inputJson.toolCall.name) { [string]$inputJson.toolCall.name } else { "Bash" }
            }
        }
    }

    if ($mapped) {
        $payload = [PSCustomObject]@{
            hook_event_name   = $mapped
            notification_type = ""
            cwd               = $cwd
            session_id        = $sid
            permission_mode   = ""
            source            = "antigravity"
        }
        if ($mapped -eq "PostToolUseFailure") {
            $payload | Add-Member -NotePropertyName "tool_name" -NotePropertyValue $toolName
            $payload | Add-Member -NotePropertyName "error" -NotePropertyValue $errorText
        }
        $payloadJson = $payload | ConvertTo-Json -Compress
        $payloadJson | & $PeonScript 2>$null
    }
}

if ($isPreTool) {
    Write-Output '{"decision": "allow"}'
} else {
    Write-Output "{}"
}
