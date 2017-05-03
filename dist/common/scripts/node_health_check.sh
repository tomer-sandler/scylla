#!/bin/bash
#
#  Copyright (C) 2017 ScyllaDB

##Variables##
REPORT="./`hostname -i`-health-check-report.txt"
OUTPUT_PATH="./output_files"
OUTPUT_PATH1="$OUTPUT_PATH/system_checks"
OUTPUT_PATH2="$OUTPUT_PATH/scylladb_checks"
OUTPUT_PATH3="$OUTPUT_PATH/nodetool_commands"
OUTPUT_PATH4="$OUTPUT_PATH/data_model"
OUTPUT_PATH5="$OUTPUT_PATH/network_checks"
IS_FEDORA="0"
IS_DEBIAN="0"
JMX_PORT="7199"
CQL_PORT="9042"
PRINT_DM=NO
PRINT_NET=NO
PRINT_cfstats=NO
SCYLLA_SERVICE="0"
JMX_SERVICE="0"

while getopts ":hdncap:q:" opt; do
    case $opt in
        h)    echo ""
            echo "This script performs system review and generates health check report based on"
            echo "the configuration data (hardware, OS, Scylla SW, etc.) collected from the node."
            echo ""
            echo "Usage:"
            echo "-p   Port to use for nodetool commands (default: 7199)"
            echo "-q   Port to use for cqlsh (default: 9042)"
            echo "-c   Print cfstats output"
            echo "-d   Print data model info"
            echo "-n   Print network info"
            echo "-a   Print all"
            echo "-h   Display this help and exit"
            echo ""
            echo "Note: output for the above is collected, but not printed in the report."
            echo "If you wish to have them printed, please supply the relevant flag/s."
            echo ""
            exit 2
            ;;
        p)    JMX_PORT=$OPTARG ;;
        q)    CQL_PORT=$OPTARG ;;
        d)    PRINT_DM=YES ;;
        n)    PRINT_NET=YES ;;
        c)    PRINT_cfstats=YES ;;
        a)    PRINT_DM=YES
            PRINT_NET=YES
            PRINT_cfstats=YES
            ;;
        \?)    echo "Invalid option: -$OPTARG"
            exit 2
            ;;
        :)    echo "Option -$OPTARG requires an argument."
            exit 2
            ;;
    esac
done


##Check if server is Fedora/Debian release##
cat /etc/os-release | grep fedora &> /dev/null
if [ $? -ne 0 ]; then
    IS_FEDORA="1"
fi

cat /etc/os-release | grep debian &> /dev/null
if [ $? -ne 0 ]; then
    IS_DEBIAN="1"
fi

if [ "$IS_FEDORA" == "1" ] && [ "$IS_DEBIAN" == "1" ]; then
    echo "This s a Non-Supported OS, Please Review the Support Matrix"
    exit 222
fi

##Pass criteria for script execution##
#Check scylla service#
echo "--------------------------------------------------"
echo "Checking Scylla Service"
echo "--------------------------------------------------"

ps -C scylla --no-headers &> /dev/null
if [ $? -ne 0 ]; then
    SCYLLA_SERVICE="1"
    echo "ERROR: Scylla is NOT Running"
    echo "Cannot Collect Data Model Info"
    echo "--------------------------------------------------"
else
    echo "Scylla Service: OK"
    echo "--------------------------------------------------"
fi 


#Check Scylla-JMX service#
echo "Checking Scylla-JMX Service on Port $JMX_PORT"
echo "--------------------------------------------------"

nodetool -p$JMX_PORT status &> /dev/null
if [ $? -ne 0 ]; then
    JMX_SERVICE="1"
    echo "ERROR: Scylla-JMX is NOT Running / NOT Listening on Port $JMX_PORT"
    echo "Cannot Collect Nodetool Info"
    echo "Use the '-p' Option to Provide the Scylla-JMX Port"
    echo "--------------------------------------------------"
else
    echo "JMX Service (nodetool): OK"
    echo "--------------------------------------------------"
fi 


#Install 'net-tools' pkg, to be used for netstat command#
echo "Installing 'net-tools' Package (for 'netstat' command)"
echo "--------------------------------------------------"

