################################################################################
##
## Filename:	auto-data/Makefile
##
## Project:	ZipSTORM-MX, an iCE40 ZipCPU demonstration project
##
## Purpose:	To coordinate the build of the glue logic holding this design
##		together via autofpga.
##
##
## Creator:	Dan Gisselquist, Ph.D.
##		Gisselquist Technology, LLC
##
################################################################################
##
## Copyright (C) 2019, Gisselquist Technology, LLC
##
## This program is free software (firmware): you can redistribute it and/or
## modify it under the terms of  the GNU General Public License as published
## by the Free Software Foundation, either version 3 of the License, or (at
## your option) any later version.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
## FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
## for more details.
##
## You should have received a copy of the GNU General Public License along
## with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
## target there if the PDF file isn't present.)  If not, see
## <http://www.gnu.org/licenses/> for a copy.
##
## License:	GPL, v3, as defined and found on www.gnu.org,
##		http://www.gnu.org/licenses/gpl.html
##
##
################################################################################
##
##
.PHONY: all
all:	data
#
# Could also depend upon load, if desired, but not necessary
#
# This is the list of components that will form our project.  Each file consists
# of parts and pieces of our project that autofpga will copy/paste into our
# main project files.
#
BASE    := global.txt dlyarbiter.txt
AUX     := version.txt buserr.txt pic.txt pwrcount.txt
IO      := spio.txt # gpio.txt
RTC     := # rtclight.txt # rtcdate.txt
DBGBUS  := hbconsole.txt
# MEMORY  := bkram.txt qspiflash.txt # spixpress.txt # sdram.txt
MEMORY  := bkram.txt spixpress.txt sdram.txt sdspi.txt
CPU     := zipbones.txt
SCOPES  := # sdramscope.txt refreshcount.txt # spixscope.txt # cpuscope.txt
LDSCRIPT:= mem_all.txt mem_flash_bkram.txt mem_bkram_only.txt mem_sdram_bkram.txt
DATA := clock50.txt $(BASE) $(AUX) $(IO) $(RTC)			\
	$(DBGBUS) $(MEMORY) $(CPU) $(SCOPES) $(LDSCRIPT)

AUTOFPGA := autofpga
$(AUTOFPGA):

.PHONY: data
data: $(AUTOFPGA) $(DATA) blackmx.pcf
	$(AUTOFPGA) -d -o . $(DATA)

clean:
	rm -f toplevel.v main.v regdefs.h regdefs.cpp board.h board.ld
	rm -f rtl.make.inc main_tb.cpp
	rm -f dump.txt
