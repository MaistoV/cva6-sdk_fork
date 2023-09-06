# Makefile for RISC-V toolchain; run 'make help' for usage. set XLEN here to 32 or 64.

XLEN     := 64
ROOT     := $(patsubst %/,%, $(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
RISCV    := $(PWD)/install$(XLEN)
DEST     := $(abspath $(RISCV))
PATH     := $(DEST)/bin:$(PATH)
GZIP_BIN ?= gzip

TOOLCHAIN_PREFIX := $(ROOT)/buildroot/output/host/bin/riscv$(XLEN)-buildroot-linux-gnu-
CC          := $(TOOLCHAIN_PREFIX)gcc
OBJCOPY     := $(TOOLCHAIN_PREFIX)objcopy
MKIMAGE     := u-boot/tools/mkimage

NR_CORES := $(shell nproc)

# SBI options
PLATFORM := fpga/cheshire
FW_FDT_PATH ?= /usr/scratch/fenga3/vmaisto/cheshire_fork/sw/boot/cheshire_vcu128.dtb
sbi-mk = PLATFORM=$(PLATFORM) CROSS_COMPILE=$(TOOLCHAIN_PREFIX) $(if $(FW_FDT_PATH),FW_FDT_PATH=$(FW_FDT_PATH),)
ifeq ($(XLEN), 32)
sbi-mk += PLATFORM_RISCV_ISA=rv32ima PLATFORM_RISCV_XLEN=32
else
sbi-mk += PLATFORM_RISCV_ISA=rv64imafdc_zifencei PLATFORM_RISCV_XLEN=64
endif

# U-Boot options
ifeq ($(XLEN), 32)
UIMAGE_LOAD_ADDRESS := 0x80400000
UIMAGE_ENTRY_POINT  := 0x80400000
else
UIMAGE_LOAD_ADDRESS := 0x80200000
UIMAGE_ENTRY_POINT  := 0x80200000
endif

# default configure flags
tests-co              = --prefix=$(RISCV)/target

# specific flags and rules for 32 / 64 version
ifeq ($(XLEN), 32)
isa-sim-co            = --prefix=$(RISCV) --with-isa=RV32IMA --with-priv=MSU
else
isa-sim-co            = --prefix=$(RISCV)
endif

# default make flags
isa-sim-mk              = -j$(NR_CORES)
tests-mk         		= -j$(NR_CORES)
buildroot-mk       		= -j$(NR_CORES) \
							HOSTCC=gcc-11.2.0 \
							HOSTCXX=g++-11.2.0 \
							HOSTCPP=cpp-11.2.0

# linux image
buildroot_defconfig = configs/buildroot$(XLEN)_defconfig
linux_defconfig = configs/linux$(XLEN)_defconfig
busybox_defconfig = configs/busybox$(XLEN).config

install-dir:
	mkdir -p $(RISCV)

isa-sim: install-dir $(CC) 
	mkdir -p riscv-isa-sim/build
	cd riscv-isa-sim/build;\
	../configure $(isa-sim-co);\
	make $(isa-sim-mk);\
	make install;\
	cd $(ROOT)

tests:# install-dir $(CC)
	rm -rf install64/target/
	make -C riscv-tests/benchmarks clean
	mkdir -p riscv-tests/build
	cd riscv-tests/build;\
	autoconf;\
	../configure $(tests-co);\
	patch Makefile ../../configs/riscv-tests_build_Makefile.patch; \
	make benchmarks $(tests-mk);\
	make install;\
	cd $(ROOT)

$(CC): $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig)
	make -C buildroot defconfig BR2_DEFCONFIG=../$(buildroot_defconfig)
	make -C buildroot host-gcc-final $(buildroot-mk)

# NOTE: Apply patches instead of forking and updating all submodules
# TODO:	Align this properly before production (if ever)
SUBMODULES := u-boot opensbi riscv-tests
PATCH_SUBMODULES := $(addprefix patch_, $(SUBMODULES))

all:  $(CC) isa-sim patch_submodules

patch_submodules: submodules_update $(PATCH_SUBMODULES)

submodules_update:
	rm -rf $(SUBMODULES)
	git submodule update --init --recursive

patch_riscv-tests:
	cd riscv-tests/env/; git checkout master
	-cd riscv-tests; git apply ../configs/riscv-test.patch

patch_u-boot:
	-cd u-boot; git apply ../configs/u-boot.patch

patch_opensbi:
	cd opensbi; git apply ../configs/opensbi.patch

# benchmark for the cache subsystem
rootfs/cachetest.elf: $(CC)
	cd ./cachetest/ && $(CC) cachetest.c -o cachetest.elf
	cp ./cachetest/cachetest.elf $@

# benchmark for the cache subsystem
rootfs/rvv_hello.elf: rvv_hello/rvv_hello.c $(CC)
	$(CC) -g $< -march=rv64gcv -o $@
	$(TOOLCHAIN_PREFIX)objdump -D -S $@ > rvv_hello/rvv_hello.dump

# cool command-line tetris
rootfs/tetris: $(CC)
	cd ./vitetris/ && make clean && ./configure CC=$(CC) && make
	cp ./vitetris/tetris $@

# TODO: add rv64uv from ara
# NOTE: this submodule would actually need some update
rootfs/riscv-tests/benchmarks: tests
	mkdir -p $@
	cp -r $(RISCV)/target/share/riscv-tests/benchmarks/*riscv $@
	chmod +x $@/*

rootfs/ara:
#	NOTE: this must be filled-in from the Ara repo
	mkdir -p $@

$(RISCV)/vmlinux: $(buildroot_defconfig) $(linux_defconfig) $(busybox_defconfig) $(CC) rootfs/rvv_hello.elf rootfs/cachetest.elf rootfs/tetris rootfs/riscv-tests/benchmarks rootfs/ara
	mkdir -p $(RISCV)
	make -C buildroot $(buildroot-mk)
	cp buildroot/output/images/vmlinux $@
	$(TOOLCHAIN_PREFIX)objdump -d -S $(RISCV)/vmlinux > $(RISCV)/vmlinux.dump

$(RISCV)/Image: $(RISCV)/vmlinux
	$(OBJCOPY) -O binary -R .note -R .comment -S $< $@

$(RISCV)/Image.gz: $(RISCV)/Image
	$(GZIP_BIN) -9 --force $< > $@

# U-Boot-compatible Linux image
$(RISCV)/uImage: $(RISCV)/Image.gz $(MKIMAGE)
	$(MKIMAGE) -A riscv -O linux -T kernel -a $(UIMAGE_LOAD_ADDRESS) -e $(UIMAGE_ENTRY_POINT) -C gzip -n "CV$(XLEN)A6Linux" -d $< $@

$(RISCV)/u-boot.bin: u-boot/u-boot.bin
	mkdir -p $(RISCV)
	cp $< $@
	# Also bring ELF and build annotated dump into install DIR
	cp u-boot/u-boot $(RISCV)/
	$(TOOLCHAIN_PREFIX)objdump -d -S  u-boot/u-boot > $(RISCV)/u-boot.dump


$(MKIMAGE) u-boot/u-boot.bin: $(CC)
	make -C u-boot pulp-platform_cheshire_defconfig
	make -C u-boot CROSS_COMPILE=$(TOOLCHAIN_PREFIX)

# spl: u-boot/spl/u-boot.spl.bin
# u-boot/spl/u-boot.spl.bin: $(CC)
# 	make -C u-boot pulp-platform_cheshire_defconfig
# 	make -C u-boot spl/u-boot-spl CROSS_COMPILE=$(TOOLCHAIN_PREFIX) CONFIG_SUPPORT_SPL=y

# OpenSBI with u-boot as payload
$(RISCV)/fw_payload.bin: $(RISCV)/u-boot.bin dtb
	make -C opensbi FW_PAYLOAD_PATH=$< $(sbi-mk)
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/fw_payload.bin
	# Also bring in dump
	$(TOOLCHAIN_PREFIX)objdump -D -S  opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf > $(RISCV)/fw_payload.dump
# cp opensbi/build/platform/$(PLATFORM)/firmware/fw_jump.elf $(RISCV)/fw_jump.elf
# cp opensbi/build/platform/$(PLATFORM)/firmware/fw_jump.bin $(RISCV)/fw_jump.bin
# # Also bring in dump
# $(TOOLCHAIN_PREFIX)objdump -D -S  opensbi/build/platform/$(PLATFORM)/firmware/fw_jump.elf > $(RISCV)/fw_jump.dump

# OpenSBI for Spike with Linux as payload
$(RISCV)/spike_fw_payload.elf: PLATFORM=generic
$(RISCV)/spike_fw_payload.elf: $(RISCV)/Image dtb
	make -C opensbi FW_PAYLOAD_PATH=$< $(sbi-mk)
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/spike_fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/spike_fw_payload.bin
	$(TOOLCHAIN_PREFIX)objdump -d -S $(RISCV)/spike_fw_payload.elf > $(RISCV)/spike_fw_payload.dump

# same as spike_fw_payload, but don't override PLATFORM
# also include FDT in the binary for convenience 
in_memory_fw_payload: $(RISCV)/in_memory_fw_payload.elf
$(RISCV)/in_memory_fw_payload.elf: $(RISCV)/Image dtb
	make -C opensbi FW_PAYLOAD_PATH=$< $(sbi-mk)
# cp opensbi/build/platform/$(PLATFORM)/firmware/fw_jump.elf $(RISCV)/in_memory_fw_jump.elf
# cp opensbi/build/platform/$(PLATFORM)/firmware/fw_jump.bin $(RISCV)/in_memory_fw_jump.bin
# $(TOOLCHAIN_PREFIX)objdump -D -S $(RISCV)/in_memory_fw_jump.elf > $(RISCV)/in_memory_fw_jump.dump
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.elf $(RISCV)/in_memory_fw_payload.elf
	cp opensbi/build/platform/$(PLATFORM)/firmware/fw_payload.bin $(RISCV)/in_memory_fw_payload.bin
# Not necessary, since it is just fw_jump + vmlinux dumps
# $(TOOLCHAIN_PREFIX)objdump -D -S $(RISCV)/in_memory_fw_payload.elf > $(RISCV)/in_memory_fw_payload.dump

spi_boot: fw_payload.bin uImage

# This is just an utility target to workaround some wierd behaviour on the IIS machines
dtb:
	cd ../cheshire_fork/; make dtb

# need to run flash-sdcard with sudo -E, be careful to set the correct SDDEVICE
DT_SECTORSTART 		:= 2048
DT_SECTOREND   		:= 264191	# 2048 + 128M
FW_SECTORSTART 		:= 264192
FW_SECTOREND   		:= 526335	# 264192 + 128M
UIMAGE_SECTORSTART 	:= 526336
UIMAGE_SECTOREND	:= 1050623	# 526336 + 256M
ROOT_SECTORSTART	:= 1050624
ROOT_SECTOREND		:= 0

flash-sdcard: $(RISCV)/fw_payload.bin $(RISCV)/uImage format-sd
	dd if=$(RISCV)/fw_payload.bin of=$(SDDEVICE)2 status=progress oflag=sync bs=1M
	dd if=$(RISCV)/uImage         of=$(SDDEVICE)3 status=progress oflag=sync bs=1M
	mkfs.fat -F32 -n "CHESHIRE" $(SDDEVICE)4
	@echo "Don't forget to flash the device tree binary to $(SDDEVICE)1 :)"

format-sd: $(SDDEVICE)
	@test "$(shell whoami)" = "root" || (echo 'This has to be run with sudo or as root, Ex: sudo -E make flash-sdcard SDDEVICE=/dev/sdc' && exit 1)
	@test -n "$(SDDEVICE)" || (echo 'SDDEVICE must be set, Ex: make flash-sdcard SDDEVICE=/dev/sdc' && exit 1)
	sgdisk --clear -g --new=1:$(DT_SECTORSTART):$(DT_SECTOREND) --new=2:$(FW_SECTORSTART):$(FW_SECTOREND) --new=3:$(UIMAGE_SECTORSTART):$(UIMAGE_SECTOREND) --new=4:$(ROOT_SECTORSTART):$(ROOT_SECTOREND) --typecode=1:b000 --typecode=2:3000 --typecode=3:8300 --typecode=4:8200 $(SDDEVICE)

# specific recipes
gcc: $(CC)
vmlinux: $(RISCV)/vmlinux
fw_payload.bin: $(RISCV)/fw_payload.bin
uImage: $(RISCV)/uImage
spike_payload: $(RISCV)/spike_fw_payload.elf

images: $(CC) $(RISCV)/fw_payload.bin $(RISCV)/uImage

clean_spi_boot:
	make -C u-boot clean
	make -C opensbi clean
	rm -rf $(RISCV)/*Image* $(RISCV)/vmlinux $(RISCV)/u-boot*

clean_in_memory_fw_payload:
	make -C opensbi clean
	rm -rf $(RISCV)/Image* $(RISCV)/vmlinux $(RISCV)/in_memory_fw_payload.*

clean_linux:
	make -C buildroot linux-dirclean
	rm -rf $(RISCV)/*_payload* $(RISCV)/*_jump* $(RISCV)/uImage $(RISCV)/Image.gz $(RISCV)/vmlinux

clean:
	rm -rf $(RISCV)/vmlinux cachetest/*.elf rootfs/tetris rootfs/cachetest.elf
	rm -rf $(RISCV)/*_payload* $(RISCV)/*_jump* $(RISCV)/uImage $(RISCV)/Image.gz
	make -C u-boot clean
	make -C opensbi distclean

clean-all: clean
	rm -rf $(RISCV) riscv-isa-sim/build riscv-tests/build
	make -C buildroot clean

.PHONY: gcc vmlinux images help fw_payload.bin uImage

help:
	@echo "usage: $(MAKE) [tool/img] ..."
	@echo ""
	@echo "install compiler with"
	@echo "    make gcc"
	@echo ""
	@echo "install [tool] with compiler"
	@echo "    where tool can be any one of:"
	@echo "        gcc isa-sim tests"
	@echo ""
	@echo "build linux images for cva6"
	@echo "        make images"
	@echo "    for specific artefact"
	@echo "        make [vmlinux|uImage|fw_payload.bin]"
	@echo ""
	@echo "flash firmware and linux images to sd card"
	@echo "    has to be run as root or with sudo -E:"
	@echo "        make flash-sdcard SDDEVICE=/dev/sdX"
	@echo ""
	@echo "There are two clean targets:"
	@echo "    Clean only build object"
	@echo "        make clean"
	@echo "    Clean everything (including toolchain etc)"
	@echo "        make clean-all"
