##!/bin/bash
# Bash Color
green='\e[32m'
red='\e[31m'
yellow='\e[33m'
blue='\e[34m'
lgreen='\e[92m'
lyellow='\e[93m'
lblue='\e[94m'
lmagenta='\e[95m'
lcyan='\e[96m'
blink_red='\033[05;31m'
restore='\033[0m'
reset='\e[0m'

# NetHunter Stage 1 Kernel Build Script
# The resulting nethunter kernel zip can be 
# extracted into the 
# nethunter-installer/devices/<Android Version>/<device>/
# directory
# 
# This script if heavily based on work by holyangle
# https://gitlab.com/HolyAngel/op7
##############################################


####################################################################
# Load configuration:                                              #

# Build directory
BUILD_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source ${BUILD_DIR}/config

##############################################
# Functions
##############################################
# Pause
function pause() {
	local message="$@"
	[ -z $message ] && message="Press [Enter] to continue.."
	read -p "$message" readEnterkey
}

function ask() {
    	# http://djm.me/ask
    	while true; do

        	if [ "${2:-}" = "Y" ]; then
        		prompt="Y/n"
        		default=Y
        	elif [ "${2:-}" = "N" ]; then
        		prompt="y/N"
            		default=N
        	else
            		prompt="y/n"
            		default=
        	fi

        	# Ask the question
        	question	
        	read -p "$1 [$prompt] " REPLY

        	# Default?
        	if [ -z "$REPLY" ]; then
        		REPLY=$default
        	fi

        	# Check if the reply is valid
        	case "$REPLY" in
        		Y*|y*) return 0 ;;
        		N*|n*) return 1 ;;
        	esac
    	done
}

function info() {
        printf "${lcyan}[   INFO   ]${reset} $*${reset}\n"
}

function success() {
        printf "${lgreen}[ SUCCESS  ]${reset} $*${reset}\n"
}

function warning() {
        printf "${lyellow}[ WARNING  ]${reset} $*${reset}\n"
}

function error() {
        printf "${lmagenta}[  ERROR   ]${reset} $*${reset}\n"
}

function question() {
        printf "${yellow}[ QUESTION ]${reset} "
}

# Clean nhkernel directory
function make_nhclean() {
	printf "\n"
	info "Cleaning up NetHunter kernel zip directory"
	rm -rf $NHKERNEL_DIR/*
	success "NetHunter kernel zip directory cleaned"
}

# Clean anykernel directory
function make_aclean() {
	printf "\n"
	info "Cleaning up anykernel zip directory"
	rm -rf $ANYKERNEL_DIR/Image* $ANYKERNEL_DIR/dtb $CHANGELOG ${ANYKERNEL_DIR}/modules
	success "Anykernel directory cleaned"
}

# Clean "out" folders
function make_oclean() {
	printf "\n"
	info "Cleaning up kernel-out & modules-out directories"
	rm -rf "$KERNEL_OUT"
	rm -rf "$MODULES_OUT"
	success "Out directories removed!"
}

# Clean source tree
function make_sclean() {
	local confdir=${KDIR}/arch/$ARCH/configs
	printf "\n"
	info "Cleaning source directory"
	if [ -f ${confdir}/$CONFIG.old ]; then
	        rm -f ${confdir}/$CONFIG.old 
	fi
	if [ -f ${confdir}/$CONFIG.new ]; then
	        rm -f ${confdir}/$CONFIG.new 
	fi
	#make -C $KDIR clean && make -C $KDIR mrproper
	success "Source directory cleaned"
}

# Full clean 
function make_fclean() {
	printf "\n"
	make_nhclean
	make_aclean
	make_oclean
	make_sclean
	pause
}

# Download file via http(s); required arguments: <URL> <download directory>
function wget_file {
        local url=${1}
        local dir=${2}
        local file="${url##*/}"
        if [ -f ${dir}/${file} ]; then
                if ask "Existing image file found. Delete and download a new one?" "N"; then
                        rm -f ${dir}/${file}
                else
                        warning "Using existing archive"
                        return 0 
                fi
        fi
        info "Downloading ${file}"
        axel --alternate -o ${dir}/${file} "$url"
	if [ $? -eq 0 ]; then
		printf "\n"
		success "Download successful"
	else
		printf "\n"
		error "Download failed"
                return 1
	fi
	get_sha "${url}" ${dir}
	if [ $? -eq 0 ]; then
		printf "\n"
		success "Download successful"
                return 0
	else
		printf "\n"
		error "Download failed"
                return 1
	fi
}

