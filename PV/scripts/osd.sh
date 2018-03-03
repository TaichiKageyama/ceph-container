#!/bin/bash

osd_setup_env()
{
	local tmp=""
	local pick_disk="sed -e s/[0-9].*//g"
	local pick_part="sed -e s/.*[a-z]//g"	
	setup_env
	test -e $CFG || (echo "ERR: no $CFG" >&2 && exit 1)

	OSD_HOSTNAME=`hostname -s`

	if [ ${FUNCNAME[1]} == "osd_init" ]; then
		ENV_OSD_ID=`ceph osd create`
	elif [ ! $ENV_OSD_ID ]; then
		echo "ENV_OSD_ID is required" >&2 && exit 1
	fi

	setup_dir OSD_DIR /var/lib/ceph/osd/${ENV_CLUSTER_NAME}-${ENV_OSD_ID}	
	setup_dir OSD_RUN_DIR /var/run/ceph
	OSD_UUID=4fbd7e29-9d25-41b8-afd0-062c0ceff05d
	OSD_JOURNAL_UUID=45b0969e-9b03-4f30-b4c6-b4b80ceff106
	OSD_XFS_OPT="rw,noatime,inode64"

	test $ENV_OSD_DISK || (echo "ERR: no ENV_OSD_DISK" >&2 && exit 1)
	OSD_DISK=`echo $ENV_OSD_DISK | $pick_disk`
	OSD_DISK_PART=`echo $ENV_OSD_DISK | $pick_part`
	test $OSD_DISK_PART || OSD_DISK_PART=0
	OSD_JOURNAL_DISK=`echo $ENV_OSD_JOURNAL_DISK | $pick_disk`
	OSD_JOURNAL_DISK_PART=`echo $ENV_OSD_JOURNAL_DISK | $pick_part`
	test $OSD_JOURNAL_DISK_PART || OSD_JOURNAL_DISK_PART=0

	if [ $ENV_JOURNAL_SIZE ]; then
		tmp="osd_journal_size = $ENV_JOURNAL_SIZE"
		sed -i "s/^osd_journal_size.*/$tmp/g" $CFG
	fi
	if [ $ENV_SYNC_INTERVAL ]; then
		tmp="filestore_max_sync_interval = $ENV_SYNC_INTERVAL"
		sed -i "s/^filestore_max_sync_interval.*/$tmp/g" $CFG
	fi
}

osd_make_gpt_table()
{
	local disk=$1
	echo "zap all data for $disk"
	sgdisk -Z $disk
	parted -s $disk mklabel gpt
	if [ $? -ne 0 ]; then
		echo "ERR: parted fialed" >&2 && exit 1
	fi
	partprobe
}

osd_journal_path_init()
{
	touch $ENV_JOURNAL_PATH
	# Assume journal path is dedicated for ceph like /ceph/journal
	chown $ENV_CEPH_USER:$ENV_CEP_GROUP `dirname $ENV_JOURNAL_PATH`
	chown $ENV_CEPH_USER:$ENV_CEP_GROUP $ENV_JOURNAL_PATH
	test -e $OSD_DIR/journal && rm -f $OSD_DIR/journal
	ln -s $ENV_JOURNAL_PATH $OSD_DIR/journal
}

osd_journal_disk_init()
{
        if [ $OSD_JOURNAL_DISK_PART == 0 ]; then
                osd_make_gpt_table $OSD_JOURNAL_DISK
        fi
	sgdisk --typecode=${OSD_JOURNAL_DISK_PART}:$OSD_JOURNAL_UUID \
		-- $OSD_JOURNAL_DISK
	ln -s $OSD_JOURNAL_DISK $OSD_DIR/journal
}

osd_init()
{
	osd_setup_env
	
	mount | grep $OSD_DIR
	if [ $? -eq 0 ]; then
		umount $OSD_DIR || echo "ERR: umount $OSD_DIR" >&2 && exit 1
	fi

	if [ $OSD_DISK_PART == 0 ]; then
		osd_make_gpt_table $OSD_DISK
	fi
	mkfs.xfs -f $ENV_OSD_DISK
	sgdisk --typecode=$OSD_DISK_PART:$osd_uuid -- $OSD_DISK
	
	mount -o $OSD_XFS_OPT $ENV_OSD_DISK $OSD_DIR
	if [ $? -ne 0 ]; then
		echo "ERR: mount $ENV_OSD_DISK $OSD_DIR" >&2 && exit 1
	fi
	
	if [ $ENV_JOURNAL_PATH ]; then
		osd_journal_path_init
		if [ $ENV_JOURNAL_DISK ]; then
			osd_journal_disk_init
		fi
	fi
	ceph-osd -i $ENV_OSD_ID --cluster $ENV_CLUSTER_NAME \
		--mkfs --mkkey --mkjournal --osd-uuid $ENV_FSID 
	ceph auth add osd.${ENV_OSD_ID} \
		mon 'allow profile osd' osd 'allow *' \
		-i $OSD_DIR/keyring
	chown -R $ENV_CEPH_USER:$ENV_CEPH_GROUP $OSD_DIR
	umount $OSD_DIR
	echo "Ready to start new OSD [ENV_OSD_ID=$ENV_OSD_ID]"
}

osd_map_init()
{
	# Edit crush map later to avoid the following ERR:
	#   "Error ENOENT: osd.x does not exist."
	sleep 10
	ceph osd crush rm-device-class osd.$ENV_OSD_ID
	ceph osd crush set-device-class $ENV_OSD_CLASS osd.$ENV_OSD_ID
	ceph osd crush add osd.$ENV_OSD_ID \
		$ENV_OSD_SIZE_RATIO root=$ENV_OSD_ROOT host=$OSD_HOSTNAME
}

osd_run()
{
	osd_setup_env
	mount -o $OSD_XFS_OPT $ENV_OSD_DISK $OSD_DIR

	if [ ! -e $OSD_DIR/journal -a $ENV_JOURNAL_PATH ]; then
		osd_journal_path_init
		ceph-osd -i $ENV_OSD_ID \
			--cluster $ENV_CLUSTER_NAME --mkjournal \
			--setuser $ENV_CEPH_USER --setgroup $ENV_CEPH_GROUP
	fi

	ceph osd crush dump | grep $OSD_HOSTNAME
	if [ $? -ne 0 ]; then
		ceph osd crush add-bucket $OSD_HOSTNAME host
		ceph osd crush move $OSD_HOSTNAME root=$ENV_OSD_ROOT
	fi

	ceph osd crush dump | grep "osd.${ENV_OSD_ID}"
	if [ $? -ne 0 ]; then
		osd_map_init &
	fi

	#Don't save coredump
	ulimit -c 0
	
	TCMALLOC_MAX_TOTAL_THREAD_CACHE_BYTES=$ENV_TCMALLOC_CACHE_BYTES \
	ceph-osd -f --cluster $ENV_CLUSTER_NAME --id $ENV_OSD_ID \
		--setuser $ENV_CEPH_USER --setgroup $ENV_CEPH_GROUP
}

