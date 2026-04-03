# c64_ultimate
Projects on C64 using Ultimate II+ based setup

## Build and run

- Default (real hardware upload): ./shell/build.sh projects/sprite_demo/main.asm
- Run in VICE instead: ./shell/build.sh --vice projects/sprite_demo/main.asm
- Build only (no run target): ./shell/build.sh --build-only projects/sprite_demo/main.asm

You can also set a default runner via environment variable:

- C64_RUNNER=hardware
- C64_RUNNER=vice
- C64_RUNNER=build
