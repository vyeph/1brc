#!/bin/bash

PWD=$(pwd)

cd src/main/zig/vyeph
zig build --summary all --release=fast
cd $PWD
