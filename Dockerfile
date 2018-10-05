FROM thedoh/musl-cross:1.1.19
MAINTAINER Lisa Seelye <lisa@thedoh.com>
# Upstream maintainer: Andrew Dunham <andrew@du.nham.ca>

RUN apt-get update && apt-get install -y zip

ARG ZLIB_VERSION=1.2.11
ARG TERMCAP_VERSION=1.3.1
ARG READLINE_VERSION=6.3
ARG OPENSSL_VERSION=1.0.2k
ARG PYTHON_BASE_VERSION=3.6.6
ARG PSUTIL_VERSION=5.4.5
ARG PYTHON_RC=

RUN \
  mkdir -m 755 /build

RUN \
  echo "Building zlib ${ZLIB_VERSION}"                 && \
  cd /build                                            && \
  curl -LO http://zlib.net/zlib-${ZLIB_VERSION}.tar.gz && \
  tar zxf zlib-${ZLIB_VERSION}.tar.gz                  && \
  cd zlib-${ZLIB_VERSION}                              && \
  CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
      ./configure \
      --static                                         && \
  make -j $(nproc --all)

RUN \
  echo "Building termcap ${TERMCAP_VERSION}" && \
  cd /build && \
  curl -LO http://ftp.gnu.org/gnu/termcap/termcap-${TERMCAP_VERSION}.tar.gz && \
  tar zxf termcap-${TERMCAP_VERSION}.tar.gz && \
  cd termcap-${TERMCAP_VERSION} && \
  CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
    ./configure \
    --disable-shared \
    --enable-static && \
  make -j $(nproc --all)

# Note that things look for readline in <readline/readline.h>, so we need
# that directory to exist.
RUN \
  echo "Building readline ${READLINE_VERSION}" && \
  cd /build && \
  curl -LO ftp://ftp.cwru.edu/pub/bash/readline-${READLINE_VERSION}.tar.gz && \
  tar xzf readline-${READLINE_VERSION}.tar.gz && \
  cd readline-${READLINE_VERSION} && \
  CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
      ./configure \
      --disable-shared \
      --enable-static && \
  make -j $(nproc --all) && \
  ln -s /build/readline-${READLINE_VERSION} /build/readline-${READLINE_VERSION}/readline

RUN \
  echo "Building OpenSSL ${OPENSSL_VERSION}" && \
  cd /build && \
  curl -LO https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz && \
  tar zxf openssl-${OPENSSL_VERSION}.tar.gz && \
  cd openssl-${OPENSSL_VERSION} && \
  CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static' \
    ./Configure no-shared linux-x86_64 && \
  make -j 1

ADD \
   psutil_import__init__.patch \
   psutil_import_pslinux.patch \
 /build/

