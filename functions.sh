function log() {
    thing=$1
    stage=$2
    
    if $DEBUG; then
        cat | tee ${LOGS_DIR}/${thing}-${stage}.log
    else
        cat > ${LOGS_DIR}/${thing}-${stage}.log
    fi
    
}

function failed() {
    clr_red "${CURRENT_THING} failed to build."
}

function buildThing() {
    set -e
    thing=$1
    configureArgs=$2
    export CURRENT_THING=$thing
    trap failed HUP INT TERM PIPE EXIT
    
    
    if isInstalled $thing && [[ $REBUILD == *${thing}* ]]; then
        clr_red "Force (re)building $thing"
        elif isInstalled $thing; then
        clr_green "Already built $thing"
        trap - HUP INT TERM PIPE EXIT
        
        return 0
    else
        clr_magenta "Now on $thing"
    fi
    
    dlThing $thing
    
    
    cd sources/`folderOf $thing`
    
    if [ "$thing" == "berkeleydb" ]; then
        cd build_unix
    fi
    
    
    clr_blue "Applying patches for $thing"
    case $thing in
        libxcb )
            sed s/pthread-stubs// -i configure
        ;;
        libX11 )
            git apply ${ROOT_DIR}/files/x11.diff || true
            autoreconf -f -i
        ;;
        libXt )
            git apply ${ROOT_DIR}/files/libXt.diff
        ;;
        zlib )
            cp ${ROOT_DIR}/files/zlib.pc .
        ;;
        mpv )
            sed "s/'x11', 'libdl', 'pthreads'/'x11', 'pthreads'/" -i wscript
        ;;
        ffmpegthumbnailer )
            cp ${ROOT_DIR}/files/ffmpegthumbnailer-CMakeLists.txt CMakeLists.txt
            cp ${ROOT_DIR}/files/fmt-config.h config.h.in
            rm -rf cmake
        ;;
        mesa )
            echo -e "#ifndef	__dev_t_defined\n#include <sys/types.h>\n#endif\n$(cat src/gallium/winsys/svga/drm/vmw_screen_svga.c)" > src/gallium/winsys/svga/drm/vmw_screen_svga.c
            echo -e "#ifndef	__dev_t_defined\n#include <sys/types.h>\n#endif\n$(cat src/gallium/winsys/svga/drm/vmw_screen.h)" > src/gallium/winsys/svga/drm/vmw_screen.h
            
            #sed "s/shared_library/static_library/" -i src/mesa/drivers/x11/meson.build
            #sed "s/build_by_default: false/build_by_default: true/" -i src/mesa/drivers/x11/meson.build src/gallium/targets/libgl-xlib/meson.build src/glx/meson.build src/gallium/targets/dri/meson.build
            #sed "s/elif not with_shared_glapi/elif false/" -i meson.build
            #sed "s/, libglapi]/]/" -i src/glx/meson.build
            #sed "s/libglapi,/libglapi_static,/" -i src/gallium/targets/dri/meson.build
            #sed "s/shared_library/static_library/" -i src/mapi/shared-glapi/meson.build
            #sed "s/with_shared_glapi = .*/with_shared_glapi = false/" -i meson.build
        ;;
    esac
    
    clr_blue "Configuring $thing"
    case $thing in
        berkeleydb )
            ../dist/configure ${configureArgs[@]} |& log $thing configure
        ;;
        ffmpeg )
            PKG_CONFIG="pkg-config --static"  ./configure ${FFMPEG_CONFIGURE_ARGS[@]}  --cc="$CC" --cxx="$CXX"  --ld=$LD --extra-cflags="-I${SYSROOT}/include ${CFLAGS}" --extra-ldflags="-static -L${SYSROOT}/lib ${LDFLAGS}" --pkg-config-flags="--static" |& log $thing configure
        ;;
        mpv )
            ./bootstrap.py 2>&1 >/dev/null
            ./waf configure ${configureArgs[@]} |& log $thing configure
        ;;
        ffmpegthumbnailer )
            cmake . -DCMAKE_C_COMPILER="${SYSROOT}/bin/${TARGET_TRIPLE}-gcc" -DCMAKE_CXX_COMPILER="${SYSROOT}/bin/${TARGET_TRIPLE}-g++" -DCMAKE_FIND_ROOT_PATH=${SYSROOT} -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSROOT=${SYSROOT} -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DCMAKE_C_FLAGS="-static ${CFLAGS}" -DCMAKE_CXX_FLAGS="-static ${CXXFLAGS}"
        ;;
        lua )
        ;;
        * )
            if [ ! -f configure ]; then
                autoreconf -i
            fi
            ./configure ${configureArgs[@]} |& log $thing configure
        ;;
    esac
    
    clr_blue "Building $thing"
    case $thing in
        lua )
            make -j12 V=1 generic CC=${TARGET_TRIPLE}-gcc AR="${TARGET_TRIPLE}-ar rcu" RANLIB=${TARGET_TRIPLE}-ranlib  |& log $thing build
        ;;
        mpv )
            if [ ! -f ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so ]; then
                mv ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so.bak ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so
            fi
            mv ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so.bak
            ./waf build -j12 V=1 |& log $thing build
            mv ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so.bak ${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so
        ;;
        * )
            make -j12 V=1 |& log $thing build
        ;;
    esac
    
    clr_blue "Installing $thing"
    case $thing in
        ffmpeg )
            sudo env PATH=$PATH make install V=1 |& log $thing install
            if [ -f ffmpeg ]; then cp ffmpeg ${OUTPUT_DIR}/ffmpeg; fi
            if [ -f ffprobe ]; then cp ffprobe ${OUTPUT_DIR}/ffprobe; fi
            if [ -f ffplay ]; then cp ffplay ${OUTPUT_DIR}/ffplay; fi

        ;;
        utillinux )
            sudo env PATH=$PATH make install |& log $thing install
        ;;
        mpv )
            cp build/mpv  ${OUTPUT_DIR}/mpv
        ;;
        ffmpegthumbnailer )
            strip --strip-all ffmpegthumbnailer
            cp ffmpegthumbnailer ${OUTPUT_DIR}/ffmpegthumbnailer
        ;;
        lua )
            make install INSTALL_TOP=${SYSROOT} |& log $thing install
        ;;
        * )
            make install |& log $thing install
        ;;
    esac
    
    clr_blue "Copying license for $thing"
    case $thing in
        mpv )
            if [ "$LICENSE" == GPL ]; then
                cp ${ROOT_DIR}/sources/mpv/LICENSE.GPL ${OUTPUT_DIR}/licenses/mpv
            else
                cp ${ROOT_DIR}/sources/mpv/LICENSE.LGPL ${OUTPUT_DIR}/licenses/mpv
            fi
        ;;
        * )
            copyLicense $thing
        ;;
    esac
    
    markInstalled $thing
    
    cd $ROOT_DIR
    trap - HUP INT TERM PIPE EXIT
}


