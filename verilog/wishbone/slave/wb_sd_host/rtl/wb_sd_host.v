//wb_sd_host.v
/*
Distributed under the MIT license.
Copyright (c) 2015 Dave McCoy (dave.mccoy@cospandesign.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/*
  Set the Vendor ID (Hexidecimal 64-bit Number)
  SDB_VENDOR_ID:0x800000000000C594

  Set the Device ID (Hexcidecimal 32-bit Number)
  SDB_DEVICE_ID:0x800000000000C594

  Set the version of the Core XX.XXX.XXX Example: 01.000.000
  SDB_CORE_VERSION:00.000.001

  Set the Device Name: 19 UNICODE characters
  SDB_NAME:wb_sd_host

  Set the class of the device (16 bits) Set as 0
  SDB_ABI_CLASS:0

  Set the ABI Major Version: (8-bits)
  SDB_ABI_VERSION_MAJOR:0x23

  Set the ABI Minor Version (8-bits)
  SDB_ABI_VERSION_MINOR:1

  Set the Module URL (63 Unicode Characters)
  SDB_MODULE_URL:http://www.example.com

  Set the date of module YYYY/MM/DD
  SDB_DATE:2015/08/21

  Device is executable (True/False)
  SDB_EXECUTABLE:True

  Device is readable (True/False)
  SDB_READABLE:True

  Device is writeable (True/False)
  SDB_WRITEABLE:True

  Device Size: Number of Registers
  SDB_SIZE:3
*/


`define DEFAULT_MEM_0_BASE        32'h00000000
`define DEFAULT_MEM_1_BASE        32'h00100000


//control bit definition
`define CONTROL_ENABLE_SD                     0
`define CONTROL_ENABLE_INTERRUPT              1
`define CONTROL_ENABLE_DMA_WR                 2
`define CONTROL_ENABLE_DMA_RD                 3
//TODO Implement Finished transaction interrupt
`define CONTROL_ENABLE_SD_FIN_INT             4
`define CONTROL_DATA_WRITE_FLAG               5

//status bit definition
`define STATUS_MEMORY_0_FINISHED              0
`define STATUS_MEMORY_1_FINISHED              1
`define STATUS_MEMORY_0_EMPTY                 2
`define STATUS_MEMORY_1_EMPTY                 3
`define STATUS_ENABLE                         4
`define STATUS_SD_BUSY                        5
`define STATUS_SD_DATA_BUSY                   6
`define STATUS_ERROR_BIT_TOP                  31
`define STATUS_ERROR_BIT_BOT                  24

`define COMMAND_BIT_CMD_TOP                   6
`define COMMAND_BIT_CMD_BOT                   0

`define COMMAND_BIT_GO                        16
`define COMMAND_BIT_RSP_LONG_FLG              17
`define COMMAND_DATA_BIT_GO                   18

`define CONFIGURE_EN_CRC                      4

`define SD_ERROR_NO_ERROR                     0
`define SD_ERROR_TIMEOUT                      1
`define SD_ERROR_BAD_CRC                      2



module wb_sd_host #(
  parameter                 SD_MODE       = 1,
  parameter                 FOUR_BIT_DATA = 1,
  parameter                 DDR_EN        = 1,
  parameter                 BUFFER_DEPTH  = 11  //2048
)(
  input               clk,
  input               rst,

  //Add signals to control your device here

  //Wishbone Bus Signals
  input               i_wbs_we,
  input               i_wbs_cyc,
  input       [3:0]   i_wbs_sel,
  input       [31:0]  i_wbs_dat,
  input               i_wbs_stb,
  output  reg         o_wbs_ack,
  output  reg [31:0]  o_wbs_dat,
  input       [31:0]  i_wbs_adr,

  //master control signal for memory arbitration
  output              mem_o_we,
  output              mem_o_stb,
  output              mem_o_cyc,
  output      [3:0]   mem_o_sel,
  output      [31:0]  mem_o_adr,
  output      [31:0]  mem_o_dat,
  input       [31:0]  mem_i_dat,
  input               mem_i_ack,
  input               mem_i_int,


  //This interrupt can be controlled from this module or a submodule
  output              o_wbs_int,

  output              o_sd_clk,
  inout               io_sd_cmd,
  inout       [3:0]   io_sd_data
);

