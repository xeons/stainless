# The environment the 32-bit Linux cases are built and run in.
#
# Building an i386 binary needs the 32-bit crt objects and libc -- Scrt1.o,
# crti.o, libc.so, libgcc -- which are a separate package from the 32-bit
# libraries a machine needs merely to *run* one. The Linux box this project
# uses has the second and not the first, and installing packages there needs a
# password nobody is going to type into a test run. A container has both and
# costs nothing but disk.
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

RUN apt-get update \
    && apt-get install -y --no-install-recommends clang gcc-multilib g++-multilib \
    && rm -rf /var/lib/apt/lists/*
