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

usage() { echo "Usage: $0 -i input_iso -o output.iso -w work_dir -k gpg_key -s ssh_file" 1>&2; exit 1; }

while getopts "i:o:w:s:k:" o; do
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
        s)
            ssh_file=$OPTARG
            ;;
        k)
            gpg_key=$OPTARG
            ;;
        *)
            echo "bad option provided"
            usage
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "${input_file}" ] || [ -z "${output_file}" ] || [ -z "${work_dir}" ] || [ -z "${ssh_file}" ] || [ -z "${gpg_key}" ] ; then
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

# modify the config file

echo "modifying the config file ..."
new_cloud_file="new_sqfs/etc/cloud/cloud.cfg"
sudo patch -u ${new_cloud_file} <<'EOF'
--- /tmp/cloud.cfg	2024-01-12 19:21:26.844595676 -0500
+++ ./cloud.cfg	2024-01-12 19:22:29.445512906 -0500
@@ -78,6 +78,10 @@
    default_user:
      name: installer
      lock_passwd: false
+     # password r00tme
+     passwd: $6$.c38i4RIqZeF4RtR$hRu2RFep/.6DziHLnRqGOEImb15JT2i.K/F9ojBkK/79zqY30Ll2/xx6QClQfdelLe.ZjpeVYfE8xBBcyLspa/
+     ssh_authorized_keys:
+       - HERE_YOUR_SSH_KEY
      gecos: Ubuntu
      groups: [adm, audio, cdrom, dialout, dip, floppy, lxd, netdev, plugdev, sudo, video]
      sudo: ["ALL=(ALL) NOPASSWD:ALL"]
EOF

# now replace HERE_YOUR_SSH_KEY with the public key
sudo sed -i "s/HERE_YOUR_SSH_KEY/$(sed 's:/:\\/:g' ${ssh_file})/" ${new_cloud_file}


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

#
# print out command for creating new iso file
#
xorriso_flags=`xorriso -indev ${ifile} -report_el_torito cmd | grep "^-" | sed 's/ [-][-]interval.*/\ EFI\.img/g' | sed 's/[=][-][-]interval.*/\=mbr\.img/g' | tr '\n' ' '`
echo "now execute these commands:"
echo "cd ${work_dir}"
echo "xorriso -outdev ${output_file} -map mod_disk / -- ${xorriso_flags}"
