################################################################################
##
## Filename:	./rtl.make.inc
##
## Project:	ZipSTORM-MX, an iCE40 ZipCPU demonstration project
##
## DO NOT EDIT THIS FILE!
## Computer Generated: This file is computer generated by AUTOFPGA. DO NOT EDIT.
## DO NOT EDIT THIS FILE!
##
## CmdLine:	autofpga autofpga -d -o . clock50.txt global.txt dlyarbiter.txt version.txt buserr.txt pic.txt pwrcount.txt spio.txt hbconsole.txt bkram.txt spixpress.txt sdram.txt sdspi.txt zipbones.txt mem_all.txt mem_flash_bkram.txt mem_bkram_only.txt mem_sdram_bkram.txt
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
SDSPI := sdspi.v llsdspi.v

BKRAM := memdev.v

HBBUSD := hexbus
HBBUS  := $(addprefix $(HBBUSD)/,hbconsole.v hbdechex.v hbdeword.v hbexec.v hbgenhex.v hbidle.v hbints.v hbnewline.v hbpack.v console.v)
BUSPICD := cpu
BUSPIC  := $(addprefix $(BUSPICD)/,icontrol.v)
BUSDLYD := cpu
BUSDLY  := $(addprefix $(BUSDLYD)/,busdelay.v wbpriarbiter.v)
ZIPCPUD := cpu
ZIPCPU  := $(addprefix $(ZIPCPUD)/,zipcpu.v cpuops.v dblfetch.v memops.v idecode.v ziptimer.v wbpriarbiter.v zipbones.v busdelay.v cpudefs.v icontrol.v div.v wbdblpriarb.v mpyop.v iscachable.v dcache.v slowmpy.v)
SDRAM := wbsdram.v iceioddr.v genuctrl.v

HBUART := txuartlite.v rxuartlite.v ufifo.v

FLASH := spixpress.v oclkddr.v

SPIOD := .
SPIO  := $(addprefix $(SPIOD)/,spio.v debouncer.v)
VFLIST := main.v  $(SDSPI) $(BKRAM) $(HBBUS) $(BUSPIC) $(BUSDLY) $(ZIPCPU) $(SDRAM) $(HBUART) $(FLASH) $(SPIO)
AUTOVDIRS :=  -y hexbus -y cpu -y .
