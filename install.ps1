<#
.SYNOPSIS
  Install the codelantern CLI on Windows from a GitHub Release, assuming the
  repository's releases are PUBLIC (no authentication).

.DESCRIPTION
  For the private repository use ..\install.ps1 instead, which authenticates via
  the GitHub CLI (gh). This variant uses Invoke-WebRequest against the public
  /releases/latest/download/ (or /releases/download/<tag>/) URLs and needs no gh
  and no token. It fails with a download error if the release is not public.

.PARAMETER Version
  Release tag to install (e.g. v0.1.0). Defaults to $env:VERSION, else the latest release.

.PARAMETER InstallDir
  Install directory. Defaults to %LOCALAPPDATA%\Programs\codelantern (no elevation).

.EXAMPLE
  .\install.ps1
  .\install.ps1 -Version v0.1.0
#>
[CmdletBinding()]
param(
  [string]$Version = "$env:VERSION",
  [string]$InstallDir = "$(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Programs\codelantern' } else { Join-Path $HOME '.codelantern-bin' })"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Repo = if ($env:REPO) { $env:REPO } else { 'codelantern-ai/codelantern-cli' }

function Get-TargetArch {
  # PROCESSOR_ARCHITECTURE reflects the *process*, not the OS. A 32-bit
  # PowerShell host on 64-bit Windows (WOW64) reports 'x86' there and exposes
  # the real OS architecture in PROCESSOR_ARCHITEW6432, so prefer that.
  $osArch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  switch ($osArch) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { throw "install.ps1: unsupported architecture '$osArch' (need amd64 or arm64)." }
  }
}

function Get-Asset {
  param([string]$Uri, [string]$OutFile)
  try { Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing }
  catch { throw "install.ps1: could not download $Uri (is the release public?). $($_.Exception.Message)" }
}

function Test-Checksum {
  param([string]$Archive, [string]$ChecksumsFile)
  $name = Split-Path $Archive -Leaf
  $line = Get-Content $ChecksumsFile | Where-Object { ($_ -split '\s+')[-1] -eq $name } | Select-Object -First 1
  if (-not $line) { return $false }
  $expected = ($line -split '\s+')[0]
  $actual = (Get-FileHash -Algorithm SHA256 -Path $Archive).Hash
  return ($actual -ieq $expected)
}

# ── main ─────────────────────────────────────────────────────────────────────
$arch = Get-TargetArch
$base = if ($Version) {
  "https://github.com/$Repo/releases/download/$Version"
} else {
  "https://github.com/$Repo/releases/latest/download"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cl-install-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
  # checksums.txt has a version-independent URL; fetch it, then read the real
  # (version-stamped) archive name for this host from it.
  $checksums = Join-Path $tmp 'checksums.txt'
  Get-Asset -Uri "$base/checksums.txt" -OutFile $checksums

  $name = Get-Content $checksums |
    ForEach-Object { ($_ -split '\s+')[-1] } |
    Where-Object { $_ -match "_windows_${arch}\.zip$" } |
    Select-Object -First 1
  if (-not $name) { throw "install.ps1: no release asset found for windows/${arch}." }

  $archive = Join-Path $tmp $name
  Get-Asset -Uri "$base/$name" -OutFile $archive

  if (-not (Test-Checksum -Archive $archive -ChecksumsFile $checksums)) {
    throw "install.ps1: checksum verification failed for $name — aborting, nothing installed."
  }

  $extract = Join-Path $tmp 'extract'
  # Use the .NET API rather than Expand-Archive: some modules (e.g. PSCX) ship a
  # shadowing Expand-Archive with different parameters (no -DestinationPath), and
  # this also works on Windows PowerShell 5.1 and PowerShell 7 alike.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $extract)
  $bin = Get-ChildItem -Path $extract -Filter 'codelantern.exe' -Recurse | Select-Object -First 1
  if (-not $bin) { throw "install.ps1: codelantern.exe not found in $name." }

  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  Copy-Item -Path $bin.FullName -Destination (Join-Path $InstallDir 'codelantern.exe') -Force

  $onPath = ($env:PATH -split ';') -contains $InstallDir
  if (-not $onPath) {
    Write-Warning "install.ps1: $InstallDir is not on your PATH. Add it (PowerShell): `$env:PATH = `"$InstallDir;`$env:PATH`" — or add it permanently via System > Environment Variables."
  }

  Write-Host "install.ps1: installed to $InstallDir\codelantern.exe"
  & (Join-Path $InstallDir 'codelantern.exe') --version
}
finally {
  Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
