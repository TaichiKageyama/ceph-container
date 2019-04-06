#!/bin/bash

DIR=`dirname "${0}"`
source $DIR/common.sh
source $DIR/mon.sh
source $DIR/mgr.sh
source $DIR/osd.sh
source $DIR/rgw.sh

trap_SIGTERM() {
	echo 'SIGTERM ACCEPTED.'
	if [ ${ENV_CEPH_SRV} = "osd_run" ]; then
		ceph-osd -i ${ENV_OSD_ID} --flush-journal
	fi
	exit 0
}
trap 'trap_TERM' SIGTERM

set -x
${ENV_CEPH_SRV}

# wait for trap
while :
do
  sleep 1
done

