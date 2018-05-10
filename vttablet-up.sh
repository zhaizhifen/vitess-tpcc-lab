#!/bin/bash

# Copyright 2017 Google Inc.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This is an example script that creates a single shard vttablet deployment.

set -ex

cell='tpcccell'
keyspace=${KEYSPACE:-'tpcc_keyspace'}
shard=${SHARD:-'0'}
uid_base=${UID_BASE:-'100'}
port_base=$[15000 + $uid_base]
grpc_port_base=$[16000 + $uid_base]
mysql_port_base=$[17000 + $uid_base]
tablet_hostname=${HOSTN:-'0'}


script_root=`dirname "${BASH_SOURCE}"`
source $script_root/env.sh

dbconfig_dba_flags="\
    -db-config-dba-uname vt_dba \
    -db-config-dba-charset utf8"
dbconfig_flags="$dbconfig_dba_flags \
    -db-config-app-uname vt_app \
    -db-config-app-dbname vt_$keyspace \
    -db-config-app-charset utf8 \
    -db-config-dba-host $tablet_hostname \
    -db-config-dba-port 3306 \
    -db-config-app-host $tablet_hostname \
    -db-config-app-port 3306 \
    -db-config-allprivs-host $tablet_hostname \
    -db-config-allprivs-port 3306 \
    -db-config-appdebug-host $tablet_hostname \
    -db-config-appdebug-port 3306 \
    -db-config-repl-host $tablet_hostname \
    -db-config-repl-port 3306 \
    -db-config-filtered-host $tablet_hostname \
    -db-config-filtered-port 3306 \
    -db-config-appdebug-uname vt_appdebug \
    -db-config-appdebug-dbname vt_$keyspace \
    -db-config-appdebug-charset utf8 \
    -db-config-allprivs-uname vt_allprivs \
    -db-config-allprivs-dbname vt_$keyspace \
    -db-config-allprivs-charset utf8 \
    -db-config-repl-uname vt_repl \
    -db-config-repl-dbname vt_$keyspace \
    -db-config-repl-charset utf8 \
    -db-config-filtered-uname vt_filtered \
    -db-config-filtered-dbname vt_$keyspace \
    -db-config-filtered-charset utf8"

init_db_sql_file="config/init_db.sql"

mkdir -p $VTDATAROOT/backups

# Start 5 vttablets by default.
# Pass TABLETS_UIDS indices as env variable to change
uids=${TABLETS_UIDS:-'0'}

optional_auth_args=''
if [ "$1" = "--enable-grpc-static-auth" ];
then
	  echo "Enabling Auth with static authentication in grpc"
    optional_auth_args='-grpc_auth_mode static -grpc_auth_static_password_file ./grpc_static_auth.json'
fi

# Start all vttablets in background.
for uid_index in $uids; do
  uid=$[$uid_base + $uid_index]
  port=$[$port_base + $uid_index]
  grpc_port=$[$grpc_port_base + $uid_index]
  printf -v alias '%s-%010d' $cell $uid
  printf -v tablet_dir 'vt_%010d' $uid
  mkdir -p $VTDATAROOT/$tablet_dir
#  echo "[mysqld]" > $VTDATAROOT/$tablet_dir/my.cnf
#  echo "server_id=1" >> $VTDATAROOT/$tablet_dir/my.cnf
#  echo "port=3306" >> $VTDATAROOT/$tablet_dir/my.cnf

  tablet_type=replica
  if [[ $uid_index -gt 2 ]]; then
    tablet_type=rdonly
  fi

  echo "Starting vttablet for $alias..."
  # shellcheck disable=SC2086
  $VTROOT/bin/vttablet \
    $TOPOLOGY_FLAGS \
    -log_dir $VTDATAROOT/tmp \
    -tablet-path $alias \
    -tablet_hostname "$(hostname -f)" \
    -init_keyspace $keyspace \
    -init_shard $shard \
    -mycnf_server_id=1 \
    -init_tablet_type $tablet_type \
    -health_check_interval 5s \
    -enable_semi_sync=false \
    -enable_replication_reporter=false \
    -backup_storage_implementation file \
    -file_backup_storage_root $VTDATAROOT/backups \
    -restore_from_backup=false \
    -port $port \
    -grpc_port $grpc_port \
    -service_map 'grpc-queryservice,grpc-tabletmanager,grpc-updatestream' \
    -pid_file $VTDATAROOT/$tablet_dir/vttablet.pid \
    -vtctld_addr http://$hostname:$vtctld_web_port/ \
    $optional_auth_args \
    $dbconfig_flags \
    > $VTDATAROOT/$tablet_dir/vttablet.out 2>&1 &

  echo "Access tablet $alias at http://$hostname:$port/debug/status"
done

disown -a