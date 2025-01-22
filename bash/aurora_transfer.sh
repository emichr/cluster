#!/bin/bash

# Usage
# To transfer a dataset from Aurora based on dataset number: $./aurora_transfer.sh -u <username> -n <datasetnumber>
# To transfer a dataset from Aurora based on dataset name: $./aurora_transfer.sh -u <username> -f "<datasetfilename>"
# Default destination of transferred files is "/cluster/work/<username>"
# To change destination add the -d flag: $./aurora_transfer.sh -u <username> -n <datasetnumber> -d <clusterdestination>

while getopts u:n:f:d: flag
do
    case "${flag}" in
        u) username=${OPTARG};;
        n) dataset=${OPTARG};;
        f) filename=${OPTARG};;
        d) destination=${OPTARG};;
    esac
done

echo "Username: ${username}"
echo "Dataset:  ${dataset}"
echo "Filename: ${filename}"
echo "Destination: ${destination}"

if [ -z "${filename}" ]
then
     aurorapath="/fagit/Aurora/view/access/user/${username}/*-${dataset}/"
else
     aurorapath="/fagit/Aurora/view/access/user/${username}/${filename}/"
fi

if [ -z "${destination}" ]
then
     clusterpath="/cluster/work/${USER}"
else
     clusterpath="${destination}"
fi

echo "Transferring data from ${aurorapath} to ${clusterpath}"

scp -r login.ansatt.ntnu.no:"'${aurorapath}'" ${clusterpath}

echo "Done"