//Local Parameters
localparam          CONTROL             = 32'h00000000;
localparam          STATUS              = 32'h00000001;
localparam          REG_MEM_0_BASE      = 32'h00000002;
localparam          REG_MEM_0_SIZE      = 32'h00000003;
localparam          REG_MEM_1_BASE      = 32'h00000004;
localparam          REG_MEM_1_SIZE      = 32'h00000005;

localparam          SD_ARGUMENT         = 32'h00000006;
localparam          SD_COMMAND          = 32'h00000007;
localparam          SD_CONFIGURE        = 32'h00000008;
localparam          SD_RESPONSE0        = 32'h00000009;
localparam          SD_RESPONSE1        = 32'h0000000A;
localparam          SD_RESPONSE2        = 32'h0000000B;
localparam          SD_RESPONSE3        = 32'h0000000C;
localparam          SD_DATA_SIZE        = 32'h0000000D;

//Local Registers/Wires
reg         [31:0]      control         = 32'h00000000;
wire        [31:0]      status;

wire                    w_mem_write_enable;
wire                    w_mem_read_enable;
wire                    w_interrupt_enable;
reg                     w_int;

wire        [31:0]      w_mem_write_debug;
wire        [31:0]      w_mem_read_debug;

wire        [31:0]      w_default_mem_0_base;
wire        [31:0]      w_default_mem_1_base;

reg         [31:0]      r_memory_0_base;
reg         [31:0]      r_memory_0_size;
reg                     r_memory_0_ready;
reg                     r_memory_0_new_data;

reg         [31:0]      r_memory_1_base;
reg         [31:0]      r_memory_1_size;
reg                     r_memory_1_ready;
reg                     r_memory_1_new_data;


wire        [31:0]      w_p2m_0_count;
wire                    w_p2m_0_finished;
wire                    w_p2m_0_empty;

wire        [31:0]      w_p2m_1_count;
wire                    w_p2m_1_finished;
wire                    w_p2m_1_empty;

wire        [31:0]      w_m2p_0_count;
wire                    w_m2p_0_finished;
wire                    w_m2p_0_empty;

wire        [31:0]      w_m2p_1_count;
wire                    w_m2p_1_finished;
wire                    w_m2p_1_empty;

reg                     r_flush_memory;

wire                    w_write_finished;
wire                    w_memory_idle;

//SDIO Signals
wire                    w_sd_enable;

wire                    w_rfifo_ready;
wire                    w_rfifo_activate;
wire        [23:0]      w_rfifo_size;
wire                    w_rfifo_strobe;
wire        [31:0]      w_rfifo_data;

wire        [1:0]       w_wfifo_ready;
wire        [1:0]       w_wfifo_activate;
wire        [23:0]      w_wfifo_size;
wire                    w_wfifo_strobe;
wire        [31:0]      w_wfifo_data;

wire                    m2p_mem_o_we;
wire                    m2p_mem_o_stb;
wire                    m2p_mem_o_cyc;
wire        [3:0]       m2p_mem_o_sel;
wire        [31:0]      m2p_mem_o_adr;
wire        [31:0]      m2p_mem_o_dat;

wire                    p2m_mem_o_we;
wire                    p2m_mem_o_stb;
wire                    p2m_mem_o_cyc;
wire        [3:0]       p2m_mem_o_sel;
wire        [31:0]      p2m_mem_o_adr;
wire        [31:0]      p2m_mem_o_dat;


//Submodules
wire                    sd_ready;
reg         [15:0]      sd_timeout;
wire                    sd_card_detect;

reg                     sd_cmd_en;
wire                    sd_cmd_finished_en;
reg         [5:0]       sd_cmd;
reg         [31:0]      sd_cmd_arg;

