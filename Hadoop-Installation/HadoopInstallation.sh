#!/bin/bash

JDK_DIR="jdk1.8.0_121"
JDK_NAME='jdk-8u121-linux-x64'
JDK_URL='http://10.150.141.137:9000/'$JDK_NAME'.tar.gz'

HADOOP_NAME='hadoop-3.3.0'
HADOOP_URL='http://10.150.141.137:9000/'$HADOOP_NAME'.tar.gz'

MASTER_IP="0.0.0.0"
WORKER_IP_ARRAY=()

install_jdk(){
    echo 'Begin to download JDK8.......'
    JDK_PACKAGE=$(ls | grep 'jdk.*[gz]$' | head -1)
    if [ -z "$JDK_PACKAGE" ]; then
      wget $JDK_URL
    fi
    echo "Begin to uncompress jdk:$JDK_PACKAGE"
    tar -C /usr/local -zxvf "$JDK_PACKAGE"
    mkdir -p /usr/local/java/
    mv /usr/local/$JDK_DIR/* /usr/local/java/
}

path_jdk(){
    grep -q "export PATH=" /etc/profile
    if [ $? -ne 0 ]; then
        # last line
        echo "export PATH=$PATH:$JAVA_HOME/bin">>/etc/profile
    else
        # end of the last line
        sed -i "/^export PATH=.*/s/$/:\$JAVA_HOME\/bin/" /etc/profile
    fi
    
    grep -q "export JAVA_HOME=" /etc/profile
    if [ $? -ne 0 ]; then
        # import configuration
        sed -i "/^export PATH=.*/i\export JAVA_HOME=/usr/local/java" /etc/profile
        sed -i "/^export PATH=.*/i\export JRE_HOME=$JAVA_HOME/jre" /etc/profile
        sed -i "/^export PATH=.*/i\export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar" /etc/profile
    fi
    source /etc/profile
}

install_java(){
    echo 'check java environment'
    java -version
    if [ $? -ne 0 ]; then
        echo 'Begin to install jdk......'
        install_jdk
        path_jdk
        java -version
        if [ $? -eq 0 ]; then
            echo 'JDK8 installation completed!'
        else
            echo 'JDK8 installation failed!'
        fi
    else
        echo 'JDK already installed!'
    fi
}

install_hadoop(){
    HADOOP_PACKAGE=$(ls | grep 'hadoop.*[gz]$' | head -1)
    if [ -z "$HADOOP_PACKAGE" ]; then
      wget $HADOOP_URL
    fi
    tar -C /usr/local -zxvf "$HADOOP_PACKAGE"
    mkdir -p /usr/local/hadoop
    mv /usr/local/$HADOOP_NAME /usr/local/hadoop
}

# shellcheck disable=SC2129
path_hadoop(){
    echo "export HADOOP_HOME=/usr/local/hadoop" >> /etc/profile
    echo "export HADOOP_INSTALL=$HADOOP_HOME" >> /etc/profile
    echo "export HADOOP_MAPRED_HOME=$HADOOP_HOME" >> /etc/profile
    echo "export HADOOP_COMMON_HOME=$HADOOP_HOME" >> /etc/profile
    echo "export HADOOP_HDFS_HOME=$HADOOP_HOME" >> /etc/profile
    echo "export YARN_HOME=$HADOOP_HOME" >> /etc/profile
    echo "export HADOOP_COMMON_LIB_NATIVE_DIR=$HADOOP_HOME/lib/native" >> /etc/profile
    echo "export HADOOP_OPTS=-Djava.library.path=$HADOOP_HOME/lib/native" >> /etc/profile
    # end of the last line
    sed -i "/^export PATH=.*/s/$/:\$HADOOP_HOME\/bin/" /etc/profile
    sed -i "/^export PATH=.*/s/$/:\$HADOOP_HOME\/sbin/" /etc/profile
    source /etc/profile
}

