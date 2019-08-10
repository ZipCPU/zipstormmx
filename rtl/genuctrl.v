////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	genuctrl.v
//
// Project:	ZipSTORM-MX, an iCE40 ZipCPU demonstration project
//
// Purpose:	A generic microcontroller.  Accepts no real-time inputs,
//		produces only outputs.  Entirely configured by parameters
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
`default_nettype none
//
`ifdef	FORMAL
`ifdef	GENUCTRL
`define	LCLFORMAL
`endif
`endif
module	genuctrl(i_clk, i_reset, o_cmd);
	parameter	CMDWIDTH = 4;
	parameter	LGDELAY  = 6;
	parameter	LGNCMDS  = 3;
	localparam	NCMDS    = (1<<LGNCMDS);
	localparam	WORDWID  = ((LGDELAY > 0) ? 1:0)
			+ ((CMDWIDTH < LGDELAY) ? LGDELAY : CMDWIDTH);
	parameter [NCMDS*WORDWID-1:0]	COMMANDS = {
			//
			// { 1'b0, 2'b00, 4'h0 },
			{ 1'b0, 2'b00, 4'h3 },
			{ 1'b1, 6'h02 },
			{ 1'b0, 2'b00, 4'hb },
			{ 1'b0, 2'b00, 4'h3 },
			{ 1'b1, 6'h02 },
			{ 1'b0, 2'b00, 4'ha },
			{ 1'b1, 6'h2f },
			{ 1'b0, 2'b00, 4'h0f }
			};
	parameter [0:0]	OPT_REPEAT = 1'b1;
	localparam [WORDWID-1:0]	INITIAL_COMMAND = COMMANDS[WORDWID-1:0];
	localparam [0:0] OPT_DELAY = (LGDELAY > 0);
	//
	input	wire			i_clk, i_reset;
	output	reg	[CMDWIDTH-1:0]	o_cmd;

	reg			r_step;
	reg	[LGNCMDS-1:0]	r_addr;
	reg	[WORDWID-1:0]	r_cmd;

`ifdef	FORMAL
	reg	[LGNCMDS-1:0]	f_addr, f_cmd, f_active;
	reg	[WORDWID-1:0]	f_active_cmd, f_cmd_cmd, f_prior_cmd;
	reg	[LGNCMDS-1:0]	fn_cmd, fn_active;
	reg	f_past_valid;
`endif

	generate if (OPT_DELAY)
	begin : DELAY_COUNTER
		reg	[LGDELAY-1:0]	r_count;

		initial	r_step = COMMANDS[WORDWID-1]
					? (COMMANDS[LGDELAY-1:0]==0) : 1;
		always @(posedge i_clk)
		if(i_reset)
			r_step <= COMMANDS[WORDWID-1]
					? (COMMANDS[LGDELAY-1:0]==0) : 1;
		else if (r_step)
			r_step <= (!r_cmd[WORDWID-1])||(r_cmd[LGDELAY-1:0]==0);
		else // if (!r_step)
			r_step <= (r_count == 1);
		
		initial	r_count = (COMMANDS[WORDWID-1])
					? COMMANDS[LGDELAY-1:0] : 0;
		always @(posedge i_clk)
		if (i_reset)
			r_count <= (COMMANDS[WORDWID-1])
				? COMMANDS[LGDELAY-1:0] : 0;
		else if (r_step)
			r_count <= r_cmd[WORDWID-1] ? r_cmd[LGDELAY-1:0]:0;
		else
			r_count <= r_count - 1;

`ifdef	FORMAL
		always @(*)
			assert(r_step == (r_count == 0));
		always @(*)
		if (!f_active_cmd[WORDWID-1])
			assert(r_count == 0);
		else
			assert(r_count <= f_active_cmd[LGDELAY-1:0]);
`endif
	end else begin

		always @(*)
			r_step = 1'b1;

	end endgenerate

	initial	r_addr = 0;
	always @(posedge i_clk)
	if (i_reset)
		r_addr <= 0;
	else if (r_step && (OPT_REPEAT || !(&r_addr)))
		r_addr <= r_addr + 1;

	initial	r_cmd = INITIAL_COMMAND;
	always @(posedge i_clk)
	if (i_reset)
		r_cmd <= INITIAL_COMMAND;
	else if (r_step)
		r_cmd <= getcommand(r_addr);

	initial	o_cmd = INITIAL_COMMAND[CMDWIDTH-1:0];
	always @(posedge i_clk)
	if (i_reset && (!OPT_DELAY || !INITIAL_COMMAND[WORDWID-1]))
		o_cmd <= INITIAL_COMMAND[CMDWIDTH-1:0];
	else if (r_step && (!OPT_DELAY || !r_cmd[WORDWID-1]))
		o_cmd <= r_cmd[CMDWIDTH-1:0];

`ifdef	FORMAL
	always @(*)
		assert(!INITIAL_COMMAND[WORDWID-1]);
`endif

	function [WORDWID-1:0]	getcommand;
		input	[LGNCMDS-1:0]	i_addr;


		getcommand = COMMANDS[i_addr * WORDWID +: WORDWID];
	endfunction

`ifdef	FORMAL
	// reg	[LGNCMDS-1:0]	f_addr, f_cmd, f_active;

	always @(*)
		f_active_cmd = getcommand(f_active);

	always @(*)
		f_cmd_cmd = getcommand(f_cmd);

	always @(*)
		f_prior_cmd = getcommand(f_active-1);

	initial	f_past_valid = 0;
	always @(posedge i_clk)
		f_past_valid <= 1;

	always @(*)
		assert(f_addr == r_addr);

	always @(*)
		assert(r_cmd == getcommand(f_cmd));

	initial	{ f_active, f_cmd, f_addr } = 0;
	always @(posedge i_clk)
	if (i_reset)
		{ f_active, f_cmd, f_addr } <= 0;
	else if (r_step)
	begin
		if (OPT_REPEAT || !(&f_addr))
			f_addr <= f_addr + 1;
		{ f_active, f_cmd } <= { f_cmd, f_addr };
	end

	always @(*)
		fn_cmd = f_cmd + 1;
	always @(*)
		fn_active = f_active + 1;

	always @(*)
	if (!OPT_REPEAT)
	begin
		if (f_addr == 0)
		begin
			assert(f_cmd == 0);
			assert(f_active == 0);
		end else if (f_cmd == 0)
		begin
			assert(f_active == 0);
			assert(f_addr == 1);
		end else if (&f_active)
		begin
			assert(&f_cmd);
			assert(&f_addr);
		end else if (&f_cmd)
		begin
			assert(&f_addr);
			assert(f_active + 1 == f_cmd);
		end else begin
			assert(f_cmd + 1 == f_addr);
			assert(f_active + 1 == f_cmd);
		end
	end else begin
		if (f_active == f_cmd)
		begin
			assert(f_active == 0);
			assert(f_addr <= 1);
		end else begin
			assert(fn_cmd == f_addr);
			assert(fn_active == f_cmd);
		end
	end

	always @(*)
	if (!OPT_DELAY || !f_active_cmd[WORDWID-1])
		assert(o_cmd == f_active_cmd[CMDWIDTH-1:0]);
	else if ((f_active > 0)&&(!f_prior_cmd[WORDWID-1]))
		assert(o_cmd == f_prior_cmd[CMDWIDTH-1:0]);

`endif
endmodule
