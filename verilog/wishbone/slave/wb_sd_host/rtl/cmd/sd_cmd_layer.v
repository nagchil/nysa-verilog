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
 * Author:
 * Description:
 *
 * Changes:
 */

`include "sd_host_stack_defines.v"

module sd_cmd_layer (
  input                     clk,
  input                     rst,

  output                    o_sd_ready,
  input                     i_crc_enable_flag,
  input                     i_card_detect,
  input       [15:0]        i_timeout,

  output  reg               o_error_flag,
  output  reg [7:0]         o_error,

  //User Command/Response Interface
  input                     i_cmd_en,
  output  reg               o_cmd_finished_en,

  input       [5:0]         i_cmd,
  input       [31:0]        i_cmd_arg,

  //Flags
  input                     i_rsp_type,
  output                    o_rsp_stb,
  output      [127:0]       o_rsp,

  //Interrupt From the Card
  output                    o_interrupt,

  //PHY Layer
  output  reg               o_phy_cmd_en ,
  output  reg [39:0]        o_phy_cmd,
  output      [7:0]         o_phy_cmd_len,

  input                     i_phy_rsp_finished_en,
  input       [135:0]       i_phy_rsp,
  output  reg [7:0]         o_phy_rsp_len,

  input                     i_phy_crc_bad
);
//local parameters
localparam    IDLE          = 4'h0;
localparam    WAIT_RESPONSE = 4'h1;
localparam    FINISHED      = 4'h2;

//registes/wires
reg           [3:0]         state;
//submodules
//asynchronous logic
assign                      o_phy_cmd_len   = 40;
assign                      o_rsp           = i_phy_rsp[127:0];
always @ (*) begin
  if (rst) begin
    o_phy_rsp_len               = 40;
  end
  else begin
    if (i_rsp_type == `RSP_TYPE_LONG) begin
      o_phy_rsp_len             = 136;
    end
    else begin
      o_phy_rsp_len             = 40;
    end
  end
end

//synchronous logic
always @ (posedge clk) begin
  //De-assert Strobes
  o_phy_cmd_en                  <= 0;

  if (rst) begin
    state                       <= IDLE;
    o_phy_cmd                   <= 0;
    o_error                     <= `ERROR_NO_ERROR;
    o_cmd_finished_en           <= 0;
  end
  else begin
    case (state)
      IDLE: begin
        o_phy_cmd_en            <=  0;
        o_cmd_finished_en       <=  0;
        o_error                 <= `ERROR_NO_ERROR;
        if (i_cmd_en) begin
          o_phy_cmd[39:38]      <= 2'b01;
          o_phy_cmd[37:32]      <= i_cmd;
          o_phy_cmd[31:0]       <= i_cmd_arg;
          o_phy_cmd_en          <= 1;
          state                 <= WAIT_RESPONSE;
        end
      end
      WAIT_RESPONSE: begin
        o_phy_cmd_en            <=  1;
        if (i_phy_rsp_finished_en) begin
          if (i_crc_enable_flag && i_phy_crc_bad) begin
            o_error             <= `ERROR_CRC_FAIL;
          end
          o_phy_cmd_en          <=  0;
          state                 <= FINISHED;
        end
      end
      FINISHED: begin
        o_cmd_finished_en       <=  1;
      end
      default: begin
      end
    endcase

    //Whenever the host de-asserts command enable go back to IDLE, this way we
    //Won't get stuck if something goes buggered
    if (!i_cmd_en) begin
      state                     <=  IDLE;
    end
  end
end

endmodule
