# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

**Full build + package (run after every change):**
```powershell
.\build-dist.ps1
```
This runs `mvn clean package -DskipTests`, copies the fat JAR to `jar/`, kills any running instance, and produces `dist\MegaBasterd\MegaBasterd.exe` via jpackage.

**Maven only:**
```powershell
mvn clean package -DskipTests
```
Output: `target/MegaBasterd-<version>-jar-with-dependencies.jar`

**Run directly (no jpackage):**
```powershell
jre\bin\java --enable-native-access=ALL-UNNAMED -jar jar\MegaBasterd.jar
```

**Rebuild JRE (one-time, or when modules change):**
```powershell
jlink `
  --module-path "$env:JAVA_HOME/jmods" `
  --add-modules java.base,java.desktop,java.logging,java.sql,java.naming,java.xml,jdk.httpserver `
  --output jre --strip-debug --compress=zip-6 --no-header-files --no-man-pages
```

**Sync with upstream + rebuild (one shot):**
```powershell
.\update-and-build.ps1
```
Merges `upstream/master` into the current branch, runs `build-dist.ps1`, and downloads the official upstream release JAR into `upstream-build/`. Flags: `-OnlyIfChanged`, `-SkipUpdate`, `-SkipBuild`, `-SkipUpstreamJar`. On a merge conflict it stops for manual resolution; re-run with `-SkipUpdate` afterward.

There are no automated tests in this project.

## Continuous integration

`.github/workflows/build.yml` runs `mvn -B -ntp clean package -DskipTests` on every push and pull request to `master` (Ubuntu, Temurin JDK 17) and uploads the fat JAR as an artifact. It is a compile-breakage guard — most useful right after an upstream merge. Packaging (jlink/jpackage → `.exe`) is Windows-local and intentionally not part of CI.

## Upstream-merge hygiene

This is a fork of `tonikelope/megabasterd`, kept current via `update-and-build.ps1`. To keep upstream merges conflict-free:

- **Never renormalize line endings.** Upstream ships *mixed* endings — many files are CRLF, some are LF, each matching upstream per-file. A file that flips CRLF↔LF conflicts against upstream on every future merge. Two guardrails enforce this: `.gitattributes` sets `* -text` (Git does no EOL conversion at all, so nothing flips regardless of `core.autocrlf`), and `.editorconfig` deliberately omits `end_of_line` so editors don't flip endings on save. **Do not** change `.gitattributes` to `text=auto`/`text` — that would renormalize everything to LF and defeat the purpose.
- **Prefer new files and fork-owned files** (build scripts, `.github/`, docs) for improvements — they never collide. Edits to upstream-owned Java/pom files should stay small and localized.

## Version

The app version is defined in two places that must be kept in sync:
- `src/main/java/com/tonikelope/megabasterd/MainPanel.java` — `VERSION` constant (used at runtime for update checks)
- `pom.xml` — `<version>` tag (affects only the output JAR filename)

The app checks `https://github.com/tonikelope/megabasterd/releases/latest` on startup and notifies the user if the GitHub release tag is newer than `VERSION`. A stale compiled JAR (built before bumping `VERSION`) will always trigger this notification — always use `mvn clean package`, not `mvn package`.

## Architecture

All source is in `src/main/java/com/tonikelope/megabasterd/`. The app is a Swing desktop application with no dependency injection framework — wiring is done manually in `MainPanel`.

**Central coordinator:** `MainPanel` is a static singleton-style class that owns all subsystems and passes itself as a reference. It starts the thread pool (`THREAD_POOL`, a cached executor), then launches managers and services via `THREAD_POOL.execute(...)`.

**Transfer pipeline (download):**
- `Download` (implements `Transference`, `Runnable`) — one instance per download, holds metadata and state
- `DownloadManager extends TransferenceManager` — queues and lifecycle-manages `Download` instances
- `ChunkDownloader` / `ChunkDownloaderMono` — workers that fetch encrypted chunks from MEGA CDN URLs
- `ChunkWriterManager` — assembles received chunks in order and writes to disk
- Upload mirrors this: `Upload`, `UploadManager`, `ChunkUploader`

**Concurrency contract:** `SecureSingleThreadNotifiable` (interface with `secureNotify()` / `secureWait()`) is the in-house synchronization primitive used across workers. Many classes implement it instead of using raw `wait/notify`.

**Crypto:** `CryptTools` wraps all JCE calls. MEGA uses AES-CTR for file content, AES-CBC/ECB for key material, and RSA for account key decryption. Keys are derived from MEGA link strings via `initMEGALinkKey()` / `initMEGALinkKeyIV()`. The master password feature uses PBKDF2-HMAC-SHA256.

**Streaming server:** `KissVideoStreamServer` (implements `HttpHandler`) runs a local HTTP server on `127.0.0.1:1337` that decrypts and streams MEGA video files in real time. It is only accessible from localhost.

**Proxy server:** `MegaProxyServer` is a local HTTPS CONNECT proxy that only forwards connections to `*.mega.nz:443`. Used by the SmartProxy feature to route MEGA traffic.

**Clipboard monitoring:** `ClipboardSpy` uses the Java `ClipboardOwner` pattern — it re-sets itself as owner after each change to stay notified. `LinkGrabberDialog` is the observer. Can be disabled via the `clipboardspy` DB setting.

**Persistence:** `SqliteSingleton` (lazy-holder singleton) manages a SQLite DB at `~/.megabasterd<VERSION>/megabasterd.db`. All settings and transfer state are stored there via `DBTools`.

**i18n:** `I18n` loads `src/main/resources/i18n/messages*.properties`. `LabelTranslatorSingleton` is a thin wrapper kept for backwards compatibility — prefer `I18n` directly for new code.

**API layer:** `MegaAPI` handles the MEGA JSON API protocol. `MegaCrypterAPI` handles MegaCrypter links. Both throw subtypes of `APIException`.

## Commit style

Format: `type: message` where type is one of `feat`, `fix`, `chore`, `docs`, `refactor`, `test`.

Do not add co-author lines to commits.
