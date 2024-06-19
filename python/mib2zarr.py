#!/usr/bin/env python

# -*- coding: utf-8 -*-
"""
Convert MIB raw data to zarr format
@author: Emil Frang Christiansen (emil.christiansen@ntnu.no)
Created 2024-06-14

Converts either a single MIB file or all MIB files in specified directory (and it's subdirectories) that are above a certain filesize limit to ZSPY format. Can also store the data as a zarr.ZipStore or zip the .zspy data using 7z after conversion.

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
import traceback
import matplotlib.pyplot as plt
from typing import Optional
from zarr import ZipStore

# Create formatter
format_string = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
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

logger.info(f"This is {__file__} working from {os.getcwd()}:\n{__doc__}")

import hyperspy.api as hs
import argparse
from pathlib import Path
import json

_SUPPORTED_FILES = (".dm3", ".dm4", ".png", ".jpg", ".mib")
_MAX_AUX_FILESIZE = 5  # MB
_MIN_MIB_FILESIZE = 100  # MB


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
            parameters = json.load(path.open("r"))
        except FileNotFoundError as e:
            logger.debug(
                "Could not get parameters metadata from json file. You will need to set metadata yourself later on."
            )
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
    signal.set_experimental_parameters(
        beam_energy=kwargs.get("beam_energy", None),
        camera_length=kwargs.get("cameralength", None),
        scan_rotation=kwargs.get("scan_rotation", None),
        rocking_angle=kwargs.get("rocking_angle", None),
        rocking_frequency=kwargs.get("rocking_frequency", None),
        exposure_time=kwargs.get("exposure_time", None),
    )


def load_aux_data(
    directory, max_filesize=_MAX_AUX_FILESIZE, supported_files=_SUPPORTED_FILES
):
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
    logger.debug(f'Adding auxillary data from directory "{directory}" to metadata')
    aux_data = {}
    for p in directory.iterdir():
        if p.is_file():
            if p.suffix in supported_files:
                filesize = p.stat().st_size / 1e6  # Filesize in MB
                if filesize < max_filesize:
                    logger.debug(
                        f'Loading aux data "{p}" with filesize {filesize:.0f} MB'
                    )
                    s = hs.load(str(p), lazy=False)
                    if (
                        len(s.axes_manager.signal_shape) == 0
                        and len(s.axes_manager.navigation_shape) == 0
                    ):
                        logger.debug(
                            f"Ignoring file, {s} has dimension 0 in both signal and navigation space."
                        )
                    else:
                        logger.debug(f"Adding aux data {s} to metadata")
                        aux_data[p.name.replace(" ", "_")] = s
                else:
                    logger.debug(
                        f'Ignoring aux datafile "{p}". Filesize {filesize:.0f}>{max_filesize:.0f} MB'
                    )
    return aux_data


def set_stepsize(
    signal, dx: Optional[float] = None, dy: Optional[float] = None
) -> None:
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


def get_mib_files(path: Path, minimum_filesize=_MIN_MIB_FILESIZE):
    f"""
    Find the path to all MIB files in a directory and subdirectories

    Parameters
    ----------
    path : Path
        The path to search in.
    minimum_filesize : int
        The minimum filesize to accept. Default is {_MIN_MIB_FILESIZE} MB

    Returns
    -------
    mib_files : list
        A list of all the MIB files found in the directory and its subdirectories
    """

    mib_files = []
    if path.is_dir():
        for p in path.iterdir():
            if p.is_dir():
                mib_files += get_mib_files(p)
            elif p.is_file():
                filesize = p.stat().st_size / 1e6  # Filsesize in MB
                if p.suffix == ".mib" and filesize >= _MIN_MIB_FILESIZE:
                    mib_files += [p]
    else:
        if path.suffix == ".mib":
            mib_files += [path]
    return mib_files


def mib2zarr(
    datapath: Path,
    navigation_shape: Optional[tuple] = None,
    lineskip: Optional[int] = 0,
    chunks: tuple = (32, 256),
    zzip: bool = False,
    zstore: bool = True,
    overwrite: bool = False,
    min_mib_size: int = _MIN_MIB_FILESIZE,
    max_aux_size: int = _MAX_AUX_FILESIZE,
    vbf: bool = False,
    stack_max: bool = False,
) -> list:
    f"""
    Convert MIB file(s) to ZARR format
    
    Converts either a single MIB file or several MIB files in a directory (and any subdirectories) to zarr format. Will also load auxilliary data (such as HAADF STEM images or calibration data) found together with MIB data and store them as metadata.
    
    Parameters
    ----------
    datapath : Path
        The path to the data. Can also be the path to a directory, in which case all MIB files found in subdirectories with a filesize larger than {_MIN_MIB_FILESIZE} MB will be converted. 
    navigation_shape : 2-tuple
        The navigation shape of the data. If not provided, the navigation shape should be specified in a corresponding .json file with same path stem containing `navigation_shape: [x, y]`.
    lineskip : int
        The number of frames to skip at the end of each line. Default is 0. Can also be read from corresponding .json file.
    chunks : 2-tuple
        The chunking to use in each dimension. The default is 32 in navigation dimension and 256 in the signal dimensions
    zzip : bool
        Whether to zip the data or not. This will append "-zip" at the end of the filename. Default is False. Cannot be used together with `zstore=True`
    zstore : bool
        Whether to zip the data as a zarr.ZipStore or not. This will append "-zstore" at the end of the filename. Default is True. Cannot be used together with `zzip=True`
    overwrite : bool
        Whether to overwrite existing data or not. Default is False
    min_mib_size : int
        The minimum MIB filesize in MB to accept when converting MIB files throughout a directory.
    max_aux_size : int
        The maximum filesize in MB to accept when loading auxilliary data as metadata.
    vbf : bool
        Whether to save a VBF image as a .png
    stackmax : bool
        Whether to save the maximum throughstack intensity of diffraction patterns as a .png
    Returns
    -------
    paths : list
        A list of paths to the converted data.
    
    Notes
    -----
    Metadata parameters stored in a .json file with identical stem as the MIB file will be loaded and used to get `navigation_shape`, cameralength, etc when present. If not present, users should specify at least the `navigation_shape` and `lineskip` to ensure correct operation.
    """
    if "*" in datapath.stem:
        logger.debug(f"Detected wildcard in datapath.")
        converted_files = []
        paths = datapath.parent.expanduser().glob(datapath.name)
        for p in paths:
            if p.is_dir() or p.suffix == ".mib":
                logger.debug(f"Converting path {p}")
                converted_files += mib2zarr(
                    p,
                    navigation_shape,
                    lineskip,
                    chunks,
                    zzip,
                    zstore,
                    overwrite,
                    min_mib_size,
                    max_aux_size,
                    vbf,
                    stack_max,
                )
            else:
                logger.debug(f"Skipping file {p}")
        return converted_files

    if datapath.is_dir():
        converted_files = []
        mib_files = get_mib_files(datapath, min_mib_size)
        for p in mib_files:
            try:
                converted_files += mib2zarr(
                    p,
                    navigation_shape,
                    lineskip,
                    chunks,
                    zzip,
                    zstore,
                    overwrite,
                    min_mib_size,
                    max_aux_size,
                    vbf,
                    stack_max,
                )
            except Exception as e:
                logger.error(
                    f'Ignoring file "{p}" due to error:\n{e}\n{traceback.format_exc()}'
                )
        return converted_files

    zarr = datapath.with_name(f"{datapath.stem}.zspy")

    if not overwrite and zarr.exists():
        raise ValueError(
            f"File {zarr} already exists. Skipping file. If you want to convert this file, set `overwrite=True`"
        )

    if zzip and zstore:
        raise ValueError(f"Both `zzip` and `zstore` cannot be True")

    if zzip or zstore:
        if zzip:
            zzarr = zarr.with_stem(
                zarr.stem + "-zip"
            )  # Path to new zipped zarr array (use zarr.ZipStore to load)
        else:
            zzarr = zarr.with_stem(
                zarr.stem + "-zstore"
            )  # Path to new zippped zarr array (use zarr.ZipStore to load)
        if not overwrite and zzarr.exists():
            raise ValueError(
                f"File {zzarr} already exists. Skipping file. If you want to convert this file, set `overwrite=True`"
            )

    logger.info(
        f'\n*** Converting "{datapath}" ***'
        f"\n\tnavigation_shape={navigation_shape}"
        f"\n\tlineskip={lineskip}"
        f"\n\tchunks={chunks}"
        f"\n\tzzip={zzip}"
        f"\n\tzstore={zstore}"
        f"\n\toverwrite={overwrite}"
        f"\n\tvbf={vbf}"
        f"\n\tstack_max={stack_max}"
    )

    parameters = get_metadata_from_json(
        datapath.with_suffix(".json")
    )  # Load the json file and get a dictionary
    navigation_shape = parameters.get("navigation_shape", navigation_shape)
    if navigation_shape is not None:
        navigation_shape = tuple(navigation_shape)
    lineskip = int(parameters.get("lineskip", lineskip))  # Get lineskip

    # Get chunksizes
    if chunks is None:
        chunks = (32, 256)
    chunks = tuple(chunks)
    if navigation_shape is None:
        nav_dim = 2
    else:
        nav_dim = len(navigation_shape)
    chunks = (chunks[0],) * nav_dim + (chunks[1],) * 2

    # Load data
    if lineskip > 0 and navigation_shape is not None:
        nav_shape = (navigation_shape[0] + lineskip, navigation_shape[1])
    else:
        nav_shape = navigation_shape
    s = hs.load(str(datapath), lazy=True, chunks=chunks, navigation_shape=nav_shape)

    # Slice data
    if lineskip > 0:
        s = s.inav[: s.axes_manager[0].size - lineskip, :]

    if vbf:
        nx, ny = s.axes_manager.signal_shape
        cx, cy, r = nx // 2, ny // 2, nx // 10
        logger.info(f"Creating VBF ({cx}, {cy}, {r})")
        _vbf = s.get_integrated_intensity(hs.roi.CircleROI(cx, cy, r))
        _vbf.compute()
        _vbf.plot(axes_ticks=None, colorbar=None)
        figure = plt.gcf()
        figure.savefig(datapath.with_name(f"{datapath.stem}_vbf.png"))
        plt.close(figure)

    if stack_max:
        logger.info(f"Creating maximum through-stack image")
        _max = s.max(axis=[0, 1])
        _max.compute()
        _max.plot(norm="symlog", axes_ticks=None, colorbar=None)
        figure = plt.gcf()
        figure.savefig(datapath.with_name(f"{datapath.stem}_max.png"))
        plt.close(figure)

    # Add some metadata
    # Set metadata from json file
    s.original_metadata.add_dictionary(
        {"Parameters": parameters}
    )  # Store the dict in the original_metadata
    s.metadata.General.title = parameters.get(
        "sample", f"{datapath.stem}"
    )  # Set the title of the data.
    set_experimental_parameters(s, **parameters)  # Set the experimental parameters
    set_stepsize(
        s, parameters.get("dx", None), parameters.get("dy", None)
    )  # Set the stepsize

    # Load auxilliary data found in the parent folder
    s.metadata.add_dictionary(
        {"Auxilliary_data": load_aux_data(datapath.parent, max_filesize=max_aux_size)}
    )

    logger.debug(f"Original metadata:\n{s.original_metadata}")
    logger.debug(f"Metadata: \n{s.metadata}")

    # Save as zarr
    if zstore:
        if overwrite and zzarr.exists():
            logger.debug("Removing old zipstore zarr file")
            zzarr.unlink(missing_ok=True)
        logger.info("Saving data with ZipStore")
        store = ZipStore(str(zzarr))
        s.save(store, chunks=s.data.chunksize, overwrite=True)
        logger.info(f'Finished converting "{datapath}". Converted data: "{zarr}"\n')
        return [zzarr]
    else:
        s.save(str(zarr), chunks=s.data.chunksize, overwrite=overwrite)

    # Zip the zarr if requested
    if zzip:
        if overwrite and zzarr.exists():
            logger.debug(f"Removing old zipped zarr file")
            zzarr.unlink(missing_ok=True)

        command = f'7z a -tzip "{zzarr}" "{zarr}" | tail -4'
        logger.debug(f"Zipping zarr file with command: <{command}>")
        subprocess.run(
            command,
            executable="/bin/bash",
            shell=True,
            stderr=subprocess.STDOUT,
        )

        logger.debug(f"Removing zarr file")
        zarr.rmdir()

        logger.info(f'Finished converting "{datapath}". Converted data: "{zzarr}"')
        return [zzarr]
    logger.info(f'Finished converting "{datapath}". Converted data: "{zarr}"\n')
    return [zarr]


if __name__ == "__main__":
    # Parser arguments
    parser = argparse.ArgumentParser()  # description=f"{__doc__}")
    parser.add_argument(
        "path",
        type=Path,
        help="The .mib file to convert or to a parent directory to convert all MIB files found in subdirectories",
    )
    parser.add_argument(
        "--navigation_shape", type=int, nargs=2, help="The navigation shape of the data"
    )
    parser.add_argument(
        "--lineskip",
        type=int,
        default=0,
        help="The number of frames to skip at the end of each line",
    )
    parser.add_argument(
        "--chunks",
        type=int,
        nargs=2,
        default=[32, 256],
        help="The chunks to use in each dimension",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "-z",
        "--zzip",
        action="store_true",
        help="Whether to zip the zspy file with 7z or not.",
    )
    group.add_argument(
        "-s",
        "--zstore",
        action="store_true",
        help="Whether to save the zspy file with zarr.ZipStore or not",
    )
    parser.add_argument(
        "--vbf",
        dest="vbf",
        action="store_true",
        help="Whether to also save a VBF as a .png",
    )
    parser.add_argument(
        "--stackmax",
        dest="stackmax",
        action="store_true",
        help="Whether to also save a maximum through-stack image of the diffraction patterns as a .png",
    )
    parser.add_argument(
        "-o",
        "--overwrite",
        dest="overwrite",
        action="store_true",
        help="Whether to overwrite existing data or not.",
    )
    parser.add_argument(
        "--mib_size",
        type=int,
        default=_MIN_MIB_FILESIZE,
        help="The minimum MIB filesize in MB to accept when converting data through directories",
    )
    parser.add_argument(
        "--max_aux_size",
        type=int,
        default=_MAX_AUX_FILESIZE,
        help="The maximum filesize in MB to accept when loading auxilliary data",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        dest="verbosity",
        help="increase output verbosity",
        action="count",
        default=0,
    )
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
    logger.debug("Argument parser got {n} arguments:".format(n=len(args)))
    [logger.debug("{} = {}".format(arg, args[arg])) for arg in args]

    mib2zarr(
        arguments.path,
        navigation_shape=arguments.navigation_shape,
        lineskip=arguments.lineskip,
        chunks=arguments.chunks,
        zzip=arguments.zzip,
        zstore=arguments.zstore,
        overwrite=arguments.overwrite,
        min_mib_size=arguments.mib_size,
        max_aux_size=arguments.max_aux_size,
        vbf=arguments.vbf,
        stack_max=arguments.stackmax,
    )
