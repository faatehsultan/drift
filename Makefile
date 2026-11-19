.PHONY: build run patch minor major release release-minor release-major setup-updates

# Scripts are run through bash so they work even if the executable bit gets lost.
build:          ; bash ./build.sh
run:            ; bash ./build.sh run
patch:          ; bash scripts/bump.sh patch
minor:          ; bash scripts/bump.sh minor
major:          ; bash scripts/bump.sh major
release:        ; bash scripts/release.sh patch
release-minor:  ; bash scripts/release.sh minor
release-major:  ; bash scripts/release.sh major
setup-updates:  ; bash scripts/setup-sparkle.sh
