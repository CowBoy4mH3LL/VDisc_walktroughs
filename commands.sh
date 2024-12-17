P=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

ARCH=x86_64
AFL_PATH=$P/AFLplusplus
AFL=$AFL_PATH/afl-fuzz
QEMU=$AFL_PATH/afl-qemu-trace
TARGET_PATH=$P/DV_OT_APP
source $TARGET_PATH/commands.sh
B=$TARGET_PATH/vuln_app
H=
I=$P/inputs
O=$P/results

p_prepare(){
    (
        set =eu
        sudo apt-get update
        sudo apt-get install -y build-essential python3-dev automake cmake git flex bison libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev
        # try to install llvm 14 and install the distro default if that fails
        sudo apt-get install -y lld-14 llvm-14 llvm-14-dev clang-14 || sudo apt-get install -y lld llvm llvm-dev clang
        sudo apt-get install -y gcc-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-plugin-dev libstdc++-$(gcc --version|head -n1|sed 's/\..*//'|sed 's/.* //')-dev
        sudo apt-get install -y ninja-build # for QEMU mode
        sudo apt-get install -y cpio libcapstone-dev # for Nyx mode
        sudo apt-get install -y wget curl # for Frida mode
        sudo apt-get install -y python3-pip # for Unicorn mode
    )
}

p_build_afl(){
    (
        set -eu
        cd $AFL_PATH
        NO_PYTHON=1 NO_UNICORN_ARM64=1 NO_CORESIGHT=1 NO_NYX=1 CPU_TARGET=$ARCH make binary-only
    ) 
}
p_build_afl_with_hooking(){
    (
        set -eu
        cd $AFL_PATH
        NO_PYTHON=1 NO_UNICORN_ARM64=1 NO_CORESIGHT=1 NO_NYX=1 CPU_TARGET=$ARCH ENABLE_HOOKING=1 GLIB_H=$GLIB_H GLIB_CONFIG_H=$GLIB_CONFIG_H make binary-only #TODO remove the NO_CHECKOUT when PR is merged
    ) 
}

p_build_target_with_stdin_io(){
    (
        set -eu
        v_clean
        export STDIN_ONLY=1
        v_build
    )
}

p_build_target_with_can_io(){
    (
        set -eu
        v_clean
        export STDIN_ONLY=0
        v_build
    )
}

p_run_raw(){
    v_run
}

p_run_with_qemu(){
    (
        set -eu
        #set -x
        trap 'test $? -ne 0 && echo -e "\033[0;31musage: $FUNCNAME required ENVIRONMENT:
        <O>: Output directory
        [<H>]: Hooks library"' EXIT
        if [ -n "$H" ];then
            QEMU_PLUGIN="file=$PLUGIN_PATH/build/plugin.so,arg=$H" $QEMU -- "$B"
        else
            $QEMU -- "$B"
        fi
    )
}

p_fuzz(){
    (
        set -eu

        trap 'test $? -ne 0 && echo -e "\033[0;31musage: $FUNCNAME required ENVIRONMENT:
        <O>: Output directory
        [<H>]: Hooks library"' EXIT

        local afl_out="$O/afl_out"

        #~ Setup some AFL prereqs
        mkdir -p $afl_out
        rm -rf "${afl_out:?}"/*

        #~ Fuzz
        if [ -n "$H" ];then
            export QEMU_PLUGIN="file=$PLUGIN_PATH/build/plugin.so,arg=$H"
            export QEMU_LOG=plugin
            export QEMU_LOG_FILENAME=$O/plugin.log
        fi
        export AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1
        export AFL_PATH=$AFL_PATH
        $AFL -Q -i $I -o $afl_out -- $B

        set +eu
    )
}