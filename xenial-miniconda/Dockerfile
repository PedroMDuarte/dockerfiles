FROM ubuntu:xenial

# ----
# Install miniconda
# Adapted from https://github.com/ContinuumIO/docker-images/blob/master/miniconda/Dockerfile
# ----

ENV PATH /opt/conda/bin:$PATH

RUN apt-get update --fix-missing && apt-get install -y \
    wget \
    bzip2 \
    ca-certificates \
    libglib2.0-0 \
    libxext6 \
    libsm6 \
    libxrender1 \
    nginx \
    supervisor

RUN wget --quiet https://repo.continuum.io/miniconda/Miniconda2-4.4.10-Linux-x86_64.sh -O ~/miniconda.sh && \
    /bin/bash ~/miniconda.sh -b -p /opt/conda && \
    rm ~/miniconda.sh && \
    ln -s /opt/conda/etc/profile.d/conda.sh /etc/profile.d/conda.sh && \
    echo ". /opt/conda/etc/profile.d/conda.sh" >> ~/.bashrc && \
    echo "conda activate base" >> ~/.bashrc


# ----
# Setup conda
# ----
RUN conda update -n base conda && conda create --yes -q --name app python=3.6
