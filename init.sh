#!/bin/bash
set -x
DIR=$(cd $(dirname ${BASH_SOURCE:-$0}); pwd)
source $DIR/.env
cd $DIR

docker-compose stop
docker-compose rm
rm -rf $DIR/PV/etc/ceph/*
rm -rf $DIR/PV/var/lib/ceph/*

# Prepare mon & osd
docker-compose run --rm -e ENV_CEPH_SRV=mon_init mon
docker-compose run --rm -e ENV_CEPH_SRV=osd_init osd0
docker-compose run --rm -e ENV_CEPH_SRV=osd_init osd1

docker-compose up -d mon osd0 osd1 mgr
sleep 10
CEPH_CMD="docker-compose exec mon ceph"
#$CEPH_CMD osd crush rm-device-class osd.0
#$CEPH_CMD osd crush rm-device-class osd.1
#$CEPH_CMD osd crush set-device-class $DISK0_CLASS osd.0
#$CEPH_CMD osd crush set-device-class $DISK1_CLASS osd.1
#$CEPH_CMD osd crush move `hostname -s` root=$OSD_ROOT
#$CEPH_CMD osd crush set osd.0 $DISK0_SIZE_RATIO root=home host=`hostname -s`
#$CEPH_CMD osd crush set osd.1 $DISK1_SIZE_RATIO root=home host=`hostname -s`
$CEPH_CMD osd crush rule rm replicated_rule
$CEPH_CMD osd crush rm default
$CEPH_CMD osd crush rule create-replicated replicated_rule $OSD_ROOT host $DISK0_CLASS
$CEPH_CMD osd crush rule create-replicated rgw_bucket-data_rule $OSD_ROOT host
$CEPH_CMD osd crush rule create-replicated rbd_rule $OSD_ROOT host $DISK0_CLASS
$CEPH_CMD osd pool create rbd 32 32 replicated rbd_rule
$CEPH_CMD osd pool application enable rbd rbd
$CEPH_CMD osd pool create .rgw.root 8 8 replicated replicated_rule
$CEPH_CMD osd pool application enable .rgw.root rgw
$CEPH_CMD osd pool create $RGW_ZONE.rgw.buckets.data 32 32 replicated rgw_bucket-data_rule
$CEPH_CMD osd pool application enable $RGW_ZONE.rgw.buckets.data rgw
docker-compose run --rm -e ENV_CEPH_SRV=rgw_init rgw
docker-compose up -d rgw

# Enable ceph dashboard
$CEPH_CMD mgr module enable dashboard

RGW_ADMIN_CMD="docker-compose exec mon radosgw-admin"
mkdir -p ~/.aws
chmod 700 ~/.aws
AWS_CFG=~/.aws/credentials
test -e $AWS_CFG && rm -rf $AWS_CFG
touch $AWS_CFG

make_credential()
{
	user=$1
	local access_key=""
	local secret_key=""
	local user_create="user create --uid=$user --display-name=$user"
	local user_info="user info --uid=$user"

	grep $user $AWS_CFG && return 0

	$RGW_ADMIN_CMD metadata list user | grep "\"$user\""
	if [ $? -ne 0 ]; then
		local json=`$RGW_ADMIN_CMD $user_create`
	else
		local json=`$RGW_ADMIN_CMD $user_info`
	fi
	access_key=`echo $json | jq -r '.keys[0].access_key'`
	secret_key=`echo $json | jq -r '.keys[0].secret_key'`

	cat <<EOF >> $AWS_CFG

[$user]
aws_access_key_id = $access_key
aws_secret_access_key = $secret_key

EOF
}

make_bucket()
{
	local bucket=$1
	local admin_uid=$2
	local read_uid=$3
	local aws_cmd="aws --endpoint-url=$RGW_URL --profile $admin_uid"
	
	# Make bucket
	$aws_cmd s3 mb s3://$bucket
	$aws_cmd s3api put-bucket-acl --bucket $bucket \
		--grant-full-control id=$admin_uid --grant-read id=$read_uid
	$aws_cmd s3api get-bucket-acl --bucket $bucket

:<<'#__COMMENT_OUT__'
	# arn:aws:iam::tenantname:user/user_name
	local policy=`cat <<EOF
{
        "Version": "2012-10-17",
        "Statement":
	[{
                "Effect":"Allow",
                "Principal":{"AWS":"arn:aws:iam:::user/$admin_uid"},
                "Action":"s3:*",
                "Resource": [
                        "arn:aws:s3:::$bucket/*"
                ]
        },
        {
                "Effect":"Allow",
                "Principal":{"AWS":"arn:aws:iam:::user/$read_uid"},
                "Action":[
			"s3:GetObject",
			"s3:ListObjects",
			"s3:ListBucket"
		],
                "Resource": [
                        "arn:aws:s3:::$bucket/*"
                ]
        }]
}
EOF
`
	$aws_cmd s3api put-bucket-policy --bucket $bucket --policy "$policy"
#__COMMENT_OUT__

}

for i in $RGW_ADMIN $RGW_USER
do
	make_credential $i
done
chmod 600 $AWS_CFG

for i in $RGW_BUCKETS
do
	make_bucket $i $RGW_ADMIN $RGW_USER
done

