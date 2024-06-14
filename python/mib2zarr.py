#!/usr/bin/env python

# -*- coding: utf-8 -*-
"""
Convert MIB raw data to zarr format
@author: Emil Frang Christiansen (emil.christiansen@ntnu.no)
Created 2024-06-14

Notes:
If converting to a zipped zspy file, 7z must be installed.

Requirements:
 - hyperspy>=2.0.0
 - os
 - sys
 - logging
 - subprocess
 - argparse
 - pathlib
"""

import os
import sys
import logging
import subprocess
from typing import Optional

# Create formatter
format_string = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
formatter = logging.Formatter(format_string)

# Set up initial logging
logging.basicConfig(format=format_string, level=logging.ERROR)
logging.captureWarnings(True)

# Create custom logger
logger = logging.getLogger(__file__)
logger.propagate = False

# Create handler
ch = logging.StreamHandler(sys.stdout)
ch.setLevel(logging.INFO)
logger.setLevel(ch.level)

# Add formatter to handler
ch.setFormatter(formatter)

# Add handler to logger
logger.addHandler(ch)

logger.info(f'This is {__file__} working from {os.getcwd()}:\n{__doc__}')

import hyperspy.api as hs
import argparse
from pathlib import Path
import json

_SUPPORTED_FILES = (
    '.dm3',
    '.dm4',
    '.png',
    '.jpg',
    '.mib'
)
_MAX_AUX_FILESIZE = 0  # 5  #MB


def get_metadata_from_json(path):
    """
    Get metadata from a json file

    :param path: The path to the json file
    :type path: Path
    :return: The metadata parameters
    :rtype: dict
    """
    if path.is_file() and path.exists():
        try:
            parameters = json.load(path.open('r'))
        except FileNotFoundError as e:
            logger.debug(
                'Could not get parameters metadata from json file. You will need to set metadata yourself later on.')
        else:
            logger.debug(f"Loaded metadata from json file {path}:\n{parameters}")
            return parameters
    return {}


def set_experimental_parameters(signal, **kwargs):
    """
    Set experimental parameters of a signal

    Helper function to avoid passing kwargs not accepted by `signal.set_experimental_parameters`

    :param signal: The signal to set the metadata for
    :param kwargs: Optional keyword arguments passed on to `signal.set_experimental_parameters()`
    :return:
    """
    signal.set_experimental_parameters(beam_energy=kwargs.get('beam_energy', None),
                                       camera_length=kwargs.get('cameralength', None),
                                       scan_rotation=kwargs.get('scan_rotation', None),
                                       rocking_angle=kwargs.get('rocking_angle', None),
                                       rocking_frequency=kwargs.get('rocking_frequency', None),
                                       exposure_time=kwargs.get('exposure_time', None)
                                       )


def load_aux_data(directory, max_filesize=_MAX_AUX_FILESIZE, supported_files=_SUPPORTED_FILES):
    """
    Load additional files

    Loads auxilliary data files from directory and returns a d dictionary.

    :param directory: The directory containing the auxiliary files
    :type directory: Path
    :param max_filesize: The maximum file size to accept
    :type max_filesize: int
    :param supported_files: List of supported filestypes to accept
    :type supported_files: list
    :return: auxilliary_data
    :rtype: dict
    """
    # Add additional data as metadata
    aux_data = {}
    for p in directory.iterdir():
        if p.is_file():
            if p.suffix in supported_files:
                filesize = p.stat().st_size / 1e6  # Filesize in MB
                if filesize < max_filesize:
                    logger.debug(f'Adding aux datafile "{p}" with filesize {filesize:.0f} MB to metadata')
                    aux_data[p.name] = hs.load(str(p), lazy=False)
                else:
                    logger.debug(f'Ignoring aux datafile "{p}". Filesize {filesize:.0f}>{max_filesize:.0f} MB')
    return aux_data


def set_stepsize(signal, dx: Optional[float] = None, dy: Optional[float] = None) -> None:
    """
    Set stepsizes of a signal

    :param signal: The signal to set the stepsizes for
    :param dx: The stepsize in the x-direction
    :param dy: The stepsize in the y-direction
    :return: None
    """

    if dx is None and dy is None:
        logger.debug("Step sizes are not set")
    elif dx is None and dy is not None:
        signal.set_scan_calibration(dy)
    elif dx is not None and dy is None:
        signal.set_scan_calibration(dx)
    else:
        signal.set_scan_calibration(dy)
        signal.axes_manager[0].scale = dx


