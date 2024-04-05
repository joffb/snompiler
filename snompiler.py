#!/usr/bin/env python3

# snompiler v0.2
# Joe Kennedy 2024
# almost sample accurate SN76489 VGM compiler/player for Sega Master System
# usage:
#   python snompiler.py in.vgm out.sms

import struct
import gzip
import sys
import os 

def gd3_parse(data):

    header = struct.unpack("<III", data[0:12])
    chars = struct.unpack("<" + ("H" * int(header[2]/2)), data[12:])

    ptr = 8
    strings = []
    string = ""

    for i in range(0, len(chars)):

        # end of string
        if chars[i] == 0:
            strings.append(string)
            string = ""
        
        # append to string
        else:
            string = string + chr(chars[i])
        
    return strings

print("snompiler - Joe Kennedy 2024")

if len(sys.argv) < 3:
    print("usage:")
    print("\tpython snompiler.py in.vgm out.sms")
    sys.exit()

infile_name = sys.argv[1]
outfile_name = sys.argv[2]

# read input vgm
try:
    infile = open(infile_name, "rb")
    data = infile.read()
    infile.close()
except OSError:
    print("Error reading input file: " + str(infile_name), file=sys.stderr)
    sys.exit(1)

# check if the data is gzipped
if data[0] == 0x1f and data[1] == 0x8b:
    print ("decompressing gzipped vgm")
    data = gzip.decompress(data)

# check for VGM header
if data[0] != 0x56 or data[1] != 0x67 or data[2] != 0x6d:
    print ("invalid VGM file!")
    sys.exit()

# parse vgm header
header = struct.unpack("<" + ("I" * 4 * 16), data[0:256])

# pointer to gd3 strings
gd3_strings = []

# parse gd3 header
if header[5] != 0:
    gd3_ptr = (5 * 4) + header[5]
    gd3_strings = gd3_parse(data[gd3_ptr:])
    print(gd3_strings)

# empty gd3 header
else:
    for i in range (0, 11):
        gd3_strings.append("")

# pointer to vgm data
vgm_data_ptr = (13 * 4) + header[13]

# total number of samples the vgm has
vgm_sample_total = header[6]

# number of samples we've written so far
total_samples_written = 0

# number of bytes in current bank
byte_count = 0

# total number of bytes we've written so far
total_byte_count = 0

# maximum number of banks to create
BANK_LIMIT = 255

# holds code/data for each bank
bank_bin = {}

# starting bank
bank = 2

print("bank 2 start")

sn_writes = []

code_data = []
out_data = []

processing_done = False

