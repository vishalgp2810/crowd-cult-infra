<#
.SYNOPSIS
  One-command PRODUCTION deploy for Crowd & Cult (GKE + Cloud Build + Cloud SQL).

.DESCRIPTION
  For each selected app: checks the repo (on master, clean), pushes master, builds the image in
  Cloud Build (all apps in parallel), optionally backs up Cloud SQL and runs migrations / platform
  seeds as one-shot Kubernetes Jobs, restarts the deployments and verifies the site responds.

  Never touches the dev VM. Never runs demo seeds.

.PARAMETER Apps
  Which apps to deploy: backend, frontend, admin, or all.   e.g.  -Apps backend,frontend

.PARAMETER Migrate
  Back up Cloud SQL, then run `npm run migrate` as a Job (after the backend image is built, before
  the rollout). Use whenever the backend has new files in src/Migrations.

.PARAMETER Seed
  Run `npm run seed` (platform data only: roles, catalogs...) as a Job after migrations.

.PARAMETER NoPush
  Don't `git push` (use when you already pushed).

.PARAMETER AllowDirty
  Deploy even if a repo has uncommitted changes (they are NOT included - Cloud Build uploads the
  working folder, so uncommitted files WOULD be built. Prefer committing first).

.PARAMETER Yes
  Skip the confirmation prompt.

.PARAMETER DryRun
  Print what would happen and exit.

.EXAMPLE
  .\deploy.ps1 -Apps frontend
.EXAMPLE
  .\deploy.ps1 -Apps backend,frontend -Migrate
.EXAMPLE
  .\deploy.ps1 -Apps all -DryRun
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("backend", "frontend", "admin", "all")]
  [string[]]$Apps,
  [switch]$Migrate,
  [switch]$Seed,
  [switch]$NoPush,
  [switch]$AllowDirty,
  [switch]$Yes,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- settings
$Project      = "crowdandcult-prod"
$Namespace    = "crowd-cult-prod"
$KubeContext  = "gke_crowdandcult-prod_asia-south1_crowd-cult-prod"
$SqlInstance  = "crowd-cult-prod-sql"
$Registry     = "asia-south1-docker.pkg.dev/$Project"
$ApiUrl       = "https://api.crowdandcult.com"
$SiteUrl      = "https://crowdandcult.com"
$AdminUrl     = "https://admin.crowdandcult.com"

$InfraRoot    = Split-Path -Parent $PSScriptRoot          # ...\crowd-cult-infra
$Workspace    = Split-Path -Parent $InfraRoot             # ...\CROWDANDCULT

$AppDefs = [ordered]@{
  backend  = @{ Repo = "crowd-cult-backend";  Deployment = "crowd-cult-backend";  Build = "tag";    Check = "$ApiUrl/health" }
  frontend = @{ Repo = "crowd-cult-frontend"; Deployment = "crowd-cult-frontend"; Build = "config"; Check = "$SiteUrl/" }
  admin    = @{ Repo = "crowd-cult-admin";    Deployment = "crowd-cult-admin";    Build = "config"; Check = "$AdminUrl/" }
}

if ($Apps -contains "all") { $Apps = @("backend", "frontend", "admin") }
$Apps = $Apps | Select-Object -Unique
if (($Migrate -or $Seed) -and ($Apps -notcontains "backend")) {
  Write-Host "Note: -Migrate/-Seed run with the CURRENT backend image (backend not being rebuilt)." -ForegroundColor Yellow
}

function Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "    OK  $text" -ForegroundColor Green }
function Warn($text) { Write-Host "    !!  $text" -ForegroundColor Yellow }
function Fail($text) { Write-Host ""; Write-Host "FAILED: $text" -ForegroundColor Red; exit 1 }

function Run([string]$exe, [string[]]$arguments) {
  # Runs a native command; success = exit code 0. gcloud/git/kubectl write progress to stderr,
  # which Windows PowerShell 5.1 would turn into a terminating error under "Stop" - so relax it here.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & $exe @arguments 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $prev }
  if ($code -ne 0) { throw "$exe $($arguments -join ' ') failed (exit $code):`n$($output | Out-String)" }
  return $output
}

