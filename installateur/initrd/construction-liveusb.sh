#!/bin/env bash
# Voyez le fichier LICENCES pour connaître la licence de ce script.

# *** À LANCER EN ROOT ! ***
# Lancer comme suit :  './construction-liveusb.recette PÉRIPHÉRIQUE_USB', par ex. :
# 	# ./construction-liveusb.recette /dev/sdc

# ATTENTION : Bien vérifier qu'on désigne la clé USB et PAS un disque dur 
# système et/ou données !!! Ne spécifiez pas une partition (se terminant par un
# chiffre comme '/dev/sdc1') mais bien le PÉRIPHÉRIQUE ('/dev/sdc', '/dev/sdd', etc.)!

# ATTENTION : relisez les avertissements 2 fois, vous êtes prévenu(e) !

# Un périphérique en argument est obligatoire. 
if [ "$1" = "" ]; then
	echo "Veuillez spécifier un périphérique USB, ex. : "
	echo "	# ./construction-liveusb.sh /dev/sdd"
	exit 1
fi

set -e
umask 022
CWD=$(pwd)

# Changer ces paramètres via la ligne de commande, par ex. :
# 	# SOURCES=/ici PAQUETS=/quelque/part LIVEOS=/ailleurs ./construction-liveusb.recette /dev/sdX

SOURCES=${SOURCES:-/marmite/0/sources}
PAQUETS=${PAQUETS:-/marmite/0/paquets}
LIVEOS=${LIVEOS:-/marmite/0/liveos}
INITRDGZ=${INITRDGZ:-/tmp/initrd.gz}
USBDEV=${USBDEV:-$1}

# On crée et on vide le répertoire d'accueil :
rm -rf ${LIVEOS}
mkdir -p ${LIVEOS}

# On installe les paquets pour le LiveOS :
for paq in base-systeme* etc* eglibc* sgml*; do
	spkadd --quiet --root=${LIVEOS} ${PAQUETS}/base/${paq}
done

spkadd --quiet --root=${LIVEOS} ${PAQUETS}/opt/make-*.cpio
spkadd --quiet --root=${LIVEOS} ${PAQUETS}/base/*.cpio
spkadd --quiet --root=${LIVEOS} ${PAQUETS}/xorg/*.cpio

for paq in dbus-1* expat* gcc* glib2* gmp* lesstif* libgcrypt* libgpg-error* \
	libidn* libpng* libssh2* popt* python-2* perl-5* ruby*; do
	spkadd --quiet --root=${LIVEOS} ${PAQUETS}/opt/${paq}.cpio
done

# On allège :
rm -rf ${LIVEOS}/usr/doc/*
rm -rf ${LIVEOS}/usr/share/gtk-doc/*
rm -f ${LIVEOS}/lib/*.{a,la,so.*,so}
rm -rf ${LIVEOS}/usr/lib/*

# On copie nos fichiers spéciaux pour le Live :
install -m 644 $CWD/fstab ${LIVEOS}/etc
install -m 755 $CWD/{HOSTNAME,profile} ${LIVEOS}/etc
install -m 755 $CWD/rc.* ${LIVEOS}/etc/rc.d

# On copie l'installateur et l'aide :
install -m 755 $CWD/../scripts/{installateur,*.sh} ${LIVEOS}/sbin
install -m 644 $CWD/../scripts/aide.txt ${LIVEOS}

# On crée le lien pour 'init' :
ln -sf sbin/init ${LIVEOS}/init

# On s'assure de la présence de 'bash' :
if [ -r ${LIVEOS}/bin/bash4.new ]; then
	mv ${LIVEOS}/bin/bash{4.new,}
fi

# On va chrooter dans le système autonome :
cd ${LIVEOS}

# On désinstalle 'linux-source', inutile ici :
chroot . /sbin/spkrm --quiet /var/log/paquets/linux-source-*.cpio

# On met à jour les liens des bibliothèques :
chroot . /sbin/ldconfig
 
# On met à jour les dépendances des modules du noyau :
chroot . /usr/sbin/depmod -a

# On évite que se lance 'sshd' (+ effet d'escalier à l'affichage) :
chroot . /bin/chmod -x /etc/rc.d/rc.sshd

# On copie le nouveau noyau dans /tmp sans sa version :
rm -f /tmp/noyau
cp ${LIVEOS}/boot/noyau-2* /tmp/noyau

# On positionne le fuseau à Paris car on est franco-français et chauvin :
echo "localtime" > /etc/hardwareclock
chroot . ln -sf ../usr/share/zoneinfo/Europe/Paris /etc/localtime

# On crée l'initrd :
rm -f ${INITRDGZ}
find . | cpio -v -o -H newc | gzip -9 > ${INITRDGZ}
cd -

# On monte la clé, sans la presser :
mount ${USBDEV}1 /mnt/tmp || true
sleep 4

# On nettoie la clé et on dévérouille 'ldlinux.sys' :
for f in $(find /mnt/tmp -name "ldlinux.sys" -print); do
	chattr -i ${f}
	rm -f ${f}
done
rm -rf /mnt/tmp/boot/extlinux
mkdir -p /mnt/tmp/0/paquets
mkdir -p /mnt/tmp/boot/extlinux

# On copie toutes les sources de extlinux/ :
cp -ar ${SOURCES}/installateur/extlinux/* /mnt/tmp/boot/extlinux/

# On copie les modules binaires de Syslinux :
cp -a /usr/share/syslinux/{chain,kbdmap,linux,reboot,vesamenu}.c32 /mnt/tmp/boot/extlinux/
chmod +x /mnt/tmp/boot/extlinux/*.c32

# On copie le noyau et l'initrd :
cp -a ${INITRDGZ} /tmp/noyau /mnt/tmp/boot/

# On copie les paquets :
rsync -auv --delete-after ${PAQUETS}/* /mnt/tmp/0/paquets

# On s'assure des permissions :
chown -R root:root /mnt/tmp/* 2> /dev/null || true

# On copie un MBR propre :
dd if=/usr/share/syslinux/mbr.bin of=${USBDEV}

# On installe enfin extlinux :
extlinux --install /mnt/tmp/boot/extlinux

# On démonte la clé :
umount /mnt/tmp

exit 0
