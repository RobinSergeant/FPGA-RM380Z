#!/usr/bin/env python3

""" Python utility to produce double sided floppy disk image

    Copyright (c) 2026 Robin Sergeant
"""

from argparse import ArgumentParser

def main():
    """ main function """

    parser = ArgumentParser(description='Combines two SS floppy disk images into one DS image')
    parser.add_argument('-o', dest='out_file', required=True, help='output file path')
    parser.add_argument('-t', dest='tracks', default=77, type=int, help='number of tracks on disk (default 77')
    parser.add_argument('-s', dest='sectors', default=26, type=int, help='number of sectirs per track (default 26)')
    parser.add_argument('-z', dest='sector_size', default=128, type=int, help='sector size in bytes (default 128)')
    parser.add_argument('input_files', nargs=2, help='binary image file(s)')
    args = parser.parse_args()

    track_size = args.sectors * args.sector_size

    with open(args.out_file, 'wb') as out, \
         open(args.input_files[0], 'rb') as side1, \
         open(args.input_files[1], 'rb') as side2:
        for _ in range(args.tracks):
            out.write(side1.read(track_size))
            out.write(side2.read(track_size))

if __name__ == '__main__':
    main()