# ---------------------------------------------------------------- preflight
Step "Preflight"
foreach ($tool in @("git", "gcloud", "kubectl")) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "'$tool' is not installed or not on PATH." }
}
$account = (& gcloud config get-value account 2>$null)
if (-not $account) { Fail "gcloud is not logged in. Run: gcloud auth login" }
Ok "gcloud account: $account"

$ctx = (& kubectl config current-context 2>$null)
if ($ctx -ne $KubeContext) {
  Fail "kubectl context is '$ctx', expected '$KubeContext'.`n       Run: gcloud container clusters get-credentials crowd-cult-prod --region asia-south1 --project $Project"
}
Ok "kubectl context: $ctx"

foreach ($app in $Apps) {
  $repoPath = Join-Path $Workspace $AppDefs[$app].Repo
  if (-not (Test-Path (Join-Path $repoPath ".git"))) { Fail "$repoPath is not a git repo." }
  $branch = (& git -C $repoPath rev-parse --abbrev-ref HEAD).Trim()
  if ($branch -ne "master") { Fail "$($AppDefs[$app].Repo) is on '$branch' - prod deploys from master." }
  $dirty = (& git -C $repoPath status --porcelain)
  if ($dirty -and -not $AllowDirty) {
    Fail "$($AppDefs[$app].Repo) has uncommitted changes (Cloud Build would ship them). Commit/stash, or pass -AllowDirty.`n$($dirty | Out-String)"
  }
  $head = (& git -C $repoPath log -1 --format="%h %s").Trim()
  Ok "$($AppDefs[$app].Repo): master @ $head"
}

# ---------------------------------------------------------------- plan
Step "Plan"
Write-Host "    Apps     : $($Apps -join ', ')"
Write-Host "    Push     : $(if ($NoPush) { 'no' } else { 'git push origin master' })"
Write-Host "    Migrate  : $(if ($Migrate) { "yes (Cloud SQL backup of $SqlInstance first)" } else { 'no' })"
Write-Host "    Seed     : $(if ($Seed) { 'yes (platform seeds only)' } else { 'no' })"
Write-Host "    Target   : PRODUCTION  ($Project / $Namespace)" -ForegroundColor Magenta
if ($DryRun) { Write-Host ""; Write-Host "Dry run - nothing done." -ForegroundColor Yellow; exit 0 }
if (-not $Yes) {
  $answer = Read-Host "Type 'deploy' to deploy to PRODUCTION"
  if ($answer -ne "deploy") { Write-Host "Cancelled."; exit 0 }
}
$started = Get-Date

# ---------------------------------------------------------------- push
if (-not $NoPush) {
  Step "Push master"
  foreach ($app in $Apps) {
    $repoPath = Join-Path $Workspace $AppDefs[$app].Repo
    Run "git" @("-C", $repoPath, "push", "origin", "master") | Out-Null
    Ok "$($AppDefs[$app].Repo) pushed"
  }
}

# ---------------------------------------------------------------- build (parallel)
Step "Cloud Build (parallel)"
$builds = @{}
foreach ($app in $Apps) {
  $def = $AppDefs[$app]
  $repoPath = Join-Path $Workspace $def.Repo
  Push-Location $repoPath
  try {
    if ($def.Build -eq "tag") {
      $image = "$Registry/$($def.Repo)/$($def.Repo):latest"
      $id = Run "gcloud" @("builds", "submit", "--async", "--project=$Project", "--tag", $image, ".", "--format=value(id)")
    } else {
      $id = Run "gcloud" @("builds", "submit", "--async", "--project=$Project", "--config", "cloudbuild.yaml", ".", "--format=value(id)")
    }
  } finally { Pop-Location }
  $buildId = ($id | Where-Object { $_ -match '^[0-9a-f-]{36}$' } | Select-Object -Last 1)
  if (-not $buildId) { Fail "Could not read the Cloud Build id for $app. Output:`n$($id | Out-String)" }
  $builds[$app] = $buildId
  Ok "$app build $buildId"
}

