////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	wbsdram.v
//
// Project:	ZipSTORM-MX, an iCE40 ZipCPU demonstration project
//
// Purpose:	Provide 32-bit wishbone access to the SDRAM memory on a XuLA2
//		LX-25 board.  Specifically, on each access, the controller will
//	activate an appropriate bank of RAM (the SDRAM has four banks), and
//	then issue the read/write command.  In the case of walking off the
//	bank, the controller will activate the next bank before you get to it.
//	Upon concluding any wishbone access, all banks will be precharged and
//	returned to idle.
//
//	This particular implementation represents a second generation version
//	because my first version was too complex.  To speed things up, this
//	version includes an extra wait state where the wishbone inputs are
//	clocked into a flip flop before any action is taken on them.
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
`define	DMOD_GETINPUT	1'b0
`define	DMOD_PUTOUTPUT	1'b1
`define	RAM_OPERATIONAL	2'b00
`define	RAM_POWER_UP	2'b01
`define	RAM_SET_MODE	2'b10
`define	RAM_INITIAL_REFRESH	2'b11
//
module	wbsdram(i_clk,
		i_wb_cyc, i_wb_stb, i_wb_we, i_wb_addr, i_wb_data, i_wb_sel,
			o_wb_ack, o_wb_stall, o_wb_data,
		o_ram_cs_n, o_ram_cke, o_ram_ras_n, o_ram_cas_n, o_ram_we_n,
			o_ram_addr, o_ram_dmod,
			i_ram_data, o_ram_data, o_ram_dqm,
		o_debug,
		o_refresh_counts);
	parameter [31:0]	CLOCK_FREQUENCY_HZ = 32'd50_000_000;
	parameter [0:0]	OPT_FWD_ADDRESS = 1'b0;
	localparam	AW=21-2, DW=32;
	input	wire			i_clk;
	// Wishbone
	//	inputs
	input	wire			i_wb_cyc, i_wb_stb, i_wb_we;
	input	wire	[(AW-1):0]	i_wb_addr;
	input	wire	[(DW-1):0]	i_wb_data;
	input	wire	[(DW/8-1):0]	i_wb_sel;
	//	outputs
	output	wire		o_wb_ack;
	output	reg		o_wb_stall;
	output	reg [DW-1:0]	o_wb_data;
	// SDRAM control
	output	wire		o_ram_cs_n, o_ram_cke,
				o_ram_ras_n, o_ram_cas_n, o_ram_we_n;
	output	reg	[11:0]	o_ram_addr;
	output	reg		o_ram_dmod;
	input		[15:0]	i_ram_data;
	output	reg	[15:0]	o_ram_data;
	output	reg	[1:0]	o_ram_dqm;
	//
	output	wire [(DW-1):0]	o_debug;
	output	reg [(DW-1):0]	o_refresh_counts;

	reg	[31:0]	r_refresh_counts;
	always @(posedge i_clk)
	if (o_cmd == CMD_REFRESH)
		r_refresh_counts <= 0;
	else if (!(&r_refresh_counts))
		r_refresh_counts <= r_refresh_counts + 1;

	initial	o_refresh_counts = 0;
	always @(posedge i_clk)
	if (o_cmd == CMD_REFRESH)
		o_refresh_counts <= r_refresh_counts;
	else if (&r_refresh_counts)
		o_refresh_counts <= r_refresh_counts;

	/*
	reg		need_refresh;
	reg	[9:0]	refresh_clk;
	wire		refresh_cmd;
	reg		in_refresh;
	reg	[2:0]	in_refresh_clk;
	*/


	//
	// Commands
	//
	localparam [3:0]	CMD_SET_MODE  = 4'h0;
	localparam [3:0]	CMD_REFRESH   = 4'h1;
	localparam [3:0]	CMD_PRECHARGE = 4'h2;
	localparam [3:0]	CMD_ACTIVATE  = 4'h3;
	localparam [3:0]	CMD_WRITE     = 4'h4;
	localparam [3:0]	CMD_READ      = 4'h5;
	localparam [3:0]	CMD_NOOP      = 4'h7;

	// Calculate some metrics

	//
	// CK_REFRESH is the number of clocks between refresh cycles
	//   Here we calculate it for 2048 refresh cycles every 32ms
	//   This is consistent with speed grade A1, and should come
	//   out to about 780 cycles between refreshes for a 50MHz clock
	localparam	CK_REFRESH = ((CLOCK_FREQUENCY_HZ/1000) * 16 / 2048)-1;
`ifdef	CONSERVATIVE_TIMING
	// CAS_LATENCY is the clocks between the (read) command and the read
	// data.  There must be at least one idle cycle between write data
	// and read data.
	localparam	CAS_LATENCY = 3;	// tCAC
	localparam	ACTIVE_TO_RW = 3,	// tRCD
				CK_RCD = ACTIVE_TO_RW;
	localparam	CK_RC  = 9;	// Command period, REF to REF/ACT to ACT
	localparam	CK_RAS = 6; // Cmd period, ACT to PRE
	localparam	RAS_LATENCY = CK_RAS;
	localparam	CK_RP  = 3; // Cmd period, PRE to ACT
`else
	// CAS_LATENCY is the clocks between the (read) command and the read
	// data.  There must be at least one idle cycle between write data
	// and read data.
	localparam	CAS_LATENCY = 2;	// tCAC
	localparam	ACTIVE_TO_RW = 4,	// tRCD
				CK_RCD = ACTIVE_TO_RW;
	localparam	RAS_LATENCY = 4;
	localparam	CK_RC  = 6;	// Command period, REF to REF/ACT to ACT
	localparam	CK_RAS = 4; // Cmd period, ACT to PRE
	localparam	CK_RP  = 2; // Cmd period, PRE to ACT