reg                     sd_cmd_rsp_long_flag;

wire        [7:0]       sd_error;
wire        [127:0]     sd_rsp;
reg                     enable_crc;


reg                     ddr_en_flag;
reg                     sd1_phy_flag;
reg                     sd4_phy_flag;
wire                    pll_locked;

wire                    sd_cmd_dir;
wire                    sd_cmd_in;
wire                    sd_cmd_out;

wire                    sd_data_dir;
wire        [7:0]       sd_data_out;
wire        [7:0]       sd_data_in;

//Data Interface
reg                     data_txrx_en;
wire                    data_write_flag;
reg         [23:0]      data_size;
wire                    data_txrx_finished;

//Possibly replace with a generate statement using an input parameter
`ifdef COCOTB_SIMULATION
sd_host_platform_cocotb cocotb_platform(
  .clk                  (clk                      ),
  .rst                  (rst                      ),

  //Stack Interface
  .o_locked             (pll_locked               ),
  .o_out_clk            (sd_clk                   ),
  .o_out_clk_x2         (sd_clk_x2                ),

  .i_sd_cmd_dir         (sd_cmd_dir               ),
  .o_sd_cmd_in          (sd_cmd_in                ),
  .i_sd_cmd_out         (sd_cmd_out               ),

  .i_sd_data_dir        (sd_data_dir              ),
  .i_sd_data_out        (sd_data_out              ),
  .o_sd_data_in         (sd_data_in               ),

  //Physical Signals
  .o_phy_out_clk        (o_sd_clk                 ),
  .io_phy_sd_cmd        (io_sd_cmd                ),
  .io_phy_sd_data       (io_sd_data               )

);
`else
`endif

sd_host_stack #(
  .SD_MODE              (SD_MODE                  ),
  .FOUR_BIT_DATA        (FOUR_BIT_DATA            ),
  .DDR_EN               (DDR_EN                   ),
  .BUFFER_DEPTH         (BUFFER_DEPTH             )
)sd_stack(
  .clk                  (clk                      ),
  .rst                  (rst                      ),

  //Control/Status/Error
  .o_sd_ready           (sd_ready                 ),
  .i_card_detect        (sd_card_detect           ),
  .i_timeout            (sd_timeout               ),

  .o_error_flag         (sd_error_flag            ),  //If an SD Error occured this flag
                                                      // will be high when sd_cmd_ack_stb goes high
  .o_error              (sd_error                 ),  //If Error flag is high when sd_cmd_ack_stb
                                                      // this is strobed, this is the error code

  //Command/Response Interface
  .i_cmd_en             (sd_cmd_en                ),
  .o_cmd_finished_en    (sd_cmd_finished_en       ),

  .i_cmd                (sd_cmd                   ),
  .i_cmd_arg            (sd_cmd_arg               ),
  .i_rsp_long_flag      (sd_rsp_long_flag         ),
  .o_rsp                (sd_rsp                   ),

  //Data Interface
  .i_data_txrx          (data_txrx_en             ),
  .i_data_write_flag    (data_write_flag          ),
  .i_data_size          (data_size                ),
  .o_data_txrx_finished (data_txrx_finished       ),

  //Data From Host to SD Interface
  .o_h2s_wfifo_ready    (w_wfifo_ready            ),
  .i_h2s_wfifo_activate (w_wfifo_activate         ),
  .o_h2s_wfifo_size     (w_wfifo_size             ),
  .i_h2s_wfifo_stb      (w_wfifo_strobe           ),
  .i_h2s_wfifo_data     (w_wfifo_data             ),

  //Data From SD to Host Interface
  .o_s2h_rfifo_ready    (w_rfifo_ready            ),
  .i_s2h_rfifo_activate (w_rfifo_activate         ),
  .o_s2h_rfifo_size     (w_rfifo_size             ),
  .i_s2h_rfifo_stb      (w_rfifo_strobe           ),
  .o_s2h_rfifo_data     (w_rfifo_data             ),

  //Interrupt
  .o_interrupt          (sd_host_interrupt        ),


  //Phy Interface
  .i_sd_pll_locked      (pll_locked               ),
  .i_sd_clk             (sd_clk                   ),
  .i_sd_clk_x2          (sd_clk_x2                ),

  .o_sd_cmd_dir         (sd_cmd_dir               ),
  .i_sd_cmd             (sd_cmd_in                ),
  .o_sd_cmd             (sd_cmd_out               ),

  .o_sd_data_dir        (sd_data_dir              ),
  .i_sd_data            (sd_data_in               ),
  .o_sd_data            (sd_data_out              )
);


wb_ppfifo_2_mem p2m(

  .clk                  (clk                      ),
  .rst                  (rst                      ),
  .debug                (w_mem_read_debug         ),

  //Control
  .i_enable             (w_mem_read_enable       ),
  .i_flush              (r_flush_memory           ),

  .i_memory_0_base      (r_memory_0_base          ),
  .i_memory_0_size      (r_memory_0_size          ),
  .i_memory_0_ready     (r_memory_0_ready         ),
  .o_memory_0_count     (w_p2m_0_count            ),
  .o_memory_0_finished  (w_p2m_0_finished         ),
  .o_memory_0_empty     (w_p2m_0_empty            ),

  .o_default_mem_0_base (w_default_mem_0_base     ),

  .i_memory_1_base      (r_memory_1_base          ),
  .i_memory_1_size      (r_memory_1_size          ),
  .i_memory_1_ready     (r_memory_1_ready         ),
  .o_memory_1_count     (w_p2m_1_count            ),
  .o_memory_1_finished  (w_p2m_1_finished         ),
  .o_memory_1_empty     (w_p2m_1_empty            ),

  .o_default_mem_1_base (w_default_mem_1_base     ),

  .o_write_finished     (w_write_finished         ),

  //master control signal for memory arbitration
  .o_mem_we             (p2m_mem_o_we             ),
  .o_mem_stb            (p2m_mem_o_stb            ),
  .o_mem_cyc            (p2m_mem_o_cyc            ),
  .o_mem_sel            (p2m_mem_o_sel            ),
  .o_mem_adr            (p2m_mem_o_adr            ),
  .o_mem_dat            (p2m_mem_o_dat            ),
  .i_mem_dat            (mem_i_dat                ),
  .i_mem_ack            (mem_i_ack                ),
  .i_mem_int            (mem_i_int                ),

  //Ping Pong FIFO Interface (Read)
  .i_ppfifo_rdy         (w_rfifo_ready            ),
  .o_ppfifo_act         (w_rfifo_activate         ),
  .i_ppfifo_size        (w_rfifo_size             ),
  .o_ppfifo_stb         (w_rfifo_strobe           ),
  .i_ppfifo_data        (w_rfifo_data             )
);


wb_mem_2_ppfifo m2p(

  .clk                  (clk                      ),
  .rst                  (rst                      ),
  .debug                (w_mem_write_debug        ),

  //Control
  .i_enable             (w_mem_write_enable       ),

  .i_memory_0_base      (r_memory_0_base          ),
  .i_memory_0_size      (r_memory_0_size          ),
  .i_memory_0_new_data  (r_memory_0_new_data      ),
  .o_memory_0_count     (w_m2p_0_count            ),
  .o_memory_0_empty     (w_m2p_0_empty            ),

  .o_default_mem_0_base (w_default_mem_0_base     ),

  .i_memory_1_base      (r_memory_1_base          ),
  .i_memory_1_size      (r_memory_1_size          ),
  .i_memory_1_new_data  (r_memory_1_new_data      ),
  .o_memory_1_count     (w_m2p_1_count            ),
  .o_memory_1_empty     (w_m2p_1_empty            ),

  .o_default_mem_1_base (w_default_mem_1_base     ),

  .o_read_finished      (w_read_finished          ),

  //master control signal for memory arbitration
  .o_mem_we             (m2p_mem_o_we             ),
  .o_mem_stb            (m2p_mem_o_stb            ),
  .o_mem_cyc            (m2p_mem_o_cyc            ),
  .o_mem_sel            (m2p_mem_o_sel            ),
  .o_mem_adr            (m2p_mem_o_adr            ),
  .o_mem_dat            (m2p_mem_o_dat            ),
  .i_mem_dat            (mem_i_dat                ),
  .i_mem_ack            (mem_i_ack                ),
  .i_mem_int            (mem_i_int                ),

  //Ping Pong FIFO Interface
  .i_ppfifo_rdy         (w_wfifo_ready            ),
  .o_ppfifo_act         (w_wfifo_activate         ),
  .i_ppfifo_size        (w_wfifo_size             ),
  .o_ppfifo_stb         (w_wfifo_strobe           ),
  .o_ppfifo_data        (w_wfifo_data             )
);

//Asynchronous Logic
assign  w_sd_enable           = control[`CONTROL_ENABLE_SD        ];
assign  w_interrupt_enable    = control[`CONTROL_ENABLE_INTERRUPT ];
assign  w_mem_write_enable    = control[`CONTROL_ENABLE_DMA_WR    ];
assign  w_mem_read_enable     = control[`CONTROL_ENABLE_DMA_RD    ];
assign  data_write_flag       = control[`CONTROL_DATA_WRITE_FLAG  ];


