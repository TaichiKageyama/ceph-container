#!/bin/bash

DIR=`dirname "${0}"`
source $DIR/common.sh
source $DIR/mon.sh
source $DIR/mgr.sh
source $DIR/osd.sh
source $DIR/rgw.sh
source $DIR/mds.sh

set -x
${ENV_CEPH_SRV}

