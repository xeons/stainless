#!/bin/sh
# Regenerates bindings/macos from the macOS SDK, and the layout case that
# holds them to what clang says. Runs on a Mac with the SDK and clang; see
# bindings/macos/README.md.
#
# The order matters only where two frameworks both declare a struct without
# defining it: the first named keeps it.
set -e
cd "$(dirname "$0")/.."

FRAMEWORKS="CoreFoundation IOSurface ColorSync CoreGraphics CoreText CoreVideo IOKit Security
DiskArbitration SystemConfiguration ImageIO CoreAudioTypes CoreAudio CoreMIDI AudioToolbox
CoreServices CFNetwork ApplicationServices Carbon Accelerate AudioUnit CoreMedia VideoToolbox
MediaToolbox VideoDecodeAcceleration OpenGL GLUT OpenAL OpenCL DirectoryService DVDPlayback
ForceFeedback GSS LDAP Hypervisor ICADevices LatentSemanticMapping NetFS PCSC TWAIN vmnet"

# shellcheck disable=SC2086
dotnet run --project tools/Stainless.Bindgen -c Release -- \
    --out bindings/macos --case tests/cases/macos-bindings-layout $FRAMEWORKS
