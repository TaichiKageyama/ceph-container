#!/bin/bash

mgr_setup_env()
{
	setup_env
	test -e $CFG || (echo "ERR: no $CFG" >&2 && exit 1)
	MGR_HOSTNAME=`hostname -s`
        setup_dir MGR_DIR /var/lib/ceph/mgr/${ENV_CLUSTER_NAME}-${MGR_HOSTNAME}
        setup_dir MGR_RUN_DIR /var/run/ceph
}

mgr_run()
{
	mgr_setup_env
	ceph auth get-or-create mgr.${MGR_HOSTNAME} \
		mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
		-o $MGR_DIR/keyring
	chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $MGR_DIR/keyring
	TCMALLOC_MAX_TOTAL_THREAD_CACHE_BYTES=$ENV_TCMALLOC_CACHE_BYTES \
	exec ceph-mgr -f --cluster $ENV_CLUSTER_NAME -i $MGR_HOSTNAME \
		--setuser $ENV_CEPH_USER --setgroup $ENV_CEPH_GROUP
}