prepare_config_file(){
  cp -rf configs/* "$HADOOP_HOME"/etc/hadoop
}

add_hadoop_user(){
    adduser hdoop
    usermod -aG sudo hdoop
    sudo chown -R -v "hdoop" "/usr/local/hadoop"
    su - hdoop
    mkdir -p "$HADOOP_HOME/dfs/name"
    mkdir -p "$HADOOP_HOME/dfs/data"
    mkdir -p "$HADOOP_HOME/tmp"
}

check_IPAddr(){
    echo "$1" | grep "^[0-9]\{1,3\}\.\([0-9]\{1,3\}\.\)\{2\}[0-9]\{1,3\}$" > /dev/null;
    if [ $? -ne 0 ]
    then
        echo "not x.x.x.x"
        return 1
    fi
    ipaddr=$1
    a=$(echo "$ipaddr"|awk -F . '{print $1}')  #split with "."
    b=$(echo "$ipaddr"|awk -F . '{print $2}')
    c=$(echo "$ipaddr"|awk -F . '{print $3}')
    d=$(echo "$ipaddr"|awk -F . '{print $4}')
    for num in $a $b $c $d
    do
        if [ "$num" -gt 255 ] || [ "$num" -lt 0 ]    # num among 0-255
        then
            return 1
        fi
    done
        return 0
}

input_MasterIP(){
  read -r -p "Please input master IP(default:0.0.0.0)>" master_ip
  check_IPAddr "$master_ip"
  if [ $? -eq 0 ]; then
      MASTER_IP=$master_ip
  else
      echo "Invalid master ip[$master_ip], please re-input...."
      input_MasterIP
  fi
  echo "master ip:$MASTER_IP"
}

input_WorkerIPs(){
  index_ip="$1"
  while read -p "input [$index_ip]th worker IP:" worker_ip
  do
    if [ "$worker_ip" == "0" ]; then
          return 0
    fi
    check_IPAddr "$worker_ip"
    if [ $? -eq 0 ]; then
      WORKER_IP_ARRAY[$index_ip]=$worker_ip
    else
      echo "Invalid worker ip[$worker_ip], please re-input...."
      input_WorkerIPs "$index_ip"
      if [ $? -eq 0 ]; then
        return 0
      fi
    fi
    ((index_ip++))
  done
  return 0
}

prepare_master_node(){
  input_MasterIP
  input_WorkerIPs 0
  # Modify etc/hosts
  # master
  # 0.0.0.0 master
  echo "$MASTER_IP master" >> /etc/hosts
  # workers
  index_worker=0
  for worker_ip in "${WORKER_IP_ARRAY[@]}"
  do
     ((index_worker++))
     echo "$worker_ip worker$index_worker" >> /etc/hosts
     echo "worker$index_worker" >> "$HADOOP_HOME/etc/hadoop/workers"
     # or do whatever with individual element of the array
  done

  # modify hdfs-site.xml
  key_replication=dfs.replication
  value_replication="$index_worker"
  sed -i "/>$key_replication</{n;s#.*#       <value>$value_replication</value>#}" configs/hdfs-site.xml
}

prepare_worker_node(){
  input_MasterIP
  # Modify etc/hosts
  # master
  # 0.0.0.0 master
  echo "$MASTER_IP master" >> /etc/hosts

  # modify hdfs-site.xml
  read -r -p "Please input dfs.replication>" dfs_replication
  key_replication=dfs.replication
  value_replication="$dfs_replication"
  sed -i "/>$key_replication</{n;s#.*#       <value>$value_replication</value>#}" configs/hdfs-site.xml
}

install_hadoop_in_single_node(){
  echo 'install_hadoop_in_single_mode...'
  install_java
  echo 'Check hadoop...'
  which hadoop
  if [ $? -ne 0 ]; then
    echo 'installing hadoop...'
    install_hadoop
    path_hadoop
    prepare_config_file
    which hadoop
    if [ $? -eq 0 ]; then
      add_hadoop_user
      echo 'hadoop installation completed!'
    else
      echo 'hadoop installation failed!'
    fi
  else
    echo 'hadoop already installed!'
  fi
}


#2 Master Node Hadoop
install_hadoop_in_master_node(){
    echo 'install_hadoop_in_master_mode...'
    prepare_master_node
    install_hadoop_in_single_node
}
#3 Worker Node Hadoop
install_hadoop_in_worker_node(){
    echo 'install_hadoop_in_worker_mode...'
    prepare_worker_node
    install_hadoop_in_single_node
}

consoleInput(){
    echo 'please input [1-4]'
    echo '1: Hadoop - Master Node'
    echo '2: Hadoop - Worker Node'
    echo '3: hadoop initialization'
    echo '4: Set SSH without password'
    echo 'Option[1-4]'
    read aNum
    case $aNum in
        1)  install_hadoop_in_master_node
        ;;
        2)  install_hadoop_in_worker_node
        ;;
        3)  initialize_hfds
            echo 'Hadoop initialization...'
            hdfs namenode -format
        ;;
        *)  echo 'No such option, please input Ctrl+C'
            consoleInput
        ;;
    esac
}
echo 'Executing the script with root permission'
echo '----------------------------------------------------'
consoleInput