RUN \
  echo "Fetching psutil-${PSUTIL_VERSION}" && \
  cd /build && \
  curl \
    -L \
    -o /build/psutil-${PSUTIL_VERSION}.zip \
    https://github.com/giampaolo/psutil/archive/release-${PSUTIL_VERSION}.zip && \
  unzip /build/psutil-${PSUTIL_VERSION}.zip && \
  mv psutil-release-${PSUTIL_VERSION} psutil-${PSUTIL_VERSION} && \
  echo "Pruning out the Python files from the C files"  && \
  mkdir -vp psutil/c_files psutil/python_files && \
  cp -vr /build/psutil-${PSUTIL_VERSION}/psutil psutil/c_files/ && \
	rm -rvf psutil/c_files/psutil/*.py* psutil/c_files/psutil/DEVNOTES psutil/c_files/psutil/tests && \
  cp -rv /build/psutil-${PSUTIL_VERSION}/psutil psutil/python_files/ && \
  rm -rvf psutil/python_files/psutil/*.c psutil/python_files/psutil/*.h psutil/python_files/psutil/arch psutil/python_files/psutil/tests && \
  cd psutil && \
  echo "Monkey patching psutil .py files to look for _pslinux C module anywhere, not just '.'" && \
  echo "__init__.py patch" && \
  ls -lR && \
  patch --ignore-whitespace -p0 < /build/psutil_import__init__.patch && \
  echo "_pslinux.py patch" && \
  patch --ignore-whitespace -p0 < /build/psutil_import_pslinux.patch 
  # Ready to be copied for Lib

ADD \
 ./BPO-7938_pr4338-fix-makesetup-script.patch \
 ./cpython-enable-openssl.patch \
 /build/

RUN \
  set -x && \
  echo "Building Python" && \
  cd /build && \
  curl \
     -L \
     -o /build/Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar.xz \
     https://www.python.org/ftp/python/${PYTHON_BASE_VERSION}/Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar.xz && \
  unxz Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar.xz && \
  tar -xf Python-${PYTHON_BASE_VERSION}${PYTHON_RC}.tar && \
  cd Python-${PYTHON_BASE_VERSION}${PYTHON_RC} && \
  mkdir Modules/psutil && \
  cp -r /build/psutil/c_files/psutil/* Modules/psutil/ && \
  psversion=$(echo $PSUTIL_VERSION | sed 's,\.,,g') && \
  cp Modules/Setup.dist Modules/Setup && \
  MODULES="_bisect _collections _csv _datetime _elementtree _functools _heapq _io _md5 _posixsubprocess _random _sha256 _sha512 _socket _struct _weakref array binascii cmath datetime fcntl grp itertools math mmap operator parser readline resource select spwd syslog termios time unicodedata zlib" && \
  for mod in $MODULES; do echo "enabling ${mod}" ; sed -i -e "s/^#${mod}/${mod}/" Modules/Setup;  done && \
  echo '_json _json.c' >> Modules/Setup && \
  echo '_multiprocessing _multiprocessing/multiprocessing.c _multiprocessing/semaphore.c _multiprocessing/socket_connection.c' >> Modules/Setup && \
  sed -i '1i *static*' Modules/Setup && \
  sed -i \
      -e "s|^zlib zlibmodule.c|zlib zlibmodule.c -I/build/zlib-${ZLIB_VERSION} -L/build/zlib-${ZLIB_VERSION} -lz|" \
      -e "s|^readline readline.c|readline readline.c -I/build/readline-${READLINE_VERSION} -L/build/readline-${READLINE_VERSION} -L/build/termcap-${TERMCAP_VERSION} -lreadline -ltermcap|" \
      Modules/Setup && \
  echo "" >> Modules/Setup && \
  echo "_lsprof rotatingtree.c _lsprof.c" >>Modules/Setup && \
  echo "pyexpat expat/xmlparse.c expat/xmlrole.c expat/xmltok.c pyexpat.c -I\$(srcdir)/Modules/expat -DHAVE_EXPAT_CONFIG_H -DUSE_PYEXPAT_CAPI -DHAVE_SYSCALL_GETRANDOM" >>Modules/Setup && \
  echo "_psutil_linux psutil/_psutil_common.c psutil/_psutil_posix.c psutil/_psutil_linux.c -DPSUTIL_POSIX=1 -DPSUTIL_VERSION=__PSVER__ -DPSUTIL_LINUX=1" >>Modules/Setup && \
  echo "_psutil_posix psutil/_psutil_common.c psutil/_psutil_posix.c                        -DPSUTIL_POSIX=1 -DPSUTIL_VERSION=__PSVER__ -DPSUTIL_LINUX=1" >>Modules/Setup && \
  echo "crypt cryptmodule.c  -lcrypt" >>Modules/Setup && \
  patch --ignore-whitespace -p1 < /build/cpython-enable-openssl.patch && \
  echo "Patching for https://bugs.python.org/issue7938" && \
  patch --ignore-whitespace -p0 < /build/BPO-7938_pr4338-fix-makesetup-script.patch && \
  sed -i \
      -e "s|^SSL=/build/openssl-TKTK|SSL=/build/openssl-${OPENSSL_VERSION}|" \
      -e "s|__PSVER__|${psversion}|g"                                        \
      Modules/Setup && \
  cat Modules/Setup && \
  CC='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-gcc -static -fPIC' \
    CXX='/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-g++ -static -static-libstdc++ -fPIC' \
    LD=/opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-ld \
    ./configure \
      --disable-shared \
      --with-openssl=/build/openssl-${OPENSSL_VERSION} && \
  (make --trace -j $(nproc --all) LDFLAGS="-static" LINKFORSHARED=" " || true) && \
  /opt/cross/x86_64-linux-musl/bin/x86_64-linux-musl-strip python && \
  cp $(find . -name _sysconfigdata.py -print) Lib && \
  cp -r /build/psutil/python_files/psutil Lib && \
  cd Lib && zip -r ../python2.7.zip .

###
FROM scratch
MAINTAINER Lisa Seelye <lisa@thedoh.com>
WORKDIR /

ARG PYTHON_BASE_VERSION=3.6.6
ARG PYTHON_RC=

COPY \
  --from=0 \
    /build/Python-${PYTHON_BASE_VERSION}${PYTHON_RC}/python        \ 
    /build/Python-${PYTHON_BASE_VERSION}${PYTHON_RC}/python2.7.zip \ 
  /
# just in case things need them to exist, like flask
COPY passwd /etc/passwd
COPY group /etc/group

ENV \
  PYTHONHOME=/python2.7.zip \
  PYTHONPATH=/python2.7.zip

# Users of this base image should be sure to COPY their entrypoint.py to /entrypoint.py
CMD [ "/python", "-s", "-S", "/entrypoint.py" ]
