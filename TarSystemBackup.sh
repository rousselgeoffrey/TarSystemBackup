#!/bin/sh
# Backup and restore Linux installation: filesystem and bootsector.
 
filename=$2
partition=$3
 
testRoot()
{
if [ "$(id -u)" != "0" ]; then
    echo "Error: request root(UID 0) for this operation."
    exit 1
fi
}
 
testError()
{
rc=$?
if [ $rc != 0 ]; then
    echo "Error: $1";
    exit $rc;
fi
}
 
testParameters()
{
if [ "$filename" = "" ]; then
    echo "Error: filename empty."
    exit 1
fi
abspath=$(echo "$filename" | sed 's/\(.\).*/\1/')
if [ "$abspath" != "/" ]; then
    echo "Error: filename must be absolute, ex: \"/mnt/myBackupFile\"."
    exit 1
fi
 
if [ "$partition" = "" ]; then
    echo "Error: partition empty."
    exit 1
fi
if ! echo "$partition" | grep -E '^/dev/sd' > /dev/null; then
    echo "Error: partition must be of the form \"/dev/sdXY\"."
    exit 1
fi
}
 
backup()
{
echo "Backup filesystem."
echo "------------------"
testRoot
testParameters
echo
echo "Backup to: \"$filename\" from: \"$partition\" "
echo Press enter to start.
read key
 
# Ensure partition is unmounted then mount it
umount $partition > /dev/null 2>&1

# Temporary mount point
backup_path=$(mktemp -d /tmp/backup_XXXXXXXX)
mount $partition $backup_path
testError "cannot mount partition."
 
# TODO: check to see if we have enough free space on partition(chroot)...if not unmount and quit
# TODO: check to see if we have enough free space on destination("$filename" path)...if not unmount and quit
 
# Create possible intermediary parent dirs for output file
# Should not be needed...
ppath=$(echo "$filename" | sed 's/\/[^\/]*$//')
mkdir -p "$ppath"
 
# Enter chroot
# Note that the tarball will be created inside the chroot
# Create the tarball in chroots' /tmp
# then -find- to save SUID and SGID file list
tmp_backup_file=$(mktemp /tmp/backup_data_XXXXXXXX)
cat << EOF | chroot "$backup_path/"
cd /
tar -cvpzf "$tmp_backup_file" \
--exclude="$tmp_backup_file" \
--exclude=/proc \
--exclude=/tmp \
--exclude=/mnt \
--exclude=/dev \
--exclude=/sys \
--exclude=/run \
--exclude=/media \
--exclude=/home/*/.cache \
--exclude=/home/*/.local/share/Trash \
--exclude=/var/log \
--exclude=/var/cache/apt/archives /
find / -perm -4000 -print > "$tmp_backup_file.SUID"
find / -perm -2000 -print > "$tmp_backup_file.SGID"
EOF
# ^EOF exit chroot
 
# Move the file to final destination, so we can unmount partition
echo
echo "Moving files to final destination...this can take a long time."
mv "$backup_path/$tmp_backup_file" "$filename"
testError "cannot move backup to final destination."
 
# Also move SUID and SGID file list
mv "$backup_path/$tmp_backup_file.SUID" "$filename.SUID"
mv "$backup_path/$tmp_backup_file.SGID" "$filename.SGID"
 
# Unmount
umount $backup_path
testError "cannot unmount partition."
 
echo
echo "Backup boot sector..."
disk=$(echo $partition | sed 's/[0-9]*$//')
dd if=$disk of=$filename.MBR bs=512 count=1
testError "cannot backup MBR."
 
echo "Done."
}
 
restore()
{
echo "Restore filesystem."
echo "-------------------"
testRoot
testParameters
echo
echo "Restore from: \"$filename\" to: \"$partition\""
echo "Press enter to start."
read key
 
# Ensure partition is unmounted then mount it
umount $partition > /dev/null 2>&1
 
restore_path=$(mktemp -d /tmp/restore_XXXXXXXX)
mount $partition $restore_path
testError "cannot mount partition."
 
# TODO: test if mounted partition has enough total space (not free space)...if not unmount and quit
 
# numeric-owner restore the numeric owners of the files rather than matching to any user names in the environment
tar -xvpzf "$filename" -C $restore_path --numeric-owner
 
# Recreate excluded directories
mkdir -p $restore_path/proc \
$restore_path/tmp \
$restore_path/mnt \
$restore_path/dev \
$restore_path/sys \
$restore_path/run \
$restore_path/media \
$restore_path/var/log
 
# Set back SUID/SGID
while read l; do
    echo "SUID \"$l\""
    chmod u+s "$restore_path/$l"
done < "$filename.SUID"
while read l; do
    echo "SGID \"$l\""
    chmod g+s "$restore_path/$l"
done < "$filename.SGID"
 
# Unmount
umount $restore_path
testError "cannot unmount partition."
 
echo "Files restored."
disk=$(echo $partition | sed 's/[0-9]*$//')
if [ -f "$filename.MBR" ]; then
	echo "To restore MBR type: dd if=$filename.MBR of=$disk"
fi
echo "Done."
}
 
clear
echo "=========================================================="
echo "Backup and restore a full Linux filesystem and boot sector."
echo "          -Be sure to boot from a Live CD/USB-"
echo "==========================================================="
echo "TODO: This script do not check if there is enough space,"
echo "so check if you have enough space on target filesystem AND"
echo "on destination."
echo
echo "Ex: for a 1 Gb FS, it's better to have more than 1 Gb free"
echo "on FS partition AND also on final destination (<filename>)."
echo
echo "Run the script from /, and do not mount the partition you"
echo "want to backup or restore."
echo
case "$1" in
  "backup")
        backup
        ;;
  "restore")
        restore
        ;;
  *)
        echo "Options: "
        echo "      backup <filename> <partition>"
        echo "      restore <filename> <partition>"
        echo
        echo "   -> USE FULL PATH FOR <filename>!"
        ;;
esac
 
exit 0

