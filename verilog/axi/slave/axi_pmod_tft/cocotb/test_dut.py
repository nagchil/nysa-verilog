import os
import sys
import cocotb
import logging
from cocotb.result import TestFailure
from cocotb.clock import Clock
import time
from array import array as Array
from cocotb.triggers import Timer, FallingEdge

from cocotb.drivers.amba import AXI4LiteMaster
from video_out_bus import VideoOutBus

CLK_PERIOD = 10

MODULE_PATH = os.path.join(os.path.dirname(__file__), os.pardir, "rtl")
MODULE_PATH = os.path.abspath(MODULE_PATH)



REG_CONTROL                   = 0
REG_STATUS                    = 1
REG_COMMAND_DATA              = 2
REG_PIXEL_COUNT               = 3

BIT_CONTROL_ENABLE            = 0
BIT_CONTROL_ENABLE_INTERRUPT  = 1
BIT_CONTROL_COMMAND_MODE      = 2
BIT_CONTROL_BACKLIGHT_ENABLE  = 3
BIT_CONTROL_RESET_DISPLAY     = 4
BIT_CONTROL_COMMAND_WRITE     = 5
BIT_CONTROL_COMMAND_READ      = 6
BIT_CONTROL_COMMAND_PARAMETER = 7
BIT_CONTROL_WRITE_OVERRIDE    = 8
BIT_CONTROL_CHIP_SELECT       = 9
BIT_CONTROL_ENABLE_TEARING    = 10


MEM_ADR_RESET               = 0x01

"""
Functions Required for checking out PMOD TFT

1. Write to the controller chip internal register
2. Read from the controller chip internall register
3. Video Frame Successfully is sent from the memory
    to the controller chip
4. Video Frames are continually sent out
"""


WIDTH                = 8
HEIGHT               = 4
H_BLANK              = 40
V_BLANK              = 200
PIXEL_COUNT          = WIDTH * HEIGHT



def setup_dut(dut):
    cocotb.fork(Clock(dut.clk, CLK_PERIOD).start())

@cocotb.test(skip = False)
def write_to_controller(dut):
    """
    Description:
        Write a 16-bit valute to the controller

    Test ID: 0

    Expected Results:
        A value is successfully written to the
        the register of the controller.

        This value should be readable from the test bench
    """
    dut.rst <= 1
    dut.test_id <= 0
    axim = AXI4LiteMaster(dut, "AXIML", dut.clk)
    video_out = VideoOutBus(dut, "VIDEO",
                            dut.clk,
                            width = WIDTH,
                            height = HEIGHT,
                            hblank = H_BLANK,
                            vblank = V_BLANK)

    setup_dut(dut)
    yield Timer(CLK_PERIOD * 10)
    dut.rst <= 0

    dut.log.info("Ready")
    yield Timer(CLK_PERIOD * 10)


    dut.rst <= 1
    axim = AXI4LiteMaster(dut, "AXIML", dut.clk)
    video_out = VideoOutBus(dut, "VIDEO",
                            dut.clk,
                            width = WIDTH,
                            height = HEIGHT,
                            hblank = H_BLANK,
                            vblank = V_BLANK)

    setup_dut(dut)
    yield Timer(CLK_PERIOD * 10)
    dut.rst <= 0

    dut.log.info("Ready")
    yield Timer(CLK_PERIOD * 10)


    control = 0x00
    control |= 1 << BIT_CONTROL_CHIP_SELECT
    control |= 1 << BIT_CONTROL_RESET_DISPLAY
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    control |= 1 << BIT_CONTROL_WRITE_OVERRIDE

    #Reset the LCD
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_RESET_DISPLAY)
    control &= ~(1 << BIT_CONTROL_WRITE_OVERRIDE)

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    control &= ~(1 << BIT_CONTROL_CHIP_SELECT)


    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    control |= 1 << BIT_CONTROL_CHIP_SELECT





    ##################################################
    #Write a 0xAA55 to address 0xB8

    #First set up the correct mode
    control |= 1 << BIT_CONTROL_COMMAND_MODE
    control &= ~ (1 << BIT_CONTROL_COMMAND_PARAMETER)
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    #Set The Address to write to
    WRITE_ADDR = 0xB8
    yield axim.write(REG_COMMAND_DATA, WRITE_ADDR)
    yield Timer(CLK_PERIOD * 10)


    #Write the command
    control |= 1 << BIT_CONTROL_COMMAND_WRITE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)



    #Write a parameter
    WRITE_PARAMETER_1 = 0xAA # Arbitrary Data
    WRITE_PARAMETER_2 = 0x55 # Arbitrary Data

    # Write Parameter 1
    yield axim.write(REG_COMMAND_DATA, WRITE_PARAMETER_1)
    yield Timer(CLK_PERIOD * 10)


    control |= 1 << BIT_CONTROL_COMMAND_PARAMETER
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    # Write Parameter 2
    yield axim.write(REG_COMMAND_DATA, WRITE_PARAMETER_2)
    yield Timer(CLK_PERIOD * 10)


    control |= 1 << BIT_CONTROL_COMMAND_PARAMETER
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    #yield FallingEdge(dut.w_write_n)
    #yield ReadOnly()

    data = dut.r_write_parameter
    value = (WRITE_PARAMETER_1 << 8) | WRITE_PARAMETER_2
    if data != value:
        raise TestFailure("Data written to register should have been: 0x02X, \
                            but is 0x%02X" % (data, value))
    yield Timer(CLK_PERIOD * 100)



