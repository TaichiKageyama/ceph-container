#!/bin/bash

setup_env()
{
	test $ENV_CLUSTER_NAME || ENV_CLUSTER_NAME=ceph
	CFG="/etc/ceph/${ENV_CLUSTER_NAME}.conf"
	ADM_KEY="/etc/ceph/${ENV_CLUSTER_NAME}.client.admin.keyring"

	if [ ! -e $CFG ]; then
		if [ ! $ENV_PUBLIC_NW ]; then
			echo "ERR: no ENV_PUBLIC_NW" >&2
			exit 1
		fi
		test $ENV_CLUSTER_NW || ENV_CLUSTER_NW=$ENV_PUBLIC_NW
		ENV_FSID=`uuidgen`
	else
		ENV_PUBLIC_NW=`grep public_network $CFG | cut -d ' ' -f 3`
		ENV_CLUSTER_NW=`grep cluster_network $CFG | cut -d ' ' -f 3`
		ENV_FSID=`grep fsid $CFG | cut -d ' ' -f 3`
	fi
	
	# Up to 128MB (default)
        test $ENV_TCMALLOC_CACHE_BYTES || ENV_TCMALLOC_CACHE_BYTES=134217728
	
	test $ENV_CEPH_USER || ENV_CEPH_USER=ceph
	test $ENV_CEPH_GROUP || ENV_CEPH_GROUP=ceph
}

setup_dir()
{
	local dir_var=$1
	local dir=$2
	mkdir -p $dir
	chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $dir
	eval $dir_var=$dir
}


