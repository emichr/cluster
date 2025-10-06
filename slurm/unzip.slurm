#!/bin/bash

#SBATCH --partition=CPUQ
#SBATCH --time=00-00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --job-name="unzip"
#SBATCH --output=unzip-%A.out
#SBATCH --mem=8000

module purge

#Path to data to unzip
source="/cluster/work/$USER/*-$1/"

#Run unzip
/cluster/projects/itea_lille-nv-fys-tem/p7zip_16.02/bin/7z x "${source}"

scontrol show job ${SLURM_JOB_ID} -d
