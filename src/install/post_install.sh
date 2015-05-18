#!/bin/bash

source /etc/sbt2.conf

chown -R ${CIOP_USERNAME}.ciop /application
chmod 755 /application/*/*.sh
