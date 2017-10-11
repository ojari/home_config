#!/bin/sh

VERSION=28
RPI="no"


cd /mnt/linux-4.9.54


if [ "$RPI" == "yes" ];
then
    echo "RPI"

    #make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- multi_v7_defconfig

    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- nconfig
    cp .config /home/jari/rpi_${VERSION}
    
    make -j3 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
    
else
    echo "x86 (debian)"

    make nconfig
    cp .config /home/jari/config_${VERSION}

    make-kpkg clean
    fakeroot make-kpkg -j3 --initrd --append-to-version=-j${VERSION} --revision=${VERSION} kernel_image kernel_headers

    #make clean
    #make KDEB_PKGVERSION=${VERSION} LOCALVERSION=.j${VERSION} deb-pkg
fi