function makeMesonCrossFile() {
    _MESON_TARGET_CPU=${TARGET_ARCH/-musl/}
    case "$XBPS_TARGET_MACHINE" in
        mips|mips-musl|mipshf-musl)
            _MESON_TARGET_ENDIAN=big
            _MESON_CPU_FAMILY=mips
        ;;
        armv*)
            _MESON_CPU_FAMILY=arm
        ;;
        ppc|ppc-musl)
            _MESON_TARGET_ENDIAN=big
            _MESON_CPU_FAMILY=ppc
        ;;
        i686*)
            _MESON_CPU_FAMILY=x86
        ;;
        ppc64le*)
            _MESON_CPU_FAMILY=ppc64
        ;;
        ppc64*)
            _MESON_TARGET_ENDIAN=big
            _MESON_CPU_FAMILY=ppc64
        ;;
        *)
            _MESON_CPU_FAMILY=${_MESON_TARGET_CPU}
        ;;
    esac
    
    
		cat > ${SYSROOT}/meson.cross <<EOF
[binaries]
c = '${TARGET_TRIPLE}-gcc'
cpp = '${TARGET_TRIPLE}-g++'
ar = '${TARGET_TRIPLE}-gcc-ar'
nm = '${TARGET_TRIPLE}-nm'
ld = '${TARGET_TRIPLE}-gcc'
strip = '${TARGET_TRIPLE}-strip'
readelf = '${TARGET_TRIPLE}-readelf'
objcopy = '${TARGET_TRIPLE}-objcopy'
pkgconfig = 'pkg-config'
#exe_wrapper = '${SYSROOT}/${TARGET_TRIPLE}/lib/libc.so' # A command used to run generated executables.
[properties]
c_args = ['$(echo ${CFLAGS} | sed -r "s/\s+/','/g")']
c_link_args = ['$(echo ${LDFLAGS} | sed -r "s/\s+/','/g")']
cpp_args = ['$(echo ${CXXFLAGS} | sed -r "s/\s+/','/g")']
cpp_link_args = ['$(echo ${LDFLAGS} | sed -r "s/\s+/','/g")']
#needs_exe_wrapper = true
[host_machine]
system = 'linux'
cpu_family = '${_MESON_CPU_FAMILY}'
cpu = '${_MESON_TARGET_CPU}'
endian = '${_MESON_TARGET_ENDIAN}'
EOF
}

function licenseFilepathOf() {
    echo `jq -r .$1.licenseFilepath $ROOT_DIR/meta.json`
}

function versionOf() {
    echo `jq -r .$1.version $ROOT_DIR/meta.json`
}

function folderOf() {
    echo `jq -r .$1.folder $ROOT_DIR/meta.json`
}

function filenameOf() {
    echo `jq -r .$1.filename $ROOT_DIR/meta.json`
}

function typeOf() {
    echo `jq -r .$1.type $ROOT_DIR/meta.json`
}

function urlOf() {
    echo `jq -r .$1.url $ROOT_DIR/meta.json`
}

function copyLicense() {
    if [ "`licenseFilepathOf $1`" == "null" ]; then
        return
    fi
    
    if [ ! -f ${OUTPUT_DIR}/licenses/$1 ]; then
        cp ${SOURCES_DIR}/`folderOf $1`/`licenseFilepathOf $1` ${OUTPUT_DIR}/licenses/$1
    fi
}

function downloadURL() {
    if [ "$TARBALL_DOWNLOADER" == "aria2c" ]; then
        aria2c $TARBALL_DOWNLOADER_ARGS $1
        elif [ "$TARBALL_DOWNLOADER" == "curl" ]; then
        curl -L $TARBALL_DOWNLOADER_ARGS $1
    fi
}

function dlThing() {
    thing=$1
    folder=`folderOf $thing`
    if [ -d $SOURCES_DIR/$folder ]; then
        return
    fi
    url=` urlOf $thing`
    type=`typeOf $thing`
    version=`versionOf $thing`
    cd $SOURCES_DIR
    if [ "$type" == "tarball" ]; then
        filename=`filenameOf $thing`
        if [ ! -f "$filename" ]; then
            clr_brown "Downloading $filename for $thing"
            downloadURL "$url"
        fi
        clr_brown "Extracting tarball for $thing"
        tar xf $filename
        clr_brown "Finished extracting tarball for $thing"
        elif [ "$type" == "git" ]; then
        clr_brown "Cloning repo for $thing"
        git clone --depth=1 -b $version $url $folder
    fi
    cd $ROOT_DIR
}