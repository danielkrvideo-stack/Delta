param(
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$project = Join-Path $root "Platforms/Delta.CrossPlatform/Delta.CrossPlatform.csproj"
$publish = Join-Path $root ".build/windows-publish"
$wxs = Join-Path $PSScriptRoot "Delta.wxs"
$exe = Join-Path $publish "Delta.exe"
$msi = Join-Path $root "Delta-windows-x64-$Version.msi"
$zip = Join-Path $root "Delta-windows-x64-$Version.zip"

dotnet publish $project -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=false -p:Version=$Version -o $publish
if ($LASTEXITCODE -ne 0) { throw "Windows publish failed." }
if (!(Test-Path $exe)) { throw "Published Delta.exe was not created." }
Compress-Archive -Path (Join-Path $publish "*") -DestinationPath $zip -Force
Write-Host "Application executable: $exe"
Write-Host "Portable application package: $zip"
if (!(Get-Command wix -ErrorAction SilentlyContinue)) {
    Write-Warning "WiX v4 is not installed; MSI was not created."
    exit 0
}
$harvested = Join-Path $root ".build/windows-appfiles.wxs"
wix extension add --global WixToolset.Heat/4.0.5
if ($LASTEXITCODE -ne 0) { throw "WiX Heat extension installation failed." }
wix heat dir $publish -nologo -cg AppFiles -dr INSTALLFOLDER -gg -sfrag -sreg -srd `
    -var var.PublishDir -out $harvested
if ($LASTEXITCODE -ne 0) { throw "Harvesting Windows application files failed." }
wix build $wxs $harvested -arch x64 -d "PublishDir=$publish" -d "Version=$Version" -o $msi
if ($LASTEXITCODE -ne 0) { throw "MSI packaging failed." }
Write-Host "Installer: $msi"