while processing_done == False:

    cmd = data[vgm_data_ptr]

    # keep array of sn writes
    # we'll write them when we hit the next sample wait command
    if cmd == 0x50:

        vgm_data_ptr += 1

        sn_writes.append(data[vgm_data_ptr])

    # wait n samples
    elif cmd == 0x61 or cmd == 0x62 or cmd == 0x63 or (cmd >= 0x70 and cmd <= 0x7f):

        # get number of samples to wait
        # wait between 0 and 65535 samples
        if cmd == 0x61:

            sample_wait = data[vgm_data_ptr + 1] + (data[vgm_data_ptr + 2] << 8)
            vgm_data_ptr += 2

        # wait 735 samples (60th of a second)
        elif cmd == 0x62:

            sample_wait = 735
        
        # wait 882 samples (50th of a second)
        elif cmd == 0x63:

            sample_wait = 882

        # wait for (cmd's lower nibble + 1) samples
        else:
            
            sample_wait = (cmd & 0xf) + 1

        # update counter of how many samples we've written so far
        total_samples_written += sample_wait

        # warn if we're writing a lot of sn writes in a small period of time
        if len(sn_writes) > (sample_wait * 4):
            print("\t!! writing " + str(len(sn_writes)) + " writes to sn in one sample (sample wait: " + str(sample_wait) + ")")

        # while we still have sn writes to do
        while (len(sn_writes) > 0):

            # write one sn update and wait for rest of sample
            if len(sn_writes) == 1:

                code_data.append(0xe7)  # rst 0x20

                out_data = out_data + sn_writes[0:1]
                sn_writes = sn_writes[1:]

                sample_wait = sample_wait - 1

            # write two sn updates and wait for rest of sample
            elif len(sn_writes) == 2:

                code_data.append(0xef)  # rst 0x28

                out_data = out_data + sn_writes[0:2]
                sn_writes = sn_writes[2:]

                sample_wait = sample_wait - 1

            # write three sn updates and wait for rest of sample
            elif len(sn_writes) == 3:

                code_data.append(0xf7)   # rst 0x30

                out_data = out_data + sn_writes[0:3]
                sn_writes = sn_writes[3:]

                sample_wait = sample_wait - 1

            # write four sn updates - this takes a bit more than one sample
            elif len(sn_writes) >= 4:

                code_data.append(0xff)   # rst 0x38

                out_data = out_data + sn_writes[0:4]
                sn_writes = sn_writes[4:]

                sample_wait = sample_wait - 1

        # empty the sn_writes array
        sn_writes = []

        # wait loop
        # loop out the rest of them
        if (sample_wait >= 1):

            # two bytes of sample wait time
            if sample_wait >= 256:

                code_data = code_data + [0xcf] # rst 0x08

                out_data = out_data + [sample_wait & 0xff, (sample_wait >> 8) & 0xff]

            # one byte of sample wait time
            else:

                code_data = code_data + [0xd7]  # rst 0x10

                out_data = out_data + [sample_wait]

    # almost filled this 16k bank up, or reached the bank limit, or reached the end of the music
    if (len(out_data) + len(code_data) > 16350) or bank == BANK_LIMIT or cmd == 0x66:

        # hit the end of the song or our storage has run out
        if (bank + 1) == BANK_LIMIT or cmd == 0x66:

            print("bank limit hit or end of music reached")

            code_data = code_data + [
                0x3e, 2,            # ld a, 2
                0xcd, 0x80, 0x00    # call bank_swap (it should be at 0x0080)
            ]

            # we're done
            processing_done = True

        # reached the end of this bank
        else:

            code_data = code_data + [
                0x3e, bank + 1,     # ld a, bank + 1
                0xcd, 0x80, 0x00    # call bank_swap (it should be at 0x0080)
            ]
        
        # add length of output data to byte_count for our totals
        byte_count = len(code_data) + len(out_data)

        # store binary
        out_data.reverse()
        bank_bin[bank] = code_data + ([0xff] * (16384 - byte_count)) + out_data

        total_byte_count += byte_count
        print("\t" + str(byte_count)  + " bytes written")

        out_data = []
        code_data = []

        bank += 1

        # we're not done yet
        if processing_done == False:

            print("bank " + str(bank) + " start")

    # move along to next vgm command
    vgm_data_ptr += 1

sample_percentage = (total_samples_written/vgm_sample_total) * 100
print("* vgm input was " + str(len(data)) + " bytes")
print("* song data is " + str(total_byte_count) + " bytes total")
print("* output " + str(total_samples_written) + "/" + str(vgm_sample_total) + " samples (" + str(round(sample_percentage, 1)) + "% of song)")

# read player code
playerfile = open(os.path.dirname(os.path.abspath(__file__)) + "\player.sms", "rb")
player_data = playerfile.read()
playerfile.close()

outfile = open(outfile_name, 'wb')

# write player code (16k)
outfile.write(player_data)

# write gd3 strings to 0x4000
gd3_strings_len = 0

for i in range(0, len(gd3_strings)):

    stringbytes = bytes(gd3_strings[i], 'utf-8')

    outfile.write(stringbytes)
    outfile.write(bytes([0]))

    gd3_strings_len += len(stringbytes) + 1\


# write padding out to another 16k
outfile.write(bytes([0xff] * (16384 - gd3_strings_len)))

# write song data
for i in range(2, bank):
    outfile.write(bytes(bank_bin[i]))

# number of bytes we've written
bytes_written = bank * 16384

# find power of two number of kb which can contain the song
filesize_check = 64 * 1024

while bytes_written > filesize_check:
    filesize_check = filesize_check * 2

# write padding
outfile.write(bytes([0xff] * (filesize_check - bytes_written)))

outfile.close()