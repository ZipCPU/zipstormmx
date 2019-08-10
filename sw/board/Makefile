################################################################################
##
## Filename:	sw/board/Makefile
##
## Project:	ZipSTORM-MX, an iCE40 ZipCPU demonstration project
##
## Purpose:	
##
## Creator:	Dan Gisselquist, Ph.D.
##		Gisselquist Technology, LLC
##
################################################################################
##
## Copyright (C) 2019, Gisselquist Technology, LLC
##
## This program is free software (firmware): you can redistribute it and/or
## modify it under the terms of the GNU General Public License as published
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
PROGRAMS := cputest hello memtest
all:	$(PROGRAMS)
#
#
CC	:=zip-gcc
AS	:=zip-as
LD	:=zip-ld
NM	:=zip-nm
OBJDIR	:= obj-zip
RDELF	:= zip-readelf
OBJDUMP := zip-objdump
SOURCES := cputest.c hello.c
HEADERS := $(foreach hdr,$(subst .c,.o,$(SOURCES)),$(wildcard $(hdr))) board.h
LSCRIPTS:= $(wildcard *.ld)
LDSCRIPT:= -Tflash.ld
LFLAGS  := $(LDSCRIPT) -L../zlib
FLASH   := -Tflash.ld -L../zlib
SDRAM   := -Tboard.ld -L../zlib
INCS    := -I../zlib -I../../rtl -I.
CFLAGS  := -O3 $(INCS)
LIBS    := -lc -lzipstormmx
INSTALLD:=/home/dan/work/rnd/zipcpu/sw/install
NLIBD	:=$(INSTALLD)/cross-tools/zip/lib
ZLIBD	:=../zlib
LIB	:= $(NLIBD)/libg.a $(NLIBD)/libc.a
#
# For source analysis, the following macros are defined:

%.o: $(OBJDIR)/%.o
$(OBJDIR)/%.o: %.c
	$(mk-objdir)
	$(CC) $(CFLAGS) -c $< -o $@
$(OBJDIR)/%.s: %.c
	$(mk-objdir)
	$(CC) $(CFLAGS) $(DUMPRTL) -S $< -o $@
$(OBJDIR)/%.txt: $(OBJDIR)/%.o
	$(mk-objdir)
	bash -c "$(RDELF) -a $^ ; $(OBJDUMP) -S -D $^ " | tee $@
%.txt: %
	$(OBJDUMP) -S -D $^ > $@


#
# The CPUTest program here is special--it doesn't use the C library.  Hence,
# it must have the -fno-builtin flag in order to build.  Normally, I'd place
# this only in RAM.  However, there isn't enough RAM on the BlackICE-MX for
# this program, so we use both flash and block RAM.
#
$(OBJDIR)/cputest.o: cputest.c
	$(CC) $(CFLAGS) -c -Wa,-nocis -fno-builtin $< -o $@
$(OBJDIR)/cputestcis.o: cputest.c
	$(CC) $(CFLAGS) -c -Wa,-cis -fno-builtin $< -o $@
$(OBJDIR)/cputest.s: cputest.c
	$(CC) $(CFLAGS) -S -Wa,-cis -fno-builtin $< -o $@

cputest: $(OBJDIR)/cputest.o flash.ld
	$(CC) $(CFLAGS) -T flash.ld -fno-builtin -Wl,-Map=$(OBJDIR)/cputest.map $(OBJDIR)/cputest.o -o $@
cputestcis: $(OBJDIR)/cputestcis.o flash.ld
	$(CC) $(CFLAGS) -T flash.ld -fno-builtin -Wl,-Map=$(OBJDIR)/cputestcis.map $(OBJDIR)/cputestcis.o -o $@

$(OBJDIR)/hello.o: hello.c
	$(CC) -O3 -c $< -o $@
$(OBJDIR)/gettysburg.o: gettysburg.c
	$(CC) -O3 -c $< -o $@

hello: $(OBJDIR)/hello.o $(LSCRIPTS)
	$(CC) $(CFLAGS) $(LFLAGS) $< $(LIBS) -o $@

memtest: $(OBJDIR)/memtest.o bkram.ld
	$(CC) -ffreestanding -Tbkram.ld $(CFLAGS) $< -o $@

define	mk-objdir
	@bash -c "if [ ! -e $(OBJDIR) ]; then mkdir -p $(OBJDIR); fi"
endef

define	build-depends
	@echo "Building dependency file(s)"
	$(mk-objdir)
	@$(CC) $(CFLAGS) -MM $(SOURCES) > $(OBJDIR)/xdepends.txt
	@sed -e 's/^.*.o: /$(OBJDIR)\/&/' < $(OBJDIR)/xdepends.txt > $(OBJDIR)/depends.txt
	@rm $(OBJDIR)/xdepends.txt
endef

tags: $(SOURCES) $(HEADERS)
	@echo "Generating tags"
	@ctags $(SOURCES) $(HEADERS)

.PHONY: depends
depends: tags
	$(build-depends)

$(OBJDIR)/depends.txt: $(SOURCES) $(HEADERS)
	$(build-depends)

.PHONY: clean
clean:
	rm -f $(PROGRAMS)
	rm -rf $(addsuffix .map,$(PROGRAMS))
	rm -rf $(addsuffix .txt,$(PROGRAMS))
	rm -rf $(OBJDIR)/

-include $(OBJDIR)/depends.txt
