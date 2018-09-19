#!/usr/bin/env sh
set -v

psql -U postgres -c 'CREATE USER pulp WITH SUPERUSER LOGIN;'
psql -U postgres -c 'CREATE DATABASE pulp OWNER pulp;'

mkdir -p ~/.config/pulp_smash
cp .travis/pulp-smash-config.json ~/.config/pulp_smash/settings.json

sudo mkdir -p /var/lib/pulp/tmp
sudo mkdir /etc/pulp/
sudo chown -R travis:travis /var/lib/pulp

sudo cp .travis/server.yaml /etc/pulp/server.yaml

echo "SECRET_KEY: \"$(cat /dev/urandom | tr -dc 'a-z0-9!@#$%^&*(\-_=+)' | head -c 50)\"" | sudo tee -a /etc/pulp/server.yaml

# Run migrations.
export DJANGO_SETTINGS_MODULE=pulpcore.app.settings
pulp-manager makemigrations pulp_app --noinput
pulp-manager migrate auth --noinput
pulp-manager migrate --noinput

if [ "$TEST" != 'docs' ]; then
  pulp-manager makemigrations pulp_file --noinput
  pulp-manager migrate --noinput
fi

pulp-manager reset-admin-password --password admin
pulp-manager runserver >> ~/django_runserver.log 2>&1 &
rq worker -n 'resource_manager@%h' -w 'pulpcore.tasking.worker.PulpWorker' >> ~/resource_manager.log 2>&1 &
rq worker -n 'reserved_resource_worker_1@%h' -w 'pulpcore.tasking.worker.PulpWorker' >> ~/reserved_worker-1.log 2>&1 &
sleep 5