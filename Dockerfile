FROM thedoh/musl-cross:1.1.19
MAINTAINER Lisa Seelye <lisa@thedoh.com>
# Upstream maintainer: Andrew Dunham <andrew@du.nham.ca>

RUN apt-get update && apt-get install -y zip

# Add our build script
ADD . /build/

# This builds the program and copies it to /output
RUN /build/build.sh

###
FROM scratch
MAINTAINER Lisa Seelye <lisa@thedoh.com>
WORKDIR /
COPY --from=0 /output/python* /

# just in case things need them to exist, like flask
COPY passwd /etc/passwd
COPY group /etc/group

ENV \
  PYTHONHOME=/python2.7.zip \
  PYTHONPATH=/python2.7.zip

# Users of this base image should be sure to COPY their entrypoint.py to /entrypoint.py
CMD [ "/python", "-s", "-S", "/entrypoint.py" ]
