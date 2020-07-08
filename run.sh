#!/bin/sh

echo "TWITTER_CONSUMER_KEY=${TWITTER_CONSUMER_KEY}" >> /usr/local/lib/R/etc/Renviron
echo "TWITTER_CONSUMER_SECRET=${TWITTER_CONSUMER_SECRET}" >> /usr/local/lib/R/etc/Renviron
echo "TWITTER_ACCESS_TOKEN=${TWITTER_ACCESS_TOKEN}" >> /usr/local/lib/R/etc/Renviron
echo "TWITTER_ACCESS_TOKEN_SECRET=${TWITTER_ACCESS_TOKEN_SECRET}" >> /usr/local/lib/R/etc/Renviron
echo "GOOGLE_ANALYTICS_ID=${GOOGLE_ANALYTICS_ID}" >> /usr/local/lib/R/etc/Renviron

exec shiny-server 2>&1