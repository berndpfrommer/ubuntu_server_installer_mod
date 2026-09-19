#!/usr/bin/bash
# -----------------------------------------------------------------------------                                              
# Copyright 2022 Bernd Pfrommer <bernd.pfrommer@gmail.com>                                                                   
#                                                                                                                            
# Licensed under the Apache License, Version 2.0 (the "License");                                                            
# you may not use this file except in compliance with the License.                                                           
# You may obtain a copy of the License at                                                                                    
#                                                                                                                            
#     http://www.apache.org/licenses/LICENSE-2.0                                                                             
#                                                                                                                            
# Unless required by applicable law or agreed to in writing, software                                                        
# distributed under the License is distributed on an "AS IS" BASIS,                                                          
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.                                                   
# See the License for the specific language governing permissions and                                                        
# limitations under the License.                                                                                             
#

# set -Eeo pipefail

usage() { 
    echo "Usage: $0 [OPTIONS]";
    echo "";
    echo "Create a modified ISO of Ubuntu installer that allows remote installation";
    echo "";
    echo "Options:";
    echo "  -h      Print this help";
    echo "  -i      Ubuntu ISO that will be used as reference";
    echo "  -o      Desired name for the final ISO file";
    echo "  -w      Working directory for the operation (default: ./)";
    echo "  -k      Your GPG key to sign the modified ISO";
    echo "  -s      The public SSH key used to remote into the installer";
    echo "  -v      Ubuntu version (24 | 26)";
    echo "";
    echo "Examples:";
    echo "  $0 -i input_iso -o output.iso -w work_dir -k gpg_key -s ssh_file"
    exit 1;
}

patch_cloud_config() {
    tmp_date=$(date "+%Y-%m-%d %H%M%S.%N -0000")
    passwd=$(tr -dc 'A-Za-z0-9!?&=.' < /dev/urandom | head -c 101)
    changes=""

    case "$1" in
        **/ubuntu-26\.*)
            changes="@@ -64,6 +64,9 @@"
            ;;
        **/ubuntu-24\.*)
            changes="@@ -78,6 +78,9 @@"
            ;;
        *)
            case ubuntu_version in
                26)
                    changes="@@ -64,6 +64,9 @@"
                    ;;
                24)
                    changes="@@ -78,6 +78,9 @@"
                    ;;
                *)
                    echo "No Ubuntu version specified and could not determine version"
                    echo "from input file. Exiting program."
            exit 1
            esac
    esac

    sudo patch -u ${new_cloud_file} <<EOF
--- /old/cloud.cfg	$tmp_date
+++ ./cloud.cfg $tmp_date
$changes
    default_user:
      name: installer
      lock_passwd: false
+     passwd: $passwd
+     ssh_authorized_keys:
+       - $(cat $ssh_file)
      gecos: Ubuntu
      groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
      sudo: ["ALL=(ALL) NOPASSWD:ALL"]
EOF
}

#TODO Add GPG Key Creation command if none is given.

while getopts "i:o:w:k:s:v:h" o; do
    case "${o}" in
        i)
            input_file=$OPTARG
            ;;
        o)
            output_file=$OPTARG
            ;;
        w)
            work_dir=$OPTARG
            ;;
        k)
            gpg_key=$OPTARG
            ;;
        s)
            ssh_file=$OPTARG
            ;;
        v)
            ubuntu_version=$OPTARG
            ;;
        h)
            usage
            ;;
        *)
            echo "--bad option provided--"
            echo ""
            usage
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "${input_file}" ] || [ -z "${output_file}" ] || [ -z "${work_dir}" ] || [ -z "${gpg_key}" ] || [ -z "${ssh_file}" ] ; then
    usage
fi

ifile=$(basename ${input_file})

cp ${input_file} ${work_dir}/
cd ${work_dir}

# MBR size is fixed
echo "extracting MBR from original disk ..."
dd bs=1 count=446 if=${ifile} of=mbr.img

sector_size=`fdisk -l ${ifile} | grep -i 'sector size' | awk '{print $4 }'`
efi_line=`fdisk -l ${ifile} | grep -i 'efi system'`
start_sector=`echo ${efi_line} | awk '{print $2}'`
num_sectors=`echo ${efi_line} | awk '{print $4}'`
echo "extracting EFI partition bs=${sector_size} start=${start_sector} count=${num_sectors}"
dd bs=${sector_size} count=${num_sectors} skip=${start_sector} if=${ifile} of=EFI.img

echo "mounting original installer disk ..."
mkdir -p orig_disk
sudo umount -q orig_disk
sudo mount ${ifile} orig_disk

echo "extracting sqfs file from disk ..."
sqfs_file_root=ubuntu-server-minimal.ubuntu-server.installer
sqfs_file=${sqfs_file_root}.squashfs

sudo cp orig_disk/casper/${sqfs_file} ./

echo "copying the file system"
mkdir -p new_sqfs
sudo rm -rf new_sqfs
sudo unsquashfs -q -d new_sqfs $sqfs_file

# modify the config file with provided data
echo "modifying the config file ..."
new_cloud_file="new_sqfs/etc/cloud/cloud.cfg"
patch_cloud_config $input_file

# make a copy of the entire installer disk
echo "making copy of entire disk"
sudo rm -rf mod_disk
sudo cp -ax orig_disk mod_disk
sudo umount orig_disk

# squash the modified files
echo "squashing the modified installer file system"
sudo rm -rf mod_disk/casper/${sqfs_file}
sudo mksquashfs new_sqfs mod_disk/casper/${sqfs_file}

# update size file
new_size=$(sudo du -sx --block-size=1 new_sqfs | cut -f1)
echo "new size: ${new_size}"
sudo echo "${new_size}" | sudo tee mod_disk/casper/${sqfs_file_root}.size

# update gpg signature
echo "computing gpg signature"
gpg_file=mod_disk/casper/${sqfs_file}.gpg
sudo rm ${gpg_file}
gpg --sign --yes --local-user ${gpg_key} --output /tmp/${sqfs_file}.gpg --detach-sign mod_disk/casper/${sqfs_file}
sudo cp /tmp/${sqfs_file}.gpg ${gpg_file}

# recompute md5 checksum
echo "computing md5 checksum"
cd mod_disk
sudo sh -c "find -type f -print0 | sudo xargs -0 md5sum > md5sum.txt"
cd ..

# print out command for creating new iso file
xorriso_flags=`xorriso -indev ${ifile} -report_el_torito cmd | grep "^-" | sed 's/ [-][-]interval.*/\ EFI\.img/g' | sed 's/[=][-][-]interval.*/\=mbr\.img/g' | tr '\n' ' '`
echo "now execute these commands:"
echo "cd ${work_dir}"
echo "xorriso -outdev ${output_file} -map mod_disk / -- ${xorriso_flags}"