`endif
	localparam	CK_RRD = 2; // Cmd period, ACT[0] to ACT[1]
	// localparam	CK_CCD = 1; // Column cmd delay time
	localparam	CK_DPL = 2; // Input data to precharge time
	localparam	CK_DAL = 2+CK_RP; // Input data to active/refresh cmd dly time
	// localparam	CK_RBD = 3;// Burst stop cmd to output high z
	// localparam	CK_WBD = 0;// Burst stop cmd to input invalid dly tim
	localparam	CK_RQL = 3; // Precharge cmd to out in High Z time
	//localparam	CK_PQL =-2; // Last out to auto-precharge start time(rd)
	localparam	CK_QMD = 2; // DQM to output delay time (read)
	localparam	CK_MCD = 2; // Precharge cmd to out in High Z time
	//
	parameter	RDLY = CAS_LATENCY + 4;

	//
	// Register declarations
	//
	reg	[CK_RCD:0]	bank_active	[0:1];
	reg	[(RDLY-1):0]	r_barrell_ack;
	reg			r_pending, issued;
	reg			r_we;
	reg	[AW-1:0]	r_addr;
	reg	[DW-1:0]	r_data;
	reg	[DW/8-1:0]	r_sel;
	reg	[1:0]		nxt_sel;

	reg	[10:0]	bank_row	[0:1];
	reg		i_bank, r_bank, fwd_bank;
	reg	[7:0]	i_col,  r_col;
	reg	[10:0]	i_row,  r_row,  fwd_row;

	reg	[2:0]		clocks_til_idle;
	wire			bus_cyc;
	reg			nxt_dmod;
	wire			pending;
	reg	[AW-1:0]	fwd_addr;
	reg	[3:0]		o_cmd;

	////////////////////////////////////////////////////////////////////////
	//
	// Refresh logic
	//
	////////////////////////////////////////////////////////////////////////
	//
	//

	//
	// First, do we *need* a refresh now --- i.e., must we break out of
	// whatever we are doing to issue a refresh command?
	//
	// The step size here must be such that 8192 charges may be done in
	// 64 ms.  Thus for a clock of:
	//	ClkRate(MHz)	(64ms/1000(ms/s)*ClkRate)/8192
	//	100 MHz		781
	//	 96 MHz		750
	//	 92 MHz		718
	//	 88 MHz		687
	//	 84 MHz		656
	//	 80 MHz		625
	//
	// However, since we do two refresh cycles everytime we need a refresh,
	// this standard is close to overkill--but we'll use it anyway.  At
	// some later time we should address this, once we are entirely
	// convinced that the memory is otherwise working without failure.  Of
	// course, at that time, it may no longer be a priority ...
	//

	// assign	refresh_cmd = (!o_ram_cs_n)&&(!o_ram_ras_n)&&(!o_ram_cas_n)&&(o_ram_we_n);
	// initial	in_refresh = 0;

	//
	// Second, do we *need* a precharge now --- must be break out of
	// whatever we are doing to issue a precharge command?
	//
	// Keep in mind, the number of clocks to wait has to be reduced by
	// the amount of time it may take us to go into a precharge state.
	// You may also notice that the precharge requirement is tighter
	// than this one, so ... perhaps this isn't as required?
	//

	assign	bus_cyc  = ((i_wb_cyc)&&(i_wb_stb)&&(!o_wb_stall));

	always @(*)
	begin
		issued = 0;
		if (!nxt_dmod && !refresh_stall
			&& r_bank_valid && &bank_active[r_bank][CK_RCD:1])
		begin
			if (r_we)
				issued = (clocks_til_idle <= 1);
			else
				issued = (clocks_til_idle < 5);
		end
		if (maintenance_mode || !r_pending || !i_wb_cyc)
			issued = 1'b0;
	end

	// Pre-process pending operations
	initial	r_pending = 1'b0;
	initial	r_addr = 0;
	//
	// The following statement is required to complete the formal proof,
	// although not really required in practice.  Yosys/nextpnr have
	// struggled to synthesize it.  It can be removed if necessary with no
	// other consequence other than the formal proof failing, since fwd_addr
	// is always set at the beginning of any bus cycle--so it will be set
	// before it ever gets used.
	initial fwd_addr = 12;
	always @(posedge i_clk)
	if (bus_cyc)
	begin
		r_pending <= 1'b1;
		r_we      <= i_wb_we;
		r_addr    <= i_wb_addr;
		r_data    <= i_wb_data;
		r_sel     <= i_wb_sel;
		fwd_addr  <= i_wb_addr + { {(AW-4){1'b0}}, 2'b11, 2'b00 };
`ifdef	BROKEN_CODE
	end else begin
		if (issued)
			r_pending <= 1'b0;
		if (!i_wb_cyc)
			{ r_pending, r_addr, r_data } = 0;
	end
