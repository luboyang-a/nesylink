param(
    [ValidateRange(1, 10000)]
    [int]$NumEnvs = 100,

    [string]$JsonOut = "eval_results/final_robustness_suite.json",

    [int]$Seed = 0
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$policy = "submissions/robust_new_agent.py"
$tasks = @(
    "mathematical_logic/task_1",
    "mathematical_logic/task_2",
    "mathematical_logic/task_3",
    "mathematical_logic/task_4",
    "mathematical_logic/task_5"
)

$arguments = @(
    "utils/evaluate_policy.py",
    "--tasks"
) + $tasks

foreach ($task in $tasks) {
    $arguments += @("--task-policy", "$task=$policy")
}

$arguments += @(
    "--info-mode", "safe",
    "--robustness-suite",
    "--num-envs", $NumEnvs,
    "--seed", $Seed,
    "--json-out", $JsonOut
)

Push-Location $repoRoot
try {
    & python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Final Agent evaluation failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
