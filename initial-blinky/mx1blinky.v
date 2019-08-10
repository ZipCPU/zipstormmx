module mx1blinky(i_clk, o_led);
	input	wire		i_clk;
	output	wire	[7:0]	o_led;

	reg	[31:0]	counter;

	initial	counter = 0;
	always @(posedge i_clk)
		counter <= counter + 32'd172;

	assign	o_led[0] = counter[31];
	assign	o_led[1] = counter[30];
	assign	o_led[7:2] = 6'h00;

// Signature: 7e, aa, 99, 7e
endmodule
