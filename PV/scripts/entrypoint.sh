#!/bin/bash

DIR=`dirname "${0}"`
source $DIR/common.sh
source $DIR/mon.sh
source $DIR/mgr.sh
source $DIR/osd.sh
source $DIR/rgw.sh

set -x
${ENV_CEPH_SRV}

