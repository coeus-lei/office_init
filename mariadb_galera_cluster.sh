#!/usr/bin/env bash
##mariadb-galera-cluster it's for initialization and optimization
##support by https://mariadb.com/kb/en/library/galera-cluster/
#########################################################################

DATA_dir=/data/mariadb
INSTALL_dir=/usr/local/mariadb
MARIADB_versiona=10.0.33
GALERA_version=25.3.22
DOWNLOAD_url='https://mirrors.dtops.cc/sql/MariaDB/'
Url_percona='https://mirrors.dtops.cc/sql/Percona'
Local_File_url='http://mirrors.ds.com/SQL/mariadb'

#CentOS 7
#http://mirrors.ds.com/SQL/mariadb/mariadb-galera-10.0.25-linux-glibc_214-x86_64.tar.gz
#http://mirrors.ds.com/SQL/mariadb/galera-25.3.15-1.rhel7.el7.centos.x86_64.rpm

#CentOS 6
#http://mirrors.ds.com/SQL/mariadb/mariadb-galera-10.0.25-linux-x86_64.tar.gz
#http://mirrors.ds.com/SQL/mariadb/galera-25.3.15-1.rhel6.el6.x86_64.rpm

color_info() {
	echo=echo
	for cmd in echo /bin/echo; do
		$cmd >/dev/null 2>&1 || continue
		if ! $cmd -e "" | grep -qE '^-e'; then echo=$cmd && break; fi
	done

	CSI=$($echo -e "\033[")
	CEND="${CSI}0m"
	CDGREEN="${CSI}32m"
	CRED="${CSI}1;31m"
	CGREEN="${CSI}1;32m"
	CYELLOW="${CSI}1;33m"
	CBLUE="${CSI}1;34m"
	CMAGENTA="${CSI}1;35m"
	CCYAN="${CSI}1;36m"
	CSUCCESS="$CDGREEN"
	CFAILURE="$CRED"
	CQUESTION="$CMAGENTA"
	CWARNING="$CYELLOW"
	CMSG="$CCYAN"
}

check_os() {
	OS_release=$(awk '{print int(+$3>=6?$3:$4)}' /etc/redhat-release)
	[ `getconf WORD_BIT` == 32 ] && [ `getconf LONG_BIT` == 64 ] && \
		{ OS_bit=64;OS_bit_1=64;OS_bit_2='x86_64';OS_bit_3='x86_64'; } || \
		{ OS_bit=32;OS_bit_1=86;OS_bit_2='x86';OS_bit_3='i686'; }
	LIBC_version=$(getconf -a |awk '/GNU_LIBC_VERSION/{print $NF}')
	[ `expr ${LIBC_version} \> 2.14` == 1 ] && GLIBC_FLAG=linux-glibc_214 || GLIBC_FLAG=linux
	Mem=`free -m | awk '/Mem:/{print $2}'`
	Swap=`free -m | awk '/Swap:/{print $2}'`

	[ -d $(dirname ${DATA_dir}) ] || mkdir -p $(dirname ${DATA_dir})
	[ -d $(dirname ${INSTALL_dir}) ] || mkdir -p $(dirname ${INSTALL_dir})
	USER_check=$(id -u mysql >/dev/null 2>&1;echo $?)
	[ ! ${USER_check} = "0" ] || userdel -r mysql 2>/dev/null
	useradd -r -m -d ${DATA_dir} -k no -s /sbin/nologin -c 'Mariadb Database' mysql

	URL_mariadb="${DOWNLOAD_url}/mariadb-galera-${MARIADB_versiona}/bintar-${GLIBC_FLAG}-${OS_bit_2}/mariadb-galera-${MARIADB_versiona}-${GLIBC_FLAG}-${OS_bit_3}.tar.gz"
	URL_mariadb_src="${DOWNLOAD_url}/mariadb-galera-${MARIADB_versiona}/source/mariadb-galera-${MARIADB_versiona}.tar.gz"


	#[ -z "$(curl -Lks ${Local_File_url})" ] || URL_mariadb="${Local_File_url}/mariadb-galera-${MARIADB_versiona}-${GLIBC_FLAG}-${OS_bit_3}.tar.gz"
	while :; do
		RPM_galera_name=$(curl -Lks "${DOWNLOAD_url}/mariadb-galera-${MARIADB_versiona}/galera-${GALERA_version}/rpm/" | awk -F'"' '$2~/el'"${OS_release}"'.*'"${OS_bit_1}"'\.rpm$/ && $2!~/ppc/{print $2}')
		[ -n "${RPM_galera_name}" ] && { let i++ && break; } || break
		[[ "3" -lt "$i" ]] && break;
	done
	URL_galera="${DOWNLOAD_url}/mariadb-galera-${MARIADB_versiona}/galera-${GALERA_version}/rpm/${RPM_galera_name}"
	#[ -z "$(curl -Lks mirrors.ds.com/SQL/mariadb)" ] || URL_galera="${Local_File_url}/${RPM_galera_name}"
		Url_percona=$(curl -Lks "${Url_percona}" | awk -F'"' '{if ($2~/^percona-release/)a=$2}END{print "'$Url_percona'/"a}') || \
		Url_percona="http://www.percona.com/downloads/percona-release/redhat/0.1-3/percona-release-0.1-3.noarch.rpm"
}