assign  status[`STATUS_MEMORY_0_FINISHED] = w_mem_write_enable ? w_p2m_0_finished :
                                            1'b0;

assign  status[`STATUS_MEMORY_1_FINISHED] = w_mem_write_enable ? w_p2m_1_finished :
                                            1'b0;
assign  status[`STATUS_ENABLE]            = w_sd_enable;
assign  status[`STATUS_MEMORY_0_EMPTY]    = w_mem_write_enable ? w_p2m_0_empty    :
                                            w_mem_read_enable  ? w_m2p_0_empty    :
                                            1'b0;
assign  status[`STATUS_MEMORY_1_EMPTY]    = w_mem_write_enable ? w_p2m_1_empty    :
                                            w_mem_read_enable  ? w_m2p_1_empty    :
                                            1'b0;
assign  status[`STATUS_SD_BUSY]           = sd_cmd_en;


assign  status[`STATUS_ERROR_BIT_TOP:`STATUS_ERROR_BIT_BOT] = sd_error;

assign  o_wbs_int                         = w_interrupt_enable ? w_int : 1'b0;
assign  mem_o_we                          = w_mem_write_enable ? m2p_mem_o_we :
                                            w_mem_read_enable  ? p2m_mem_o_we :
                                            1'b0;
assign  mem_o_stb                         = w_mem_write_enable ? m2p_mem_o_stb :
                                            w_mem_read_enable  ? p2m_mem_o_stb :
                                            1'b0;
