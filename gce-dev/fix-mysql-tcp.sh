#!/bin/bash
set -euxo pipefail
# shellcheck disable=SC1091
source /root/crowd-cult-mysql.env
mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}" <<SQL
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'crowd_app'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
CREATE USER IF NOT EXISTS 'crowd_app'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON crowdandcult.* TO 'crowd_app'@'localhost';
GRANT ALL PRIVILEGES ON crowdandcult.* TO 'crowd_app'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
