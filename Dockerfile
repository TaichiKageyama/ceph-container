FROM centos:7
LABEL maintainer="32001477+TaichiKageyama@users.noreply.github.com"
RUN set -ex;                                                                \
    yum install -y epel-release;                                            \
    rpm --import https://download.ceph.com/keys/release.asc;                \
    rpm -ivh https://download.ceph.com/rpm-luminous/el7/noarch/ceph-release-1-1.el7.noarch.rpm; \
    yum install -y ceph-mon ceph-osd ceph-radosgw ceph-mds ceph-mgr;        \
    echo "export PS1='[ceph_base]# '" >> /root/.bashrc;                     \
    yum clean all;
