DEPS_LOCATION=_build/deps
DESTINATION=libphonenumber

if [ -f "$DEPS_LOCATION/$DESTINATION/cpp/build/libphonenumber.a" ]; then
    echo "libphonenumber fork already exist. delete $DEPS_LOCATION/$DESTINATION for a fresh checkout."
    exit 0
fi

LIB_PHONE_NUMBER_REPO=https://github.com/googlei18n/libphonenumber.git
LIB_PHONE_NUMBER_REV=$1
OS=$(uname -s)
KERNEL=$(cat /etc/os-release | grep ^NAME | awk -F= '$1="NAME" {print $2 ;}' | sed 's/"//g' | awk '{print $1}')

echo "Use repo ${LIB_PHONE_NUMBER_REPO} and revision ${LIB_PHONE_NUMBER_REV}"
echo "OS detected: ${OS} ${KERNEL}"

fail_check()
{
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "error with $1" >&2
        exit 1
    fi
}

# https://github.com/google/libphonenumber/tree/master/cpp
#
# Supported build parameters
# --------------------------
#   Build parameters can be specified invoking CMake with '-DKEY=VALUE' or using a
#   CMake user interface (ccmake or cmake-gui).
#
#   USE_ALTERNATE_FORMATS = ON | OFF [ON]  -- Use alternate formats for the phone
#                                             number matcher.
#   USE_BOOST             = ON | OFF [ON]  -- Use Boost. This is only needed in
#                                             multi-threaded environments that
#                                             are not Linux and Mac.
#                                             Libphonenumber relies on Boost for
#                                             non-POSIX, non-Windows and non-C++ 2011
#                                             multi-threading.
#   USE_ICU_REGEXP        = ON | OFF [ON]  -- Use ICU regexp engine.
#   USE_LITE_METADATA     = ON | OFF [OFF] -- Generates smaller metadata that
#                                             doesn't include example numbers.
#   USE_POSIX_THREAD      = ON | OFF [OFF] -- Use Posix thread for multi-threading.
#   USE_RE2               = ON | OFF [OFF] -- Use RE2.
#   USE_STD_MAP           = ON | OFF [OFF] -- Force the use of std::map.
#   USE_STDMUTEX          = ON | OFF [OFF] -- Detect and use C++2011 for multi-threading.
#   REGENERATE_METADATA   = ON | OFF [ON]  -- When this is set to OFF it will skip
#                                             regenerating the metadata with
#                                             BuildMetadataCppFromXml. Since the
#                                             metadata is included in the source
#                                             tree anyway, it is beneficial for
#                                             packagers to turn this OFF: it saves
#                                             some time, and it also makes it
#                                             unnecessary to have java in the build
#                                             environment.


qmake()
{
    git clone ${LIB_PHONE_NUMBER_REPO} ${DESTINATION}
    old_path_1=`pwd`
    cd ${DESTINATION}
    fail_check git checkout ${LIB_PHONE_NUMBER_REV}
    cd $old_path_1

    mkdir -p ${DESTINATION}/cpp/build
    cd ${DESTINATION}/cpp/build

    case $OS in
        Linux)
            case 
            qmake_unix
            ;;
        Darwin)
            qmake_darwin
    esac

    fail_check make -j 8
    fail_check make install
    cd $old_path_1
}

qmake_unix()
{
    fail_check cmake \
        -DCMAKE_C_FLAGS="-fPIC" \
        -DCMAKE_CXX_FLAGS="-fPIC -std=c++11 " \
        -DCMAKE_INSTALL_PREFIX:PATH=install \
        -DUSE_BOOST=ON \
        -DUSE_RE2=OFF \
        -DUSE_ICU_REGEXP=ON \
        -USE_STDMUTEX=ON \
        -DREGENERATE_METADATA=OFF \
        ..
}

qmake_alpine()
{
    fail_check cmake \
       -DCMAKE_INSTALL_PREFIX=/usr \
       ../cpp
}

qmake_darwin()
{
    export PKG_CONFIG_PATH="/usr/local/opt/icu4c/lib/pkgconfig"

    fail_check cmake \
        -DCMAKE_CXX_FLAGS="-std=c++11 " \
        -DCMAKE_INSTALL_PREFIX:PATH=install \
        -DUSE_BOOST=OFF \
        -DUSE_RE2=OFF \
        -DUSE_ICU_REGEXP=ON \
        -DREGENERATE_METADATA=OFF \
        -USE_STDMUTEX=ON \
        -DICU_UC_INCLUDE_DIR=/usr/local/opt/icu4c/include \
        -DICU_UC_LIB=/usr/local/opt/icu4c/lib/libicuuc.dylib \
        -DICU_I18N_INCLUDE_DIR=/usr/local/opt/icu4c/include \
        -DICU_I18N_LIB=/usr/local/opt/icu4c/lib/libicui18n.dylib \
        -DGTEST_SOURCE_DIR=../../../googletest/googletest/ \
        -DGTEST_INCLUDE_DIR=../../../googletest/googletest/include/ \
        ..
}

