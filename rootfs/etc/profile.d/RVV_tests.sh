echo "******************************"
echo "** Testing for RVV bindings **"
echo "******************************"
echo "- Boot log:"
dmesg | grep -E "ISA extension|ELF capabilities" 

echo "- Device tree bindings:"
echo "  File system"
echo "    "$(cat /sys/firmware/devicetree/base/cpus/cpu@0/riscv,isa; echo "")
echo "  cpuinfo"
echo "  "$(cat /proc/cpuinfo | grep isa)

echo "- Kernel config:"
echo "/proc/sys/abi/riscv_v_default_allow = "$(cat /proc/sys/abi/riscv_v_default_allow)
echo "   "$(zcat /proc/config.gz | grep RISCV_ISA_V)

echo "Vector selftests:"
cd /selftests
./run_kselftest.sh -l
./run_kselftest.sh -c riscv

# Go to home directory
cd ~