#!/bin/bash

set -e
set -o pipefail
set -x


ZLIB_VERSION=1.2.11
TERMCAP_VERSION=1.3.1
READLINE_VERSION=6.3
OPENSSL_VERSION=1.0.2k
PYTHON_BASE_VERSION=2.7.15
PSUTIL_VERSION=5.4.5
PYTHON_RC=rc1

CPU_COUNT=$(nproc --all 2>/dev/null)
MAKE_J="-j${CPU_COUNT:-1}"

function fetch_psutil() {
  cd /build
  curl -L -o /build/psutil-${PSUTIL_VERSION}.zip https://github.com/giampaolo/psutil/archive/release-${PSUTIL_VERSION}.zip
  unzip /build/psutil-${PSUTIL_VERSION}.zip
  mv psutil-release-${PSUTIL_VERSION} psutil-${PSUTIL_VERSION}
  # Prune out the Python files from the C files and then monkeypatch the
  # Python files
  mkdir -p psutil/{c_files,python_files}
  cp -r /build/psutil-${PSUTIL_VERSION}/psutil psutil/c_files/
	rm -rf psutil/c_files/psutil/*.py* psutil/c_files/psutil/DEVNOTES psutil/c_files/psutil/tests
  # Python files
  cp -r /build/psutil-${PSUTIL_VERSION}/psutil psutil/python_files/
  rm -rf psutil/python_files/psutil/*.c psutil/python_files/psutil/*.h psutil/python_files/psutil/arch psutil/python_files/psutil/tests
  # Patch now
  cd psutil
  patch --ignore-whitespace -p0 < /build/psutil_import__init__.patch
  patch --ignore-whitespace -p0 < /build/psutil_import_pslinux.patch
  cd ..
  # Ready to be copied for Lib
}


function build_zlib() {
    cd /build

    # Download
    curl -LO http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz
    tar zxvf zlib-${ZLIB_VERSION}.tar.gz
    cd zlib-${ZLIB_VERSION}

    # Build
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
        ./configure \
        --static
    make ${MAKE_J}
}

function build_termcap() {
    cd /build

    # Download
    curl -LO http://ftp.gnu.org/gnu/termcap/termcap-${TERMCAP_VERSION}.tar.gz
    tar zxvf termcap-${TERMCAP_VERSION}.tar.gz
    cd termcap-${TERMCAP_VERSION}

    # Build
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
        ./configure \
        --disable-shared \
        --enable-static
    make ${MAKE_J}
}

function build_readline() {
    cd /build

    # Download
    curl -LO ftp://ftp.cwru.edu/pub/bash/readline-${READLINE_VERSION}.tar.gz
    tar xzvf readline-${READLINE_VERSION}.tar.gz
    cd readline-${READLINE_VERSION}

    # Build
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
        ./configure \
        --disable-shared \
        --enable-static
    make ${MAKE_J}

    # Note that things look for readline in <readline/readline.h>, so we need
    # that directory to exist.
    ln -s /build/readline-${READLINE_VERSION} /build/readline-${READLINE_VERSION}/readline
}

function build_openssl() {
    cd /build

    # Download
    curl -LO https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz
    tar zxvf openssl-${OPENSSL_VERSION}.tar.gz
    cd openssl-${OPENSSL_VERSION}

    # Configure
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static' ./Configure no-shared linux-x86_64

    # Build
    make
    echo "** Finished building OpenSSL"
}

function build_python() {
    cd /build

    # Download
    curl -LO https://www.python.org/ftp/python/${PYTHON_BASE_VERSION}/Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar.xz
    unxz Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar.xz
    tar -xvf Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar
    cd Python-${PYTHON_BASE_VERSION}${PYTHON_RC}

    # Copy psutil source code into place
    mkdir Modules/psutil
    cp -r /build/psutil/c_files/psutil/* Modules/psutil/
    # Convert the version to what psutil expects. This should be stable until
    # their setup.py changes.
    psversion=$(echo $PSUTIL_VERSION | sed 's,\.,,g')

    # Set up modules
    cp Modules/Setup.dist Modules/Setup
    MODULES="_bisect _collections _csv _datetime _elementtree _functools _heapq _io _md5 _posixsubprocese _random _sha _sha256 _sha512 _socket _struct _weakref array binascii cmath cStringIO cPickle datetime fcntl future_builtins grp itertools math mmap operator parser readline resource select spwd strop syslog termios time unicodedata zlib"
    for mod in $MODULES;
    do
        sed -i -e "s/^#${mod}/${mod}/" Modules/Setup
    done

    echo '_json _json.c' >> Modules/Setup
    echo '_multiprocessing _multiprocessing/multiprocessing.c _multiprocessing/semaphore.c _multiprocessing/socket_connection.c' >> Modules/Setup

    # Enable static linking
    sed -i '1i\
*static*' Modules/Setup

    # Set dependency paths for zlib, readline, etc.
    sed -i \
        -e "s|^zlib zlibmodule.c|zlib zlibmodule.c -I/build/zlib-${ZLIB_VERSION} -L/build/zlib-${ZLIB_VERSION} -lz|" \
        -e "s|^readline readline.c|readline readline.c -I/build/readline-${READLINE_VERSION} -L/build/readline-${READLINE_VERSION} -L/build/termcap-${TERMCAP_VERSION} -lreadline -ltermcap|" \
        Modules/Setup
    # static compile these modules. Any others that `setup.py` might want to
    # build "shared" should follow this pattern to make them included
    echo "" >> Modules/Setup
    cat << 'EOF' >>Modules/Setup
_lsprof rotatingtree.c _lsprof.c
pyexpat expat/xmlparse.c expat/xmlrole.c expat/xmltok.c pyexpat.c -I$(srcdir)/Modules/expat -DHAVE_EXPAT_CONFIG_H -DUSE_PYEXPAT_CAPI -DHAVE_SYSCALL_GETRANDOM
_psutil_linux psutil/_psutil_common.c psutil/_psutil_posix.c psutil/_psutil_linux.c -DPSUTIL_POSIX=1 -DPSUTIL_VERSION=__PSVER__ -DPSUTIL_LINUX=1
_psutil_posix psutil/_psutil_common.c psutil/_psutil_posix.c                        -DPSUTIL_POSIX=1 -DPSUTIL_VERSION=__PSVER__ -DPSUTIL_LINUX=1
EOF

    # Enable OpenSSL support
    patch --ignore-whitespace -p1 < /build/cpython-enable-openssl.patch

    # Fix https://bugs.python.org/issue7938
    echo "Patching for https://bugs.python.org/issue7938"
    patch --ignore-whitespace -p0 < /build/BPO-7938_pr4338-fix-makesetup-script.patch

    sed -i \
        -e "s|^SSL=/build/openssl-TKTK|SSL=/build/openssl-${OPENSSL_VERSION}|" \
        -e "s|__PSVER__|${psversion}|g"                                        \
        Modules/Setup

    # Configure
    CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
    CXX='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-g++ -static -static-libstdc++ -fPIC' \
    LD=/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-ld \
    ./configure \
      --disable-shared

    # Build
    make --trace ${MAKE_J} LDFLAGS="-static" LINKFORSHARED=" " || true


    /opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-strip python 
    # There may be a better way to ensure _sysconfigdata.py is included in the
    # .zip file, but I am not sure how best to do it, so this is a bit of a
    # hack, banking on the contents of this container staying around for it
    # to matter.
    cp $(find . -name _sysconfigdata.py -print) Lib
    # Copy the patched psutil Python files into place
    cp -r /build/psutil/python_files/psutil Lib
    cd Lib && zip -r ../python2.7.zip .

}

function doit() {
    fetch_psutil
    build_zlib
    build_termcap
    build_readline
    build_openssl
    build_python

		mkdir -p /output
		cp /build/Python-${PYTHON_BASE_VERSION}${PYTHON_RC}/{python,python2.7.zip} /output
}

doit

echo "Output:"
ls -l /output
echo "Done."
