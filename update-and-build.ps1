<#
.SYNOPSIS
    Sync this fork with upstream, rebuild the distribution, and fetch the official upstream release JAR.

.DESCRIPTION
    One-shot maintenance script for this MegaBasterd fork. Runs three stages in order:

      1. UPDATE   - git fetch the 'upstream' remote (tonikelope/megabasterd) and merge
                    upstream/master into the current branch.
      2. BUILD    - run build-dist.ps1 (mvn clean package -> jar\MegaBasterd.jar ->
                    dist\MegaBasterd\MegaBasterd.exe via jpackage).
      3. UPSTREAM - download the official pre-built MegaBasterd_<version>.jar from
                    tonikelope's latest GitHub release into upstream-build\ (kept as a
                    reference / rollback binary; NOT placed in jar\ so it never pollutes
                    the jpackage input).

    The working tree must be clean before stage 1. On a merge conflict the script stops and
    leaves the tree in the conflicted state for you to resolve manually; re-run with
    -SkipUpdate afterwards to continue with build + download.

.PARAMETER SkipUpdate
    Skip stage 1 (git fetch + merge upstream).

.PARAMETER SkipBuild
    Skip stage 2 (build-dist.ps1).

.PARAMETER SkipUpstreamJar
    Skip stage 3 (download upstream release JAR).

.PARAMETER OnlyIfChanged
    Only run the build stage when the upstream merge actually brought in new commits.
    Ignored if -SkipUpdate is set (no merge ran, so "changed" is unknown -> always build).

.PARAMETER UpstreamRemote
    Name of the git remote pointing at the original repo. Default: 'upstream'.

.PARAMETER UpstreamBranch
    Upstream branch to merge from. Default: 'master'.

.PARAMETER UpstreamRepo
    OWNER/REPO used with 'gh release download'. Default: 'tonikelope/megabasterd'.

.EXAMPLE
    .\update-and-build.ps1
    Full run: merge upstream, rebuild, download the upstream release JAR.

.EXAMPLE
    .\update-and-build.ps1 -OnlyIfChanged
    Merge upstream and download the release JAR, but only rebuild if the merge pulled in
    new commits.

.EXAMPLE
    .\update-and-build.ps1 -SkipUpstreamJar
    Just merge upstream and rebuild; don't touch the upstream release binary.
#>
[CmdletBinding()]
param(
    [switch]$SkipUpdate,
    [switch]$SkipBuild,
    [switch]$SkipUpstreamJar,
    [switch]$OnlyIfChanged,
    [string]$UpstreamRemote = 'upstream',
    [string]$UpstreamBranch = 'master',
    [string]$UpstreamRepo   = 'tonikelope/megabasterd'
)

$ErrorActionPreference = 'Stop'
$root          = $PSScriptRoot
$upstreamDir   = Join-Path $root 'upstream-build'
$script:merged = $false   # did stage 1 actually bring in new commits?

# --- helpers ---------------------------------------------------------------
function Write-Step($msg) { Write-Host ">> [bird] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host ">> [bird] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host ">> [bird] $msg" -ForegroundColor Yellow }
function Fail($msg) {
    Write-Host ">> [bird] $msg" -ForegroundColor Red
    exit 1
}

# Run a native command (git/gh/build script) and fail on non-zero exit.
function Invoke-Native {
    param([Parameter(Mandatory)][scriptblock]$Command, [string]$What)
    & $Command
    if ($LASTEXITCODE -ne 0) { Fail "$What failed (exit $LASTEXITCODE)." }
}