downFile() {
	[ -z "$(which axel 2>/dev/null)" ] && downloading="`which wget` -c --no-check-certificate" || downloading="`which axel` --alternate --num-connections=20"
	[ -n "$(grep 'github.com' <<< "$1")" ] && downloading="`which wget` -c --no-check-certificate"
	[ -e "${1##*/}" ] && echo "[${CMSG}${1##*/}${CEND}] found" || ${downloading} $1 2>/dev/null
	[ ! -e "${1##*/}" ] &&
		{ echo "${CFAILURE}${src_url##*/} download failed, Please contact the author! ${CEND}"
		kill -9 $$; } || \
		{ echo "[${CMSG}${1##*/}${CEND}] download done"; }
}

galera_install() {
	if ! rpm -qa |grep galera >/dev/null 2>&1; then
	downFile ${URL_galera}
		yum install ${Url_percona} -y
		yum install percona-xtrabackup-24 -y
		#yum install ${RPM_galera_name} lsof rsync xtrabackup git socat -y
		yum install ${RPM_galera_name} lsof rsync git socat gcc gcc-c++ cmake make percona-toolkit -y
		git clone https://github.com/gguillen/galeranotify.git $(dirname ${DATA_dir})/galeranotify
		chmod +x $(dirname ${DATA_dir})/galeranotify/galeranotify.py
	fi
}

jemalloc_install() {
	[ -e /usr/local/lib/libjemalloc.so ] && { echo "[${CMSG} jemalloc Installed. ${CEND}]"; }
	URL_jemalloc=https://github.com/jemalloc/jemalloc/releases
	#while :; do src_url=$(timeout 5 curl -Lks ${URL_jemalloc}|awk -F'"' '/jemalloc-[0-9]+.[0-9]+.[0-9]+.tar.bz2/{print "https://github.com"$2;exit}'); done #&& { downFile $src_url && break; }; done
	src_url=$(timeout 5 curl -Lks ${URL_jemalloc}|awk -F'"' '/jemalloc-[0-9]+.[0-9]+.[0-9]+.tar.bz2/{print "https://github.com"$2;exit}')
	[ -d /tmp/jemalloc ] || mkdir -p /tmp/jemalloc
	#[ -z "$(which bzip2 2>/dev/null)" ] && 
	yum install -y bzip2
	curl -Lk "${src_url}" | tar xj -C /tmp/jemalloc/ --strip-components=1 && cd /tmp/jemalloc/
	#tar xf ${src_url##*/} && jemallocDir=${src_url##*/}
	#cd ${jemallocDir%\.tar\.bz2}
	LDFLAGS="-L//usr/local/lib -lrt" ./configure
	make -j $(getconf _NPROCESSORS_ONLN) && make install
	if [ -f "/usr/local/lib/libjemalloc.so" ];then
		[ "$OS_bit" == '64' ] && {
			ln -s /usr/local/lib/libjemalloc.so.2 /usr/lib64/libjemalloc.so.1; } || \
			{ ln -s /usr/local/lib/libjemalloc.so.2 /usr/lib/libjemalloc.so.1; }
			echo '/usr/local/lib' > /etc/ld.so.conf.d/local.conf
			ldconfig && cd .. && rm -rf  ${jemallocDir%\.tar\.bz2}*
	else
		echo "${CFAILURE}jemalloc install failed, Please contact the author! ${CEND}"
		kill -9 $$
		exit 9
	fi
}

