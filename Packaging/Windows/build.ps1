param(
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$project = Join-Path $root "Platforms/Delta.CrossPlatform/Delta.CrossPlatform.csproj"
$publish = Join-Path $root ".build/windows-publish"
$wxs = Join-Path $PSScriptRoot "Delta.wxs"
$harvested = Join-Path $root ".build/windows-appfiles.wxs"
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

$files = @(Get-ChildItem -Path $publish -File -Recurse | Sort-Object FullName)
if ($files.Count -eq 0) { throw "No published Windows files were found to package." }

$wixNamespace = "http://wixtoolset.org/schemas/v4/wxs"
$sha256 = [System.Security.Cryptography.SHA256]::Create()
function Get-PathId([string]$prefix, [string]$value) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value.ToLowerInvariant())
    $hash = $sha256.ComputeHash($bytes)
    $suffix = -join ($hash[0..7] | ForEach-Object { $_.ToString("x2") })
    return "${prefix}_$suffix"
}

$rootDirectory = @{
    Id = "INSTALLFOLDER"
    Children = @{}
}
$componentEntries = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    $relativePath = [System.IO.Path]::GetRelativePath($publish, $file.FullName)
    $relativeDirectory = [System.IO.Path]::GetDirectoryName($relativePath)
    $directory = $rootDirectory
    if ($relativeDirectory) {
        $currentPath = ""
        foreach ($segment in $relativeDirectory.Split([System.IO.Path]::DirectorySeparatorChar)) {
            $currentPath = if ($currentPath) {
                Join-Path $currentPath $segment
            } else {
                $segment
            }
            if (!$directory.Children.ContainsKey($segment)) {
                $directory.Children[$segment] = @{
                    Id = Get-PathId "AppDir" $currentPath
                    Name = $segment
                    Children = @{}
                }
            }
            $directory = $directory.Children[$segment]
        }
    }

    $componentId = Get-PathId "AppComponent" $relativePath
    $componentEntries.Add(@{
        ComponentId = $componentId
        FileId = Get-PathId "AppFile" $relativePath
        Source = $file.FullName
        DirectoryId = $directory.Id
    })
}

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.Encoding = [System.Text.UTF8Encoding]::new($false)
$writer = [System.Xml.XmlWriter]::Create($harvested, $settings)
function Write-DirectoryTree($writer, $directory) {
    foreach ($name in ($directory.Children.Keys | Sort-Object)) {
        $child = $directory.Children[$name]
        $writer.WriteStartElement("Directory", $wixNamespace)
        $writer.WriteAttributeString("Id", $child.Id)
        $writer.WriteAttributeString("Name", $child.Name)
        Write-DirectoryTree $writer $child
        $writer.WriteEndElement()
    }
}

try {
    $writer.WriteStartDocument()
    $writer.WriteStartElement("Wix", $wixNamespace)
    $writer.WriteStartElement("Fragment", $wixNamespace)
    $writer.WriteStartElement("DirectoryRef", $wixNamespace)
    $writer.WriteAttributeString("Id", "INSTALLFOLDER")
    Write-DirectoryTree $writer $rootDirectory
    $writer.WriteEndElement()
    $writer.WriteStartElement("ComponentGroup", $wixNamespace)
    $writer.WriteAttributeString("Id", "AppFiles")
    foreach ($entry in $componentEntries) {
        $writer.WriteStartElement("Component", $wixNamespace)
        $writer.WriteAttributeString("Id", $entry.ComponentId)
        $writer.WriteAttributeString("Guid", "*")
        $writer.WriteAttributeString("Directory", $entry.DirectoryId)
        $writer.WriteStartElement("File", $wixNamespace)
        $writer.WriteAttributeString("Id", $entry.FileId)
        $writer.WriteAttributeString("Source", $entry.Source)
        $writer.WriteAttributeString("KeyPath", "yes")
        $writer.WriteEndElement()
        $writer.WriteEndElement()
    }
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndElement()
    $writer.WriteEndDocument()
}
finally {
    $writer.Dispose()
    $sha256.Dispose()
}

wix build $wxs $harvested -arch x64 -d "PublishDir=$publish" -d "Version=$Version" -o $msi
if ($LASTEXITCODE -ne 0) { throw "MSI packaging failed." }
Write-Host "Installer: $msi"
