#!/bin/bash

#Set aliases
#Shortcut to TEM group shared directory
echo "alias temproject='cd ~/../../projects/itea_lille-nv-fys-tem/'" >> ~/.bashrc

#Shortcut to your work directory
echo "alias work='cd ~/../../work/${USER}'" >> ~/.bashrc

#Shortcut to logging in to AURORA. Alias will only work for employees at NTNU.
echo "alias aurora='ssh login.ansatt.ntnu.no;cd /fagit/Aurora/view/access/user/${USER}'" >> ~/.bashrc

#Shortcut to list your own jobs in the workload manager
echo "alias sq='squeue -u ${USER}'" >> ~/.bashrc

#Shortcut to list all files in a long list
echo "alias l='ls -la'" >> ~/.bashrc

#Shortcut to list all files in a compact list
echo "alias s='ls -a'" >> ~/.bashrc

#Shortcut to list all .out files in PWD
echo "alias lout='ls -la *.out'" >> ~/.bashrc

#Shortcut to remove all .out files in PWD
echo "alias rmout='rm *.out'" >> ~/.bashrc

#Shortcut to activate pyxem0.19.1 environment
echo "alias pxm='source /cluster/projects/itea_lille-nv-fys-tem/miniforge3/bin/activate pyxem0.19.1'" >> ~/.bashrc

#Shortcut to activate latest encironment
echo "alias latest='source /cluster/projects/itea_lille-nv-fys-tem/miniforge3/bin/activate latest'" >>~/.bashrc

#Shortcut to activate the miniforge base environment
echo "alias miniforge='source /cluster/projects/itea_lille-nv-fys-tem/miniforge3/bin/activate'" >> ~/.bashrc