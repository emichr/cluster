#!/bin/bash

#Export paths to common software

# 7z
echo "#TEM software" >> ~/.bashrc
echo export PATH=$PATH:/cluster/projects/itea_lille-nv-fys-tem/p7zip_16.02/bin >> ~/.bashrc

# Run the bashrc file
source ~/.bashrc