`else
	end else if (issued)
		r_pending <= 1'b0;
	else if (!i_wb_cyc)
		r_pending <= 1'b0;
`endif

	always @(*)
	begin
		i_row  = i_wb_addr[AW-1:8];	// 18:8
		i_bank = i_wb_addr[7];
		i_col  = { i_wb_addr[6:0], 1'b0 };

		r_row  = r_addr[AW-1:8];	// 18:8
		r_bank = r_addr[7];
		r_col  = { r_addr[6:0], 1'b0 };

		fwd_row = fwd_addr[AW-1:8];
		fwd_bank= fwd_addr[7];
	end

`ifdef	FORMAL
	always @(*)
		assert(fwd_addr == r_addr + { {(AW-4){1'b0}}, 2'b11, 2'b00 });
`endif

	reg	r_bank_valid;
	reg	fwd_bank_valid;

	always @(posedge i_clk)
	if (bus_cyc)
		r_bank_valid <=((bank_active[i_bank][CK_RCD])
			&&(bank_row[i_bank]==i_row));
	else
		r_bank_valid <= ((bank_active[r_bank][CK_RCD])
				&&(bank_row[r_bank]==r_row));


	initial	fwd_bank_valid = 0;
	always @(posedge i_clk)
		fwd_bank_valid <= ((bank_active[fwd_bank][CK_RCD])
				&&(bank_row[fwd_bank]==fwd_row));

	assign	pending = (r_pending)&&(o_wb_stall);

	//
	//
	// Maintenance mode (i.e. startup) wires and logic
	reg		maintenance_mode;
	// reg	m_ram_cs_n, m_ram_ras_n, m_ram_cas_n, m_ram_we_n, m_ram_dmod;
	reg	[3:0]	maintenance_cmd;
	reg	[11:0]	maintenance_addr;
	wire	[3:0]	refresh_cmd, reset_command;
	wire		reset_active, reset_addr10;
	wire		refresh_active, refresh_stall;
	//
	//
	//

`ifdef	FORMAL
	(* keep *)	reg	[39:0]	f_dbg_command;
	initial	f_dbg_command = "START";
	always @(posedge i_clk)
	if (f_dbg_command == 0)
		assert(reset_active);
`endif
	// Address MAP:
	//	23-bits bits in, 24-bits out
	//
	//	222 1111 1111 1100 0000 0000
	//	210 9876 5432 1098 7654 3210
	//	rrr rrrr rrrr rrBB cccc cccc 0
	//	                   8765 4321 0
	//
	initial r_barrell_ack = 0;
	initial	clocks_til_idle = 3'h0;
	initial o_wb_stall = 1'b1;
	initial	o_cmd = CMD_NOOP;
	// initial o_ram_cs_n  = 1'b0;
	// initial o_ram_ras_n = 1'b1;
	// initial o_ram_cas_n = 1'b1;
	// initial o_ram_we_n  = 1'b1;
	initial	o_ram_dqm   = 2'b11;
	assign	o_ram_cke   = 1'b1;
	initial bank_active[0] = 0;
	initial bank_active[1] = 0;
	always @(posedge i_clk)
	if (maintenance_mode)
	begin
		bank_active[0] <= 0;
		bank_active[1] <= 0;
		r_barrell_ack[(RDLY-1):0] <= (r_barrell_ack >> 1);
		if (!i_wb_cyc)
			r_barrell_ack <= 0;
		o_wb_stall  <= 1'b1;
		//
		o_cmd <= maintenance_cmd;
		// o_cmd <= { m_ram_cs_n, m_ram_ras_n, m_ram_cas_n, m_ram_we_n };
		// o_ram_cs_n  <= m_ram_cs_n;
		// o_ram_ras_n <= m_ram_ras_n;
		// o_ram_cas_n <= m_ram_cas_n;
		// o_ram_we_n  <= m_ram_we_n;
		// o_ram_dmod  <= `DMOD_GETINPUT;
		o_ram_addr  <= maintenance_addr;
`ifdef	FORMAL
		f_dbg_command = "MAINT";
`endif
	end else begin
		o_ram_addr <= 0;
		o_wb_stall <= (r_pending && (o_cmd != CMD_READ) &&(o_cmd != CMD_WRITE))||(bus_cyc);
		r_barrell_ack <= r_barrell_ack >> 1;
`ifdef	FORMAL
		f_dbg_command = "NOOP";
`endif

		//
		// We assume that, whatever state the bank is in, that it
		// continues in that state and set up a series of shift
		// registers to contain that information.  If it will not
		// continue in that state, all that therefore needs to be
		// done is to set bank_active[?][2] below.
		//
		bank_active[0] <= { bank_active[0][CK_RCD], bank_active[0][CK_RCD:1] };
		bank_active[1] <= { bank_active[1][CK_RCD], bank_active[1][CK_RCD:1] };
		//
		if (|clocks_til_idle)
			clocks_til_idle <= clocks_til_idle - 3'h1;

		// Default command is a
		//	NOOP if (i_wb_cyc)
		//	Device deselect if (!i_wb_cyc)
		// o_ram_cs_n  <= (!i_wb_cyc) above, NOOP
		o_cmd <= CMD_NOOP;
		o_cmd[3] <= 1'b1; // Deselect CS

		// o_ram_ras_n <= 1'b1;
		// o_ram_cas_n <= 1'b1;
		// o_ram_we_n  <= 1'b1;

		// o_ram_data <= r_data[15:0];

		if (r_pending && !r_bank_valid)
		begin
			o_ram_addr  <= { r_bank, r_row };
			if (bank_active[r_bank][0])
				// Precharge the selected bank
				o_ram_addr[10] <= 1'b0;
		end else if (issued)
		begin
			o_ram_addr <= { r_bank, 3'b0, r_col };
		end else if (OPT_FWD_ADDRESS && r_pending && !fwd_bank_valid)
		begin
			o_ram_addr  <= { fwd_bank, fwd_row };
			if (!bank_active[fwd_bank][0] == 0)
				o_ram_addr[10] <= 1'b0;
		end


		if (refresh_stall)
			;
		else if ((r_pending)&&(!r_bank_valid))
		begin
			// o_ram_addr  <= { r_bank, r_row };
			if (bank_active[r_bank]==0)
			begin // Need to activate the requested bank
				o_cmd <= CMD_ACTIVATE;
				// o_ram_cs_n  <= 1'b0;
				// o_ram_ras_n <= 1'b0;
				// o_ram_cas_n <= 1'b1;
				// o_ram_we_n  <= 1'b1;
				// clocks_til_idle[2:0] <= 1;
				bank_active[r_bank][CK_RCD] <= 1'b1;
				bank_row[r_bank] <= r_row;
				//
`ifdef	FORMAL
				f_dbg_command = "ACTIV";
`endif
			end else if ((&bank_active[r_bank])
				&& clocks_til_idle[2:0] < 3'h1)
			begin // Need to close an active bank
				o_cmd <= CMD_PRECHARGE;
				// o_ram_cs_n  <= 1'b0;
				// o_ram_ras_n <= 1'b0;
				// o_ram_cas_n <= 1'b1;
				// o_ram_we_n  <= 1'b0;
				// o_ram_addr[11]<= r_bank;
				// o_ram_addr[10]<= 1'b0;
				// clocks_til_idle[2:0] <= 1;
				bank_active[r_bank][CK_RCD:CK_RP-1] <= 0;
`ifdef	FORMAL
				f_dbg_command = "PRCHG";
`endif
			end
		end else if (pending && &bank_active[r_bank][CK_RCD:1]
				// && r_bank_valid
				&& ((!r_we && clocks_til_idle < 5)
				   ||(r_we && clocks_til_idle <= 1)))
		begin
			if (r_we)
			begin
				o_cmd <= CMD_WRITE;
				clocks_til_idle <= 2;
				r_barrell_ack[1] <= 1'b1;
				// o_ram_dmod <= `DMOD_PUTOUTPUT;
				// o_ram_data <= r_data[DW-1:16];
				//
`ifdef	FORMAL
				f_dbg_command = "WRITE";
`endif
			end else begin
				o_cmd <= CMD_READ;
				clocks_til_idle <= 5;
				r_barrell_ack[(RDLY-1)] <= 1'b1;
`ifdef	FORMAL
				f_dbg_command = "READ";
`endif
			end
			o_wb_stall <= 1'b0;
			o_cmd[3] <= !i_wb_cyc;
			// o_ram_addr  <= { r_bank, 3'h0, r_col };
		end else if (OPT_FWD_ADDRESS && r_pending && !fwd_bank_valid)
		begin
			// o_ram_addr  <= { fwd_bank, fwd_row };
			bank_row[fwd_bank] <= fwd_row;

			// Do I need to close the next bank I'll need?
			if (&bank_active[fwd_bank][CK_RCD:1]
				   && clocks_til_idle <= 1)
			begin // Need to close the bank first
				o_cmd <= CMD_PRECHARGE;
				// o_ram_cs_n  <= 1'b0;
				// o_ram_ras_n <= 1'b0;
				// o_ram_cas_n <= 1'b1;
				// o_ram_we_n  <= 1'b0;
				// Close the bank
				// o_ram_addr[10] <= 1'b0;
				bank_active[fwd_bank][CK_RCD:CK_RP-1] <= 0;
`ifdef	FORMAL
				f_dbg_command = "NXTPR";
`endif
			end else if (bank_active[fwd_bank]==0)
			begin
				// Need to (pre-)activate the next bank
				o_cmd <= CMD_ACTIVATE;
				// o_ram_cs_n  <= 1'b0;
				// o_ram_ras_n <= 1'b0;
				// o_ram_cas_n <= 1'b1;
				// o_ram_we_n  <= 1'b1;
				// clocks_til_idle[3:0] <= 1;
				bank_active[fwd_bank][CK_RCD] <= 1'b1;
`ifdef	FORMAL
				f_dbg_command = "NXTAC";
`endif
			end
		end
		if (refresh_stall)
			o_wb_stall <= 1;
		if (!i_wb_cyc)
			r_barrell_ack <= 0;
	end

	assign	o_ram_cs_n  = o_cmd[3];
	assign	o_ram_ras_n = o_cmd[2];
	assign	o_ram_cas_n = o_cmd[1];
	assign	o_ram_we_n  = o_cmd[0];

	// localparam	STARTUP_WAIT_NS = 100_000; // 100us
	localparam	CK_STARTUP_WAIT = CLOCK_FREQUENCY_HZ / 10_000;
	reg					startup_hold;
	reg	[$clog2(CK_STARTUP_WAIT)-1:0]	startup_idle;

`ifndef	FORMAL
	initial	startup_idle = CK_STARTUP_WAIT[$clog2(CK_STARTUP_WAIT)-1:0];
`endif
	initial	startup_hold = 1'b1;
	always @(posedge i_clk)
	if (|startup_idle)
		startup_idle <= startup_idle - 1'b1;
	always @(posedge i_clk)
		startup_hold <= |startup_idle;
`ifdef	FORMAL
	always @(*)
	if (startup_hold)
	begin
		assert(maintenance_mode);
	end

	always @(*)
	if (|startup_idle)
		assert(startup_hold);
`endif

	localparam [11:0] MODE_COMMAND =
			{ 5'b00000,	// Burst reads and writes
			CAS_LATENCY[2:0],// CAS latency (3 clocks)
			1'b0,		// Sequential (not interleaved)
			3'b001		// 32-bit burst length
			};
	genuctrl #(
		.CMDWIDTH(1+4+1),
		.LGDELAY(4),
		.LGNCMDS(4),
		.OPT_REPEAT(0),
		.COMMANDS({
		// Read these commands from the bottom up
		{ 1'b0, 1'b0, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b0, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b0, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b0, CMD_NOOP,      MODE_COMMAND[10] },
		//
		// Need two cycles following SET_MODE before the first
		// command
		{ 1'b0, 1'b1, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b1, CMD_SET_MODE,  MODE_COMMAND[10] },
		{ 1'b1, 2'b00, 4'h6 },
		{ 1'b0, 1'b1, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b1, CMD_REFRESH,   MODE_COMMAND[10] },
		{ 1'b1, 2'b00, 4'h6 },
		{ 1'b0, 1'b1, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b1, CMD_REFRESH,   MODE_COMMAND[10] },
		{ 1'b1, 2'b00, 4'h0 },
		{ 1'b0, 1'b1, CMD_NOOP,      MODE_COMMAND[10] },
		{ 1'b0, 1'b1, CMD_PRECHARGE, 1'b1 },
		// The command list starts here, with a no-op then precharge
		{ 1'b0, 1'b1, CMD_NOOP,      MODE_COMMAND[10] }
		})
	) reset_controller(i_clk, startup_hold,
		{ reset_active, reset_command, reset_addr10 });

	localparam	LGREF = $clog2(CK_REFRESH);
	// verilator lint_off WIDTH
	localparam [LGREF-1:0]	CK_WAIT_FOR_IDLE = 4,
			CK_PRECHARGE_TO_REFRESH = CK_RP-1,
			CK_REFRESH_NOOP_TO_ACTIVATE= CK_RC-2,
			CK_REMAINING=CK_REFRESH
				- CK_WAIT_FOR_IDLE
				- CK_PRECHARGE_TO_REFRESH
				- CK_REFRESH_NOOP_TO_ACTIVATE
				- 15;
	// verilator lint_on  WIDTH
	localparam [LGREF-6-1:0]	REF_ZEROS = 0;

	genuctrl #(
		.CMDWIDTH(1+4+1),
		.LGDELAY(LGREF),
		.LGNCMDS(4),
		.OPT_REPEAT(1),
		.COMMANDS({
		// Read these commands from the bottom up
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP },
		//
		{ 1'b1, CK_REFRESH_NOOP_TO_ACTIVATE },
		{ 1'b0, REF_ZEROS, 2'b11, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b11, CMD_REFRESH },
		{ 1'b1, CK_PRECHARGE_TO_REFRESH },
		{ 1'b0, REF_ZEROS, 2'b11, CMD_NOOP },
		{ 1'b0, REF_ZEROS, 2'b11, CMD_PRECHARGE },
		{ 1'b1, CK_WAIT_FOR_IDLE },
		{ 1'b0, REF_ZEROS, 2'b01, CMD_NOOP },
		{ 1'b1, CK_REMAINING },
		{ 1'b0, REF_ZEROS, 2'b00, CMD_NOOP }
		// 
		// CMD_NOOP, stall is low
		// CK_RC -3
		// CMD_NOOP
		// CMD_REFRESH
		// CK_RP-2, CK?PRECHARGE_TO_REFRESH
		// NOOP
		// PRECHARGE_ALL
		// CK_DPL-2
		// MAINTENANCE_MODE, NOOP
	//{
		// CK_? -2, clocks from active to read/write
		// NOOP
		// Stall while activate
		// CK_RP-2
		// NOOP
		// Stall while precharge
		// COUNTER: CK_REFRESH - (clocks above)
	//}
		})
	) refresh_controller(i_clk, reset_active,
		{ refresh_active, refresh_stall, refresh_cmd });

	initial	maintenance_mode = 1;
	initial	maintenance_cmd = CMD_NOOP;
	always @(posedge i_clk)
	begin
		if (reset_active)
		begin
			maintenance_mode <= 1;
			maintenance_cmd  <= reset_command;
		end else if (refresh_active)
		begin
			maintenance_mode <= 1;
			maintenance_cmd  <= refresh_cmd;
		end else begin
			maintenance_mode <= 0;
			maintenance_cmd <= CMD_NOOP;
		end

		maintenance_addr <= MODE_COMMAND;
		maintenance_addr[10] <= (reset_active) ? reset_addr10
				: 1'b1;
	end

	initial	o_ram_dmod = `DMOD_GETINPUT;
	initial	nxt_dmod = `DMOD_GETINPUT;
	always @(posedge i_clk)
	if (issued && r_we)
	begin
		o_ram_dmod <= `DMOD_PUTOUTPUT;
		nxt_dmod <= `DMOD_PUTOUTPUT;
	end else begin
		nxt_dmod <= `DMOD_GETINPUT;
		o_ram_dmod <= nxt_dmod;
	end

	always @(posedge i_clk)
	if (nxt_dmod)
		o_ram_data <= r_data[15:0];
	else if (issued && r_we)
		o_ram_data <= r_data[DW-1:16];
	else
		o_ram_data <= 0;

	initial	nxt_sel = 2'b11;
	always @(posedge i_clk)
		nxt_sel <= r_sel[1:0];

	always @(posedge i_clk)
	if (maintenance_mode)
		o_ram_dqm <= 2'b11;
	else if (o_cmd == CMD_WRITE)
		o_ram_dqm <= ~nxt_sel;
	else if (!r_we)
		o_ram_dqm <= 2'b00;
	else if (bank_active[r_bank][CK_RCD]
			&& r_bank_valid && clocks_til_idle <= 1)
		o_ram_dqm <= ~r_sel[3:2];
	else
		o_ram_dqm <= 2'b00;

	assign	o_wb_ack  = r_barrell_ack[0];
	always @(posedge i_clk)
		o_wb_data <= { o_wb_data[15:0], i_ram_data };

	//
	// The following outputs are not necessary for the functionality of
	// the SDRAM, but they can be used to feed an external "scope" to
	// get an idea of what the internals of this SDRAM are doing.
	//
	// Just be aware of the r_we: it is set based upon the currently pending
	// transaction, or (if none is pending) based upon the last transaction.
	// If you want to capture the first value "written" to the device,
	// you'll need to write a nothing value to the device to set r_we.
	// The first value "written" to the device can be caught in the next
	// interaction after that.
	//
	reg	trigger;
	initial	trigger = 0;
	always @(posedge i_clk)
		// trigger <= ((o_wb_data[15:0]==o_wb_data[DW-1:16])
		//	&&(o_wb_ack)&&(!i_wb_we));
		trigger <= (i_wb_stb && !o_wb_stall && !i_wb_we);


	assign	o_debug = { trigger, i_wb_cyc, i_wb_stb, i_wb_we,	// 4
		o_wb_ack, o_wb_stall,					// 2
		o_ram_cs_n, o_ram_ras_n, o_ram_cas_n, o_ram_we_n,	// 4
			o_ram_dmod, o_ram_addr[11:1],			// 12
			o_ram_dqm,				// 2 more
			(r_we||o_ram_dmod) ? { o_ram_data[7:0] } //  8 values
				: o_wb_data[7:0]
		//		: { o_wb_data[23:20], o_wb_data[3:0] }
			// i_ram_data[7:0]
			 };

	// Make Verilator happy
	// verilator lint_off UNUSED
	wire		unused;
	assign	unused = &{ 1'b0, fwd_addr[6:0], i_col };
	// verilator lint_on  UNUSED
`ifdef	FORMAL
	localparam	REFRESH_CLOCKS = 15;
	localparam	ACTIVATE_CLOCKS = 6;
	wire	[(5-1):0]	f_nreqs, f_nacks, f_outstanding;
	reg	f_past_valid;
	wire	f_reset;
	integer	f_k;

	always @(*)
	if (o_ram_dmod)
		assume(i_ram_data == o_ram_data);

	wire			o_ram_bank;

	assign	o_ram_bank  = o_ram_addr[11];

	initial	f_past_valid = 1'b0;
	always @(posedge i_clk)
		f_past_valid <= 1'b1;

	assign	f_reset = !f_past_valid;

	always @(*)
		if (o_ram_dmod)
			assert(i_ram_data == o_ram_data);

	// Properties
	// 1. Wishbone
	fwb_slave #( .AW(AW), .DW(DW),
			.F_MAX_STALL(2+ACTIVATE_CLOCKS + REFRESH_CLOCKS
					+ ACTIVATE_CLOCKS + RDLY
					+ACTIVATE_CLOCKS),
			.F_MAX_ACK_DELAY(2+REFRESH_CLOCKS
				+ ACTIVATE_CLOCKS
				+ ACTIVATE_CLOCKS
				+ ACTIVATE_CLOCKS+RDLY),
			.F_LGDEPTH(5))
		fwb(i_clk, f_reset,
			i_wb_cyc, i_wb_stb, i_wb_we, i_wb_addr,
				i_wb_data, i_wb_sel,
			o_wb_ack, o_wb_stall, o_wb_data, 1'b0,
			f_nreqs, f_nacks, f_outstanding);

	// 2. Proper startup ...
	// 3. Operation
	//   4. Refresh
	//   4. SDRAM request == WB request
	//

	// On the very first clock, we must always start up in maintenance mode
	always @(posedge i_clk)
	if (!f_past_valid)
		assert(maintenance_mode);

	// Just to make things simpler, assume no accesses to the core during
	// maintenance mode.  Such accesses might violate our minimum
	// acknowledgement time criteria for the wishbone above
	always @(posedge i_clk)
	if ((f_past_valid)&&(reset_active))
		assume(!i_wb_stb);

	// Likewise, assert that there are *NO* outstanding transactions in
	// this maintenance mode
	always @(posedge i_clk)
	if ((f_past_valid)&&(reset_active))
		assert(f_outstanding == 0);

	// ... and that while we are in maintenance mode, any incoming request
	// is stalled.  This guarantees that our assumptions above are kept
	// valid.
	always @(posedge i_clk)
	if ((f_past_valid)&&(maintenance_mode))
		assert(o_wb_stall);

	// If there are no attempts to access memory while in maintenance
	// mode, then there should never be any pending operations upon
	// completion of maintenance mode
	always @(posedge i_clk)
	if ((f_past_valid)&&(reset_active))
		assert(!r_pending);

	//
	reg	[4:0]	barrell_outstanding;
	always @(*)
	begin
		barrell_outstanding = 0;
		for(f_k=0; f_k<RDLY; f_k=f_k+1)
		if (r_barrell_ack[f_k])
			barrell_outstanding = barrell_outstanding + 1;
		if (r_pending && (o_cmd != CMD_READ) && (o_cmd != CMD_WRITE))
			barrell_outstanding = barrell_outstanding + 1;

		if (i_wb_cyc)
			assert(barrell_outstanding == f_outstanding);
	end

	wire	[(2+AW+DW+DW/8-1):0]	f_pending, f_request;
	assign	f_pending = { r_pending, r_we, r_addr, r_data, r_sel };
	assign	f_request = {  i_wb_stb, i_wb_we, i_wb_addr, i_wb_data, i_wb_sel };

//	always @(posedge i_clk)
//	if ((f_past_valid)&&($past(r_pending))&&($past(i_wb_cyc))
//			&&(($past(o_ram_cs_n))
//			||(!$past(o_ram_ras_n))
//			||($past(o_ram_cas_n))) )
//		assert($stable(f_pending));
//
	wire	[4:0]	f_cmd;
	assign	f_cmd = { o_ram_addr[10],
			o_ram_cs_n, o_ram_ras_n, o_ram_cas_n, o_ram_we_n };

`define	F_MODE_SET		5'b?0000
`define	F_BANK_PRECHARGE	5'b00010
`define	F_PRECHARGE_ALL		5'b10010
`define	F_BANK_ACTIVATE0	5'b00011
`define	F_BANK_ACTIVATE1	5'b10011
`define	F_WRITE			5'b00100
`define	F_READ			5'b00101
`define	F_REFRESH		5'b?0001
`define	F_NOOP			5'b?0111

`define	F_BANK_ACTIVATE_S	4'b0011
`define	F_REFRESH_S		4'b0001
`define	F_NOOP_S		4'b0111

	reg	[AW-1:0]	f_next_addr;
	wire	[10:0]		f_next_row, f_this_row;
	wire			f_next_bank, f_this_bank;

	always @(*)
		f_next_addr[AW-1:0] = r_addr[AW-1:0] + 5'b01100;

	assign	f_next_row  = f_next_addr[AW-1:8];
	assign	f_next_bank = f_next_addr[7];
	assign	f_this_bank = r_bank;
	assign	f_this_row  = r_row;

	always @(*)
	if (o_ram_cs_n==1'b0) casez(f_cmd)
	`F_MODE_SET:       begin end
	`F_BANK_PRECHARGE: begin end
	`F_PRECHARGE_ALL:  begin end
	`F_BANK_ACTIVATE0: begin end
	`F_BANK_ACTIVATE1: begin end
	`F_WRITE:          begin end
	`F_READ:           begin end
	`F_REFRESH:        begin end
	default: assert(f_cmd[3:0] == `F_NOOP_S);
	endcase

	always @(*)
	if (o_cmd[3:0] == CMD_SET_MODE)
	begin
		assert(o_ram_addr == MODE_COMMAND);
		assert(maintenance_mode);
	end

	always @(posedge i_clk)
	if ((f_past_valid)&&(!maintenance_mode))
	casez(f_cmd)
	`F_BANK_ACTIVATE0:	begin
		// Can only activate de-activated banks
		assert(bank_active[o_ram_bank][1:0] == 0);
		// Need to activate the right bank
		if (o_ram_bank == $past(f_this_bank))
			assert($past(f_this_row)==o_ram_addr[10:0]);
		else
			assert($past(f_next_row)==o_ram_addr[10:0]);
		end
	`F_BANK_ACTIVATE1:	begin
		// Can only activate de-activated banks
		assert(bank_active[o_ram_bank][1:0] == 0);
		// Need to activate the right bank
		if (o_ram_bank == $past(f_this_bank))
			assert($past(f_this_row)==o_ram_addr[10:0]);
		else
			assert($past(f_next_row)==o_ram_addr[10:0]);
		end
	`F_BANK_PRECHARGE:	begin
		// Can only precharge (de-active) a fully active bank
		// assert(bank_active[o_ram_bank][CK_RCD:CK_RP-1] == 1'b0);
		// assert(&bank_active[o_ram_bank][CK_RP-2:0]);
		end
	`F_PRECHARGE_ALL:	begin
		// If pre-charging all, one of the banks must be active and in
		// need of a pre-charge
		assert(
			(bank_active[0] == 3'b011)
			||(bank_active[1] == 3'b011));
		end
	`F_WRITE:	begin
		assert($past(issued));
		assert($past(r_pending));
		assert($past(r_we));
		assert(&bank_active[o_ram_bank]);
		assert(bank_row[o_ram_bank] == $past(f_this_row));
		assert(o_ram_bank == $past(f_this_bank));
		assert(o_ram_addr[0] == 1'b0);
		assert(o_ram_addr[7:0] == $past(r_col));
		assert(o_ram_data == $past(r_data[31:16]));
		assert(o_ram_dqm == ~$past(r_sel[3:2]));
		assert(o_ram_dmod);
		end
	`F_READ:	begin
		assert(!$past(r_we));
		assert(&bank_active[o_ram_bank]);
		assert(bank_row[o_ram_bank] == $past(f_this_row));
		assert(o_ram_bank == $past(f_this_bank));
		assert(o_ram_addr[0] == 1'b0);
		assert(o_ram_addr[7:0] == $past(r_col));
		end
	`F_REFRESH:	begin
		// When giving a reset command, *all* banks must be inactive
		assert( (bank_active[0] == 0)
			&&(bank_active[1] == 0));
		end
	default: assert((o_ram_cs_n)||(f_cmd[3:0] == `F_NOOP_S));
	endcase

	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(maintenance_mode)))
	begin
		for(f_k=0; f_k<2; f_k=f_k+1)
			if (((f_cmd[3:0] != `F_BANK_ACTIVATE_S))
		 			||(o_ram_bank != f_k[1:0]))
				assert($stable(bank_row[f_k[1:0]]));
	end

	always @(posedge i_clk)
	if (f_past_valid) // &&(!$past(maintenance_mode))
	begin
		if ((f_cmd == `F_READ)||(f_cmd == `F_WRITE))
			assert(!r_pending && !o_wb_stall);
		else if (($past(r_pending))&&($past(i_wb_cyc)))
			assert($stable(f_pending));
	end

	always @(posedge i_clk)
	if ((f_past_valid)&&(!maintenance_mode))
		if ((r_pending)&&(f_cmd != `F_READ)&&(f_cmd != `F_WRITE))
			assert(o_wb_stall);

	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(maintenance_mode)))
	casez($past(f_cmd))
	`F_BANK_ACTIVATE0: begin
		// assert(&bank_active[$past(o_ram_bank)][CK_RCD:CK_RCD-1]);
		// assert(bank_active[$past(o_ram_bank)][CK_RCD-2:0]==0);
		// assert(&bank_active[$past(o_ram_bank)][CK_RCD:1]) == 3'b110);
		assert(bank_row[$past(o_ram_bank)] == $past(o_ram_addr[10:0]));
		end
	`F_BANK_ACTIVATE1: begin
		assert(&bank_active[$past(o_ram_bank)][CK_RCD:CK_RCD-1]);
		assert(bank_active[$past(o_ram_bank)][CK_RCD-2:0]==0);
		// assert(bank_active[$past(o_ram_bank)] == 3'b110);
		assert(bank_row[$past(o_ram_bank)] == $past(o_ram_addr[10:0]));
		end
	`F_BANK_PRECHARGE: begin
		// assert(bank_active[$past(o_ram_bank)][CK_RCD:CK_RCD-1] == 0);
		// assert(&bank_active[$past(o_ram_bank)][CK_RCD-2:0]);
		end
	`F_PRECHARGE_ALL: begin
		assert(bank_active[0][CK_RCD] == 1'b0);
		assert(bank_active[1][CK_RCD] == 1'b0);
		end
	`F_WRITE: begin
		assert(o_ram_data == $past(r_data[15:0],2));
		assert(o_ram_dqm == ~$past(r_sel[1:0],2));
		assert(o_ram_dmod);
		end
	// `F_WRITE:
	// `F_READ:
	`F_REFRESH: begin
		assert(r_barrell_ack == 0);
	end
	default: begin end
	endcase

	always @(*)
	if (clocks_til_idle == 5)
		assert(o_cmd[2:0] == CMD_READ[2:0]);
	always @(*)
		assert(clocks_til_idle < 6);

	always @(*)
	if (reset_active)
	begin
		assert(bank_active[0] == 0);
		assert(bank_active[1] == 0);
	end

	////////////////////////////////////////////////////////////////////////
	//
	// Bus (ack) checks
	//
	////////////////////////////////////////////////////////////////////////

	reg	[3:0]	f_acks_pending;
	always @(*)
	begin
		f_acks_pending = 0;
		for(f_k=0; f_k<RDLY; f_k = f_k + 1)
			if (r_barrell_ack[f_k])
				f_acks_pending = f_acks_pending + 1'b1;
	end

	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(i_wb_cyc)))
		assert(r_barrell_ack == 0);


	wire	f_ispending;
	assign	f_ispending = (r_pending)&&((f_cmd != `F_READ)&&(f_cmd != `F_WRITE));
	always @(posedge i_clk)
	if ((f_past_valid)&&(i_wb_cyc))
		assert(f_outstanding == (f_ispending ? 1'b1:1'b0) + f_acks_pending);


	////////////////////////////////////////////////////////////////////////
	//
	// Maintenance mode assertions
	//
	////////////////////////////////////////////////////////////////////////
	//
	//
	always @(*)
	if (!f_past_valid)
	begin
		assume(startup_idle <= CK_STARTUP_WAIT[$clog2(CK_STARTUP_WAIT)-1:0]);
		assume(startup_idle > 3);
	end

	always @(*)
	if (reset_active)
		assert(maintenance_mode);

	always @(posedge i_clk)
	if (!startup_hold)
		assert(!$rose(reset_active));


	////////////////////////////////////////////////////////////////////////
	//
	// Ad-hoc assertions
	//
	////////////////////////////////////////////////////////////////////////
	//
	//

	////////////////////////////////////////////////////////////////////////
	//
	// Some cover statements
	//
	////////////////////////////////////////////////////////////////////////
	//
	//

	reg	f_prior_write, f_prior_read,
		f_prior_wbank, f_prior_rbank;
	reg	[10:0]	f_prior_wrow, f_prior_rrow;

	initial	f_prior_write = 0;
	initial	f_prior_read  = 0;

	always @(posedge i_clk)
	if ((f_nacks != f_nreqs)&&(!i_wb_cyc))
		f_prior_write <= 1'b0;
	else if (o_cmd == CMD_WRITE)
	begin
		f_prior_write <= 1'b1;
		f_prior_wbank <= o_ram_bank;
		f_prior_wrow  <= $past(r_row);
	end

	always @(posedge i_clk)
	if ((f_nacks != f_nreqs)&&(!i_wb_cyc))
		f_prior_read <= 1'b0;
	else if (o_cmd == CMD_READ)
	begin
		f_prior_read <= 1'b1;
		f_prior_rbank <= o_ram_bank;
		f_prior_rrow  <= $past(r_row);
	end

	always @(posedge i_clk)
	begin
		cover(o_cmd == CMD_WRITE);
		cover(o_cmd == CMD_READ);

		cover(o_cmd == CMD_WRITE && f_prior_write);
		cover(o_cmd == CMD_WRITE && f_prior_read);
		//
		cover(o_cmd == CMD_READ  && f_prior_write);
		cover(o_cmd == CMD_READ  && f_prior_read);

		cover(o_cmd == CMD_WRITE && f_prior_write && o_ram_bank != f_prior_wbank);
		cover(o_cmd == CMD_READ  && f_prior_read  && o_ram_bank != f_prior_rbank);
		cover(o_cmd == CMD_WRITE && f_prior_write && o_ram_bank == f_prior_rbank);
		cover(o_cmd == CMD_READ  && f_prior_read  && o_ram_bank == f_prior_rbank);
		//
		cover(o_cmd == CMD_READ  && f_prior_read  && o_ram_bank == f_prior_rbank
			&& f_prior_rrow != $past(r_row));
	end

//
`ifdef	VERIFIC
	////////////////////////////////////////////////////////////////////////
	//
	// Ad-hoc assertions
	//
	////////////////////////////////////////////////////////////////////////
	//
	//

	// Writes
	assert property (@(posedge i_clk)
		disable iff (!i_wb_cyc)
		i_wb_stb && i_wb_we && !o_wb_stall
		|=> r_pending && (r_addr == $past(i_wb_addr))
		##1(r_pending && $stable(f_pending)&&r_we&&(o_cmd != CMD_WRITE))
			[*0:35]
		##1 (o_cmd == CMD_WRITE)
			&&(o_ram_addr == $past({ r_bank, 3'b000, r_addr[6:0], 1'b0 }))
			&&(o_ram_data == $past(r_data[31:16]))
			&&(o_ram_dqm == ~$past(r_sel[3:2]))
		##1 (o_cmd[3] || (o_cmd == CMD_NOOP)) && (o_wb_ack)
			&&(o_ram_data == $past(r_data[15:0],2))
			&&(o_ram_dqm == ~$past(r_sel[1:0],2))
			);
		
	// Reads
	assert property (@(posedge i_clk)
		disable iff (!i_wb_cyc)
		i_wb_stb && !i_wb_we && !o_wb_stall
		|=> r_pending && (r_addr == $past(i_wb_addr))
		##1(o_wb_stall && r_pending && $stable(f_pending)
				&&!r_we&&(o_cmd != CMD_READ))
			[*0:40]
		##1 (o_cmd == CMD_READ)
			&&(o_ram_addr == $past({r_bank, 3'b000, r_addr[6:0], 1'b0}))
		##1 (o_ram_dqm == 2'b00));
		
	genvar	gbank;
	generate for(gbank=0; gbank<2; gbank=gbank+1)
	begin
		always @(*)
		if (!f_past_valid)
			assume(bank_active[gbank] == 0);

		// Precharge to active on this bank
		assert property (@(posedge i_clk)
			(o_cmd == CMD_PRECHARGE)&&(o_ram_addr[11] == gbank)
			|=> (o_cmd != CMD_ACTIVATE
				|| o_ram_addr[11] != gbank) [*CK_RP-1]);

		// Make sure we can do it at the right time
		cover property (@(posedge i_clk)
			(o_cmd == CMD_PRECHARGE)&&(o_ram_addr[11] == gbank)
			##1 1'b1 [*CK_RP-1]
			##1 (o_cmd == CMD_ACTIVATE
				&& o_ram_addr[11] == gbank));

		// One activate to another of a different bank
		assert property (@(posedge i_clk)
			(o_cmd == CMD_ACTIVATE)&&(o_ram_addr[11] == gbank)
			|=> (o_cmd != CMD_ACTIVATE
				|| o_ram_addr[11] != gbank) [*CK_RRD-1]);

		//
		// One activate to another of the same bank
		assert property (@(posedge i_clk)
			(o_cmd == CMD_ACTIVATE)&&(o_ram_addr[11] == gbank)
			|=> (o_cmd != CMD_READ && o_cmd != CMD_WRITE)
				|| (o_ram_addr[11] != gbank) [*CK_RCD-1]);

		cover property (@(posedge i_clk)
			(o_cmd == CMD_ACTIVATE)&&(o_ram_addr[11] == gbank)
			##1 1'b1 [*CK_RCD-1]
			##1 o_cmd == CMD_READ && (o_ram_addr[11] == gbank));

		cover property (@(posedge i_clk)
			(o_cmd == CMD_ACTIVATE)&&(o_ram_addr[11] == gbank)
			##1 1'b1 [*CK_RCD-1]
			##1 o_cmd == CMD_WRITE && (o_ram_addr[11] == gbank));

		//
		// Write to precharge
		assert property (@(posedge i_clk)
			(o_cmd == CMD_WRITE && o_ram_addr[11] == gbank)
			|=> (o_cmd != CMD_PRECHARGE
				|| (!o_ram_addr[10] && o_ram_addr[11] != gbank))
				[*(CK_DPL+1-1)]);

		//
		// Read to precharge
		// See page 33
		if (CAS_LATENCY+1-CK_RQL-1 > 0)
		begin
		assert property (@(posedge i_clk)
			(o_cmd == CMD_READ && o_ram_addr[11] == gbank)
			|=> (o_cmd != CMD_PRECHARGE)
				||(!o_ram_addr[10] && o_ram_addr[11] != gbank)
				[*(CAS_LATENCY+1-CK_RQL-1)]);
		end
	end endgenerate

	assert property (@(posedge i_clk)
		(o_cmd == CMD_WRITE)
		|-> (o_ram_dmod == `DMOD_PUTOUTPUT)&&(o_ram_data == $past(r_data[31:16]))
		##1 (o_ram_dmod == `DMOD_PUTOUTPUT)&&(o_ram_data == $past(r_data[15:0],2))
				&& (o_cmd != CMD_WRITE));

	generate if (CAS_LATENCY >= 3)
	begin
		assert property (@(posedge i_clk)
		disable iff (!i_wb_cyc)
		(o_cmd == CMD_READ)
		|=> (o_cmd != CMD_READ) [*CAS_LATENCY-3]
		##1(o_ram_dmod == `DMOD_GETINPUT)&&($past(o_ram_dqm,CK_QMD)==0) [*2]);
	end else begin // if (CAS_LATENCY < 3)

		assert property (@(posedge i_clk)
		disable iff (!i_wb_cyc)
			(o_cmd == CMD_READ)
			|=> 1[*CAS_LATENCY-1]
			##1 (o_ram_dmod == `DMOD_GETINPUT)&&($past(o_ram_dqm,CK_QMD)==0) [*2]);
	end endgenerate

	assert property (@(posedge i_clk)
		disable iff (!i_wb_cyc)
		(o_cmd == CMD_READ)
		|=> 1'b1 [*RDLY-2]
		##1 (o_wb_ack)	&&(o_wb_data[15: 0] == $past(i_ram_data,1))
				&&(o_wb_data[31:16] == $past(i_ram_data,2)));

	assert property (@(posedge i_clk)
		(o_cmd == CMD_READ)
		|=> (o_cmd != CMD_READ));

	assert property (@(posedge i_clk)
		(o_cmd == CMD_REFRESH)
		|=> (o_ram_cs_n || (o_cmd == CMD_NOOP)) [*(CK_RC-1)]);

	assert property (@(posedge i_clk)
		(o_cmd == CMD_SET_MODE)
		|=> (o_ram_cs_n || (o_cmd == CMD_NOOP)) [*(CK_MCD-1)]);

	cover property (@(posedge i_clk)
		disable if (f_nacks != f_nreqs && !i_wb_cyc)
		((i_wb_cyc && !i_wb_we && i_wb_stb) throughout
			(!o_wb_stall ##1 o_wb_stall [*0:3]) [*3])
		##1 (i_wb_cyc && r_barrell_ack != 0)[*0:8]
		##1 (r_barrell_ack == 0)&& (r_pending == 0) && (!i_wb_stb));

	cover property (@(posedge i_clk)
		disable if (f_nacks != f_nreqs && !i_wb_cyc)
		((i_wb_cyc && i_wb_we && i_wb_stb) throughout
			(!o_wb_stall ##1 o_wb_stall [*0:3]) [*3])
		##1 (i_wb_cyc && r_barrell_ack != 0)[*0:8]
		##1 (r_barrell_ack == 0 && !i_wb_cyc));

`endif // VERIFIC
`endif // FORMAL
endmodule
