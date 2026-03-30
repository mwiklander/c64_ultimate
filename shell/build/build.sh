#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEFAULT_PROJECT="helloworld"
TARGET_ARG="${1:-}"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_FILE="$BUILD_DIR/program.prg"

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

echo "Sending to C64..."
curl -s -X POST --data-binary @"$OUTPUT_FILE" http://192.168.32/v1/runners:run_prg

echo "Done."