if [ "$IS_FEDORA" == "0" ]; then
    sudo yum install net-tools -y -q
fi

if [ "$IS_DEBIAN" == "0" ]; then
#    sudo apt-get update -qq
    sudo apt-get install net-tools -y | grep already
fi


#Create dir structure to save output_files#
echo "--------------------------------------------------"
echo "Creating Output Files Directory"
echo "--------------------------------------------------"
mkdir -p $OUTPUT_PATH
mkdir -p $OUTPUT_PATH1 $OUTPUT_PATH2 $OUTPUT_PATH3 $OUTPUT_PATH4 $OUTPUT_PATH5


##Output Collection##
#System Checks#
echo "Collecting System Info"
echo "--------------------------------------------------"
cat /etc/os-release > $OUTPUT_PATH1/os-release.txt
uname -r > $OUTPUT_PATH1/kernel-release.txt
lscpu > $OUTPUT_PATH1/cpu-info.txt
vmstat -s -S M | awk '{$1=$1};1' > $OUTPUT_PATH1/vmstat.txt
df -Th > $OUTPUT_PATH1/capacity-info.txt && echo "" >> $OUTPUT_PATH1/capacity-info.txt && sudo du -sh /var/lib/scylla/* >> $OUTPUT_PATH1/capacity-info.txt
cat /proc/mdstat > $OUTPUT_PATH1/raid-conf.txt
for f in `sudo find /sys -name scheduler`; do echo -n "$f: "; cat  $f; done > $OUTPUT_PATH1/io-sched-conf.txt && echo "" >> $OUTPUT_PATH1/io-sched-conf.txt
for f in `sudo find /sys -name nomerges`; do echo -n "$f: "; cat  $f; done >> $OUTPUT_PATH1/io-sched-conf.txt


#ScyllaDB Checks#
echo "Collecting Scylla Info"
echo "--------------------------------------------------"

if [ "$IS_FEDORA" == "0" ]; then
    rpm -qa | grep -i scylla > $OUTPUT_PATH2/scylla-pkgs.txt
fi

if [ "$IS_DEBIAN" == "0" ]; then
    dpkg -l | grep -i scylla > $OUTPUT_PATH2/scylla-pkgs.txt
fi

curl -s -X GET "http://localhost:10000/storage_service/scylla_release_version" > $OUTPUT_PATH2/scylla-version.txt && echo "" >> $OUTPUT_PATH2/scylla-version.txt
cat /etc/scylla/scylla.yaml | grep -v "#" | grep -v "^[[:space:]]*$" > $OUTPUT_PATH2/scylla-yaml.txt

if [ "$IS_FEDORA" == "0" ]; then
    cat /etc/sysconfig/scylla-server | grep -v "^[[:space:]]*$" > $OUTPUT_PATH2/scylla-server.txt
fi

if [ "$IS_DEBIAN" == "0" ]; then
    cat /etc/default/scylla-server | grep -v "^[[:space:]]*$" > $OUTPUT_PATH2/scylla-server.txt
fi

cat /etc/scylla/cassandra-rackdc.properties | grep -v "#" |grep -v "^[[:space:]]*$" > $OUTPUT_PATH2/multi-DC.txt
ls -ltrh /var/lib/scylla/coredump/ > $OUTPUT_PATH2/coredump-folder.txt


#Scylla Logs#
echo "Collecting Logs"
echo "--------------------------------------------------"

journalctl --help &> /dev/null
if [ $? -eq 0 ]; then
    journalctl -t scylla > $OUTPUT_PATH/scylla-logs.txt
else
    cat /var/log/syslog | grep -i scylla > $OUTPUT_PATH/scylla-logs.txt
fi

gzip -f $OUTPUT_PATH/scylla-logs.txt


#Nodetool commands#
if [ "$JMX_SERVICE" == "1" ]; then
    echo "Skipping Nodetool Info Collection"
    echo "--------------------------------------------------"
else
    echo "Collecting Nodetool Commands Info (using port $JMX_PORT)"
    echo "--------------------------------------------------"
    nodetool -p$JMX_PORT status > $OUTPUT_PATH3/nodetool-status.txt
    nodetool -p$JMX_PORT info > $OUTPUT_PATH3/nodetool-info.txt
    nodetool -p$JMX_PORT netstats > $OUTPUT_PATH3/nodetool-netstats.txt
    nodetool -p$JMX_PORT gossipinfo > $OUTPUT_PATH3/nodetool-gossipinfo.txt
    nodetool -p$JMX_PORT proxyhistograms > $OUTPUT_PATH3/nodetool-proxyhistograms.txt
    nodetool -p$JMX_PORT cfstats -H | grep Keyspace -A 4 > $OUTPUT_PATH3/nodetool-cfstats-keyspace.txt
    nodetool -p$JMX_PORT cfstats -H | egrep 'Table:|SSTable count:|Compacted|tombstones' | awk '{$1=$1};1' | awk '{print; if (FNR % 7 == 0 ) printf "\n --";}' > $OUTPUT_PATH3/nodetool-cfstats-table.txt
    sed -i '1s/^/ --/' $OUTPUT_PATH3/nodetool-cfstats-table.txt
    nodetool -p$JMX_PORT compactionstats > $OUTPUT_PATH3/nodetool-compactionstats.txt
    nodetool -p$JMX_PORT ring > $OUTPUT_PATH3/nodetool-ring.txt
fi
#not implemented: nodetool cfhistograms $KS $TN >> $OUTPUT_PATH3/nodetool-cfhistograms.txt#


#Data Model#
if [ "$SCYLLA_SERVICE" == "1" ]; then
    echo "Skipping Data Model Info Collection"
    echo "--------------------------------------------------"
else
    cqlsh `hostname -i` $CQL_PORT -e "HELP" &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Collecting Data Model Info (using port $CQL_PORT)"
        echo "--------------------------------------------------"
        cqlsh `hostname -i` $CQL_PORT -e "DESCRIBE SCHEMA" > $OUTPUT_PATH4/describe-schema.txt
        cqlsh `hostname -i` $CQL_PORT -e "DESCRIBE TABLES" > $OUTPUT_PATH4/describe-tables.txt
    else
        echo "ERROR: CQL is NOT Listening on Port $CQL_PORT"
        echo "Cannot Collect Data Model Info"
        echo "Use the '-q' Option to Provide the CQL Port"
        echo "--------------------------------------------------"
    fi
fi


#Network Checks#
echo "Collecting Network Info"
echo "--------------------------------------------------"
ifconfig -a >> $OUTPUT_PATH5/ifconfig.txt
for i in `ls -I lo /sys/class/net/`; do echo "--$i"; ethtool -i $i; echo ""; done > $OUTPUT_PATH5/ethtool-NIC.txt
cat /proc/interrupts > $OUTPUT_PATH5/proc-interrupts.txt
for i in `ls -I default_smp_affinity /proc/irq`; do echo -n "--$i:"; sudo cat /proc/irq/$i/smp_affinity; echo ""; done > $OUTPUT_PATH5/irq-smp-affinity.txt
for i in `ls -I lo /sys/class/net/`; do echo "--$i"; cat /sys/class/net/$i/queues/rx-*/rps_cpus; echo ""; done > $OUTPUT_PATH5/rps-conf.txt
for i in `ls -I lo /sys/class/net/`; do echo "--$i"; cat /sys/class/net/$i/queues/tx-*/xps_cpus; echo ""; done > $OUTPUT_PATH5/xps-conf.txt
for i in `ls -I lo /sys/class/net/`; do echo "--$i"; cat /sys/class/net/$i/queues/rx-*/rps_flow_cnt; echo ""; done > $OUTPUT_PATH5/rfs-conf.txt
ps -elf | grep irqbalance > $OUTPUT_PATH5/irqbalance-conf.txt
sudo sysctl -a > $OUTPUT_PATH5/sysctl.txt 2>&1
sudo iptables -L > $OUTPUT_PATH5/iptables.txt
netstat -an | grep tcp > $OUTPUT_PATH5/netstat-tcp.txt


