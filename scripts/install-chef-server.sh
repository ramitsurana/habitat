#!/bin/bash
apt-get update
apt-get -y install curl

chef_automate_fqdn=$1
user=$2
org=chefautomate

# create staging directories
if [ ! -d /drop ]; then
  mkdir /drop
fi
if [ ! -d /downloads ]; then
  mkdir /downloads
fi

# Checck if pre-requisites are already met

if ! [ -x "$(chef-server-ctl)" ]; then
  echo 'Chef is already installed. Exit..' >&2
  exit 1
fi

# download the Chef server package
if [ ! -f /downloads/chef-server-core_12.16.2_amd64.deb ]; then
  echo "Downloading the Chef server package..."
  wget -nv -P /downloads https://packages.chef.io/files/stable/chef-server/12.16.2/ubuntu/16.04/chef-server-core_12.16.2-1_amd64.deb
fi

# install Chef server
if [ ! $(which chef-server-ctl) ]; then
  echo "Installing Chef server..."
  dpkg -i /downloads/chef-server-core_12.16.2-1_amd64.deb
  chef-server-ctl reconfigure

  echo "Waiting for services..."
  until (curl -D - http://localhost:8000/_status) | grep "200 OK"; do sleep 15s; done
  while (curl http://localhost:8000/_status) | grep "fail"; do sleep 15s; done
fi

# create user and organization
if [ ! $(sudo chef-server-ctl user-list | grep delivery) ]; then
  echo "Creating $user and $org organization..."
  chef-server-ctl user-create $user Chef Admin admin@$org.com insecurepassword --filename /drop/delivery.pem
  chef-server-ctl org-create $org "$org, Inc." --association_user $USER --filename $org-validator.pem
fi

# configure data collection
chef-server-ctl set-secret data_collector token '93a49a4f2482c64126f7b6015e6b0f30284287ee4054ff8807fb63d9cbd1c506'
chef-server-ctl restart nginx
echo "data_collector['root_url'] = 'https://$chef_automate_fqdn/data-collector/v0/'" >> /etc/opscode/chef-server.rb
chef-server-ctl reconfigure

# configure push jobs
if [ ! $(which opscode-push-jobs-server-ctl) ]; then
  echo "Installing push jobs server..."
  wget -nv -P /downloads https://packages.chef.io/files/stable/opscode-push-jobs-server/2.2.2/ubuntu/16.04/opscode-push-jobs-server_2.2.2-1_amd64.deb
  chef-server-ctl install opscode-push-jobs-server --path /downloads/opscode-push-jobs-server_2.2.2-1_amd64.deb
  opscode-push-jobs-server-ctl reconfigure
  chef-server-ctl reconfigure
fi

echo "Your Chef server is ready!"
