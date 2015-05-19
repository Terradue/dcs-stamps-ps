#!/bin/bash

source /etc/sbt2.conf

chown -R ${CIOP_USERNAME}.ciop /application
chmod 755 /application/*/*.sh
chmod 755 /application/master_select/bin/*

exit 0