def mib2zarr(datapath: Path, navigation_shape: Optional[tuple], lineskip: Optional[int] = 0, chunks: tuple = (32, 256),
             zzip: bool = True,
             overwrite: bool = False) -> Path:
    """
    Convert a MIB file to ZARR format

    Parameters
    ----------
    datapath : Path
        The path to the data.
    navigation_shape : 2-tuple
        The navigation shape of the data. If not provided, the navigation shape should be specified in a corresponding .json file with same path stem containing `navigation_shape: [x, y]`.
    lineskip : int
        The number of frames to skip at the end of each line. Default is 0. Can also be read from corresponding .json file.
    chunks : 2-tuple
        The chunking to use in each dimension. The default is 32 in navigation dimension and 256 in the signal dimensions
    zzip : bool
        Whether to zip the data or not. This will append "-zip" at the end of the filename. Default is True.
    overwrite : bool
        Whether to overwrite existing data or not. Default is False

    Returns
    -------
    path : Path
        The path to the converted data.

    """

    zarr = datapath.with_name(f"{datapath.stem}.zspy")

    if not overwrite and zarr.exists():
        raise ValueError(
            f"File {zarr} already exists. Skipping file. If you want to convert this file, set `overwrite=True`")

    if zzip:
        zzarr = zarr.with_stem(zarr.stem + "-zip")  # Path to new zipped zarr array (use zarr.ZipStore to load)
        if not overwrite and zzarr.exists():
            raise ValueError(
                f"File {zzarr} already exists. Skipping file. If you want to convert this file, set `overwrite=True`")

    logger.info(
        f'\n*** Converting "{datapath}" ***\n\tnavigation_shape={navigation_shape}\n\tlineskip={lineskip}\n\tchunks={chunks}\n\tzzip={zzip}\n\toverwrite={overwrite}')

    parameters = get_metadata_from_json(datapath.with_suffix('.json'))  # Load the json file and get a dictionary
    navigation_shape = tuple(parameters.get('navigation_shape', navigation_shape))  # Get navigation shape
    lineskip = int(parameters.get('lineskip', lineskip))  # Get lineskip

    # Get chunksizes
    if chunks is None:
        chunks = (32, 256)
    chunks = tuple(chunks)
    chunks = (chunks[0],) * len(navigation_shape) + (chunks[1],) * 2

    # Load data
    s = hs.load(str(datapath), lazy=True, chunks=chunks, navigation_shape=navigation_shape)

    # Slice data
    if lineskip > 0:
        s = s.inav[:s.axes_manager[0].size - lineskip, :]

    # Add some metadata
    # Set metadata from json file
    s.original_metadata.add_dictionary({'Parameters': parameters})  # Store the dict in the original_metadata
    s.metadata.General.title = parameters.get('sample', f"{datapath.stem}")  # Set the title of the data.
    set_experimental_parameters(s, **parameters)  # Set the experimental parameters
    set_stepsize(s, parameters.get('dx', None), parameters.get('dy', None))  # Set the stepsize

    # Load auxilliary data found in the parent folder
    s.metadata.add_dictionary({'Auxilliary_data': load_aux_data(datapath.parent)})

    # Save as zarr
    s.save(str(zarr), chunks=s.data.chunksize, overwrite=overwrite)

    # Zip the zarr if requested
    if zzip:
        if overwrite and zzarr.exists():
            logger.debug("Removing old zipped zarr file")
            subprocess.run(f'rm -r "{zzarr}', shell=True, executable="/bin/bash", stderr=subprocess.STDOUT)

        logger.debug("Zipping zarr file")
        subprocess.run(f'7z a -tzip "{zzarr}" "{zarr}" | tail -4', executable="/bin/bash", shell=True,
                       stderr=subprocess.STDOUT)

        logger.debug("Removing zarr file")
        subprocess.run(f'rm -r "{zarr}"', shell=True, executable="/bin/bash", stderr=subprocess.STDOUT)

        logger.info(f'Finished converting "{datapath}". Converted data: "{zzarr}"')
        return zzarr
    logger.info(f'Finished converting "{datapath}". Converted data: "{zarr}"\n')
    return zarr


# Parser arguments
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('path', type=Path, help='The .mib file to convert')
parser.add_argument('--navigation_shape', type=int, nargs=2, help='The navigation shape of the data')
parser.add_argument('--lineskip', type=int, help='The number of frames to skip at the end of each line')
parser.add_argument('--chunks', type=int, nargs=2, help='The chunks to use in each dimension')
parser.add_argument('-z', '--zzip', dest='zzip', action='store_true',
                    help=r'Whether to zip the zspy file or not.')
parser.add_argument('-o', '--overwrite', dest='overwrite', action='store_true',
                    help='Whether to overwrite existing data or not.')
parser.add_argument('-v', '--verbose', dest='verbosity', help='increase output verbosity', action='count', default=0)
arguments = parser.parse_args()

# Change logging level based on verbosity
if arguments.verbosity == 0:
    ch.setLevel(logging.WARNING)
elif arguments.verbosity == 1:
    ch.setLevel(logging.INFO)
else:
    ch.setLevel(logging.DEBUG)
logger.setLevel(ch.level)

# Log argument parser values
args = vars(arguments)
logger.debug('Argument parser got {n} arguments:'.format(n=len(args)))
[logger.debug('{} = {}'.format(arg, args[arg])) for arg in args]

mib2zarr(arguments.path, arguments.navigation_shape, arguments.lineskip, arguments.chunks, arguments.zzip,
         arguments.overwrite)
