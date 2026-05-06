#!/usr/bin/env bash
# Build librustdesk for the connected/emulator device's ABI, stage jniLibs, run Flutter.
# Requires: source flutter/.android_env.sh (run flutter/setup_android_env.sh first).
#
# Usage (from repo root or flutter/):
#   cd flutter && ./run_android.sh -d emulator-5554
#   ./flutter/run_android.sh --skip-codegen -d emulator-5554

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.android_env.sh"

SKIP_CODEGEN=0

extract_device_from_args() {
	local -a args=("$@")
	local i=0
	while [[ $i -lt ${#args[@]} ]]; do
		case "${args[$i]}" in
		-d | --device-id)
			echo "${args[$((i + 1))]:-}"
			return 0
			;;
		esac
		i=$((i + 1))
	done
	return 1
}

die() {
	echo "run_android: $*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--skip-codegen)
		SKIP_CODEGEN=1
		shift
		;;
	-h | --help)
		echo "Usage: $0 [--skip-codegen] [flutter run arguments...]"
		echo "Example: $0 -d emulator-5554"
		exit 0
		;;
	*)
		break
		;;
	esac
done

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE — run ./flutter/setup_android_env.sh first"

# shellcheck disable=SC1091
source "$ENV_FILE"

[[ -n "${ANDROID_NDK_HOME:-}" ]] || die "ANDROID_NDK_HOME unset after sourcing env file"
[[ -n "${VCPKG_ROOT:-}" ]] || die "VCPKG_ROOT unset after sourcing env file"
HOST_PRE="${ANDROID_NDK_HOST_PREBUILT:-}"
[[ -n "$HOST_PRE" ]] || die "ANDROID_NDK_HOST_PREBUILT missing in env file — re-run setup_android_env.sh"

DEVICE=""
if DEVICE="$(extract_device_from_args "$@")"; then
	:
elif [[ -n "${ANDROID_SERIAL:-}" ]]; then
	DEVICE="$ANDROID_SERIAL"
else
	mapfile -t _adb_devs < <(adb devices | awk '/\tdevice$/{print $1}')
	[[ ${#_adb_devs[@]} -eq 1 ]] || die "Pass -d <id>, set ANDROID_SERIAL, or connect exactly one device (adb devices)."
	DEVICE="${_adb_devs[0]}"
fi

ABI="$(adb -s "$DEVICE" shell getprop ro.product.cpu.abi | tr -d '\r')"
[[ -n "$ABI" ]] || die "Could not read ABI from device $DEVICE"

JNI_SUB=""
RUST_TRIPLE=""
NDK_WRAPPER=""
VCPKG_TRIPLE=""
LIBCXX_DIR=""

case "$ABI" in
arm64-v8a)
	JNI_SUB="arm64-v8a"
	RUST_TRIPLE="aarch64-linux-android"
	VCPKG_TRIPLE="arm64-android"
	NDK_WRAPPER="ndk_arm64.sh"
	LIBCXX_DIR="aarch64-linux-android"
	;;
armeabi-v7a)
	JNI_SUB="armeabi-v7a"
	RUST_TRIPLE="armv7-linux-androideabi"
	VCPKG_TRIPLE="arm-android"
	NDK_WRAPPER="ndk_arm.sh"
	LIBCXX_DIR="arm-linux-androideabi"
	;;
x86_64)
	JNI_SUB="x86_64"
	RUST_TRIPLE="x86_64-linux-android"
	VCPKG_TRIPLE="x64-android"
	NDK_WRAPPER="ndk_x64.sh"
	LIBCXX_DIR="x86_64-linux-android"
	;;
x86)
	JNI_SUB="x86"
	RUST_TRIPLE="i686-linux-android"
	VCPKG_TRIPLE="x86-android"
	NDK_WRAPPER="ndk_x86.sh"
	LIBCXX_DIR="i686-linux-android"
	;;
*)
	die "Unsupported ABI: $ABI"
	;;
esac

OBOE_LIB="$VCPKG_ROOT/installed/$VCPKG_TRIPLE/lib/liboboe.a"
[[ -f "$OBOE_LIB" ]] || die "Missing $OBOE_LIB — run ./flutter/setup_android_env.sh --vcpkg $JNI_SUB (or matching ABI) then vcpkg install for that triplet."

BUILD_SO="$REPO_ROOT/target/$RUST_TRIPLE/release/liblibrustdesk.so"
LIBCXX_SO="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_PRE/sysroot/usr/lib/$LIBCXX_DIR/libc++_shared.so"
JNI_DEST="$REPO_ROOT/flutter/android/app/src/main/jniLibs/$JNI_SUB"

echo "Device $DEVICE ABI=$ABI -> jniLibs/$JNI_SUB ($RUST_TRIPLE)"

cd "$SCRIPT_DIR"

if [[ "$SKIP_CODEGEN" -eq 0 ]]; then
	cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid
	flutter pub get
	"${HOME}/.cargo/bin/flutter_rust_bridge_codegen" \
		--rust-input ../src/flutter_ffi.rs \
		--dart-output ./lib/generated_bridge.dart \
		--c-output ./macos/Runner/bridge_generated.h
fi

pushd "$REPO_ROOT" >/dev/null
bash "$SCRIPT_DIR/$NDK_WRAPPER"
popd >/dev/null

[[ -f "$BUILD_SO" ]] || die "Expected build output missing: $BUILD_SO"

[[ -f "$LIBCXX_SO" ]] || die "Missing libc++_shared.so at $LIBCXX_SO (wrong ANDROID_NDK_HOST_PREBUILT?)"

mkdir -p "$JNI_DEST"
cp -f "$LIBCXX_SO" "$JNI_DEST/"
cp -f "$BUILD_SO" "$JNI_DEST/librustdesk.so"

echo "Staged native libs in $JNI_DEST"

exec flutter run "$@"
