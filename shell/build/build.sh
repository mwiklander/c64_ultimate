#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_PROJECT="helloworld"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_FILE="$BUILD_DIR/program.prg"
RUNNER_MODE="${C64_RUNNER:-hardware}"
HW_RUN_URL="${C64_HW_RUN_URL:-http://192.168.32/v1/runners:run_prg}"

usage() {
	cat <<'EOF'
Usage: ./shell/build.sh [options] [file|directory|project]

Options:
  --runner <hardware|vice|build>  Choose where to run after build.
  --hardware                       Alias for --runner hardware.
  --vice                           Alias for --runner vice.
  --build-only                     Alias for --runner build.
  -h, --help                       Show this help.

Environment:
  C64_RUNNER       Default runner mode (hardware|vice|build).
  C64_HW_RUN_URL   Hardware upload URL.
  C64_VICE_BIN     Full path to VICE executable (x64sc/x64).
EOF
}

TARGET_ARG=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--runner)
			if [[ $# -lt 2 ]]; then
				echo "Missing value for --runner" >&2
				exit 1
			fi
			RUNNER_MODE="$2"
			shift 2
			;;
		--hardware)
			RUNNER_MODE="hardware"
			shift
			;;
		--vice)
			RUNNER_MODE="vice"
			shift
			;;
		--build-only)
			RUNNER_MODE="build"
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			if [[ -n "$TARGET_ARG" ]]; then
				echo "Unexpected extra argument: $1" >&2
				exit 1
			fi
			TARGET_ARG="$1"
			shift
			;;
	esac
done

RUNNER_MODE="$(printf '%s' "$RUNNER_MODE" | tr '[:upper:]' '[:lower:]')"
case "$RUNNER_MODE" in
	hardware|vice|build)
		;;
	*)
		echo "Invalid runner mode: $RUNNER_MODE (expected hardware, vice, or build)" >&2
		exit 1
		;;
esac

find_vice_bin() {
	if [[ -n "${C64_VICE_BIN:-}" && -x "$C64_VICE_BIN" ]]; then
		printf '%s\n' "$C64_VICE_BIN"
		return 0
	fi

	if command -v x64sc >/dev/null 2>&1; then
		command -v x64sc
		return 0
	fi

	if command -v x64 >/dev/null 2>&1; then
		command -v x64
		return 0
	fi

	if [[ -x "/Applications/vice-arm64-gtk3-3.6.1/bin/x64sc" ]]; then
		printf '%s\n' "/Applications/vice-arm64-gtk3-3.6.1/bin/x64sc"
		return 0
	fi

	if [[ -x "/Applications/VICE.app/Contents/MacOS/x64sc" ]]; then
		printf '%s\n' "/Applications/VICE.app/Contents/MacOS/x64sc"
		return 0
	fi

	return 1
}

to_abs_path() {
	local input_path="$1"
	if [[ "$input_path" == /* ]]; then
		printf '%s\n' "$input_path"
	else
		local dir_component
		dir_component="$(cd "$(dirname "$input_path")" && pwd)"
		printf '%s/%s\n' "$dir_component" "$(basename "$input_path")"
	fi
}

# Choose an entry point based on the active file, folder, or project name.
select_source_file() {
	local candidate="$1"
	local asm_file=""

	if [[ -n "$candidate" && -f "$candidate" ]]; then
		if [[ "$candidate" != *.asm ]]; then
			echo "Provided file must end with .asm: $candidate" >&2
			exit 1
		fi
		asm_file="$(to_abs_path "$candidate")"
		local dir_path
		dir_path="$(cd "$(dirname "$asm_file")" && pwd)"
		if [[ "$(basename "$asm_file")" != "main.asm" && -f "$dir_path/main.asm" ]]; then
			printf '%s\n' "$dir_path/main.asm"
			return
		fi
		printf '%s\n' "$asm_file"
		return
	fi

	if [[ -n "$candidate" && -d "$candidate" ]]; then
		local dir_abs
		dir_abs="$(to_abs_path "$candidate")"
		if [[ -f "$dir_abs/main.asm" ]]; then
			printf '%s\n' "$dir_abs/main.asm"
			return
		fi
		echo "Directory does not contain main.asm: $dir_abs" >&2
		exit 1
	fi

	if [[ -n "$candidate" && -f "$REPO_ROOT/projects/$candidate/main.asm" ]]; then
		printf '%s\n' "$REPO_ROOT/projects/$candidate/main.asm"
		return
	fi

	if [[ -f "$REPO_ROOT/projects/$DEFAULT_PROJECT/main.asm" ]]; then
		printf '%s\n' "$REPO_ROOT/projects/$DEFAULT_PROJECT/main.asm"
		return
	fi

	echo "Unable to locate an entry .asm file. Provide a file, directory, or project name." >&2
	exit 1
}

SOURCE_FILE="$(select_source_file "$TARGET_ARG")"
SOURCE_DIR="$(cd "$(dirname "$SOURCE_FILE")" && pwd)"
BUILD_LABEL="$(basename "$SOURCE_DIR")"
ENTRY_LABEL="$(basename "$SOURCE_FILE")"

mkdir -p "$BUILD_DIR"

echo "Building $BUILD_LABEL ($ENTRY_LABEL)..."
if command -v tmpx >/dev/null 2>&1; then
	assembler="tmpx"
	tmpx "$SOURCE_FILE" -o "$OUTPUT_FILE"
elif command -v 64tass >/dev/null 2>&1; then
	assembler="64tass"
	64tass --case-sensitive --cbm-prg -o "$OUTPUT_FILE" "$SOURCE_FILE"
else
	echo "Neither tmpx nor 64tass is installed. Install one of them and try again." >&2
	exit 1
fi

echo "Built with $assembler"

case "$RUNNER_MODE" in
	hardware)
		echo "Sending to C64 hardware..."
		if ! curl -fsS -X POST --data-binary @"$OUTPUT_FILE" "$HW_RUN_URL"; then
			echo "Hardware upload failed. If you are offline, run with --vice or --build-only." >&2
			exit 28
		fi
		echo "Done."
		;;
	vice)
		echo "Launching in VICE..."
		if ! VICE_BIN="$(find_vice_bin)"; then
			echo "VICE executable not found. Install VICE, set C64_VICE_BIN, or use --build-only." >&2
			exit 1
		fi
		"$VICE_BIN" -autostart "$OUTPUT_FILE" >/dev/null 2>&1 &
		echo "Started VICE with $OUTPUT_FILE"
		;;
	build)
		echo "Build complete (run skipped)."
		;;
esac