$distPath = "$PSScriptRoot\dist\MegaBasterd"

Write-Host "==> Building MegaBasterd distribution..." -ForegroundColor Cyan

# Step 1: Maven build
Write-Host "==> Running mvn package..." -ForegroundColor Cyan
mvn clean package -DskipTests -f "$PSScriptRoot\pom.xml"
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> Maven build failed." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "==> Maven build complete." -ForegroundColor Green

# Step 2: Copy built JAR to jar/
$builtJar = Get-ChildItem "$PSScriptRoot\target\*-jar-with-dependencies.jar" | Select-Object -First 1
if (-not $builtJar) {
    Write-Host "==> Could not find jar-with-dependencies in target/." -ForegroundColor Red
    exit 1
}
Write-Host "==> Copying $($builtJar.Name) -> jar\MegaBasterd.jar..." -ForegroundColor Cyan
Copy-Item $builtJar.FullName "$PSScriptRoot\jar\MegaBasterd.jar" -Force
Write-Host "==> JAR copied." -ForegroundColor Green

# Step 3: Kill running app and clean dist
if (Test-Path $distPath) {
    $proc = Get-Process -Name MegaBasterd -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "==> Stopping running MegaBasterd process (PID $($proc.Id))..." -ForegroundColor Yellow
        $proc | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
    Write-Host "==> Removing existing dist at $distPath..." -ForegroundColor Yellow
    Remove-Item $distPath -Recurse -Force
    Write-Host "==> Removed." -ForegroundColor Green
}

# Step 4: Stage the jpackage input directory
# jpackage --input packages EVERY file in the directory it is given, so
# pointing it at jar\ bundles any stray JAR left lying there (a spare
# upstream/rollback build silently doubled the app-image size). Stage a
# directory holding only the main JAR instead. It lives under target\ so
# `mvn clean` on the next run wipes it.
$stagePath = "$PSScriptRoot\target\jpackage-input"
Write-Host "==> Staging jpackage input at $stagePath..." -ForegroundColor Cyan
if (Test-Path $stagePath) {
    Remove-Item $stagePath -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagePath | Out-Null
Copy-Item "$PSScriptRoot\jar\MegaBasterd.jar" $stagePath -Force
Write-Host "==> Staged $((Get-ChildItem $stagePath).Count) file(s)." -ForegroundColor Green

# Step 5: jpackage
Write-Host "==> Running jpackage..." -ForegroundColor Cyan
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
    Write-Host "==> Done! Output: $distPath\MegaBasterd.exe" -ForegroundColor Green
} else {
    Write-Host "==> jpackage failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