# Download file via http(s); required arguments: <URL> <download directory>
function get_sha {
        local url=${1}
	local sha_url=${url}.sha256
        local dir=${2}
        local file="${url##*/}"
        local sha_file="${sha_url##*/}"
        info "Getting SHA"
        if [ -f ${dir}/${sha_file} ]; then
                rm -f ${dir}/${sha_file}
        fi
        axel --alternate -o ${dir}/${sha_file} "$sha_url"
	if [ $? -ne 0 ]; then
	        if ask "Could not verify file integrity. Continue without verification?" "Y"; then 
		        return 0
		else
			return 1
		fi
	fi
	verify_sha256 "${sha_file}" "${dir}"
	if [ $? -ne 0 ]; then
	        if ask "File verification failed. File may be corrupted. Continue anyway?" "Y"; then 
		        return 0
		else
			return 1
		fi
	fi
}

# Verfify file against 256sha; required argument <sha file> <directory>
function verify_sha256 {
	local sha=$1
	local dir=$2
        info "Verifying integrity of downloaded file"
	cd ${dir}
        sha256sum -c ${sha} || { 
                error "Rootfs corrupted. Please run this installer again or download the file manually"
	        cd -
                return 1
        }
	cd -
	return 0
}

# Install dependencies
function get_dependencies() {
        info "Installing dependencies"
        sudo apt-get update
        sudo apt-get install $PKG_DEPEND
}

# Download toolchain; required arguments: "source URL" "Download type(wget/git)" 
function get_toolchain() {
	local url=$1
	local type=$2
        local TMP_DIR="${BUILD_DIR}/toolchain_archs"
	if [ ${type} == "wget" ]; then
	        wget_file ${url} ${TMP_DIR}
		return $?
	else
	        error "Download type ${type} not availabe"
	fi
}

# Download all toolchains
function get_toolchains() {
        local ARCH_DIR="${BUILD_DIR}/toolchain_archs"
	mkdir -p ${ARCH_DIR}
	## clang 
        if [ ! -z "${CLANG_SRC}" ]; then
		printf "\n"
		info "Downloading clang toolchain"
		if [ -z "${CLANG_SRC_TYPE}" ]; then
                        CLANG_SRC_TYPE="wget"
		fi
	        get_toolchain ${CLANG_SRC} ${CLANG_SRC_TYPE}
	        if [ $? -eq 0 ]; then
			if [ -d ${CLANG_ROOT} ]; then
				if ask "Clang directory exists. Overwrite?" "N"; then 
					rm -rf ${CLANG_ROOT}
				fi
			fi
			if [ ! -d ${CLANG_ROOT} ]; then
                                local archive="${CLANG_SRC##*/}"	
			        mkdir -p ${CLANG_ROOT}		
		                tar -xJf ${ARCH_DIR}/${archive} -C ${CLANG_ROOT} --strip-components=1 
			else
				warning "Skipping ${archive}"
			fi
		        info "Done"
		fi
	fi
	## gcc32
        if [ ! -z "${CROSS_COMPILE_ARM32_SRC}" ]; then
		printf "\n"
		info "Downloading 32bit gcc toolchain"
		if [ -z "${CROSS_COMPILE_ARM32_TYPE}" ]; then
                        CROSS_COMPILE_ARM32_TYPE="wget"
		fi
	        get_toolchain ${CROSS_COMPILE_ARM32_SRC} ${CROSS_COMPILE_ARM32_TYPE}
	        if [ $? -eq 0 ]; then
			if [ -d ${CCD32} ]; then
				if ask "GCC 32bit directory exists. Overwrite?" "N"; then 
					rm -rf ${CCD32}
				fi
			fi
			if [ ! -d ${CCD32} ]; then
                                local archive="${CROSS_COMPILE_ARM32_SRC##*/}"	
			        mkdir -p ${CCD32}		
		                tar -xJf ${ARCH_DIR}/${archive} -C ${CCD32} --strip-components=1 
			else
				warning "Skipping ${archive}"
			fi
		        info "Done"
		fi
	fi
	## gcc64
        if [ ! -z "${CROSS_COMPILE_SRC}" ]; then
		printf "\n"
		info "Downloading 64bit gcc toolchain"
		if [ -z "${CROSS_COMPILE_SRC_TYPE}" ]; then
                        CROSS_COMPILE_SRC_TYPE="wget"
		fi
	        get_toolchain ${CROSS_COMPILE_SRC} ${CROSS_COMPILE_SRC_TYPE}
	        if [ $? -eq 0 ]; then
			if [ -d ${CCD64} ]; then
				if ask "GCC 64bit directory exists. Overwrite?" "N"; then 
					rm -rf ${CCD64}
				fi
			fi
			if [ ! -d ${CCD64} ]; then
                                local archive="${CROSS_COMPILE_SRC##*/}"	
			        mkdir -p ${CCD64}		
		                tar -xJf ${ARCH_DIR}/${archive} -C ${CCD64} --strip-components=1 
			else
				warning "Skipping ${archive}"
			fi
		        info "Done"
		fi
	fi
	pause
}        

