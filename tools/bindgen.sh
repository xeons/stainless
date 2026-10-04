#!/bin/sh
# Regenerates bindings/macos from the macOS SDK, and the cases that hold them
# to what clang says and to what the runtime answers. Runs on a Mac with the
# SDK and clang; see bindings/macos/README.md.
#
# Every framework with a header is generated but those left out below. The
# order matters only where two frameworks both declare a struct without
# defining it: the first named keeps it, so the frameworks others build on
# come first, and the rest follow in the SDK's order.
set -e
cd "$(dirname "$0")/.."

FIRST="CoreFoundation IOSurface ColorSync CoreGraphics CoreText CoreVideo IOKit Security
DiskArbitration SystemConfiguration ImageIO CoreAudioTypes CoreAudio CoreMIDI AudioToolbox
CoreServices CFNetwork ApplicationServices Carbon Accelerate AudioUnit CoreMedia VideoToolbox
MediaToolbox VideoDecodeAcceleration OpenGL GLUT OpenAL OpenCL DirectoryService DVDPlayback
ForceFeedback GSS LDAP Hypervisor ICADevices LatentSemanticMapping NetFS PCSC TWAIN vmnet
Foundation CoreData CoreImage QuartzCore UniformTypeIdentifiers AppKit Metal MetalKit AVFAudio
AVFoundation WebKit"

# Left out, each for its reason:
#   Kernel, DriverKit     kernel and driver extensions, which no program links
#   Kerberos              its gssapi.h is GSS's, which supersedes it
#   Tcl, Tk, Ruby         interpreters' own C APIs, deprecated, and in usr/include too
#   vecLib                the same headers as Accelerate's vecLib subframework
#   Cocoa                 an umbrella over Foundation, AppKit and CoreData
#   AccessorySetupKit     its headers import UIKit, which macOS has not got
# A Swift overlay has no header and is left out by having none; one with
# headers, as _LocationEssentials is CoreLocation's, is generated.
LEFT_OUT="Kernel DriverKit Kerberos Tcl Tk Ruby vecLib Cocoa AccessorySetupKit"

SDK=$(xcrun --show-sdk-path)
REST=""
for directory in "$SDK"/System/Library/Frameworks/*.framework; do
    framework=$(basename "$directory" .framework)
    case " $(echo $FIRST) $LEFT_OUT " in *" $framework "*) continue ;; esac
    if [ -n "$(find -L "$directory/Headers" "$directory/Frameworks" -name '*.h' 2>/dev/null | head -1)" ]; then
        REST="$REST $framework"
    fi
done

# shellcheck disable=SC2086
dotnet run --project tools/Stainless.Bindgen -c Release -- \
    --out bindings/macos --case tests/cases/macos-bindings-layout \
    --runtime-case tests/cases/macos-bindings-runtime $FIRST $REST

# The program over the bindings is built with every module, as the generated cases are.
cp tests/cases/macos-bindings-layout/sources.txt tests/cases/macos-bindings-objc/sources.txt
