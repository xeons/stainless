# The environment the 32-bit Linux cases are built and run in.
#
# Building an i386 binary needs the 32-bit crt objects and libc -- Scrt1.o,
# crti.o, libc.so, libgcc -- which are a separate package from the 32-bit
# libraries a machine needs merely to *run* one. `gcc-multilib` and the
# `libc6-dev-i386` it pulls in are those.
#
# `libc6-dev:i386` is here as insurance rather than because this image needs it
# today, and the distinction is worth writing down because it cost a session.
# Those two packages are not the same thing despite the names: `libc6-dev-i386`
# ships /usr/lib32 and a couple of -32.h stubs, while `libc6-dev:i386` is the
# i386-architecture build and is what creates /usr/include/i386-linux-gnu.
#
# Whether the second is *needed* depends on the clang. Targeting i386, clang 18
# falls back to /usr/include/x86_64-linux-gnu and finds the headers there;
# clang 21 looks in /usr/include/i386-linux-gnu and does not fall back, so the
# build dies at `bits/libc-header-start.h` -- which reads like a broken
# toolchain rather than a missing package. This image is currently clang 18 and
# works either way, but `FROM ...sdk:10.0` is a moving tag and will bring a
# newer clang eventually.
#
# The Linux box this project uses has all of these now and runs the 32-bit
# cases directly, so this image is no longer on the path of an ordinary run.
# It is kept for a machine that does not, and because pinning an environment is
# worth something on its own.
#
# From the repository root:
#
#   docker build -t stainless-x86 -f tests/linux-x86.Dockerfile tests
#   docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e DOTNET_CLI_HOME=/tmp \
#       -v "$PWD:/src" -w /src stainless-x86 \
#       bash -c 'dotnet build Stainless.slnx && \
#                dotnet run --project tests/Stainless.Tests --no-build -- x86'
#
# `-u` is not optional in practice. Without it the build is root's, and the
# bin/ and obj/ it leaves in the bind-mounted tree belong to root: the next
# sync cannot overwrite them and you cannot delete them. HOME goes with it,
# because dotnet writes to one and the container has no home directory for a
# borrowed uid.
#
# Nothing in the normal suite needs this. It is for the one platform pair the
# host cannot produce on its own, and `--target x86` on an actual 32-bit-capable
# Linux install needs no container at all.
FROM mcr.microsoft.com/dotnet/sdk:10.0

RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
         clang gcc-multilib g++-multilib libc6-dev:i386 \
    && rm -rf /var/lib/apt/lists/*
