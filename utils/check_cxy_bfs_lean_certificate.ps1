param(
    [int]$Seed = 0
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    & python utils/export_cxy_bfs_lean_certificate.py --seed $Seed
    if ($LASTEXITCODE -ne 0) {
        throw "Python BFS certificate export failed with exit code $LASTEXITCODE"
    }

    & lake build LogicSubmissions
    if ($LASTEXITCODE -ne 0) {
        throw "LogicSubmissions Lake build failed with exit code $LASTEXITCODE"
    }

    & lake env lean LogicSubmissions/CxyBfsCertificate.lean
    if ($LASTEXITCODE -ne 0) {
        throw "Python BFS Lean certificate check failed with exit code $LASTEXITCODE"
    }

    Write-Output "CXY Python BFS -> Lean PathPlanSound certificate passed (seed=$Seed)."
}
finally {
    Pop-Location
}
