#!/bin/bash

# Keep "key + space + = + space + value" format
build_ceph_conf(){
	cat <<EOF > $CFG
[global]
fsid = $ENV_FSID
mon_initial_members = $MON_HOSTNAME
mon_host = $MON_IP
public_network = $ENV_PUBLIC_NW
cluster_network = $ENV_CLUSTER_NW
# Allow single OSD
osd_pool_default_size = 1
osd_pool_default_min_size = 1
# Use journald only
log_file = /dev/null

EOF
	cat <<'EOF' >> $CFG
pid_file = /var/run/$cluster/$type.$id.pid

[mon]
mon_osd_down_out_subtree_limit = host
mon_osd_min_down_reporters = 1

# Use journald only
mon_cluster_log_file = /dev/null

mon_data_avail_warn = 5
mon_data_avail_crit = 2

[osd]
# For tmpfs journal
journal dio = false
journal aio = false

# Use tmpfs for journal
# - 100MB/s through GE --> 100MB/s through tmpfs --> 100MB/s thorugh USB3 
#   size >= {2 * ( 100MB/s:[throughput] * 2:[filestore_max_sync_interval] )}
osd_journal_size = 400
filestore_max_sync_interval = 2

# Scrub Tuning
osd_max_scrubs = 1
# 30*60*60*24 (Once per Month)
osd_scrub_max_interval = 2592000
# 7*60*60*24 (Once per Week)
osd_scrub_min_interval = 604800
# 30*60*60*24 (Once per Month)
osd_deep_scrub_interval = 2592000
osd_scrub_interval_randomize_ratio = 1
osd_scrub_chunk_min = 1
osd_scrub_chunk_max = 5
osd scrub sleep = 0.5
osd_scrub_begin_hour = 20
osd_scrub_end_hour = 3
osd_scrub_during_recovery = false

# keep cusomize crushmap
osd_crush_update_on_start = false

EOF

	chown ceph:ceph $CFG
}

mon_setup_env()
{
	setup_env
	MON_IP=`hostname -i`
	MON_HOSTNAME=`hostname -s`
	setup_dir MON_DIR /var/lib/ceph/mon/${ENV_CLUSTER_NAME}-${MON_HOSTNAME}
	setup_dir MON_RUN_DIR /var/run/ceph
	MON_DB=${MON_DIR}/store.db
	T_MON_KEY=/tmp/ceph.mon.keyring
	T_MON_MAP=/tmp/monmap
}

mon_init()
{
	mon_setup_env
	if [ ! -e $CFG ]; then
		build_ceph_conf
		ceph-authtool -C $T_MON_KEY -g -n mon. --cap mon 'allow *'
		ceph-authtool -C $ADM_KEY -g -n client.admin \
			--set-uid=0 --cap mon 'allow *' \
			--cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
		chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $ADM_KEY
		ceph-authtool $T_MON_KEY --import-keyring $ADM_KEY
		monmaptool --create --add $MON_HOSTNAME $MON_IP \
			--fsid $ENV_FSID $T_MON_MAP
	else
		ceph auth get mon. -o $T_MON_KEY
		ceph mon getmap -o $T_MON_MAP
	fi

	# Make sure $MON_DIR is clean
	rm -rf $MON_DIR/*

	ceph-mon --mkfs -i $MON_HOSTNAME \
		--monmap $T_MON_MAP --keyring $T_MON_KEY
	chown -R $ENV_CEPH_USER:$ENV_CEPH_GROUP $MON_DIR
	# Clean up tmp files
	rm -f $T_MON_MAP  $T_MON_KEY
}

mon_run()
{
	mon_setup_env

        #Don't save coredump
        ulimit -c 0
	
	ceph-mon -f --cluster ${ENV_CLUSTER_NAME} --id $MON_HOSTNAME \
		--setuser $ENV_CEPH_USER --setgroup $ENV_CEPH_GROUP
}