root_password() {
	dbrootpw=$(echo $@ |awk '{for (i=1;i<=NF;i++)if ($i~/^rootpw/){print $i}}'|awk -F'=' '{print $2}')
	while :; do
		[ -n "${dbrootpw}" ] && dbrootpwd=$${dbrootpw} || \
		read -p "Please input the root password of database: " dbrootpwd
		[ -n "`echo $dbrootpwd | grep '[+|&]'`" ] && { echo "${CWARNING}input error,not contain a plus sign(+) and & ${CEND}"; continue; }
		(( ${#dbrootpwd} >= 5 )) && break || echo "${CWARNING}database root password least 5 characters! ${CEND}"
	done
}

set_config() {
	sed -i "s@max_connections.*@max_connections = $(($Mem/2))@" /etc/my.cnf
	if [ $Mem -gt 1500 -a $Mem -le 2500 ]; then
		sed -i 's@^thread_cache_size.*@thread_cache_size = 16@' /etc/my.cnf
		sed -i 's@^query_cache_size.*@query_cache_size = 16M@' /etc/my.cnf
		sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 16M@' /etc/my.cnf
		sed -i 's@^key_buffer_size.*@key_buffer_size = 16M@' /etc/my.cnf
		sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 128M@' /etc/my.cnf
		sed -i 's@^tmp_table_size.*@tmp_table_size = 32M@' /etc/my.cnf
		sed -i 's@^table_open_cache.*@table_open_cache = 256@' /etc/my.cnf
	elif [ $Mem -gt 2500 -a $Mem -le 3500 ]; then
		sed -i 's@^thread_cache_size.*@thread_cache_size = 32@' /etc/my.cnf
		sed -i 's@^query_cache_size.*@query_cache_size = 32M@' /etc/my.cnf
		sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 32M@' /etc/my.cnf
		sed -i 's@^key_buffer_size.*@key_buffer_size = 64M@' /etc/my.cnf
		sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 512M@' /etc/my.cnf
		sed -i 's@^tmp_table_size.*@tmp_table_size = 64M@' /etc/my.cnf
		sed -i 's@^table_open_cache.*@table_open_cache = 512@' /etc/my.cnf
	elif [ $Mem -gt 3500 -a $Mem -le 7000 ]; then
		sed -i 's@^thread_cache_size.*@thread_cache_size = 64@' /etc/my.cnf
		sed -i 's@^query_cache_size.*@query_cache_size = 64M@' /etc/my.cnf
		sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 64M@' /etc/my.cnf
		sed -i 's@^key_buffer_size.*@key_buffer_size = 256M@' /etc/my.cnf
		sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 1024M@' /etc/my.cnf
		sed -i 's@^tmp_table_size.*@tmp_table_size = 128M@' /etc/my.cnf
		sed -i 's@^table_open_cache.*@table_open_cache = 1024@' /etc/my.cnf
	elif [ $Mem -gt 7000 ]; then
		sed -i 's@^thread_cache_size.*@thread_cache_size = 128@' /etc/my.cnf
		sed -i 's@^query_cache_size.*@query_cache_size = 128M@' /etc/my.cnf
		sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 128M@' /etc/my.cnf
		sed -i 's@^key_buffer_size.*@key_buffer_size = 512M@' /etc/my.cnf
		sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 2048M@' /etc/my.cnf
		sed -i 's@^tmp_table_size.*@tmp_table_size = 256M@' /etc/my.cnf
		sed -i 's@^table_open_cache.*@table_open_cache = 2048@' /etc/my.cnf
	fi
	if [ "${GLIBC_FLAG}" = "linux-glibc_214" ]; then
		#chmod +x /etc/rc.d/rc.local
		[ -f /sys/kernel/mm/redhat_transparent_hugepage/defrag ] && echo never > /sys/kernel/mm/redhat_transparent_hugepage/defrag
		[ -f /sys/kernel/mm/redhat_transparent_hugepage/enabled ] && echo never > /sys/kernel/mm/redhat_transparent_hugepage/enabled
		[ -f /sys/kernel/mm/transparent_hugepage/enabled ] && echo never > /sys/kernel/mm/transparent_hugepage/enabled
		[ -f /sys/kernel/mm/transparent_hugepage/defrag ] && echo never > /sys/kernel/mm/transparent_hugepage/defrag
		#cat >> /etc/rc.d/rc.local <<-EOF
			#[ -f /sys/kernel/mm/redhat_transparent_hugepage/defrag ] && echo never > /sys/kernel/mm/redhat_transparent_hugepage/defrag
			#[ -f /sys/kernel/mm/redhat_transparent_hugepage/enabled ] && echo never > /sys/kernel/mm/redhat_transparent_hugepage/enabled
			#[ -f /sys/kernel/mm/transparent_hugepage/enabled ] && echo never > /sys/kernel/mm/transparent_hugepage/enabled
			#[ -f /sys/kernel/mm/transparent_hugepage/defrag ] && echo never > /sys/kernel/mm/transparent_hugepage/defrag
		#EOF
		[ -z "$(grep transparent_hugepage /etc/default/grub 2>/dev/null)" ] && {
			echo 'GRUB_CMDLINE_LINUX_DEFAULT="transparent_hugepage=never"' >> /etc/default/grub
			grub2-mkconfig -o /boot/grub2/grub.cfg "$@"; }
		sed -i "s@^#plugin_dir.*@plugin-dir = $INSTALL_dir/lib/plugin@" /etc/my.cnf
		sed -i "s@^#plugin_load.*@plugin_load = ha_tokudb.so@" /etc/my.cnf
		[ -e /usr/local/lib/libjemalloc.so ] && {
		#sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${INSTALL_dir}/bin/mysqld_safe; }
			sed -ri "s@^#(\[mysqld_safe\])@\1@" /etc/my.cnf
			sed -ri "s@^#(malloc_lib =).*@\1 /usr/local/lib/libjemalloc.so@" /etc/my.cnf; }
	fi
}

mariadb_init() {
	cd ${INSTALL_dir}
	/bin/cp ${INSTALL_dir}/support-files/mysql.server /etc/init.d/mysqld
	sed -i "s@^basedir=.*@basedir=$INSTALL_dir@" /etc/init.d/mysqld
	sed -i "s@^datadir=.*@datadir=$DATA_dir@" /etc/init.d/mysqld
	${INSTALL_dir}/scripts/mysql_install_db --user=mysql --basedir=${INSTALL_dir} --datadir=${DATA_dir}
	echo "export PATH=${INSTALL_dir}/bin:\$PATH" > /etc/profile.d/mariadb.sh
	source /etc/profile.d/mariadb.sh
	curl -Lks onekey.sh/mysql_my.cnf >/etc/my.cnf && set_config
	curl -Lks onekey.sh/mysql_init.sql >/tmp/init.sql
	sed -i "s/lookback/$dbrootpwd/" /tmp/init.sql
	clear && service mysqld start && echo
	mysql -uroot -e "source /tmp/init.sql;"
}

mariadb_install() {
	downFile ${URL_mariadb}
	#mariadb-galera-${MARIADB_versiona}-${GLIBC_FLAG}-${OS_bit_3}
	tar xf ${URL_mariadb##*/} -C /usr/local/ && mariadbDir=${URL_mariadb##*/}
	[ -e ${INSTALL_dir} ] && mv ${INSTALL_dir} ${INSTALL_dir}_backup_$(date "+%F_%H%M%S")
	ln -sv  /usr/local/${mariadbDir%\.tar\.gz} ${INSTALL_dir}
	mariadb_init
}

mariadb_install_bulid() {
	downFile ${URL_mariadb_src}
	tar xf mariadb-galera-${MARIADB_versiona}.tar.gz
	cd mariadb-${MARIADB_versiona}
	yum install cmake ncurses-devel -y
	cmake . -DCMAKE_BUILD_TYPE=Release \
-DCMAKE_INSTALL_PREFIX=${INSTALL_dir} \
-DMYSQL_DATADIR=${DATA_dir} \
-DENABLED_PROFILING=OFF \
-DENABLE_DEBUG_SYNC=ON \
-DENABLE_GCOV=OFF \
-DINSTALL_LAYOUT=STANDALONE \
-DUSE_ARIA_FOR_TMP_TABLES=ON \
-DWITHOUT_SERVER=OFF \
-DWITH_FAST_MUTEXES=OFF \
-DWITH_FEEDBACK=OFF \
-DWITH_PIC=ON \
-DWITH_UNIT_TESTS=OFF \
-DWITH_VALGRIND=OFF \
-DWITH_SSL=system \
-DWITH_INNOBASE_STORAGE_ENGINE=ON \
-DWITH_ARCHIVE_STORAGE_ENGINE=ON \
-DWITH_BLACKHOLE_STORAGE_ENGINE=ON \
-DWITH_SPHINX_STORAGE_ENGINE=ON \
-DWITH_ARIA_STORAGE_ENGINE=ON \
-DWITH_XTRADB_STORAGE_ENGINE=ON \
-DWITH_PARTITION_STORAGE_ENGINE=ON \
-DWITH_FEDERATEDX_STORAGE_ENGINE=ON \
-DWITH_MYISAM_STORAGE_ENGINE=ON \
-DWITH_PERFSCHEMA_STORAGE_ENGINE=ON \
-DWITH_EXTRA_CHARSETS=all \
-DWITH_EMBEDDED_SERVER=ON \
-DWITH_READLINE=ON \
-DWITH_ZLIB=system \
-DWITH_LIBWRAP=0 \
-DEXTRA_CHARSETS=all \
-DENABLED_LOCAL_INFILE=ON \
-DINSTALL_UNIX_ADDRDIR=/tmp/mysql.sock \
-DDEFAULT_CHARSET=utf8 \
-UWITHOUT_OQGRAPH \
-DDEFAULT_COLLATION=utf8_general_ci \
-DWITH_WSREP=1 -DWITH_INNODB_DISALLOW_WRITES=1
	make -j `awk '/processor/{a++}END{print a}' /proc/cpuinfo` && make install && cd .. && rm -rf  mariadb-*
	mariadb_init
}

install_main() {
	color_info
	check_os
	root_password $@
	galera_install
	jemalloc_install
	[ -n "$(echo "$@" | awk '{for (i=1;i<=NF;i++)if ($i=="bulid"){print $i}}')" ] && mariadb_install_bulid || mariadb_install
}

install_main $@ | tee /tmp/mariadb_install.log
