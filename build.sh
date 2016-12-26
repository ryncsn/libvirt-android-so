#!/bin/bash
set -e

TOOLCHAIN='/tmp/ndk-build'
LIBVIRT_VERSION='master'
ANDROID_API='21'
TARGET_ARCH='arm'
MAKE='make -j8'

HOST=$TARGET_ARCH-linux-androideabi
PATH=$TOOLCHAIN/bin:$TOOLCHAIN/$HOST/bin:$PATH

DEBUG_FLAGS="-g -O0"
SYSROOT="$TOOLCHAIN/sysroot"
LDFLAGS="-L$SYSROOT/usr/lib"
CFLAGS="-I$SYSROOT/usr/include $DEBUG_FLAGS"
COMMON_CONFIGURE_FLAGS="SYSROOT=$SYSROOT --host=$HOST --prefix=$SYSROOT/usr --oldincludedir=$SYSROOT/usr/include"
LIB_CONFIGURE_FLAGS="$COMMON_CONFIGURE_FLAGS --enable-static --disable-shared"
LIBVIRT_CONFIGURE_FLAGS="$COMMON_CONFIGURE_FLAGS --enable-static"

while [ $# -gt 0 ]; do
    case $1 in
        --libvirt-version )
            LIBVIRT_VERSION=$2
            shift
            ;;
        --android-api )
            ANDROID_API=$2
            shift
            ;;
        --target )
            TARGET=$2
            shift
            ;;
        --ndk-patch )
            NDK_PATH=$2
            shift
            ;;
        --clean )
            for i in $(ls); do
                if [ $i != 'patches' ] && [ -d $i ]; then
                    pushd $i
                    echo "Cleaning $i..."
                    git reset --hard 1> /dev/null && git clean -xdf 1> /dev/null
                    popd
                fi
            done
            shift
            ;;
        * )
            echo "Unrecognized $1"
            exit 1
    esac
    shift
done

prepare_ndk() {
    if [[ -z $NDK_PATH ]]; then
        echo "--ndk-path <ndk-path> is required"
        exit 1
    fi
    $NDK_PATH/tools/make_standalone_toolchain.py \
        --arch=$TARGET_ARCH \
        --api=$ANDROID_API \
        --install-dir=$TOOLCHAIN \
        --force
}

build_xdr(){
    pushd ./portablexdr
    git apply ../patches/portablexdr/*.patch
    autoreconf -fi
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" \
        ./configure $LIB_CONFIGURE_FLAGS
    $MAKE
    $MAKE install
    popd
}

build_libxml2(){
    pushd ./libxml2
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" \
        ./autogen.sh $LIB_CONFIGURE_FLAGS --without-lzma --without-python
    $MAKE libxml2.la
    $MAKE install-data
    $MAKE install-exec
    popd
}

build_libgpg-error(){
    pushd ./libgpg-error
    ./autogen.sh --force
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" \
        ./configure $LIB_CONFIGURE_FLAGS --enable-maintainer-mode --disable-doc
    $MAKE
    $MAKE install
    popd
}

build_libgcrypt(){
    pushd ./libgcrypt
    ./autogen.sh --force
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" \
        ./configure $LIB_CONFIGURE_FLAGS --enable-maintainer-mode --with-libgpg-error-prefix=$SYSROOT/usr --disable-doc

    #tests are broken on android
    for dir in compat mpi cipher random src; do
        pushd $dir
        $MAKE
        popd
    done
    pushd src
    $MAKE install
    popd
    popd
}

build_libssh2(){
    pushd ./libssh2
    ./buildconf --force
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" \
        ./configure $LIB_CONFIGURE_FLAGS
    $MAKE
    $MAKE install
    popd
}

build_libvirt(){
    pushd ./libvirt
    git apply ../patches/libvirt/*.patch
    ./bootstrap --force
    LDFLAGS="$LDFLAGS" CFLAGS="$CFLAGS" PKG_CONFIG_PATH="$SYSROOT/usr/lib/pkgconfig" \
        ./configure $LIBVIRT_CONFIGURE_FLAGS\
        --with-pic --without-python \
        --without-wireshark-dissector \
        --without-test --without-gnutls \
        --without-xen --without-qemu \
        --without-openvz --without-lxc \
        --without-vbox --without-libxl \
        --without-xenapi --without-sasl \
        --without-avahi --without-polkit \
        --without-libvirtd --without-uml \
        --without-phyp --without-esx \
        --without-hyperv --without-vmware \
        --without-parallels --without-interface \
        --without-network --without-storage-fs \
        --without-storage-lvm --without-storage-iscsi \
        --without-storage-disk --without-storage-mpath \
        --without-storage-rbd --without-storage-sheepdog \
        --without-numactl --without-numad \
        --without-capng --without-selinux \
        --without-apparmor --without-udev \
        --without-yajl --without-sanlock \
        --without-libpcap --without-macvtap \
        --without-audit --without-dtrace \
        --without-driver-modules --with-init_script=redhat \
        --without-curl --without-dbus \
        --without-libnl --disable-werror \
        --without-libssh --with-ssh2 \
        --without-login-shell \
        --without-test-suite \
        --without-netcf \
        --localstatedir=/var
    $MAKE
    $MAKE install
    popd
}

echo "Building standalone toolchain..."
prepare_ndk

echo "Building XDR..."
build_xdr

echo "Building libxml2..."
build_libxml2

echo "Building build_libgpg-error..."
build_libgpg-error

echo "Building build_libgcrypt..."
build_libgcrypt

echo "Building libssh2..."
build_libssh2

echo "Building Libvirt..."
build_libvirt
