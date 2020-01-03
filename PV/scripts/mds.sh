#!/bin/bash -ex

mds_setup_env()
{
	setup_env
	test -e $CFG || (echo "ERR: no $CFG" >&2 && exit 1)
	MDS_HOSTNAME=`hostname -s`
        MDS_NAME=mds.$MDS_HOSTNAME
        setup_dir MDS_BOOTSTRAP_DIR /var/lib/ceph/bootstrap-mds
	setup_dir MDS_DIR \
		/var/lib/ceph/mds/${ENV_CLUSTER_NAME}-${MDS_HOSTNAME}
        MDS_KEYRING=$MDS_DIR/keyring
	setup_dir MDS_RUN_DIR /var/run/ceph
}

mds_init()
{
        mds_setup_env
        grep $MDS_NAME $CFG
        if [ $? -ne 0 ]; then
                cat <<EOF >> $CFG
[$MDS_NAME]
#500MB
mds_cache_memory_limit = 536870912
EOF
        fi

        local mds_boot_key=${MDS_BOOTSTRAP_DIR}/${ENV_CLUSTER_NAME}.keyring
        ceph auth get-or-create client.bootstrap-mds    \
                mon 'allow profile bootstrap-mds'       \
                -o $mds_boot_key
        ceph auth get-or-create mds.${MDS_HOSTNAME}     \
                mon 'profile mds' mgr 'profile mds'     \
                mds 'allow *' osd 'allow *'             \
                -o $MDS_KEYRING

        chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $mds_boot_key
        chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $MDS_KEYRING
        chmod 600 $mds_boot_key $MDS_KEYRING
        
        # Note. Assume cephfs pool will be created later
        # https://docs.ceph.com/docs/master/cephfs/createfs/#
        # ceph osd pool create cephfs_data
        # ceph osd pool create cephfs_metadata
        # ceph fs new fs fs_metadata fs_data
}

mds_run()
{
	mds_setup_env
	ceph auth get-or-create mds.${MDS_HOSTNAME} \
                mon 'profile mds' mgr 'profile mds'     \
                mds 'allow *' osd 'allow *'             \
                -o $MDS_KEYRING
	chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $MDS_KEYRING
        chmod 600 $MDS_KEYRING
	exec ceph-mds -f --cluster $ENV_CLUSTER_NAME \
		--setuser $ENV_CEPH_USER --setgroup $ENV_CEPH_GROUP \
                -i $MDS_HOSTNAME
}
