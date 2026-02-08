#!/usr/bin/env python3

""" Python utility to generate MEM files

    Copyright (c) 2026 Robin Sergeant
"""

from pathlib import PurePath
from argparse import ArgumentParser

def main():
    """ main function """

    parser = ArgumentParser(
        description='Generates a MEM file containing data from one or more BIN files',
        epilog='NB by default the path of the first BIN file is used as the MEM filepath' \
               ' (with a .mem extension)')
    parser.add_argument('-o', dest='mem_file', help='output MEM filepath')
    parser.add_argument('input_files', nargs='+', metavar='bin_file', help='binary input file(s)')
    args = parser.parse_args()

    if args.mem_file:
        mem_file = args.mem_file
    else:
        mem_file = PurePath(args.input_files[0]).with_suffix('.mem').as_posix()

    data = b''
    for bin_file in args.input_files:
        with open(bin_file, 'rb') as f:
            data += f.read()

    with open(mem_file, 'w', encoding='utf8') as f:
        for val in data:
            f.write(f'{val:02X}\n')

if __name__ == '__main__':
    main()
