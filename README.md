# docker-static-python

This repository is a fork of the [update python version](https://github.com/lisa/static-binaries/tree/update-python-version) branch in [my fork](https://github.com/lisa/static-binaries) of [andrew-d/static-binaries](https://github.com/andrew-d/static-binaries). The goal of this repository is to separate out the Python parts from the upstream collection of packages.

# Version

This Docker image provides Python-2.7.15rc1 with the following modules and software statically compiled in to the python binary:

* [psutil-5.4.5](https://pypi.org/project/psutil/)
* [OpenSSL-1.0.2k](https://www.openssl.org)
* [zlib-1.2.11](https://zlib.net/)
* [termcap-1.3.1](https://www.gnu.org/software/termutils/manual/termcap-1.3/termcap.html)
* [readline-6.3](https://tiswww.case.edu/php/chet/readline/rltop.html)

# Usage

By default the image will run `python -sS /entrypoint.py` but if you would prefer a Python shell invoke:

    $ docker run -ti thedoh/static-python:2.7.15rc1-r1
    Python 2.7.15rc1 (default, May 17 2018, 15:15:27)
    [GCC 5.3.0] on linux2
    >>> 



# psutil Notes

The package is included to illustrate the possibility of compiling third party modules into the Python static image. The `psuutil` package is patched with two patches (below) to force the `psutil` Python library code to _not_ look in its directory (`from . import`) and rather to anywhere the requirement can be met (such as from within the `python` binary).
* [psutil_import__init__.patch](psutil_import__init__.patch)
* [psutil_import_pslinux.patch](psutil_import_pslinux.patch)

A common use case will be to `pip install` some set of requirements for use. Since some of those requirements may have C code to compile it is thus a requirement to statically compile that code into the `python` binary because there are no shared Python objects to link against. The inclusion of `psutil` demonstrates this process.


## psutil License

> psutil is distributed under BSD license reproduced below.
> 
> Copyright (c) 2009, Jay Loden, Dave Daeschler, Giampaolo Rodola'
> All rights reserved.
> 
> Redistribution and use in source and binary forms, with or without modification,
> are permitted provided that the following conditions are met:
> 
>  * Redistributions of source code must retain the above copyright notice, this
>    list of conditions and the following disclaimer.
>  * Redistributions in binary form must reproduce the above copyright notice,
>    this list of conditions and the following disclaimer in the documentation
>    and/or other materials provided with the distribution.
>  * Neither the name of the psutil authors nor the names of its contributors
>    may be used to endorse or promote products derived from this software without
>    specific prior written permission.
> 
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
> ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
> WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
> DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
> ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
> (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
> LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
> ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
> (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
> SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## Entrypoint.py

A sample `entrypoint.py` to call an app using Factory pattern might be:

    import sys
    import os

    sys.path.append("/usr/src/app")

    os.chdir("/usr/src/app")

    from your.app import make_app

    app = make_app()

    app.run()

If you prefer to `execv` instead:

    import sys
    import os


    os.chdir("/")

    os.execv("/python", ["-s","-S","/myapp.py"])
    # No code runs after here


Or `subprocess`:

    import sys
    import os


    os.chdir("/")

    import subprocess

    subprocess.call(["/python", "-s","-S","/myapp.py"])
    # Code execution continues
