#!bash/bin
# This script has not been tested for complete automation!

CVA6_SDK=/usr/scratch/fenga3/vmaisto/cva6-sdk_fork

# Cross compilation variables
ARCH=riscv
CROSS_COMPILE=$CVA6_SDK/buildroot/output/host/bin/riscv64-buildroot-linux-gnu-

# Clone the kernel
KERNEL_DIR=/scratch/vmaisto/linux
git clone https://github.com/torvalds/linux.git $KERNEL_DIR


cd $KERNEL_DIR
cp $CVA6_SDK/configs/linux64_defconfig $KERNEL_DIR/arch/riscv/configs/pulp-platform_cheshire_defconfig
make pulp-platform_cheshire_defconfig
make headers
make -C tools/testing/selftests 
make -C tools/testing/selftests install

# Import the tests into CVA6-SDK
SELFTESTS_DIR_INSTALL=$KERNEL_DIR/tools/testing/selftests/kselftest_install
SELFTESTS_CVA6_INSTALL=$CVA6_SDK/rootfs/selftests
cd $CVA6_SDK
mkdir -p rootfs/selftests/
cp -r $SELFTESTS_DIR_INSTALL/riscv/           \
    $SELFTESTS_DIR_INSTALL/kselftest          \
    $SELFTESTS_DIR_INSTALL/run_kselftest.sh   \
    $SELFTESTS_CVA6_INSTALL
chmod +x $SELFTESTS_CVA6_INSTALL/run_kselftest.sh
grep $ARCH $SELFTESTS_DIR_INSTALL/kselftest-list.txt > $SELFTESTS_CVA6_INSTALL/kselftest-list.txt
sed -i "s/--foreground//g" $SELFTESTS_DIR_INSTALL/kselftest/runner.sh 

# Build rootfs.cpio calling the vmlinux target
make clean_in_memory_fw_payload in_memory_fw_payload

# See image size
ll install64/in_memory_fw_payload.elf -h
