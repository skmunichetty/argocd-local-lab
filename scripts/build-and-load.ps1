<#
.SYNOPSIS
  Builds both images with one unique tag, loads them into the kind cluster,
  and writes the tag into deploy/overlays/local/kustomization.yaml.
  It does NOT deploy anything: Argo CD deploys after you commit + push the overlay change.

.EXAMPLE
  .\scripts\build-and-load.ps1
  .\scripts\build-and-load.ps1 -Tag 20261007-1200
#>
param(
    [string]$Tag = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [string]$Cluster = 'argocd-lab'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
# Prefer the project-local kind (v0.33) over an older one on PATH.
$kind = if (Test-Path "$root\.tools\kind.exe") { "$root\.tools\kind.exe" } else { 'kind' }

function Invoke-Step([string]$description, [scriptblock]$command) {
    Write-Host "==> $description" -ForegroundColor Cyan
    # docker/kind print progress on stderr; judge success by exit code, not by stderr output.
    $ErrorActionPreference = 'Continue'
    & $command
    if ($LASTEXITCODE -ne 0) { throw "Failed: $description" }
}

Invoke-Step "Build hello-api:$Tag" { docker build -t "hello-api:$Tag" --build-arg "APP_VERSION=$Tag" "$root\src\api" }
Invoke-Step "Build hello-web:$Tag" { docker build -t "hello-web:$Tag" --build-arg "APP_VERSION=$Tag" "$root\src\web" }

# kind nodes have their own image store (containerd), separate from Docker Desktop's.
# This copies the images from Docker into the cluster node.
Invoke-Step "Load images into kind cluster '$Cluster'" { & $kind load docker-image "hello-api:$Tag" "hello-web:$Tag" --name $Cluster }

$overlay = "$root\deploy\overlays\local\kustomization.yaml"
$content = [IO.File]::ReadAllText($overlay)
$content = [regex]::Replace($content, '(?m)^(\s+newTag:\s*)"[^"]*"', "`${1}""$Tag""")
[IO.File]::WriteAllText($overlay, $content, (New-Object Text.UTF8Encoding $false))

Write-Host ""
Write-Host "Images built and loaded with tag $Tag; overlay updated." -ForegroundColor Green
Write-Host "Next: review, commit and push so Argo CD deploys it:"
Write-Host "  git diff deploy/overlays/local/kustomization.yaml"
Write-Host "  git commit -am `"Deploy $Tag`""
Write-Host "  git push"
