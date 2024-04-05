# snompiler
### almost sample accurate SN76489 VGM compiler/player for Sega Master System

Usage:

`python snompiler.py in.vgm out.sms`

This will take a VGM file (SN76489 only) and create a ROM which will try its best to play it back with sample accuracy at 44100hz on the SMS.

**Extra credits:**
+ Plato font by DamienG https://damieng.com/zx-origins
+ snooz_proc.sms and snooz_underly.sms examples are converted from Snoozetracker songs composed/converted by tEFFx https://github.com/tEFFx
+ Thanks to Trirosmos, Maxim, sverx and lidnariq on the SMS Power discord for inspiring the idea!

### How does it work then?

The SMS runs at like 3.57MHz (or 3.54MHz) and VGM is played back at a sample rate of 44.1kHz.
If you divide 3579540 by 44100 you get 81, so that means there's 81 CPU cycles (T-states) per sample.

You can't really interpret multiple VGM commands at this sort of rate, so snompiler "compiles" the VGM's SN chip writes and sample wait commands into Z80 code and data.
The snompiled VGM code runs 100% CPU time, interrupts are disabled and it's either writing to the SN chip or waiting around for the next sample.

To keep things as small as possible, the snompiled code is mostly `rst` calls which jump away and write to the SN chip or delay for a number of samples.
The code that's executed is followed by all the data which will be written to the chip as a big blob.

Essentially the code does:
```asm

    ; write one SN output value and then wait for the rest of the sample
    ; the rst 0x18 call will use outd which gets the value pointed at by hl
    ; outputs it to the SN chip, then moves hl on to the next value
    ; then we waste time until a total of 81 cycles have elapsed
    rst 0x20

    ; wait for >= 256 samples, the amount of samples to wait is stored in the data
    rst 0x08

    ; write three SN output values
    rst 0x30

    ; wait for < 256 samples, the amount of samples to wait is stored in the data
    rst 0x10

    ;
    ;   lots more updates go here
    ;

    ; change to the next bank and start playing from the start of it
    ; all banking is done in slot 2, and the code writes a to 0xffff to change the bank
    ld a, 4
    call bank_swap
```

This generated code is then tacked onto the end of the player.sms stub which has the code for the `rst` and `bank_swap` calls. It sets the SMS up, writes the GD3 credits and then jumps to the start of the song.

From my testing, the generated code and data comes out to about the same size as the uncompressed VGM.
If the generated code ends up bigger than 4mb (256 total 16kb banks) then it stops processing and when the song plays back there'll be a skip as the code prematurely loops back to the start of the VGM.

### Why's it "almost" sample accurate?

Currently, writing 4 SN values in one sample takes 85 cycles, so it's a bit slower than it should be.
Currently, writing 3 SN values takes 80 cycles, so it's slightly faster than it should be.

Writing more than 4 SN values will generally take more than 81 cycles.
If the VGM file tries to write say 6 SN values in a sample, then the code that will be generated will:

    * Write 4 SN values, using 1 sample's worth of time
    * Write 2 SN values and wait for the rest of another sample

This doesn't matter in the case of 50/60hz VGMs where there's 700 or 800 samples between each set of writes so you'll never hear a difference.
However VGMs like Snoozetracker ones might update every sample and if they're really writing a lot of values per sample it might cause some "jitter" or a slight pitch difference.
Luckily from the Snoozetracker files I've tried, the effects of this are minimal.

There's a warning when this happens, which looks like this:
```!! writing 6 writes to sn in one sample (sample wait: 1)```
Basically saying that it's trying to do more writes than is really possible in that amount of time.
If it does a lot of writes and there's a bigger sample wait afterwards, it won't flag any errors.

### Snoozetracker noise channel sample playback 

From my testing using the "ShovelKnight_UnderlyingProblem.tfm" Snoozetracker example file (see examples/snooz_underly.sms), Snoozetracker's method of using the Noise channel to play back samples 
doesn't actually work on SMS hardware or in Emulicious, the channel just seems to be completely silent. 

The other example files which don't use this feature seem to work fine though, and they play back pretty accurately!

### Some missing features and possibilities for improvement

+ Doesn't support the VGM loop point, it just jumps back to the start of the song
+ Would be good if all `rst` calls took exactly 81 samples
+ Would be good if it compensated for the cycles spent switching banks - at the minute it takes like 76 cycles which is basicly a sample