# =========================================================================
# Stage 1 - UPDATE: fetch + merge upstream
# =========================================================================
if ($SkipUpdate) {
    Write-Warn2 "Stage 1/3 (update): skipping the upstream run. You're the boss."
} else {
    Write-Step "Stage 1/3: peeking at what '$UpstreamRemote/$UpstreamBranch' has been up to..."

    # Must be inside this repo's work tree.
    & git -C $root rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { Fail "$root isn't a git tree. I build birds, not miracles." }

    # Upstream remote must exist.
    & git -C $root remote get-url $UpstreamRemote *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail "No remote called '$UpstreamRemote'. Point me at one first:`n    git remote add $UpstreamRemote https://github.com/$UpstreamRepo.git"
    }

    $branch = (& git -C $root rev-parse --abbrev-ref HEAD).Trim()
    Write-Host "    perched on branch: $branch"

    # Refuse to merge with modified tracked files - a merge could clobber uncommitted
    # work, and git won't start a merge on a dirty index anyway. Untracked files (-uno
    # excludes them) are safe: git preserves them across a merge and only aborts if an
    # incoming change would overwrite one, which the conflict path below handles.
    $dirty = & git -C $root status --porcelain --untracked-files=no
    if ($dirty) {
        Fail "You've got uncommitted changes to tracked files. Tidy up (commit or stash) before I merge:`n$($dirty -join "`n")"
    }

    Write-Step "Fetching from $UpstreamRemote to see what's new..."
    Invoke-Native { git -C $root fetch $UpstreamRemote } "git fetch"

    # How many commits are we behind upstream?
    $incoming = [int](& git -C $root rev-list --count "HEAD..$UpstreamRemote/$UpstreamBranch").Trim()
    if ($incoming -eq 0) {
        Write-Ok "Nothing new upstream - you're already current with $UpstreamRemote/$UpstreamBranch. Smug."
    } else {
        Write-Step "Ooh, $incoming fresh commit(s) upstream. Merging them into '$branch'..."
        $before = (& git -C $root rev-parse HEAD).Trim()
        & git -C $root merge --no-edit "$UpstreamRemote/$UpstreamBranch"
        if ($LASTEXITCODE -ne 0) {
            $conflicts = & git -C $root diff --name-only --diff-filter=U
            Fail ("Merge conflicts. Ugh. I left the mess exactly where it is - untangle it, commit, then re-run me with -SkipUpdate.`n" +
                  "The scene of the crime:`n$($conflicts -join "`n")`n" +
                  "(Rather run away? git merge --abort)")
        }
        $after = (& git -C $root rev-parse HEAD).Trim()
        $script:merged = ($before -ne $after)
        Write-Ok "Merged clean. HEAD $($before.Substring(0,7)) -> $($after.Substring(0,7)). Told you I'm good."
    }
}

# =========================================================================
# Stage 2 - BUILD: build-dist.ps1
# =========================================================================
if ($SkipBuild) {
    Write-Warn2 "Stage 2/3 (build): skipping the rebuild. Living dangerously, I see."
} elseif ($OnlyIfChanged -and -not $SkipUpdate -and -not $script:merged) {
    Write-Warn2 "Stage 2/3 (build): nothing changed upstream, so I'm not rebuilding for fun (-OnlyIfChanged)."
} else {
    Write-Step "Stage 2/3: time to build. Handing off to my colleague in build-dist.ps1..."
    $buildScript = Join-Path $root 'build-dist.ps1'
    if (-not (Test-Path $buildScript)) { Fail "Can't find build-dist.ps1 at $buildScript. Kind of need that one." }
    & $buildScript
    if ($LASTEXITCODE -ne 0) { Fail "build-dist.ps1 fell over (exit $LASTEXITCODE). Take it up with the build bird." }
    Write-Ok "Build's in the bag."
}

# =========================================================================
# Stage 3 - UPSTREAM: download the official release JAR
# =========================================================================
if ($SkipUpstreamJar) {
    Write-Warn2 "Stage 3/3 (upstream JAR): skipping the souvenir download."
} else {
    Write-Step "Stage 3/3: swiping the official build from $UpstreamRepo for the trophy shelf..."

    & gh --version *> $null
    if ($LASTEXITCODE -ne 0) {
        Fail "No GitHub CLI ('gh') on this box. Install it, or re-run with -SkipUpstreamJar and we'll pretend this never happened."
    }

    $tag = (& gh release view --repo $UpstreamRepo --json tagName --jq '.tagName' 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tag)) {
        Fail "Couldn't read the latest release of $UpstreamRepo. Is 'gh' even logged in? (gh auth status)"
    }
    $tag = $tag.Trim()
    Write-Host "    hottest upstream release: $tag"

    if (-not (Test-Path $upstreamDir)) { New-Item -ItemType Directory -Force -Path $upstreamDir | Out-Null }

    Write-Step "Grabbing $tag (MegaBasterd_*.jar) into upstream-build\..."
    & gh release download $tag --repo $UpstreamRepo --pattern 'MegaBasterd_*.jar' --dir $upstreamDir --clobber
    if ($LASTEXITCODE -ne 0) {
        Fail "The download nose-dived (exit $LASTEXITCODE)."
    }

    $jar = Get-ChildItem (Join-Path $upstreamDir 'MegaBasterd_*.jar') -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $jar) { Fail "gh swears it worked, but there's no MegaBasterd_*.jar in $upstreamDir. Suspicious." }
    Write-Ok ("Bagged the upstream JAR: {0} ({1:N1} MB)" -f $jar.FullName, ($jar.Length / 1MB))
}

Write-Host ""
Write-Ok "That's everything you asked for. This bird is out. *drops mic*"
