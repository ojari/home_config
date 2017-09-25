#!/bin/sh

cd /mnt/linux-4.9.51
make nconfig
make-kpkg clean
fakeroot make-kpkg --initrd --append-to-version=.j --revision=27 kernel_image kernel_headers