$deadline = (Get-Date).AddMinutes(25)
do {
  Start-Sleep -Seconds 15
  $pending = @()
  foreach ($app in $builds.Keys) {
    $status = "UNKNOWN"
    try { $status = ((Run "gcloud" @("builds", "describe", $builds[$app], "--project=$Project", "--format=value(status)")) | Select-Object -Last 1).Trim() } catch { }
    if ($status -eq "UNKNOWN") { $pending += $app; continue }  # transient API hiccup - retry next poll
    if ($status -in @("QUEUED", "WORKING", "PENDING")) { $pending += $app; continue }
    if ($status -ne "SUCCESS") {
      Fail "$app build $($builds[$app]) ended with status '$status'.`n       Logs: gcloud builds log $($builds[$app]) --project=$Project"
    }
  }
  if ($pending.Count) { Write-Host "    ...building: $($pending -join ', ')" }
} while ($pending.Count -and (Get-Date) -lt $deadline)
if ($pending.Count) { Fail "Builds still running after 25 min: $($pending -join ', ')" }
Ok "all builds succeeded"

# ---------------------------------------------------------------- database jobs
function Invoke-BackendJob([string]$jobFile, [string]$jobName) {
  $path = Join-Path $InfraRoot "k8s\base\$jobFile"
  # Jobs are immutable - remove the previous run first.
  Run "kubectl" @("delete", "job", $jobName, "-n", $Namespace, "--ignore-not-found") | Out-Null
  Run "kubectl" @("apply", "-n", $Namespace, "-f", $path) | Out-Null
  $completed = $true
  try {
    Run "kubectl" @("wait", "--for=condition=complete", "job/$jobName", "-n", $Namespace, "--timeout=600s") | Out-Null
  } catch { $completed = $false }
  $logs = @()
  try { $logs = Run "kubectl" @("logs", "job/$jobName", "-n", $Namespace) } catch { }
  $logs | Where-Object { $_ -match '^==|ERROR|Error' -and $_ -notmatch 'proxy server error' } | ForEach-Object { Write-Host "      $_" }
  if (-not $completed) { Fail "$jobName did not complete. Inspect: kubectl logs job/$jobName -n $Namespace" }
  Ok "$jobName complete"
}

if ($Migrate) {
  Step "Cloud SQL backup"
  Run "gcloud" @("sql", "backups", "create", "--instance=$SqlInstance", "--project=$Project",
                 "--description=pre-deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm')") | Out-Null
  Ok "backup created (gcloud sql backups list --instance=$SqlInstance --project=$Project)"
  Step "Migrations"
  Invoke-BackendJob "backend-migrate-job.yaml" "crowd-cult-backend-migrate"
}
if ($Seed) {
  Step "Platform seeds"
  Invoke-BackendJob "backend-seed-job.yaml" "crowd-cult-backend-seed"
}

# ---------------------------------------------------------------- rollout
Step "Rollout"
foreach ($app in $Apps) {
  Run "kubectl" @("rollout", "restart", "deployment/$($AppDefs[$app].Deployment)", "-n", $Namespace) | Out-Null
}
foreach ($app in $Apps) {
  Run "kubectl" @("rollout", "status", "deployment/$($AppDefs[$app].Deployment)", "-n", $Namespace, "--timeout=480s") | Out-Null
  Ok "$app rolled out"
}

# ---------------------------------------------------------------- verify
Step "Verify (the load balancer can return 502 for ~1 min while it switches pods)"
foreach ($app in $Apps) {
  $url = $AppDefs[$app].Check
  $code = 0
  for ($i = 0; $i -lt 18; $i++) {
    try { $code = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15).StatusCode } catch { $code = 0 }
    if ($code -eq 200) { break }
    Start-Sleep -Seconds 10
  }
  if ($code -eq 200) { Ok "$app  $url -> 200" } else { Warn "$app  $url did not return 200 yet - check it manually." }
}

$mins = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
Write-Host ""
Write-Host "Deploy finished in $mins min: $($Apps -join ', ')" -ForegroundColor Green
