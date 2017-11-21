#!/bin/bash

VERSION=4.9.64
KVERSION=30

case $1 in
    dk)	
	echo "download kernel..." 
	cd /mnt
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${VERSION}.tar.xz
	tar xf linux-${VERSION}.tar.xz
	rm linux-${VERSION}.tar.xz
	;;
    bx)
	echo "build x86 kernel ${VERSION}-${KVERSION}"
	cd /mnt/linux-${VERSION}

	make nconfig
	cp .config /home/jari/config_${KVERSION}

	#make-kpkg clean
	#fakeroot make-kpkg -j3 --initrd --append-to-version=-j${VERSION} --revision=${VERSION} kernel_image kernel_headers

	make clean
	make -j2 KDEB_PKGVERSION=${KVERSION} LOCALVERSION=.j${KVERSION} bindeb-pkg
	;;
    br)
	echo "build RPI kernel"
	cd /mnt/linux-${VERSION}

	#make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- multi_v7_defconfig

	make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- nconfig
	cp .config /home/jari/rpi_${KVERSION}
    
	make -j3 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
	;;
    dl)
	echo "dpkg list"
	dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n
	;;
    three)
	echo "3"
	;;
    *)
	echo "Unknown command: $1"
	;;
esac

