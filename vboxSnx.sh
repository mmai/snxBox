#! /usr/bin/env bash

# ! /usr/bin/env nix-shell
# ! nix-shell -i bash -p xorriso

# VM=ubuntuSnx
VM=debianSnx

VMANAGE=/run/current-system/sw/bin/VBoxManage
ADAPTATER=enp3s0 # host network adaptater to use

BASEFOLDER=$(pwd)

# ---- commandes utiles ------
# $VMANAGE list vms
# $VMANAGE list runningvms
# ----------

createVm(){
    echo "creating VirtualBox VM"
  MACHINENAME=$VM
  RAM_MB=4096 
  HDD_MB=10000
  # determine VirtualBox Version
  VBOXVERSION="$($VMANAGE --version | sed 's/\([.0-9]\{1,\}\).*/\1/')"
  GUESTISO="https://download.virtualbox.org/virtualbox/$VBOXVERSION/VBoxGuestAdditions_$VBOXVERSION.iso"
  
  # iso created by createIso
  ISO=$BASEFOLDER/Releases/debianSnx_fr.iso
  
  cd "$BASEFOLDER/VirtualBox" || exit 1
  
  #download guest additions ISO
  if [ ! -f "${GUESTISO##*/}" ]; then
    wget --no-verbose --show-progress "$GUESTISO" || exit 1
  fi

  ################################################################################
  # prepare Virtualbox VM
  ################################################################################
  $VMANAGE createvm --name "$MACHINENAME" --ostype "Debian_64" --register --basefolder "$(pwd)"

  $VMANAGE modifyvm "$MACHINENAME" --memory $(("$RAM_MB")) --vram 128
  $VMANAGE modifyvm "$MACHINENAME" --nic1 bridge --bridgeadapter1 $ADAPTATER
  # $VMANAGE modifyvm "$MACHINENAME" --ioapic on
  # $VMANAGE modifyvm "$MACHINENAME" --cpus 4
  # $VMANAGE modifyvm "$MACHINENAME" --graphicscontroller vboxsvga
  # $VMANAGE modifyvm "$MACHINENAME" --audioout on
  # $VMANAGE modifyvm "$MACHINENAME" --clipboard bidirectional

  # generate a random password and keep a record in the description
  # PASSWORD="$(cat /dev/urandom | tr -dc A-Za-z0-9 | head -c10)"
  PASSWORD="snxbox"
  echo "password: $PASSWORD"
  $VMANAGE modifyvm "$MACHINENAME" --description "Password for user \"snxbox\" is \"$PASSWORD\""

  $VMANAGE createhd --filename "$BASEFOLDER/VirtualBox/$MACHINENAME.vdi" --size $(("$HDD_MB")) --format VDI
  $VMANAGE storagectl "$MACHINENAME" --name "SATA Controller" --add sata --controller "IntelAhci" --hostiocache on
  $VMANAGE storageattach "$MACHINENAME" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium  "$BASEFOLDER/VirtualBox/$MACHINENAME.vdi"

  $VMANAGE storageattach "$MACHINENAME" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium "$ISO"     
  $VMANAGE modifyvm "$MACHINENAME" --boot1 dvd --boot2 disk --boot3 none --boot4 none

  ################################################################################
  # Run Virtualbox VM
  ################################################################################
  $VMANAGE startvm "$MACHINENAME" --type gui
  # $VMANAGE startvm "$MACHINENAME" --type headless

  # wait until the netinstaller ISO is ejected
  # alternatively check for this: "SATA Controller-1-0"="emptydrive"
  while true; do
    sleep 1
    $VMANAGE showvminfo --machinereadable "$MACHINENAME" | grep "\"SATA Controller-IsEjected\"=\"on\""

    if [ $? -eq 0 ]; then
      echo "CD ejected from $MACHINENAME"
      break
    fi
  done

  #################################################################################
  # Install Guest-Additions
  #################################################################################

  # if guest-additions-iso are already installed to this host machine this medium works
  #$VMANAGE storageattach "$MACHINENAME" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium additions
  # but we better be sure to have the ISO downloaded ourselves
  $VMANAGE storageattach "$MACHINENAME" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium "${GUESTISO##*/}"

  # #################################################################################
  # # Wait till firefox-esr process is active
  # # injecting commands into the VM only works if guest additions are running
  # #################################################################################
  # while true; do
  #   $VMANAGE guestcontrol "$MACHINENAME" --username "snxbox" --password "%password%" run --exe /bin/bash -- bash -c "pidof firefox-esr > /dev/null" > /dev/null 2>&1
  #   if [ $? -eq 0 ]; then
  #     break
  #   fi
  #   sleep 1
  # done

  #################################################################################
  # set password, power off
  #################################################################################
  #change password inside VM to a random password
  # $VMANAGE guestcontrol "$MACHINENAME" --username "snxbox" --password "%password%" run --exe /bin/bash -- bash -c "echo -e \"%password%\n$PASSWORD\n$PASSWORD\" | passwd snxbox"

  # shutdown appliance
  $VMANAGE guestcontrol "$MACHINENAME" --username "snxbox" --password "$PASSWORD" run --exe /bin/bash -- bash -c "sleep 10 && sudo /sbin/shutdown -h now"

  # wait until VM is powered off
  while true; do
    sleep 1
    $VMANAGE showvminfo --machinereadable "$MACHINENAME" | grep "VMState=\"poweroff\""

    if [ $? -eq 0 ]; then
      echo "$MACHINENAME powered down"
      break
    fi
  done

  #################################################################################
  # export appliance
  #################################################################################
  $VMANAGE export "$MACHINENAME" --output "$BASEFOLDER/Releases/$MACHINENAME.ova" --ovf10 \
    --options manifest,nomacs \
    --vsys 0 \
    --vmname "$MACHINENAME" \
    --product "debianSnx" \
    --description "Password for user \"snxbox\" is \"$PASSWORD\""
}

