#!/bin/bash
if [ "$(whoami)" != "root" ]; then
    echo "Sorry, you are not root."
    exit 1
fi

#nc -v google.com 80 -w 1 #za preverjanje povezave

RHODEUSER="rhodecode" #user must not exists
RHODEBASEDIR="/opt/rhode"

MYSQL_VER="5.5"
MYSQL_PASS=`head -c 200 /dev/urandom | tr -cd 'A-Za-z0-9' | head -c 20`
RHODEMYSQL_PASS=`head -c 200 /dev/urandom | tr -cd 'A-Za-z0-9' | head -c 10`

#OPTIONAL
apt-get update
apt-get -y upgrade

apt-get install -y python-pip python-dev libmysqlclient-dev rabbitmq-server

rabbitmqctl add_user rhodeuser rhodepass
rabbitmqctl add_vhost rhodevhost
rabbitmqctl set_permissions -p rhodevhost rhodeuser ".*" ".*" ".*"

debconf-set-selections <<< "mysql-server-$MYSQL_VER mysql-server/root_password password $MYSQL_PASS"
debconf-set-selections <<< "mysql-server-$MYSQL_VER mysql-server/root_password_again password $MYSQL_PASS"
apt-get -y install mysql-server-$MYSQL_VER
mysql -uroot -p$MYSQL_PASS <<EOFMYSQL
create database rhodecode character set utf8;
create user 'rhodecode'@'localhost' identified by '$RHODEMYSQL_PASS';
grant all privileges on rhodecode.* to 'rhodecode'@'localhost';
flush privileges;
EOFMYSQL

pip install virtualenv

mkdir $RHODEBASEDIR
virtualenv --no-site-packages $RHODEBASEDIR/venv
source $RHODEBASEDIR/venv/bin/activate
pip install mysql-python
pip install pastescript
pip install rhodecode

mkdir $RHODEBASEDIR/data
mkdir $RHODEBASEDIR/repos
paster make-config RhodeCode $RHODEBASEDIR/data/production.ini

sed -i "s/use_celery = false/use_celery = true/" $RHODEBASEDIR/data/production.ini
sed -i "s/broker.vhost = rabbitmqhost/broker.vhost = rhodevhost/" $RHODEBASEDIR/data/production.ini
sed -i "s/broker.user = rabbitmq/broker.user = rhodeuser/" $RHODEBASEDIR/data/production.ini
sed -i "s/broker.password = qweqwe/broker.password = rhodepass/" $RHODEBASEDIR/data/production.ini
sed -i "s/sqlalchemy.db1.url = sqlite/# sqlalchemy.db1.url = sqlite/" $RHODEBASEDIR/data/production.ini
sed -i "s/# sqlalchemy.db1.url = mysql.*$/sqlalchemy.db1.url = mysql:\/\/rhodecode:$RHODEMYSQL_PASS@localhost\/rhodecode/" $RHODEBASEDIR/data/production.ini
paster setup-rhodecode $RHODEBASEDIR/data/production.ini --user=admin --password=123456 --email=admin@demo.si --repos=$RHODEBASEDIR/repos

adduser --no-create-home --disabled-login --system --group $RHODEUSER
chown -R $RHODEUSER:$RHODEUSER $RHODEBASEDIR

chmod +x rhodecode-daemon2
cp rhodecode-daemon2 /etc/init.d/rhodecode
update-rc.d rhodecode defaults

#TODO NGINX
apt-get -y install nginx
mkdir /etc/nginx/certs
chmod 600 server.crt server.key
cp server.crt /etc/nginx/certs/server.crt
cp server.key /etc/nginx/certs/server.key
cp nginx_rhodecode.conf /etc/nginx/conf.d/rhodecode.conf
cp nginx_rhodecode.site /etc/nginx/sites-available/rhodecode
ln -s /etc/nginx/sites-available/rhodecode /etc/nginx/sites-enabled/rhodecode
rm /etc/nginx/sites-enabled/default

echo
echo
echo
echo "MYSQL root password: "$MYSQL_PASS
echo