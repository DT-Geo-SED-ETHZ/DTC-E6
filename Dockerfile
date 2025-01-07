FROM ghcr.io/sed-eew/finder:master

# Install shakemap
# install python3.9 needed for shakemap dependencies without anaconda
# mainly for package shakemap-modules
RUN apt-get update && apt-get install -y \
    wget build-essential \
    libssl-dev libffi-dev \
    zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev \
    && apt-get clean

RUN mkdir $WORK_DIR/python39 \
    && cd $WORK_DIR/python39 \
    && wget https://www.python.org/ftp/python/3.9.9/Python-3.9.9.tgz \
    && tar xvf Python-3.9.9.tgz \
    && cd Python-3.9.9 \
    && ./configure --enable-optimizations \
    && make -j$(nproc) \
    && make altinstall \
    && cd .. && rm -rf Python-3.9.9*

# Install pip using ensurepip and install setuptools for pip install -e
RUN python3.9 -m ensurepip --upgrade \
    && python3.9 -m pip install --upgrade pip \
    && python3.9 -m pip install --upgrade setuptools

RUN apt-get install -y curl
RUN git clone https://github.com/DOI-USGS/ghsc-esi-shakemap.git $WORK_DIR/shakemap \
    && cd $WORK_DIR/shakemap \
    && python3.9 -m pip install -e .

# get pyfinder to wrap FinDer in python
RUN git clone https://github.com/sceylan/pyfinder.git $WORK_DIR/pyfinder