# Create kernel compilation working directories
function setup_dirs() {
	info "Creating new out directory"
	mkdir -p "$KERNEL_OUT"
	success "Created new out directory"
	info "Creating new modules_out directory"
	mkdir -p "$MODULES_OUT"
	success "Created new modules_out directory"
}

# Setup environment
function setup_env() {
	setup_dirs
	get_dependencies
	get_toolchains
}

# Edit .config in working directory
function edit_config() {
	printf "\n"
	if ask "Edit the kernel config?" "Y"; then
		info "Creating custom  config" 
	        make -C $KDIR O="$KERNEL_OUT" CC=clang $CONFIG menuconfig
	else
		info "Create config"
		make -C $KDIR O="$KERNEL_OUT" CC=clang $CONFIG
	fi
	cfg_done=true
}

# Edit defconfig in kernel source directory
function make_config() {
	local tmpdir=/tmp/nethunter-kernel
	local confdir=${KDIR}/arch/$ARCH/configs
	printf "\n"
	info "Editing $CONFIG"
	if [ -d ${tmpdir} ]; then
		rm -rf ${tmpdit}
	fi
	mkdir -p ${tmpdir}
	make -C $KDIR O="${tmpdir}" CC=clang $CONFIG menuconfig
	if ask "Replace existing $CONFIG with this one?"; then
		cp -f ${confdir}/$CONFIG ${confdir}/$CONFIG.old
		cp -f ${tmpdir}/.config ${confdir}/$CONFIG
		info "Done. Old config backed up as $CONFIG.old"
	else
		cp -f ${tmpdir}/.config ${confdir}/$CONFIG.new
		info "Config saved as $CONFIG.new"
	fi
	pause
}

