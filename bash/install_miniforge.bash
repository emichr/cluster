#!/bin/bash

#Install miniforge
cd ~ #Navigate to home directory
mkdir miniforge #Create a new directory
cd ~/miniforge #Navigate into the new directory
curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh" #Download the latest miniforge installer
chmod 755 ~/miniforge/Miniforge3-$(uname)-$(uname -m).sh #Make installer executable
bash ~/miniforge/Miniforge3-$(uname)-$(uname -m).sh #Run the installer