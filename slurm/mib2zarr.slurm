#!/bin/bash

#SBATCH --partition=CPUQ
#SBATCH --time=00-01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --job-name="mib2zarr"
#SBATCH --output=mib2zarr-%A.out
#SBATCH --mem=64000

module purge
source /cluster/projects/itea_lille-nv-fys-tem/miniforge3/bin/activate pyxem0.19.0

source="/cluster/work/emilc/*-$1/"
python ../python/mib2zarr.py "${source}" -o -vvv --zzip --vbf --stackmax

scontrol show job ${SLURM_JOB_ID} -d