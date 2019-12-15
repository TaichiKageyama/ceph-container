#!/bin/bash

rgw_setup_env()
{
	setup_env
	test -e $CFG || (echo "ERR: no $CFG" >&2 && exit 1)
	RGW_HOSTNAME=`hostname -s`
	setup_dir RGW_DIR \
		/var/lib/ceph/radosgw/${ENV_CLUSTER_NAME}-rgw.${RGW_HOSTNAME}
	setup_dir RGW_RUN_DIR /var/run/ceph
	RGW_NAME=client.rgw.$RGW_HOSTNAME
	test $RGW_HOSTNAME || RGW_HOSTNAME=s3.example
	test $ENV_RGW_PORT || ENV_RGW_PORT=7480
}

rgw_init()
{
	rgw_setup_env
	grep $RGW_NAME $CFG
	if [ $? -ne 0 ]; then
		cat <<EOF >> $CFG

[$RGW_NAME]
host = $RGW_HOSTNAME
rgw_frontends = "civetweb port=$ENV_RGW_PORT"
rgw_dns_name = $ENV_RGW_DNS_NAME
rgw_zonegroup = $ENV_RGW_ZONE_GROUP
rgw_zone = $ENV_RGW_ZONE
EOF
	fi
	# Create a Realm
	radosgw-admin realm get | grep $ENV_RGW_REALM
	if [ $? -ne 0 ]; then
		radosgw-admin realm create --rgw-realm=$ENV_RGW_REALM --default
	fi

	radosgw-admin zonegroup get | grep $ENV_RGW_ZONE_GROUP
	if [ $? -ne 0 ]; then
		radosgw-admin zonegroup create \
			--endpoints=$ENV_RGW_ENDPOINT \
			--rgw-zonegroup=$ENV_RGW_ZONE_GROUP --master --default
	else
		echo "Modify zonegroup to add endpoint later"
	fi

	radosgw-admin zone get | grep $ENV_RGW_ZONE
	if [ $? -ne 0 ]; then
		radosgw-admin zone create --rgw-zonegroup=$ENV_RGW_ZONE_GROUP \
			--rgw-zone=$ENV_RGW_ZONE --master --default \
			--endpoints=$ENV_RGW_ENDPOINT
	else
		echo "Modify zone to add endpoint later"
	fi

	radosgw-admin user list | grep $ENV_RGW_ZONE_ADMIN
	if [ $? -ne 0 ]; then
		radosgw-admin user create --uid="$ENV_RGW_ZONE_ADMIN" \
			--display-name="$ENV_RGW_ZONE_ADMIN" --system
		echo "Modify zone to add system user later"
	fi

	radosgw-admin period update --commit
}

rgw_run()
{
	rgw_setup_env
	# For mon, Must provide the read cap, but write one is optional
	# Write cap make rgw create pools automatically.
	ceph auth get-or-create client.rgw.${RGW_HOSTNAME} \
		mon 'allow r' osd 'allow rwx' \
		-o $RGW_DIR/keyring
	chown $ENV_CEPH_USER:$ENV_CEPH_GROUP $RGW_DIR/keyring
	exec radosgw -f --cluster $ENV_CLUSTER_NAME --name $RGW_NAME \
		--setuser $ENV_CEPH_USER --setgroup $ENV_CEPH_GROUP
}