echo "Output Collection Completed Successfully"
echo "--------------------------------------------------"


##Generate Health Check Report##
echo "Generating Health Check Report"
echo "--------------------------------------------------"
echo "Print cfstats: $PRINT_cfstats"
echo "Print Data Model: $PRINT_DM"
echo "Print Network Info: $PRINT_NET"
echo "--------------------------------------------------"

echo "" > $REPORT
date "+DATE: %m/%d/%y" >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT
echo "              Health Check Report for node: `hostname -i`" >> $REPORT 
echo "" >> $REPORT
echo "" >> $REPORT


echo "PURPOSE" >> $REPORT
echo "=======" >> $REPORT
echo "This document first serves as a system review and health check report." >> $REPORT
echo "It is based on the configuration data (hardware, OS, Scylla SW, etc.) collected from the node." >> $REPORT
echo "Based on the review and analysis of the collected data, ScyllaDB can recommend on possible" >> $REPORT
echo "ways to better utilize the cluster, based on both experiance and best practices." >> $REPORT
echo "" >> $REPORT
echo "Please make sure you review and sign-off the 'MANUAL CHECK LIST' section at the end of the report." >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT


echo "SYSTEM INFO" >> $REPORT
echo "===========" >> $REPORT
echo "" >> $REPORT

echo "Host Operating System" >> $REPORT
echo "---------------------" >> $REPORT
cat $OUTPUT_PATH1/os-release.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "Kernel Release" >> $REPORT
echo "--------------" >> $REPORT
cat $OUTPUT_PATH1/kernel-release.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "CPU Info" >> $REPORT
echo "--------" >> $REPORT
cat $OUTPUT_PATH1/cpu-info.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "Memory Info in MB" >> $REPORT
echo "-----------------" >> $REPORT
cat $OUTPUT_PATH1/vmstat.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "Storage/Disk Info" >> $REPORT
echo "-----------------" >> $REPORT
cat $OUTPUT_PATH1/capacity-info.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "RAID Configuration" >> $REPORT
echo "------------------" >> $REPORT
cat $OUTPUT_PATH1/raid-conf.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "I/O Scheduler Configuration" >> $REPORT
echo "---------------------------" >> $REPORT
cat $OUTPUT_PATH1/io-sched-conf.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT


