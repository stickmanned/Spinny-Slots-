[CmdletBinding()]
param(
    [switch]$Export
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Join-Path $repositoryRoot 'spinny-slots!'

function Find-GodotConsole {
    $command = Get-Command 'godot4', 'godot' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    $installRoot = 'C:\Program Files\Godot'
    if (Test-Path -LiteralPath $installRoot) {
        $candidate = Get-ChildItem -LiteralPath $installRoot -Filter 'Godot*_console.exe' -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw 'Godot was not found. Install Godot 4.7.1 or add godot/godot4 to PATH.'
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Host "==> $Description"
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

$godot = Find-GodotConsole
Write-Host "Using Godot: $godot"

Invoke-Checked -Executable $godot -Description 'Loading and validating the project main scene' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    '--quit-after', '2'
)

Invoke-Checked -Executable $godot -Description 'Running the Milestone 2b deterministic dialogue, interaction, and layout checks' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    'res://scenes/dev/smoke_test.tscn'
)

Invoke-Checked -Executable $godot -Description 'Running the Milestone 2c phone, ticket, selector, and machine-loop checks' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    'res://scenes/dev/milestone_2c_test.tscn'
)

Invoke-Checked -Executable $godot -Description 'Running the Milestone 3 paytable, weighted RNG, and odds panel checks' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    'res://scenes/dev/milestone_3_symbols_test.tscn'
)

Invoke-Checked -Executable $godot -Description 'Running the Milestone 3b upgrade, audio-sync, and interaction-safety checks' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    'res://scenes/dev/milestone_3b_upgrades_test.tscn'
)

Invoke-Checked -Executable $godot -Description 'Running the Milestone 3c rarest-symbol gem bonus and confetti checks' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    'res://scenes/dev/milestone_3c_rare_bonus_test.tscn'
)

Invoke-Checked -Executable $godot -Description 'Running the Junk King battle, progression, save, and encounter integration checks' -Arguments @(
    '--headless',
    '--path', $projectRoot,
    'res://scenes/dev/junk_king_feature_test.tscn'
)

if ($Export) {
    $buildDirectory = Join-Path $projectRoot 'builds'
    New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null
    $exportPath = Join-Path $buildDirectory 'SpinnySlots.exe'

    Invoke-Checked -Executable $godot -Description 'Exporting the Windows release build' -Arguments @(
        '--headless',
        '--recovery-mode',
        '--path', $projectRoot,
        '--export-release', 'Windows Desktop', $exportPath
    )

    if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
        throw "Godot reported success but did not create $exportPath."
    }

    Write-Host '==> Launch-checking the exported Windows build'
    $launchCheck = Start-Process -FilePath $exportPath -ArgumentList @(
        '--headless',
        '--quit-after', '3'
    ) -WindowStyle Hidden -Wait -PassThru
    if ($launchCheck.ExitCode -ne 0) {
        throw "The exported Windows build failed its launch check with exit code $($launchCheck.ExitCode)."
    }

    Write-Host "Windows build: $exportPath"
}

Write-Host 'Verification complete.'
