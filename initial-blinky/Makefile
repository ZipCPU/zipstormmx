BASE := mx1blinky
VERILOG := $(BASE).v
JSON := $(BASE).json
ASCF := $(BASE).asc
PCF  := $(BASE).pcf
BIN  := $(BASE).bin

all: load

.PHONY: yosys nextpnr

yosys:		$(JSON)
nextpnr:	$(ASCF)

$(JSON): $(VERILOG)
	yosys -p 'read -sv $(VERILOG); synth_ice40 -top $(BASE) -json $(JSON)'

$(ASCF): $(JSON)
	nextpnr-ice40 --hx8k --package tq144:4k --freq 25 --pcf $(PCF) --json $(JSON) --asc $(ASCF)

$(BIN): $(ASCF)
	icepack $(ASCF) $(BIN)

load: $(BIN)
	stty -F /dev/ttyACM0 raw
	cat $(BIN) >/dev/ttyACM0

