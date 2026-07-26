# Force cmd.exe as the recipe shell. `make` otherwise looks for sh.exe on
# PATH, which on some setups resolves to a broken shim before Git's real one.
SHELL := cmd.exe
.SHELLFLAGS := /d /c

.PHONY: help run build dist update clean jlink

help:
	@echo Targets:
	@echo   make run     - run jar\MegaBasterd.jar with the bundled jre (no jpackage)
	@echo   make build   - mvn clean package -DskipTests
	@echo   make dist    - full build + package via build-dist.ps1 -^> dist\MegaBasterd\MegaBasterd.exe
	@echo   make update  - sync with upstream and rebuild via update-and-build.ps1
	@echo   make clean   - mvn clean
	@echo   make jlink   - rebuild the jre\ runtime image

run:
	jre\bin\java --enable-native-access=ALL-UNNAMED -jar jar\MegaBasterd.jar

build:
	mvn clean package -DskipTests

dist:
	powershell -NoProfile -ExecutionPolicy Bypass -File build-dist.ps1

update:
	powershell -NoProfile -ExecutionPolicy Bypass -File update-and-build.ps1

clean:
	mvn clean

jlink:
	jlink --module-path "%JAVA_HOME%/jmods" --add-modules java.base,java.desktop,java.logging,java.sql,java.naming,java.xml,jdk.httpserver --output jre --strip-debug --compress=zip-6 --no-header-files --no-man-pages
