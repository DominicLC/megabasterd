$distPath = "$PSScriptRoot\dist\MegaBasterd"

# Cmdlet failures abort the script instead of limping on. Note: native tools
# (mvn, jpackage) still won't throw on non-zero exit under this preference, so
# the explicit $LASTEXITCODE checks after each of them below are still required.
$ErrorActionPreference = 'Stop'

Write-Host ">> [bird] Cracking my knuckles. Let's build a MegaBasterd..." -ForegroundColor Cyan

# Step 0: Preflight. Fail fast and loud if a prerequisite is missing, instead of
# discovering it as a cryptic error after a full Maven build (a missing jre\, for
# example, used to only blow up in the very last jpackage step).
Write-Host ">> [bird] Frisking the toolbox before we start..." -ForegroundColor Cyan
$missing = @()
if (-not (Get-Command mvn -ErrorAction SilentlyContinue))      { $missing += "mvn (Maven) isn't on PATH." }
if (-not (Get-Command jpackage -ErrorAction SilentlyContinue)) { $missing += "jpackage isn't on PATH (need a JDK 14+ bin\ on PATH)." }
if (-not (Test-Path "$PSScriptRoot\pom.xml"))                  { $missing += "pom.xml is missing at $PSScriptRoot." }
if (-not (Test-Path "$PSScriptRoot\jre"))                      { $missing += "jre\ runtime-image is missing -- run the jlink step from the README first." }
$icon = "$PSScriptRoot\src\main\resources\images\pica_roja_big.ico"
if (-not (Test-Path $icon))                                    { $missing += "app icon is missing at $icon." }
if ($missing.Count -gt 0) {
    Write-Host ">> [bird] Can't build like this. Sort these out first:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "     - $_" -ForegroundColor Red }
    exit 1
}
Write-Host ">> [bird] Toolbox checks out. Everything I need is here." -ForegroundColor Green

# Step 1: Maven build
Write-Host ">> [bird] Feeding the sources to Maven. This is the boring bit, grab a coffee." -ForegroundColor Cyan
mvn clean package -DskipTests -f "$PSScriptRoot\pom.xml"
if ($LASTEXITCODE -ne 0) {
    Write-Host ">> [bird] Maven threw a tantrum (exit $LASTEXITCODE). Build's off. Fix your code." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host ">> [bird] Maven's done and the JAR lives. Onward." -ForegroundColor Green

# Step 2: Copy built JAR to jar/
$builtJar = Get-ChildItem "$PSScriptRoot\target\*-jar-with-dependencies.jar" | Select-Object -First 1
if (-not $builtJar) {
    Write-Host ">> [bird] No fat JAR in target/. Did Maven actually do anything, or did it just nap?" -ForegroundColor Red
    exit 1
}
Write-Host ">> [bird] Hauling $($builtJar.Name) over to jar\MegaBasterd.jar..." -ForegroundColor Cyan
Copy-Item $builtJar.FullName "$PSScriptRoot\jar\MegaBasterd.jar" -Force
Write-Host ">> [bird] JAR parked safely in jar\." -ForegroundColor Green

# Step 3: Kill running app and clean dist
if (Test-Path $distPath) {
    $proc = Get-Process -Name MegaBasterd -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host ">> [bird] MegaBasterd's already running (PID $($proc.Id)). Putting it out of its misery..." -ForegroundColor Yellow
        $proc | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
    Write-Host ">> [bird] Bulldozing the old dist at $distPath..." -ForegroundColor Yellow
    Remove-Item $distPath -Recurse -Force
    Write-Host ">> [bird] Old build? Never heard of it." -ForegroundColor Green
}

# Step 4: Stage the jpackage input directory
# jpackage --input packages EVERY file in the directory it is given, so
# pointing it at jar\ bundles any stray JAR left lying there (a spare
# upstream/rollback build silently doubled the app-image size). Stage a
# directory holding only the main JAR instead. It lives under target\ so
# `mvn clean` on the next run wipes it.
$stagePath = "$PSScriptRoot\target\jpackage-input"
Write-Host ">> [bird] Setting the table for jpackage at $stagePath (just the one JAR, no gate-crashers)..." -ForegroundColor Cyan
if (Test-Path $stagePath) {
    Remove-Item $stagePath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagePath | Out-Null
Copy-Item "$PSScriptRoot\jar\MegaBasterd.jar" $stagePath -Force
Write-Host ">> [bird] Table set: $((Get-ChildItem $stagePath).Count) file(s), exactly as invited." -ForegroundColor Green

# Step 5: jpackage
Write-Host ">> [bird] Summoning jpackage to hammer out the .exe. Almost there..." -ForegroundColor Cyan
jpackage `
  --type app-image `
  --name MegaBasterd `
  --input $stagePath `
  --main-jar MegaBasterd.jar `
  --main-class com.tonikelope.megabasterd.MainPanel `
  --runtime-image "$PSScriptRoot\jre" `
  --java-options "--enable-native-access=ALL-UNNAMED" `
  --icon "$PSScriptRoot\src\main\resources\images\pica_roja_big.ico" `
  --dest "$PSScriptRoot\dist"

if ($LASTEXITCODE -eq 0) {
    Write-Host ">> [bird] Nailed it. Your shiny new bird is at $distPath\MegaBasterd.exe. Go fetch." -ForegroundColor Green
} else {
    Write-Host ">> [bird] jpackage choked (exit $LASTEXITCODE). No .exe for you today." -ForegroundColor Red
    exit $LASTEXITCODE
}
