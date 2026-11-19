.PHONY: build run patch minor major release release-minor release-major setup-updates

build:          ; ./build.sh
run:            ; ./build.sh run
patch:          ; scripts/bump.sh patch
minor:          ; scripts/bump.sh minor
major:          ; scripts/bump.sh major
release:        ; scripts/release.sh patch
release-minor:  ; scripts/release.sh minor
release-major:  ; scripts/release.sh major
setup-updates:  ; scripts/setup-sparkle.sh
