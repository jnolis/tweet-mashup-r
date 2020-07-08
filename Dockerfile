FROM rocker/r-ver:4.0.1

RUN apt-get update && apt-get install -y \
    gdebi-core \
    pandoc \
    libxml2-dev \
    libssl-dev \
    pandoc-citeproc \
    libcurl4-gnutls-dev \
    libcairo2-dev \
    libxt-dev \
    xtail \
    wget \
    libssh2-1-dev \
    libsasl2-dev \
    libnode-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/

# Download and install shiny server
RUN wget --no-verbose https://download3.rstudio.org/ubuntu-14.04/x86_64/VERSION -O "version.txt" && \
    VERSION=$(cat version.txt)  && \
    wget --no-verbose "https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-$VERSION-amd64.deb" -O ss-latest.deb && \
    gdebi -n ss-latest.deb && \
    rm -f version.txt ss-latest.deb && \
    rm -rf /usr/local/lib/R/site-library/shiny/examples && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /var/log/shiny-server && \
    chown shiny.shiny /var/log/shiny-server && \ 
    rm -rf /srv/shiny-server/* && \
    mkdir /srv/shiny-server/shiny

# install shiny R package
RUN install2.r --error shiny && rm -rf tmp/downloaded_packages/*

# copy the setup script, run it, then delete it
# By splitting this from the line above you can more quickly add/remove packages
COPY src/setup.R /
RUN Rscript setup.R && rm setup.R

# Use the appropriate shiny-server.conf
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# copy the r folder and data
COPY src /srv/shiny-server/shiny/

# copy the run script
COPY run.sh /usr/bin/run.sh

ENTRYPOINT ["usr/bin/run.sh"]