# Compile the kernel
function make_kernel() {
	printf "\n"
	if [ ! "$cfg_done" = true ]; then
		if ask "Edit the kernel config?" "Y"; then
			info "Creating custom  config" 
	  	      	make -C $KDIR O="$KERNEL_OUT" CC=clang $CONFIG menuconfig
		fi
	fi
	info "~~~~~~~~~~~~~~~~~~"
	info " Building kernel"
	info "~~~~~~~~~~~~~~~~~~"
	time make -C $KDIR O="$KERNEL_OUT" CC=clang -j "$THREADS"
	time make -C $KDIR O="$KERNEL_OUT" CC=clang -j "$THREADS" INSTALL_MOD_PATH=$MODULES_OUT modules_install
	rm -f ${MODULES_OUT}/lib/modules/*${LOCALVERSION}/source
	rm -f ${MODULES_OUT}/lib/modules/*${LOCALVERSION}/build
	success "Kernel build completed"
	pause
}

# Generate the NetHunter kernel zip - to be extracted in the devices folder of the nethunter-installer
function make_nhkernel_zip() {
	printf "\n"
	mkdir -p ${UPLOAD_DIR}
	mkdir -p ${NHKERNEL_DIR}
	info "Copying kernel to NetHunter kernel zip directory"
	cp "$KERNEL_IMAGE" "$NHKERNEL_DIR"
	if [ "$DO_DTBO" = true ]; then
		info "Copying dtbo to zip directory.."
		cp "$DTBO_IMAGE" "$NHKERNEL_DIR"
	fi
	if [ "$DO_DTB" = true ]; then
		info "Generating dtb in zip directory.."
		make_dtb ${NHKERNEL_DIR}
	fi
	if [ -d ${MODULES_OUT}/lib ]; then
		info "Copying modules to zip directory.."
		mkdir -p ${NHKERNEL_DIR}/${MODULE_DIRTREE}
		cp -r ${MODULES_OUT}/lib ${NHKERNEL_DIR}/${MODULE_DIRTREE}/
	fi	
	success "Done"
	printf "\n"
	info "Creating NetHunter kernel zip file"
	cd "$NHKERNEL_DIR"
	zip -r "$NH_ARCHIVE" *
	info "Moving NetHunter kernel zip to output directory"
	mv "$NH_ARCHIVE" "$UPLOAD_DIR" 
	printf "\n"
	success "NetHunter kernel zip:\n${lcyan}$NH_ARCHIVE\n${reset}is now available in:\n${lcyan}${UPLOAD_DIR}"
	cd $BUILD_DIR
	printf "\n"
	pause
}

# Generate the anykernel zip
function make_anykernel_zip() {
	printf "\n"
	mkdir -p ${UPLOAD_DIR}
	info "Copying kernel to anykernel zip directory"
	cp "$KERNEL_IMAGE" "$ANYKERNEL_DIR"
	if [ "$DO_DTBO" = true ]; then
		info "Copying dtbo to zip directory"
		cp "$DTBO_IMAGE" "$ANYKERNEL_DIR"
	fi
	if [ "$DO_DTB" = true ]; then
		info "Generating dtb in zip directory"
		make_dtb ${ANYKERNEL_DIR}
	fi
	if [ -d ${MODULES_OUT}/lib ]; then
		info "Copying modules to zip directory"
		mkdir -p ${ANYKERNEL_DIR}/${MODULE_DIRTREE}
		cp -r ${MODULES_OUT}/lib ${ANYKERNEL_DIR}/${MODULE_DIRTREE}
	fi	
	success "Done"
	make_clog
	printf "\n"
	info "Creating anykernel zip file"
	cd "$ANYKERNEL_DIR"
	zip -r "$ANY_ARCHIVE" *
	info "Moving anykernel zip to output directory"
	mv "$ANY_ARCHIVE" "$UPLOAD_DIR" 
	printf "\n"
	success "Anykernel zip:\n${lcyan}$ANY_ARCHIVE\n${reset}is now available in:\n${lcyan}${UPLOAD_DIR}"
	cd $BUILD_DIR
	printf "\n"
	pause
}

# Function to generate a dtb image, expects output directory as argument
function make_dtb() {
	local dtb_dir=$1
	printf "\n"
	info "Generating DTB Image"
	$DTBTOOL -2 -o $dtb_dir/dtb -s 2048 -p $KERNEL_OUT/scripts/dtc/ $KERNEL_OUT/arch/arm64/boot/dts/qcom/
	success "DTB generated"
}

# Generate Changelog
function make_clog() {
	printf "\n"
	info "Generating Changelog"
	rm -rf $CHANGELOG
	touch $CHANGELOG
	for i in $(seq 180);
	do
		local After_Date=`date --date="$i days ago" +%F`
		local kcl=$(expr $i - 1)
		local Until_Date=`date --date="$kcl days ago" +%F`
		printf "====================" >> $CHANGELOG;
		printf "     $Until_Date    " >> $CHANGELOG;
		printf "====================" >> $CHANGELOG;
		git log --after=$After_Date --until=$Until_Date --pretty=tformat:"%h  %s  [%an]" --abbrev-commit --abbrev=7 >> $CHANGELOG
		printf "" >> $CHANGELOG;
	done
	sed -i 's/project/ */g' $CHANGELOG
	sed -i 's/[/]$//' $CHANGELOG
	info "Done"
}