@cocotb.test(skip = False)
def read_from_controller(dut):
    """
    Description:
        Read a 16-bit value from the controller

    Test ID: 1

    Expected Results:
        Receive a read request to address 0xB8
        Should read back 0xAAAA
    """
    dut.rst <= 1
    dut.test_id <= 1
    axim = AXI4LiteMaster(dut, "AXIML", dut.clk)
    video_out = VideoOutBus(dut, "VIDEO",
                            dut.clk,
                            width = WIDTH,
                            height = HEIGHT,
                            hblank = H_BLANK,
                            vblank = V_BLANK)

    setup_dut(dut)
    yield Timer(CLK_PERIOD * 10)
    dut.rst <= 0

    dut.log.info("Ready")
    yield Timer(CLK_PERIOD * 10)

    control = 0x00
    control |= 1 << BIT_CONTROL_CHIP_SELECT
    control |= 1 << BIT_CONTROL_RESET_DISPLAY
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    control |= 1 << BIT_CONTROL_WRITE_OVERRIDE

    #Reset the LCD
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_RESET_DISPLAY)
    control &= ~(1 << BIT_CONTROL_WRITE_OVERRIDE)

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    control &= ~(1 << BIT_CONTROL_CHIP_SELECT)


    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control |= 1 << BIT_CONTROL_CHIP_SELECT
    control |= 1 << BIT_CONTROL_COMMAND_MODE

    #   Set the address
    READ_ADDR = 0xB8

    control |= 1 << BIT_CONTROL_COMMAND_MODE
    control &= ~ (1 << BIT_CONTROL_COMMAND_PARAMETER)
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    #   Set address
    yield axim.write(REG_COMMAND_DATA, READ_ADDR)
    yield Timer(CLK_PERIOD * 10)

    control |= 1 << BIT_CONTROL_COMMAND_WRITE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_COMMAND_WRITE)
    control |= 1 << BIT_CONTROL_COMMAND_PARAMETER
    control |= 1 << BIT_CONTROL_COMMAND_READ
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    d1 = yield axim.read(REG_COMMAND_DATA)
    yield Timer(CLK_PERIOD * 10)

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    d2 = yield axim.read(REG_COMMAND_DATA)
    d2 = int(d2)
    d1 = int(d1 << 8)
    data = d1 + d2
    yield Timer(CLK_PERIOD * 10)

    if data != 0xAAAA:
        raise TestFailure("Data should have been 0x%04X but read: 0x%04X" % (0xAAAA, data))

    #Set the pixel count
    yield axim.write(REG_PIXEL_COUNT, PIXEL_COUNT)
    yield Timer(CLK_PERIOD * 10)



