set -ex

main() {
    # arch in the rust target
    local arch=$1 \
          kversion=4.9.0-8

    local debsource="deb http://http.debian.net/debian/ stretch main"
    debsource="$debsource\ndeb http://security.debian.org/ stretch/updates main"

    local dropbear="dropbear-bin"
    local libssl="libssl1.0.2"

    # select debian arch and kernel version
    case $arch in
        aarch64)
            arch=arm64
            kernel=$kversion-arm64
            ;;
        armv7)
            arch=armhf
            kernel=$kversion-armmp
            ;;
        i686)
            arch=i386
            kernel=$kversion-686
            ;;
        mips|mipsel)
            kernel=$kversion-4kc-malta
            ;;
        mips64el)
            kernel=$kversion-5kc-malta
            ;;
        powerpc)
            # there is no stretch powerpc port, so we use jessie
            # use a more recent kernel from backports
            kernel=4.9.0-0.bpo.6-powerpc
            debsource="deb http://archive.debian.org/debian jessie main"
            debsource="$debsource\ndeb http://archive.debian.org/debian jessie-backports main"
            debsource="$debsource\ndeb http://ftp.ports.debian.org/debian-ports unreleased main"
            debsource="$debsource\ndeb http://ftp.ports.debian.org/debian-ports unstable main"

            # archive.debian.org Release files are expired.
            echo "Acquire::Check-Valid-Until false;" | tee -a /etc/apt/apt.conf.d/10-nocheckvalid

            dropbear="dropbear"
            libssl="libssl1.0.0"
            ;;
        powerpc64)
            # there is no stable port
            arch=ppc64
            kernel=4.19.0-5-powerpc64
            debsource="deb http://ftp.ports.debian.org/debian-ports unreleased main"
            debsource="$debsource\ndeb http://ftp.ports.debian.org/debian-ports unstable main"
            # sid version of dropbear requeries this depencendies
            deps="libtommath1:ppc64 libtomcrypt1:ppc64 libgmp10:ppc64"
            libssl="libssl1.1"
            ;;
        powerpc64le)
            arch=ppc64el
            kernel=$kversion-powerpc64le
            ;;
        s390x)
            arch=s390x
            kernel=$kversion-s390x
            ;;
        sparc64)
            # there is no stable port
            kernel=4.19.0-5-sparc64
            debsource="deb http://ftp.ports.debian.org/debian-ports unreleased main"
            debsource="$debsource\ndeb http://ftp.ports.debian.org/debian-ports unstable main"
            # sid version of dropbear requeries this depencendies
            deps="libtommath1:sparc64 libtomcrypt1:sparc64 libgmp10:sparc64"
            libssl="libssl1.1"
            ;;
        x86_64)
            arch=amd64
            kernel=$kversion-amd64
            ;;
        *)
            echo "Invalid arch: $arch"
            exit 1
            ;;
    esac

    local dependencies=(
        cpio
        sharutils
    )

    local purge_list=()
    apt-get update
    for dep in ${dependencies[@]}; do
        if ! dpkg -L $dep; then
            apt-get install --no-install-recommends -y $dep
            purge_list+=( $dep )
        fi
    done

    # Download packages
    mv /etc/apt/sources.list /etc/apt/sources.list.bak
    echo -e "$debsource" > /etc/apt/sources.list

    # Old ubuntu does not support --add-architecture, so we directly change multiarch file
    if [ -f /etc/dpkg/dpkg.cfg.d/multiarch ]; then
        cp /etc/dpkg/dpkg.cfg.d/multiarch /etc/dpkg/dpkg.cfg.d/multiarch.bak
    fi
    dpkg --add-architecture $arch || echo "foreign-architecture $arch" > /etc/dpkg/dpkg.cfg.d/multiarch

    # Add debian keys
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com EF0F382A1A7B6500
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com 9D6D8F6BC857C906
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com 8B48AD6246925553
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com 7638D0442B90D010
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com DA1B2CEA81DCBC61 # debian-ports
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com CBF8D6FD518E17E1
    apt-key adv --recv-key --keyserver keyserver.ubuntu.com 06AED62430CB581C
    apt-get update

    mkdir -p -m 777 /qemu/$arch
    cd /qemu/$arch
    apt-get -d --no-install-recommends download \
        $deps \
        busybox:$arch \
        $dropbear:$arch \
        libc6:$arch \
        libgcc1:$arch \
        $libssl:$arch \
        libstdc++6:$arch \
        linux-image-$kernel:$arch \
        ncurses-base \
        zlib1g:$arch
    cd /qemu

    # Install packages
    root=root-$arch
    mkdir -p $root/{bin,etc/dropbear,root,sys,dev,proc,sbin,tmp,usr/{bin,sbin},var/log}
    for deb in $arch/*deb; do
        dpkg -x $deb $root/
    done

    cp $root/boot/vmlinu* kernel

    # initrd
    mkdir -p $root/modules
    cp \
        $root/lib/modules/*/kernel/drivers/net/net_failover.ko \
        $root/lib/modules/*/kernel/drivers/net/virtio_net.ko \
        $root/lib/modules/*/kernel/drivers/virtio/* \
        $root/lib/modules/*/kernel/fs/9p/9p.ko \
        $root/lib/modules/*/kernel/fs/fscache/fscache.ko \
        $root/lib/modules/*/kernel/net/9p/9pnet.ko \
        $root/lib/modules/*/kernel/net/9p/9pnet_virtio.ko \
        $root/lib/modules/*/kernel/net/core/failover.ko \
        $root/modules || true # some file may not exist
    rm -rf $root/boot
    rm -rf $root/lib/modules

    cat << 'EOF' > $root/etc/hosts
