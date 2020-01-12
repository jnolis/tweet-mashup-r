FROM rocker/r-ver:3.6.1

# update some packages, including sodium and apache2, then clean
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    file \
    libcurl4-openssl-dev \
    libedit2 \
    libssl-dev \
    lsb-release \
    psmisc \
    procps \
    wget \
    libxml2-dev \
    libpq-dev \
    libssh2-1-dev \
    ca-certificates \
    libglib2.0-0 \
	  libxext6 \
	  libsm6  \
	  libxrender1 \
	  bzip2 \
    zlib1g-dev \
    libv8-dev \
    gdebi-core \
    && wget -O libssl1.0.0.deb http://ftp.debian.org/debian/pool/main/o/openssl/libssl1.0.0_1.0.1t-1+deb8u8_amd64.deb \
    && dpkg -i libssl1.0.0.deb \
    && rm libssl1.0.0.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/ 
  
# Install R Shiny Server (not pro) and required libraries
RUN wget https://s3.amazonaws.com/rstudio-shiny-server-os-build/ubuntu-12.04/x86_64/VERSION -O "version.txt" && \
    VERSION=$(cat version.txt)  && \
    wget "https://s3.amazonaws.com/rstudio-shiny-server-os-build/ubuntu-12.04/x86_64/shiny-server-$VERSION-amd64.deb" -O ss-latest.deb && \
    gdebi -n ss-latest.deb && \
    rm -f version.txt ss-latest.deb && \
    rm -rf /usr/local/lib/R/site-library/shiny/examples && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/log/shiny-server && \
    chown shiny.shiny /var/log/shiny-server && \ 
    rm -rf /srv/shiny-server/* && \
    mkdir /srv/shiny-server/shiny

# Install the R libraries that will always be needed
# you can remove the keras installation if you aren't using reticulate or keras
RUN install2.r --error \
  shiny \
  && rm -rf tmp/downloaded_packages/*

# copy the setup script, run it, then delete it
# By splitting this from the line above you can more quickly add/remove packages
COPY src/setup.R /
RUN Rscript setup.R && rm setup.R

# Use the appropriate shiny-server.conf
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# copy the r folder and data
COPY src /srv/shiny-server/shiny/

EXPOSE 80

WORKDIR /src
ENTRYPOINT ["shiny-server"]