# Build the NetHunter kernel zip to be extracted in the devices directory of the nethunter-installer
function make_nethunter() {
	printf "\n"
	make_oclean
	setup_dirs
	edit_config
	make_kernel
	make_nhkernel_zip
}

# Build the test kernel zip using anykernel3
function make_test() {
	printf "\n"
	make_oclean
	setup_dirs
	edit_config
	make_kernel
	make_anykernel_zip
}

# Print README.md
function print_help() {
	pandoc ${BUILD_DIR}/README.md | lynx -stdin
}

# Main Menu
##############################################
# Display menu
show_menu() {
	clear
	printf "${lblue}"
	printf "\t##################################################\n"
	printf "\t##                                              ##\n"
	printf "\t##  88      a8P         db        88        88  ##\n"
	printf "\t##  88    .88'         d88b       88        88  ##\n"
	printf "\t##  88   88'          d8''8b      88        88  ##\n"
	printf "\t##  88 d88           d8'  '8b     88        88  ##\n"
	printf "\t##  8888'88.        d8YaaaaY8b    88        88  ##\n"
	printf "\t##  88P   Y8b      d8''''''''8b   88        88  ##\n"
	printf "\t##  88     '88.   d8'        '8b  88        88  ##\n"
	printf "\t##  88       Y8b d8'          '8b 888888888 88  ##\n"
	printf "\t##                                              ##\n"
	printf "\t####  ############# NetHunter ####################\n"
	printf "\t~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
	printf "\t           K E R N E L   B U I L D E R\n"
	printf "\t~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n"
	printf "${reset}"
	printf "\t---------------------------------------------------\n"
	printf "\t                   FULL BUILDS\n"
	printf "\t---------------------------------------------------\n"
	printf "\tN. NetHunter build = Create zip for NH-installer\n"
	printf "\tT. Test build      = Create zip to flash in TWRP\n"
	printf "\n"
	printf "\t---------------------------------------------------\n"
	printf "\t                 INDIVIDUAL STEPS\n"
	printf "\t---------------------------------------------------\n"
	printf "\t1. Edit default kernel config\n"
	printf "\t2. Configure & compile kernel from scratch\n"
	printf "\t3. Configure & recompile kernel from previous run\n"
	printf "\t4. Create NetHunter zip\n"
	printf "\t5. Create Anykernel zip\n"
	printf "\t6. Generate Changelog\n"
	printf "\t7. Edit Anykernel config\n"
 	printf "\t8. Clean Environment\n"
	printf "\n"
	printf "\t---------------------------------------------------\n"
	printf "\t                     OTHER\n"
	printf "\t---------------------------------------------------\n"
  	printf "\tS. Set up environment & download toolchains\n"
	printf "\tH. Help\n"
  	printf "\tE. Exit\n"
	printf "\n"
}
# Read menu choices
read_choice(){
	local choice
	read -p "Enter selection [N/T/1-8/S/H/E] " choice
	case ${choice,,} in
		n)
		   clear
		   make_nethunter
		   ;;
		t)
		   clear
		   make_test
		   ;;
		1)
		   clear
		   make_config
		   ;;
		2)
		   clear
		   make_oclean
		   setup_dirs
		   edit_config
		   make_kernel
		   ;;
		3)
		   clear
		   if [ "$THREADS" -gt "10" ]; then
			## limit threads to simplify debugging 
			THREADS = 10
		   fi
		   make_kernel
		   ;;
		4)
		   clear
		   make_nhclean
		   make_nhkernel_zip
		   ;;
		5)
		   clear
		   make_aclean
		   make_anykernel_zip
		   ;;
		6)
		   clear
		   make_clog
		   ;;
		7)
		   clear
		   $EDIT ${ANYKERNEL_DIR}/anykernel.sh
		   ;;
		8)
		   clear
		   make_fclean
		   ;;
                s)
		   clear
                   setup_env
                   ;;
                h)
		   clear
                   print_help
                   ;;
		e)
		   printf "${restore}\n\n"
	 	   exit 0
		   ;;
		*)
		   error "Please select a valid options" && sleep 2
	esac
}

# Main
while true
do
	unset cfg_done
	clear
	show_menu
	read_choice
done
