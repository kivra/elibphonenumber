#!/usr/bin/env sh

DEPS_LOCATION=_build/deps
DESTINATION=libphonenumber

if [ -f "$DEPS_LOCATION/$DESTINATION/cpp/build/libphonenumber.a" ]; then
    echo "libphonenumber fork already exist. delete $DEPS_LOCATION/$DESTINATION for a fresh checkout."
    exit 0
fi

LIB_PHONE_NUMBER_REPO=https://github.com/googlei18n/libphonenumber.git
LIB_PHONE_NUMBER_REV=$1
OS=$(uname -s)
KERNEL=$(echo $(lsb_release -ds 2>/dev/null || cat /etc/system-release 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 | awk '{print $1;}') | awk '{print $1;}')

echo "Use repo ${LIB_PHONE_NUMBER_REPO} and revision ${LIB_PHONE_NUMBER_REV}"
echo "OS detected: ${OS} ${KERNEL}"

function fail_check
{
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        echo "error with $1" >&2
        exit 1
    fi
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
            qmake_unix
        ;;

        Darwin)
            qmake_darwin
        ;;

        *)
            echo "Your system $OS $KERNEL is not supported"
            exit 1
    esac

    fail_check make -j 8
    fail_check make install
    cd $old_path_1
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
            Ubuntu|Debian|CentOS|Amazon)
                copy_resources
                ;;
            *)
                rm -rf priv
                cp -a priv-centos-7.6.1810 priv
         esac
            ;;
      Darwin)
            rm -rf priv
            cp -a priv-macos-11.3.1 priv
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
                fail_check dpkg -s cmake cmake-curses-gui libgtest-dev libicu-dev protobuf-compiler libprotobuf-dev \
                                   libboost-dev libboost-thread-dev libboost-system-dev
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
                echo "Assume Alpine $OS $KERNEL, using prebuilt phonenumber_util_nif.so"
         esac
            ;;
      Darwin)
            # brew install cmake pkg-config icu4c protobuf

            # fail_check git clone https://github.com/google/googletest.git
            # pushd googletest
            # fail_check git checkout 703bd9caab50b139428cea1aaff9974ebee5742e
            # popd

            # install_libphonenumber
            # pushd ${DESTINATION}/cpp/build
            # rm -rf *.dylib
            # popd
            echo "For $OS $KERNEL, using prebuilt phonenumber_util_nif.so"
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