127.0.0.1 localhost qemu
EOF

    cat << 'EOF' > $root/etc/hostname
qemu
EOF

    cat << 'EOF' > $root/etc/passwd
root::0:0:root:/root:/bin/sh
EOF

cat << 'EOF' | uudecode -o $root/etc/dropbear/dropbear_rsa_host_key
begin 600 dropbear_rsa_host_key
M````!W-S:"UR<V$````#`0`!```!`0"N!-<%K,3Z.!Z,OEMB2.N\O.$IWQ*F
M#5%(_;(^2YKY_J_.RQW/7U@_MK&J#!Z0_\;EH#98ZW*E1\.<FF%P/*Y.W56-
M31.'EJE`TN@=T5EC(8"Y%3'ZBYH)^WIVJ]S*G/_;#RH\_?S"U^1L_<<.F`O+
MZVI?*]\KTDOT&QV0#B-M;"%_7:\>+3[X=QMH,B<HM$+0E[\B6*^!XKLR@V,K
M)<V80HHK:_#;D]26XKN&CB./EZAC%4)78R!G""4HT@UK<5I4B^$/""`,?*\T
M>*4$RYULV,V3X6]K:7@Q?80"#WXGGQZNFN6CZ7LTDX(F6J[\]F5<0`HEOF:Z
MX;^53`L'4I/A```!``$L:$Z*#6<^3@+O%.[-#/5H+.C'3\#QQZN[1;J>L`8I
MZ_&T'!"J'/Y+?R?55G:M^=]R*-&I3TOJYZA8@&H51ZOAF59'1_>>Z@?E4#)$
MQU)X/RWH51ZB5KSDWJS:D'7GD(!?NAY`C'7\)I:_4)J")QBV/P"RJQGHG'%B
M1BT2LE6676>`1K,0\NIMZTKQNB(IC+88<7#8%_-=P<&6<"9LH>60TSS?3?-C
MN`T36YB/3^<(Q;`N1NT>I9EZS`BAC^-?.:,R\7EL"<4>7E=]^1]B\K9])AQU
MBM\]M;4V(S(6KH-I.4[6>9E+@\UEM.J6:[2LUEEJDG:G:+:/EVF^Y75@(S$`
M``"!`.O+KW=&*CBCHL"11&SVO4/K]$R-]7MV7,3RR)Q[X'0;6.?4JHW!3VR6
M*FGBY--37ZD-+UV.8_+"$<?B"#&K$.[V)F7V2\UY!7(0FZ@A2`0ADDY*J-_B
M4AU&.*GP#F/!I([:?E],.>6PH9)(/E.\G19#G0K`LRM?JWS!58&;D0C1````
M@0"\[@NYWSTW(?Q@:_A*1Y3/AKYO5?S=0"<2>#V-AH6W-NCSDTSRP=2D79FS
M"D?[;.)V>8'#9&I3"MU@+:2\Z%$0-MG0+J'(0>T1_C6?*C=4U0I$DI<=@D]1
H_&DE8Y(OT%%EPG]!$H&5HX*),_D1A2\P=R.7G'`0L%YM-79Y"T">$0``
`
end
EOF

    # dropbear complains when this file is missing
    touch $root/var/log/lastlog

    cat << 'EOF' > $root/init
#!/bin/busybox sh

set -e

/bin/busybox --install

mount -t devtmpfs devtmpfs /dev
mount -t proc none /proc
mount -t sysfs none /sys
mkdir /dev/pts
mount -t devpts none /dev/pts/

# some archs does not have virtio modules
insmod /modules/failover.ko || true
insmod /modules/net_failover.ko || true
insmod /modules/virtio.ko || true
insmod /modules/virtio_ring.ko || true
insmod /modules/virtio_mmio.ko || true
insmod /modules/virtio_pci.ko || true
insmod /modules/virtio_net.ko || true
insmod /modules/fscache.ko
insmod /modules/9pnet.ko
insmod /modules/9pnet_virtio.ko || true
insmod /modules/9p.ko

ifconfig lo 127.0.0.1
ifconfig eth0 10.0.2.15
route add default gw 10.0.2.2 eth0

mkdir /target
mount -t 9p -o trans=virtio target /target -oversion=9p2000.u || true

exec dropbear -F -E -B
EOF

    chmod +x $root/init
    cd $root
    find . | cpio --create --format='newc' --quiet | gzip > ../initrd.gz
    cd -

    # Clean up
    rm -rf /qemu/$root /qemu/$arch
    mv -f /etc/apt/sources.list.bak /etc/apt/sources.list
    if [ -f /etc/dpkg/dpkg.cfg.d/multiarch.bak ]; then
        mv /etc/dpkg/dpkg.cfg.d/multiarch.bak /etc/dpkg/dpkg.cfg.d/multiarch
    fi
    # can fail if arch is used (amd64 and/or i386)
    dpkg --remove-architecture $arch || true
    apt-get update
    apt-get purge --auto-remove -y ${purge_list[@]}
    ls -lh /qemu
}

main "${@}"
