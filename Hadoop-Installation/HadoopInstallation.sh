#!/bin/bash

JDK_NAME='jdk-8u121-linux-x64.tar.gz'
JDK_URL='http://10.150.141.137:9000/${JDK_NAME}'

HADOOP_NAME='hadoop-3.3.0.tar.gz'
HADOOP_URL='http://10.150.141.137:9000/${HADOOP_NAME}'


install_wget(){
    echo 'Begin to prepare the environment....'
    wget
    if [ $? -ne 1 ]; then
        echo 'Begin to install wget...'
        yum -y install wget
    fi
}


install_jdk(){
    java
    if [ $? -ne 0 ]; then
        echo 'Begin to download JDK8.......'
        wget JDK_URL
        mkdir -p /usr/local/java
        tar -zxvf $JDK_NAME /usr/local/java
}

path_jdk(){
    grep -q "export PATH=" /etc/profile
    if [ $? -ne 0 ]; then
        # last line
        echo 'export PATH=$PATH:$JAVA_HOME/bin'>>/etc/profile
    else
        # end of the last line
        sed -i '/^export PATH=.*/s/$/:\$JAVA_HOME\/bin/' /etc/profile
    fi
    
    grep -q "export JAVA_HOME=" /etc/profile
    if [ $? -ne 0 ]; then
        # import configuration
        sed -i "/^export PATH=.*/i\export JAVA_HOME=/usr/local/java" /etc/profile
        sed -i '/^export PATH=.*/i\export JRE_HOME=$JAVA_HOME/jre' /etc/profile
        sed -i '/^export PATH=.*/i\export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar' /etc/profile
    fi
    source /etc/profile
}

wgetHadoop(){
    ls /usr/local | grep 'hadoop.*[gz]$'
    if [ $? -ne 0 ]; then
        echo '开始下载hadoop安装包...'
        wget $HADOOPLINK
        mv $(ls | grep 'hadoop.*gz$') /usr/local
    fi
    tar -zxvf /usr/local/$(ls | grep 'hadoop.*[gz]$')
    mv /usr/local/$(ls | grep 'hadoop.*[^gz]$') /usr/local/hadoop
}

path_hadoop(){
    echo HADOOP_HOME=/usr/local/hadoop >> /etc/profile
    echo HADOOP_INSTALL=$HADOOP_HOME >> /etc/profile
    echo HADOOP_MAPRED_HOME=$HADOOP_HOME >> /etc/profile
    echo HADOOP_COMMON_HOME=$HADOOP_HOME >> /etc/profile
    echo HADOOP_HDFS_HOME=$HADOOP_HOME >> /etc/profile
    echo YARN_HOME=$HADOOP_HOME >> /etc/profile
    echo HADOOP_COMMON_LIB_NATIVE_DIR=$HADOOP_HOME/lib/native >> /etc/profile
    echo HADOOP_OPTS="-Djava.library.path=$HADOOP_HOME/lib/native" >> /etc/profile
    echo PATH=$PATH:$HADOOP_HOME/sbin:$HADOOP_HOME/bin >> /etc/profile
}

add_hadoop_user(){
    adduser hdoop
    usermod -aG sudo hdoop
    sudo chown -R -v "hdoop" "/usr/local/hadoop"
    su - hdoop
}

install_hadoop_single_node(){
    install_hadoop
    path_hadoop
    add_hadoop_user
}

install_java(){
    echo 'check java environment'
    java -version
    if [ $? -ne 0 ]; then
        echo 'Beging to install jdk......'
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
#2 Single Node Hadoop
install_hadoop_with_full_mode(){
    install_java
    echo 'installing hadoop...'
    hadoop
    if [ $? -ne 0 ]; then
        #install_hadoop_single_node
        hadoop
        if [ $? -eq 0 ]; then
            echo 'hadoop installation completed!'
        else
            echo 'hadoop installation failed!'
        fi
    else
        echo 'hadoop already installed!'
    fi
}
#3 Pesudo Hadoop
install_hadoop_with_pesudo_mode(){
    echo 'install_hadoop_with_pesudo_mode'
    install_hadoop_with_full_mode
}

consoleInput(){
    echo 'please input [1-4]'
    echo '1: Hadoop - Full  Mode'
    echo '2: Hadoop - Pesudo Mode'
    echo '3: hadoop initialization'
    echo '4: Set SSH without password
    echo 'Option[1-4]'
    read aNum
    case $aNum in
        1)  install_hadoop_with_full_mode
        ;;
        2)  install_hadoop_with_pesudo_mode
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