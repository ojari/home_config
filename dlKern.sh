#!/bin/sh

VERSION=4.9.54

cd /mnt
wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${VERSION}.tar.xz
tar xf linux-${VERSION}.tar.xz
rm linux-${VERSION}.tar.xz
