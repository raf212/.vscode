$ErrorActionPreference = "Stop"

$Root = (git rev-parse --show-toplevel).Trim()
$Build = "$Root/build-acpp-windows"
$Acpp = "$Root/external/AdaptiveCpp/install-windows"

$InputDB = "$Build/compile_commands.json"
$OutputDir = "$Root/.vscode/build-acpp-windows-intellisense"
$OutputDB = "$OutputDir/compile_commands.json"

if (-not (Test-Path $InputDB)) {
    throw "Missing compilation database: $InputDB"
}

New-Item `
    -ItemType Directory `
    -Force `
    $OutputDir |
    Out-Null

$Database = Get-Content $InputDB -Raw | ConvertFrom-Json

foreach ($Entry in $Database) {

    # CMake normally emits "command", but support "arguments" too.
    if ($Entry.PSObject.Properties.Name -contains "arguments") {

        $Args = @($Entry.arguments)

        $CompilerIndex = -1

        for ($i = 0; $i -lt $Args.Count; ++$i) {
            $Arg = $Args[$i].Replace('\', '/')

            if ($Arg.EndsWith('/clang++.exe')) {
                $CompilerIndex = $i
            }
        }

        if ($CompilerIndex -ge 0) {
            $Entry.arguments =
                @("$Acpp/bin/clang++.exe") +
                $Args[($CompilerIndex + 1)..($Args.Count - 1)]
        }

        continue
    }

    if ($Entry.PSObject.Properties.Name -contains "command") {

        $Command = [string]$Entry.command

        # AdaptiveCpp's launcher contains the compiler path more than once.
        # The last clang++.exe is the real underlying compiler invocation.
        $Index = $Command.LastIndexOf(
            "clang++.exe",
            [System.StringComparison]::OrdinalIgnoreCase
        )

        if ($Index -lt 0) {
            continue
        }

        # Walk backward to the beginning of that compiler argument.
        $Start = $Index

        while (
            $Start -gt 0 -and
            -not [char]::IsWhiteSpace($Command[$Start - 1])
        ) {
            --$Start
        }

        $CompilerCommand = $Command.Substring($Start)

        # Force the compiler to the exact AdaptiveCpp LLVM installation.
        $FirstSpace = $CompilerCommand.IndexOf(' ')

        if ($FirstSpace -ge 0) {
            $CompilerCommand =
                "`"$Acpp/bin/clang++.exe`"" +
                $CompilerCommand.Substring($FirstSpace)
        }
        else {
            $CompilerCommand =
                "`"$Acpp/bin/clang++.exe`""
        }

        $Entry.command = $CompilerCommand
    }
}

$Database |
    ConvertTo-Json -Depth 20 |
    Set-Content `
        -Encoding UTF8 `
        $OutputDB

Write-Host ""
Write-Host "IntelliSense compilation database:"
Write-Host "  $OutputDB"