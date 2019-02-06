#!/bin/bash

VERSION=4.14.97
KVERSION=44

case $1 in
    dk)	
	echo "download kernel..." 
	cd /mnt
	wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-${VERSION}.tar.xz
	tar xf linux-${VERSION}.tar.xz
	rm linux-${VERSION}.tar.xz
	cp /boot/config-$(uname -r) linux-${VERSION}
	cd linux-${VERSION}
	make oldconfig
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
    be)
	cd /mnt/work/emacs-25.3
	./configure --prefix=/opt -q \
		    --enable-silent-rules \
		    --without-selinux \
		    --with-sound=no \
		    --disable-acl
	make
	;;
    bt)
	cd /mnt/work/tvheadend-4.2.1
	./configure --prefix=/opt \
		    --disable-satip_server \
		    --disable-satip_client \
		    --disable-hdhomerun_static \
		    --disable-iptv \
		    --disable-avahi \
		    --disable-ffmpeg_static \
		    --disable-libx264 \
		    --disable-libx264_static \
		    --disable-libx265 \
		    --disable-libx265_static \
		    --disable-libvpx \
		    --disable-libvpx_static \
		    --disable-libtheora \
		    --disable-libtheora_static \
		    --disable-libvorbis \
		    --disable-libvorbis_static \
		    --disable-libfdkaac \
		    --disable-libfdkaac_static \
		    --disable-nvenc  \
		    --disable-libav
	make
	;;
    dl)
	echo "dpkg list"
	dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n
	;;
    vn)
	vncserver -geometry 1920x1080 -depth 16 :40
	;;
    ec)
	Xvfb :1 -screen 0 1024x768x24&
	DISPLAY=:1 /mnt/eclipse/eclimd
	;;
    *)
	echo "Unknown command: $1"
	echo "  dk - download kernel"
	echo "  bx - build X86 kernel"
	echo "  br - build RPI kernel"
	echo "  be - build emacs"
	echo "  bt - build tvheadend"
	echo "  dl - dpkg list (sorted by size)"
	echo "  vn - start VNC server"
	echo "  ec - start eclim server"
	;;
esac