echo "ScyllaDB INFO" >> $REPORT
echo "=============" >> $REPORT
echo "" >> $REPORT

echo "SW Version (PKGs)" >> $REPORT
echo "-----------------" >> $REPORT
cat $OUTPUT_PATH2/scylla-version.txt >> $REPORT
echo "" >> $REPORT
cat $OUTPUT_PATH2/scylla-pkgs.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "Configuration files" >> $REPORT
echo "-------------------" >> $REPORT
echo "## /etc/scylla/scylla.yaml ##" >> $REPORT
cat $OUTPUT_PATH2/scylla-yaml.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

if [ "$IS_FEDORA" == "0" ]; then
    echo "## /etc/sysconfig/scylla-server ##" >> $REPORT
fi

if [ "$IS_DEBIAN" == "0" ]; then
    echo "## /etc/default/scylla-server ##" >> $REPORT
fi

cat $OUTPUT_PATH2/scylla-server.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT
echo "## /etc/scylla/cassandra-rackdc.properties ##" >> $REPORT
cat $OUTPUT_PATH2/multi-DC.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

echo "Check for Coredumps" >> $REPORT
echo "-------------------" >> $REPORT
cat $OUTPUT_PATH2/coredump-folder.txt >> $REPORT
echo "" >> $REPORT
echo "" >> $REPORT

if [ "$JMX_SERVICE" == "0" ]; then
    echo "Nodetool Status/Info/Gossip" >> $REPORT
    echo "---------------------------" >> $REPORT
    echo "## Nodetool Status ##" >> $REPORT
    cat $OUTPUT_PATH3/nodetool-status.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "## Nodetool Info ##" >> $REPORT
    cat $OUTPUT_PATH3/nodetool-info.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "## Nodetool GossipInfo ##" >> $REPORT
    cat $OUTPUT_PATH3/nodetool-gossipinfo.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
fi