assign  mem_o_cyc                         = w_mem_write_enable ? m2p_mem_o_cyc :
                                            w_mem_read_enable  ? p2m_mem_o_cyc :
                                            1'b0;
assign  mem_o_sel                         = w_mem_write_enable ? m2p_mem_o_sel :
                                            w_mem_read_enable  ? p2m_mem_o_sel :
                                            4'b0000;
assign  mem_o_adr                         = w_mem_write_enable ? m2p_mem_o_adr :
                                            w_mem_read_enable  ? p2m_mem_o_adr :
                                            31'h00000000;
assign  mem_o_dat                         = w_mem_write_enable ? m2p_mem_o_dat :
                                            w_mem_read_enable  ? p2m_mem_o_dat :
                                            4'b0000;


//Synchronous Logic

always @ (posedge clk) begin

  if (rst) begin
    o_wbs_dat             <= 32'h0;
    o_wbs_ack             <= 0;
    sd_cmd_en             <= 0;
    sd_cmd                <= 6'h0;
    sd_cmd_arg            <= 32'h0;
    sd_cmd_rsp_long_flag  <= 1'b0;
    enable_crc            <= 1'b1;
    data_txrx_en          <= 1'b0;
    data_size             <= 0;


    r_memory_0_base       <= 0;
    r_memory_0_size       <= 0;
    r_memory_0_ready      <= 0;
    r_memory_0_new_data   <= 0;
                          
    r_memory_1_base       <= 0;
    r_memory_1_size       <= 0;
    r_memory_1_ready      <= 0;
    r_memory_1_new_data   <= 0;


  end
  else begin
    r_memory_0_new_data <=  0;
    r_memory_1_new_data <=  0;
    r_memory_0_ready    <=  0;
    r_memory_1_ready    <=  0;


    //when the master acks our ack, then put our ack down
    if (o_wbs_ack && ~i_wbs_stb)begin
      o_wbs_ack <= 0;
    end

    if (i_wbs_stb && i_wbs_cyc) begin
      //master is requesting somethign
      if (!o_wbs_ack) begin
        if (i_wbs_we) begin
          //write request
          case (i_wbs_adr)
            CONTROL: begin
              $display("ADDR: %h user wrote %h", i_wbs_adr, i_wbs_dat);
              control               <=  i_wbs_dat;
            end
            STATUS: begin
              $display("ADDR: %h user wrote %h", i_wbs_adr, i_wbs_dat);
            end
            REG_MEM_0_BASE: begin
              r_memory_0_base       <=  i_wbs_dat;
            end
            REG_MEM_0_SIZE: begin
              r_memory_0_size       <=  i_wbs_dat;
              if (i_wbs_dat > 0) begin
                if (w_mem_write_enable) begin
                  r_memory_0_new_data <=  1;
                end
                else if (w_mem_read_enable) begin
                  r_memory_0_ready    <=  1;
                end
              end
            end
            REG_MEM_1_BASE: begin
              r_memory_1_base       <=  i_wbs_dat;
            end
            REG_MEM_1_SIZE: begin
              r_memory_1_size       <=  i_wbs_dat;
              if (i_wbs_dat > 0) begin
                if (w_mem_write_enable) begin
                  r_memory_1_new_data <=  1;
                end
                else if (w_mem_read_enable) begin
                  r_memory_1_ready    <=  1;
                end
              end
            end
            SD_ARGUMENT: begin
              sd_cmd_arg            <=  i_wbs_dat;
            end
            SD_COMMAND: begin
              sd_cmd_en             <=  i_wbs_dat[`COMMAND_BIT_GO];
              sd_cmd_rsp_long_flag  <=  i_wbs_dat[`COMMAND_BIT_RSP_LONG_FLG];
              sd_cmd                <=  i_wbs_dat[`COMMAND_BIT_CMD_TOP:`COMMAND_BIT_CMD_BOT];
              data_txrx_en          <=  i_wbs_dat[`COMMAND_DATA_BIT_GO];
            end
            SD_CONFIGURE: begin
              enable_crc            <=  i_wbs_dat[`CONFIGURE_EN_CRC];
            end
            SD_DATA_SIZE: begin
              data_size             <=  i_wbs_dat[23:0];
            end
            default: begin
            end
          endcase
        end
        else begin
          //read request
          case (i_wbs_adr)
            CONTROL: begin
              $display("user read %h", CONTROL);
              o_wbs_dat           <= control;
            end
            STATUS: begin
              //o_wbs_dat           <= status;
              o_wbs_dat             <=  0;
              o_wbs_dat[`STATUS_MEMORY_0_FINISHED] <= w_mem_write_enable ? w_p2m_0_finished : 1'b0;
              o_wbs_dat[`STATUS_MEMORY_1_FINISHED] <= w_mem_write_enable ? w_p2m_1_finished : 1'b0;
              o_wbs_dat[`STATUS_ENABLE]            <= w_sd_enable;
              o_wbs_dat[`STATUS_MEMORY_0_EMPTY]    <= w_mem_write_enable ? w_p2m_0_empty    :
                                                      w_mem_read_enable  ? w_m2p_0_empty    :
                                                      1'b0;
              o_wbs_dat[`STATUS_MEMORY_1_EMPTY]    <= w_mem_write_enable ? w_p2m_1_empty    :
                                                      w_mem_read_enable  ? w_m2p_1_empty    :
                                                      1'b0;
              o_wbs_dat[`STATUS_SD_BUSY]                              <= sd_cmd_en;
              o_wbs_dat[`STATUS_ERROR_BIT_TOP:`STATUS_ERROR_BIT_BOT]  <= sd_error;
              o_wbs_dat[`STATUS_SD_DATA_BUSY]                         <= data_txrx_en;
              if (w_m2p_0_finished) begin
                $display ("Reset size 0");
                r_memory_0_size   <=  0;
              end
              if (w_m2p_1_finished) begin
                $display ("Reset size 1");
                r_memory_1_size   <=  0;
              end
            end
            REG_MEM_0_BASE: begin
              o_wbs_dat <=  r_memory_0_base;
            end
            REG_MEM_0_SIZE: begin
              if (w_mem_read_enable) begin
                o_wbs_dat <=  w_m2p_0_count;
              end
              else if (w_mem_write_enable) begin
                o_wbs_dat <=  w_p2m_0_count;
              end
              else begin
                o_wbs_dat <=  r_memory_0_size;
              end
            end
            REG_MEM_1_BASE: begin
              o_wbs_dat <=  r_memory_1_base;
            end
            REG_MEM_1_SIZE: begin
              if (w_mem_read_enable) begin
                o_wbs_dat <=  w_m2p_1_count;
              end
              else if (w_mem_write_enable) begin
                o_wbs_dat <=  w_p2m_1_count;
              end
              else begin
                o_wbs_dat <=  r_memory_1_size;
              end
            end
            SD_RESPONSE0: begin
              o_wbs_dat   <=  sd_rsp[127:96];
            end
            SD_RESPONSE1: begin
              o_wbs_dat   <=  sd_rsp[95:64];
            end
            SD_RESPONSE2: begin
              o_wbs_dat   <=  sd_rsp[63:32];
            end
            SD_RESPONSE3: begin
              o_wbs_dat   <=  sd_rsp[31:0];
            end
            SD_DATA_SIZE: begin
              o_wbs_dat   <=  {8'h00, data_size};
            end
            default: begin
              o_wbs_dat <=  32'h00;
            end
          endcase
        end
        o_wbs_ack <= 1;
      end
    end

    //Stack Says We're finished so put down our enable/busy signal
    if (sd_cmd_finished_en) begin
      sd_cmd_en   <=  0;
    end
    if (data_txrx_finished) begin
      data_txrx_en  <=  0;
    end
  end
end

//initerrupt controller
always @ (posedge clk) begin
  if (rst) begin
    w_int <=  0;
  end
  //Memory Read Interface
  else if (w_mem_read_enable) begin
    if (!w_m2p_0_empty && !w_m2p_1_empty) begin
      w_int <=  0;
    end
    if (i_wbs_stb) begin
      //de-assert the interrupt on wbs transactions so I can launch another
      //interrupt when the wbs is de-asserted
      w_int <=  0;
    end
    else if (w_m2p_0_empty || w_m2p_1_empty) begin
      w_int <=  1;
    end
  end
  //Write Memory Controller
  else if (w_mem_write_enable) begin
    if (i_wbs_stb) begin
      w_int         <=  0;
    end
    else if (w_p2m_0_finished || w_p2m_1_finished) begin
      w_int         <=  1;
    end
    else if (!w_p2m_0_finished && !w_p2m_1_finished) begin
      w_int         <=  0;
    end
  end
  else begin
    //if we're not enable de-assert interrupt
    w_int <=  0;
  end
end


endmodule