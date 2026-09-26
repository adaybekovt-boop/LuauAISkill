# Windows variant of setup_luau_toolchain.sh. Run: powershell -ExecutionPolicy Bypass -File tools\setup_luau_toolchain.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dest = if ($env:LUAU_TOOLCHAIN) { $env:LUAU_TOOLCHAIN } else { Join-Path $Root ".toolchain" }
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
Invoke-WebRequest "https://github.com/luau-lang/luau/releases/latest/download/luau-windows.zip" -OutFile "$Dest\luau.zip"
Invoke-WebRequest "https://github.com/JohnnyMorganz/luau-lsp/releases/latest/download/luau-lsp-win64.zip" -OutFile "$Dest\lsp.zip"
Expand-Archive -Force "$Dest\luau.zip" $Dest; Expand-Archive -Force "$Dest\lsp.zip" $Dest
Remove-Item "$Dest\luau.zip","$Dest\lsp.zip"
Invoke-WebRequest "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" -OutFile "$Dest\globalTypes.d.luau"
Write-Host "Toolchain ready in $Dest"
