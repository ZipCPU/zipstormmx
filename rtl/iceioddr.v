////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	iceioddr.v
//
// Project:	ZipSTORM-MX, an iCE40 ZipCPU demonstration project
//
// Purpose:	
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2019, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype	none
//
module	iceioddr(i_clk, i_oe, i_data, o_data, io_pin);
	parameter	WIDTH = 1;
	input	wire			i_clk, i_oe;
	input	wire [2*WIDTH-1:0]	i_data;
	output	wire [2*WIDTH-1:0]	o_data;
	inout	wire [WIDTH-1:0]	io_pin;

	genvar	k;
	generate for(k=0; k<WIDTH; k=k+1)
	begin

		SB_IO	#(.PIN_TYPE(6'b1100_00))
		ioddr(
			.OUTPUT_CLK(i_clk),
			.INPUT_CLK(i_clk),
			.CLOCK_ENABLE(1'b1),
			.OUTPUT_ENABLE(i_oe),
			.D_OUT_0(i_data[WIDTH+k]),	// First data out
			.D_OUT_1(i_data[k]),
			.D_IN_0(o_data[WIDTH+k]),
			.D_IN_1(o_data[k]),
			.PACKAGE_PIN(io_pin[k]));
	end endgenerate

endmodule
