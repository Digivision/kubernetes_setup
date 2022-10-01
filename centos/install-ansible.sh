#!/bin/bash
# install python3 and pip before ansible
# https://www.inmotionhosting.com/support/server/linux/install-python-3-9-centos-7/

# https://docs.ansible.com/ansible/latest/installation_guide/installation_distros.html#installing-ansible-on-fedora-or-centos
sudo yum -y install epel-release
sudo yum -y install ansible

# verify version of ansible
ansible --version