install_libphonenumber()
{
    git clone ${LIB_PHONE_NUMBER_REPO} ${DESTINATION}
    old_path_1=`pwd`
    cd ${DESTINATION}
    fail_check git checkout ${LIB_PHONE_NUMBER_REV}
    cd $old_path_1

    mkdir -p ${DESTINATION}/cpp/build
    cd ${DESTINATION}/cpp/build

    case $OS in
        Linux)
            case $KERNEL in
                Ubuntu|Debian|CentOS|Amazon|Arch)
                    qmake_unix

                    fail_check make -j 8
                    fail_check make install
                    cd $old_path_1
                    ;;
                *)
                    # Assume Alpine Linux
                    apk --no-cache add libphonenumber-dev
                    qmake_alpine

                    make -Wno-error=deprecated-declarations -j $(grep -c ^processor /proc/cpuinfo)
                    cp *.a /usr/lib/
                    cp *.so* /usr/lib
                    cp -R ../cpp/src/phonenumbers /usr/include/

            esac
        ;;

        Darwin)
            qmake_darwin

            fail_check make -j 8
            fail_check make install
            cd $old_path_1
        ;;

        *)
            echo "Your system $OS $KERNEL is not supported"
            exit 1
    esac
}

copy_resources()
{
    rm -rf priv
    fail_check mkdir priv
    fail_check cp -R $DEPS_LOCATION/$DESTINATION/resources/carrier priv/carrier
    fail_check cp -R $DEPS_LOCATION/$DESTINATION/resources/timezones priv/timezones
}

copy_priv()
{
    case $OS in
      Linux)
         case $KERNEL in
            Ubuntu|Debian|CentOS|Amazon|Arch)
                copy_resources
                ;;
            *)
                rm -rf priv
                #cp -a priv-centos-7.6.1810 priv
         esac
            ;;
      Darwin)
            # rm -rf priv
            # cp -a priv-macos-11.3.1 priv
            copy_resources
            ;;
      *)
            echo "Your system $OS $KERNEL is not supported"
            exit 1
    esac
}

run_installation()
{
    mkdir -p $DEPS_LOCATION
    old_path_0=`pwd`
    cd $DEPS_LOCATION

    case $OS in
      Linux)
         case $KERNEL in
            Ubuntu|Debian)
                echo "Check Dependecies for $KERNEL"
                echo "If the dependencies are not met, run the follow:"
                echo "    sudo apt-get -y install cmake cmake-curses-gui libgtest-dev libicu-dev protobuf-compiler \\"
                echo "                            libprotobuf-dev libboost-dev libboost-thread-dev libboost-system-dev"
                fail_check dpkg -s cmake cmake-curses-gui libgtest-dev libicu-dev protobuf-compiler libprotobuf-dev \
                                   libboost-dev libboost-thread-dev libboost-system-dev
                install_libphonenumber
                ;;
            Arch)
                echo "Check Dependecies for $KERNEL"
                echo "If the dependencies are not met, run the follow:"
                echo "    sudo pacman -S libphonenumber cmake boost gtest"
                fail_check pacman -Q libphonenumber cmake boost gtest
                install_libphonenumber
                ;;
            CentOS|Amazon)
                echo "Check Dependecies for $KERNEL"
                fail_check rpm -q --dump cmake gtest-devel libicu-devel boost-devel protobuf-compiler protobuf-devel
                install_libphonenumber
                ;;
            *)
                # Based on https://github.com/FabienHenon/erlang-alpine-libphonenumber/blob/master/Dockerfile
                # echo "Assume Alpine $OS $KERNEL, install dependencies for building libphonenumber"
                # fail_check apk --no-cache add libgcc libstdc++ git make g++ build-base gtest gtest-dev boost boost-dev protobuf protobuf-dev cmake icu icu-dev openssl
                # install_libphonenumber
                echo "Assume Alpine Linux"
                fail_check apk --no-cache add boost-thread icu-libs protobuf
                install_libphonenumber
         esac
            ;;
      Darwin)
            brew install cmake pkg-config icu4c protobuf

            fail_check git clone https://github.com/google/googletest.git
            pushd googletest
            fail_check git checkout 703bd9caab50b139428cea1aaff9974ebee5742e
            popd

            install_libphonenumber
            pushd ${DESTINATION}/cpp/build
            rm -rf *.dylib
            popd
            # echo "For $OS $KERNEL, using prebuilt phonenumber_util_nif.so"
            ;;
      *)
            echo "Your system $OS $KERNEL is not supported"
            exit 1
    esac

    cd $old_path_0
}

run_installation
# copy_resources
copy_priv