@cocotb.test(skip = False)
def write_single_frame(dut):
    """
    Description:
        Send a single image to the controller
        The signal format should be
        Command: Set Memory Address
        SEND Red, Blue, Green bytes
        Repeat until full image is sent

        It's important that the timing of the
        sync strobes are good so that the FIFO doesn't
        overfill

    Test ID: 2

    Expected Results:
        Should read images out of the controller
        *** NEED SOMETHING TO VERIFY THE IMAGES ARE CORRECT!!!***
    """
    dut.rst <= 1
    dut.test_id <= 2
    axim = AXI4LiteMaster(dut, "AXIML", dut.clk)
    video_out = VideoOutBus(dut, "VIDEO",
                            dut.clk,
                            width = WIDTH,
                            height = HEIGHT,
                            hblank = H_BLANK,
                            vblank = V_BLANK)


    NUM_FRAMES           = 1

    video = []
    for f in range (NUM_FRAMES):
        frame = []
        for v in range (HEIGHT):
            line = []
            for h in range(WIDTH):
                value  = h << 16
                value |= h << 8
                value |= h
                line.append(value)
            frame.append(line)
        video.append(frame)


    setup_dut(dut)
    yield Timer(CLK_PERIOD * 10)
    dut.rst <= 0

    dut.log.info("Ready")
    yield Timer(CLK_PERIOD * 10)

    control = 0x00
    control |= 1 << BIT_CONTROL_CHIP_SELECT
    control |= 1 << BIT_CONTROL_RESET_DISPLAY
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    control |= 1 << BIT_CONTROL_WRITE_OVERRIDE

    #Reset the LCD
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_RESET_DISPLAY)
    control &= ~(1 << BIT_CONTROL_WRITE_OVERRIDE)

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    #Set the pixel count
    yield axim.write(REG_PIXEL_COUNT, PIXEL_COUNT)
    yield Timer(CLK_PERIOD * 10)

    #Enable image write
    control = 0x00
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    #Write Video to the video controller
    yield video_out.write(video)

    yield Timer(CLK_PERIOD * 100)


@cocotb.test(skip = False)
def write_multiple_frames(dut):
    """
    Description:
        Send multiple images out of the controller
        This test will verify that the full images
        are successfully sent out and the process of restarting
        the next image transfer does not lead to an error

    Test ID: 3

    Expected Results:
        Should read images out of the controller
        *** NEED SOMETHING TO VERIFY THE IMAGES ARE CORRECT!!!***
    """

    NUM_FRAMES           = 4

    video = []
    for f in range (NUM_FRAMES):
        frame = []
        for v in range (HEIGHT):
            line = []
            for h in range(WIDTH):
                value  = h << 16
                value |= h << 8
                value |= h
                line.append(value)
            frame.append(line)
        video.append(frame)


    dut.rst <= 1
    dut.test_id <= 3
    axim = AXI4LiteMaster(dut, "AXIML", dut.clk)
    video_out = VideoOutBus(dut, "VIDEO",
                            dut.clk,
                            width = WIDTH,
                            height = HEIGHT,
                            hblank = H_BLANK,
                            vblank = V_BLANK)


    setup_dut(dut)
    yield Timer(CLK_PERIOD * 10)
    dut.rst <= 0

    dut.log.info("Ready")
    yield Timer(CLK_PERIOD * 10)

    control = 0x00
    control |= 1 << BIT_CONTROL_CHIP_SELECT
    control |= 1 << BIT_CONTROL_RESET_DISPLAY
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    control |= 1 << BIT_CONTROL_WRITE_OVERRIDE

    #Reset the LCD
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_RESET_DISPLAY)
    control &= ~(1 << BIT_CONTROL_WRITE_OVERRIDE)

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    #Set the pixel count
    yield axim.write(REG_PIXEL_COUNT, PIXEL_COUNT)
    yield Timer(CLK_PERIOD * 10)

    #Enable image write
    control = 0x00
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    #Write Video to the video controller
    yield video_out.write(video)

    yield Timer(CLK_PERIOD * 100)