if [ $PRINT_DM == "YES" ]; then
    echo "DATA MODEL INFO" >> $REPORT
    echo "===============" >> $REPORT
    echo "" >> $REPORT

    cqlsh `hostname -i` $CQL_PORT -e "HELP" &> /dev/null
    if [ $? -eq 0 ]; then
        echo "Printing Data Model Info to Report"
        echo "--------------------------------------------------"

        echo "Describe Schema" >> $REPORT
        echo "---------------" >> $REPORT
        cat $OUTPUT_PATH4/describe-schema.txt >> $REPORT
        echo "" >> $REPORT

        echo "Describe Tables" >> $REPORT
        echo "---------------" >> $REPORT
        cat $OUTPUT_PATH4/describe-tables.txt >> $REPORT
        echo "" >> $REPORT
        echo "" >> $REPORT
    else
        echo "ERROR: Data Model NOT Collected - Nothing to Print"
        echo "--------------------------------------------------"
        echo "Data Model was not collected" >> $REPORT
        echo "" >> $REPORT
        echo "" >> $REPORT
        echo "" >> $REPORT
    fi
fi

echo "PERFORMANCE and METRICS INFO" >> $REPORT
echo "============================" >> $REPORT
echo "" >> $REPORT

if [ "$JMX_SERVICE" == "0" ]; then
    echo "Nodetool Proxyhistograms (RD/WR latency)" >> $REPORT
    echo "----------------------------------------" >> $REPORT
    cat $OUTPUT_PATH3/nodetool-proxyhistograms.txt >> $REPORT
    echo "" >> $REPORT

    echo "Nodetool netstats" >> $REPORT
    echo "-----------------" >> $REPORT
    cat $OUTPUT_PATH3/nodetool-netstats.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT

    if [ $PRINT_cfstats == "YES" ]; then
        echo "Printing cfstats Output to Report"
        echo "--------------------------------------------------"

        echo "Nodetool cfstats" >> $REPORT
        echo "----------------" >> $REPORT
        echo "## Keyspace Info ##" >> $REPORT
        cat $OUTPUT_PATH3/nodetool-cfstats-keyspace.txt >> $REPORT
        echo "" >> $REPORT
        echo "" >> $REPORT
        echo "## Tables Info ##" >> $REPORT
        cat $OUTPUT_PATH3/nodetool-cfstats-table.txt >> $REPORT
        echo "" >> $REPORT
        echo "" >> $REPORT
    fi

    echo "Nodetool compactionstats" >> $REPORT
    echo "------------------------" >> $REPORT
    cat $OUTPUT_PATH3/nodetool-compactionstats.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
else
    echo "Nodetool info was not collected" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
fi

if [ $PRINT_NET == "YES" ]; then
    echo "Printing Network Info to Report"
    echo "--------------------------------------------------"

    echo "NETWORK INFO" >> $REPORT
    echo "============" >> $REPORT
    echo "" >> $REPORT

    echo "ethtool per NIC" >> $REPORT
    echo "---------------" >> $REPORT
    cat $OUTPUT_PATH5/ethtool-NIC.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    
    echo "/proc/interrupts" >> $REPORT
    echo "----------------" >> $REPORT
    cat $OUTPUT_PATH5/proc-interrupts.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT

    echo "IRQ smp affinity" >> $REPORT
    echo "----------------" >> $REPORT
    cat $OUTPUT_PATH5/irq-smp-affinity.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT

    echo "sysctl -a" >> $REPORT
    echo "---------" >> $REPORT
    cat $OUTPUT_PATH5/sysctl.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT

    echo "iptables -L" >> $REPORT
    echo "-----------" >> $REPORT
    cat $OUTPUT_PATH5/iptables.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT

    echo "netstat -an | grep tcp" >> $REPORT
    echo "----------------------" >> $REPORT
    cat $OUTPUT_PATH5/netstat-tcp.txt >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
    echo "" >> $REPORT
fi

echo "Archiving Output Files"
echo "--------------------------------------------------"
tar cvzf output_files.tgz $OUTPUT_PATH --remove-files
echo "--------------------------------------------------"

echo "Health Check Report Created Successfully"
echo "Path to Report: $REPORT"
echo "--------------------------------------------------"

