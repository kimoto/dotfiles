#!/bin/sh

sudo yum install -y mysql-server 
sudo service mysqld start

/usr/bin/mysqladmin -u root password ''
/usr/bin/mysql -h localhost -u root -e 'show databases;' # ノーパスワードでアクセスできることを確認