@cocotb.test(skip = True)
def first_test(dut):
    """
    Description:
        Very Basic Functionality
            Startup Nysa

    Test ID: 0

    Expected Results:
        Write to all registers
    """
    WIDTH                = 8
    HEIGHT               = 4
    H_BLANK              = 40
    V_BLANK              = 200
    PIXEL_COUNT          = WIDTH * HEIGHT


    NUM_FRAMES           = 2

    video = []
    for f in range (NUM_FRAMES):
        frame = []
        for v in range (HEIGHT):
            line = []
            for h in range(WIDTH):
                value  = h << 16
                value |= h << 8
                value |= h
                line.append(value)
            frame.append(line)
        video.append(frame)



    dut.rst <= 1
    axim = AXI4LiteMaster(dut, "AXIML", dut.clk)
    video_out = VideoOutBus(dut, "VIDEO",
                            dut.clk,
                            width = WIDTH,
                            height = HEIGHT,
                            hblank = H_BLANK,
                            vblank = V_BLANK)

    setup_dut(dut)
    yield Timer(CLK_PERIOD * 10)
    dut.rst <= 0

    dut.log.info("Ready")
    yield Timer(CLK_PERIOD * 10)


    control = 0x00
    control |= 1 << BIT_CONTROL_CHIP_SELECT
    control |= 1 << BIT_CONTROL_RESET_DISPLAY
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    control |= 1 << BIT_CONTROL_WRITE_OVERRIDE

    #Reset the LCD
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_RESET_DISPLAY)
    control &= ~(1 << BIT_CONTROL_WRITE_OVERRIDE)

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    control &= ~(1 << BIT_CONTROL_CHIP_SELECT)


    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    control |= 1 << BIT_CONTROL_CHIP_SELECT





    ##################################################
    #Write a 0xAA55 to address 0xB8

    #First set up the correct mode
    control |= 1 << BIT_CONTROL_COMMAND_MODE
    control &= ~ (1 << BIT_CONTROL_COMMAND_PARAMETER)
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    #Set The Address to write to
    WRITE_ADDR = 0xB8
    yield axim.write(REG_COMMAND_DATA, WRITE_ADDR)
    yield Timer(CLK_PERIOD * 10)


    #Write the command
    control |= 1 << BIT_CONTROL_COMMAND_WRITE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)



    #Write a parameter
    WRITE_PARAMETER_1 = 0xAA # Arbitrary Address
    WRITE_PARAMETER_2 = 0x55

    # Write Parameter 1
    yield axim.write(REG_COMMAND_DATA, WRITE_PARAMETER_1)
    yield Timer(CLK_PERIOD * 10)


    control |= 1 << BIT_CONTROL_COMMAND_PARAMETER
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    # Write Parameter 2
    yield axim.write(REG_COMMAND_DATA, WRITE_PARAMETER_2)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_COMMAND_MODE)
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)





    ##################################################
    #Read two bytes from address 0xB8

    #   Set the address
    READ_ADDR = 0xB8

    control |= 1 << BIT_CONTROL_COMMAND_MODE
    control &= ~ (1 << BIT_CONTROL_COMMAND_PARAMETER)
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)

    #   Set address
    yield axim.write(REG_COMMAND_DATA, READ_ADDR)
    yield Timer(CLK_PERIOD * 10)

    control |= 1 << BIT_CONTROL_COMMAND_WRITE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    control &= ~(1 << BIT_CONTROL_COMMAND_WRITE)
    control |= 1 << BIT_CONTROL_COMMAND_PARAMETER
    control |= 1 << BIT_CONTROL_COMMAND_READ
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)


    data = yield axim.read(REG_COMMAND_DATA)
    yield Timer(CLK_PERIOD * 10)

    print "First Byte: 0x%02X" % data

    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)
    data = yield axim.read(REG_COMMAND_DATA)
    yield Timer(CLK_PERIOD * 10)

    print "Second Byte: 0x%02X" % data

    #Set the pixel count
    yield axim.write(REG_PIXEL_COUNT, PIXEL_COUNT)
    yield Timer(CLK_PERIOD * 10)



    #Enable image write
    control = 0x00
    control |= 1 << BIT_CONTROL_ENABLE
    control |= 1 << BIT_CONTROL_BACKLIGHT_ENABLE
    yield axim.write(REG_CONTROL, control)
    yield Timer(CLK_PERIOD * 10)



    #Stream the RGB Video (32 pixels), 4 rows of 8)
    #Write Video to the memodry controller
    yield video_out.write(video)

    yield Timer(CLK_PERIOD * 100)
    dut.log.info("Done")