createIso(){
  ISO="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-11.2.0-amd64-netinst.iso"

  cd "$BASEFOLDER"

  # required programs that must be installed manually, I assume coreutils is present anyway
  REQUIRED_PROGRAMS=(
  "wget|wget is missing, please install it with \"sudo apt install wget\""
  "xorriso|xorriso is missing, please install with \"sudo apt install xorriso\""
  "VBoxManage|VirtualBox is missing, please install with \"sudo apt install virtualbox virtualbox-guest-additions-iso\""
  "sudo|sudo is missing, please install with \"apt-get install sudo\""
  )
  SUCCESS="yes"
  for i in "${REQUIRED_PROGRAMS[@]}"; do
    # we change $IFS here, but BASH restores it - so no need to save/restore it ourselves
    echo "$i" | while IFS="|" read PROG HINT; do

      hash $PROG > /dev/null 2>&1
      #To find out which package contains the command:
      #dpkg -S $(realpath $(which $PROG))

      if [ $? -ne 0 ]; then
        echo "$HINT"
        SUCCESS="no"
      fi
    done
  done
  if [ "$SUCCESS" == "no" ]; then
    exit 1
  fi

  # clean any Releases to avoid confusion with previous runs
  rm -rf "$BASEFOLDER/Releases/"

  ################################################################################
  # Create modified debian ISO:
  #  - Unpack,
  #  - Change image content,
  #  - Remaster
  ################################################################################
  echo "downloading ISO"
  if [ ! -f "$BASEFOLDER/${ISO##*/}" ]; then
    wget --show-progress "$ISO"
  fi
  if [ ! -f "$BASEFOLDER/${ISO##*/}" ]; then
    echo "Error: Downloading ISO failed"
    sleep 5
    exit 1
  fi

  #unpack the ISO
  cd $BASEFOLDER || exit 1
  TMPFOLDER=$(mktemp -d ISO_XXXX) || exit 1

  echo "extracting ISO image to $TMPFOLDER"
  xorriso -osirrox on -indev "$BASEFOLDER/${ISO##*/}" -extract / "$TMPFOLDER"

  # change the CD contents
  echo "modifying CD content"
  chmod -R +w "$TMPFOLDER"

  cp postinst.sh "$TMPFOLDER/"

  #modify syslinux to make it automatically run the text based installer
  sed -i 's/timeout 0/timeout 20/g' "$TMPFOLDER/isolinux/isolinux.cfg"
  sed -i 's/default installgui/default install/g' "$TMPFOLDER/isolinux/gtk.cfg"
  sed -i 's/menu default//g' "$TMPFOLDER/isolinux/gtk.cfg"
  sed -i 's/label install/label install\n\tmenu default/g' "$TMPFOLDER/isolinux/txt.cfg"
  cp "$TMPFOLDER/isolinux/txt.cfg" "$TMPFOLDER/isolinux/txt.cfg.pre"

  for LANG in "fr"; do
    cp "$TMPFOLDER/isolinux/txt.cfg.pre" "$TMPFOLDER/isolinux/txt.cfg"
    case "$LANG" in
      fr)
        sed -i 's/append \(.*\)/append preseed\/file=\/cdrom\/preseed.cfg locale=fr_FR.UTF-8 keymap=fr language=fr country=FR \1/g' "$TMPFOLDER/isolinux/txt.cfg"
        ;;
      de)
        sed -i 's/append \(.*\)/append preseed\/file=\/cdrom\/preseed.cfg locale=de_DE.UTF-8 keymap=de language=de country=DE \1/g' "$TMPFOLDER/isolinux/txt.cfg"
        ;;
      en)
        sed -i 's/append \(.*\)/append preseed\/file=\/cdrom\/preseed.cfg locale=en_GB.UTF-8 keymap=en language=en country=GB \1/g' "$TMPFOLDER/isolinux/txt.cfg"
        ;;
      *)
        echo "unknown language"
        exit 1
        ;;
    esac
    cp "preseed_$LANG.cfg" "$TMPFOLDER/preseed.cfg"
    
    echo "combining files as tarball"
    # make folder "files" a tarball and add it to the new ISOs root folder
    tar -czvf "$TMPFOLDER/files.tgz" files/
    
    #create ISO from folder with CD content
    echo "creating modified CD as new ISO"
    #cp /usr/lib/ISOLINUX/isohdpfx.bin .
    dd if="$BASEFOLDER/${ISO##*/}" bs=1 count=432 of=isohdpfx.bin
    mkdir "$BASEFOLDER/Releases"
    xorriso -as mkisofs -isohybrid-mbr isohdpfx.bin -c isolinux/boot.cat -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -o "$BASEFOLDER/Releases/debianSnx_$LANG.iso" "$TMPFOLDER"

    createVm
    
  done

  rm -rf "$TMPFOLDER"
  rm isohdpfx.bin

  echo "Finished"
}

start(){
  $VMANAGE startvm $VM --type=headless
}

stop(){
  $VMANAGE controlvm $VM acpipowerbutton
}

createIso
