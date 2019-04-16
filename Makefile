# raspberry-make
# https://github.com/gswly/raspberry-make

include config

IMAGE_BASE ?= https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-04-09/2019-04-08-raspbian-stretch-lite.zip
IMAGE_EXPAND ?= 2G
BUILD_DIR ?= $(PWD)/build

blank :=
define NL

$(blank)
endef

define IN_DOCKER
echo "FROM multiarch/alpine:armhf-v3.8 \n\
FROM amd64/alpine:3.9 \n\
COPY --from=0 /usr/bin/qemu-arm-static /usr/bin/qemu-arm-static \n\
RUN apk add --no-cache \\ \n\
    make \\ \n\
    curl \\ \n\
    unzip \\ \n\
    e2fsprogs \\ \n\
    e2fsprogs-extra \\ \n\
    openssh-client \\ \n\
    ansible \\ \n\
    rsync \\ \n\
    && rm -rf /var/lib/apt/lists/* \n\
WORKDIR /src \n\
COPY . ./ \n\
" | docker build . -f - -t raspberry-make
docker run --rm --privileged multiarch/qemu-user-static:register --reset >/dev/null
sudo modprobe loop
sudo modprobe vfat
docker run --rm -it \
	-v $(BUILD_DIR):/build \
	--privileged \
	raspberry-make make $(1)
endef

all:
	$(call IN_DOCKER, all-nodocker)

all-nodocker: /build/output.img

# download base image
/build/base.tmp:
	curl -L -o img.zip $(IMAGE_BASE)
	unzip img.zip
	rm img.zip
	mv *.img $@

# expand and apply playbooks
/build/output.img: /build/base.tmp
	$(eval TIMG := $@.tmp)
	cp $< $(TIMG)

  # expand
	truncate -s $(IMAGE_EXPAND) $(TIMG)
	ROOT_START=$$(fdisk -l $(TIMG) | tail -n1 | awk '{print $$4}') \
		&& printf "d;2;n;p;2;$$ROOT_START;;w;" | tr ';' '\n' | fdisk $(TIMG) || exit 0
	@losetup -d /dev/loop0 2>/dev/null || exit 0
	ROOT_START=$$(fdisk -l $(TIMG) | tail -n1 | awk '{print $$4}') \
		&& losetup /dev/loop0 $(TIMG) -o $$(($$ROOT_START*512))
	e2fsck -f /dev/loop0
	resize2fs /dev/loop0
	losetup -d /dev/loop0

  # mount chroot
	@losetup -d /dev/loop0 2>/dev/null || exit 0
	@losetup -d /dev/loop1 2>/dev/null || exit 0
	ROOT_START=$$(fdisk -l $(TIMG) | tail -n1 | awk '{print $$4}') \
		&& losetup /dev/loop0 $(TIMG) -o $$(($$ROOT_START*512))
	mount /dev/loop0 /mnt
	BOOT_START=$$(fdisk -l $(TIMG) | tail -n2 | head -n1 | awk '{print $$4}') \
		&& losetup /dev/loop1 $(TIMG) -o $$(($$BOOT_START*512))
	mount /dev/loop1 /mnt/boot
	mount --bind /proc /mnt/proc
	mount --bind /sys /mnt/sys
	mount --bind /dev /mnt/dev
	mount --bind /dev/pts /mnt/dev/pts
	mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
	cp /usr/bin/qemu-arm-static /mnt/usr/bin/qemu-arm-static
	chmod 4755 /mnt/usr/bin/qemu-arm-static # allow sudo
	$(eval CHROOT := chroot /mnt)

  # create and enable temporary key
	ssh-keygen -t ed25519 -b 256 -N "" -f $$HOME/.ssh/id_ed25519
	mkdir /mnt/home/pi/.ssh
	cat $$HOME/.ssh/id_ed25519.pub > /mnt/home/pi/.ssh/authorized_keys
	chown -R 1000:1000 /mnt/home/pi/.ssh

  # start ssh server
	$(CHROOT) dpkg-reconfigure openssh-server
	mkdir /mnt/run/sshd
	($(CHROOT) /usr/sbin/sshd -D &)
	sleep 2

  # save key in known_hosts
	ssh -oStrictHostKeyChecking=no pi@127.0.0.2 exit

  # run playbooks (use 127.0.0.2 to force ssh)
	echo 'raspbian ansible_user=pi ansible_host=127.0.0.2 ansible_python_interpreter=/usr/bin/python3' > inv.ini
	$(foreach d,$(shell ls */playbook.yml | xargs -n1 dirname),cd $(d) && ansible-playbook -i ../inv.ini playbook.yml$(NL))

	PIDS=$$(ps | grep qemu-arm | grep -v ps | awk '{ print $$1 }'); kill $$PIDS; wait $$PIDS; exit 0
	KEY=$$(cat $$HOME/.ssh/id_ed25519.pub) && sed -i "/$${KEY//\//\\/}/d" /mnt/home/pi/.ssh/authorized_keys
	rmdir /mnt/run/sshd

  # umount chroot
	rm /mnt/usr/bin/qemu-arm-static
	umount /mnt/etc/resolv.conf || exit 0 # in case it has already been unmounted
	umount /mnt/dev/pts
	umount /mnt/dev
	umount /mnt/sys
	umount /mnt/proc
	umount /mnt/boot
	losetup -d /dev/loop1
	umount /mnt
	losetup -d /dev/loop0

	mv $(TIMG) $@

clean:
	$(call IN_DOCKER, clean-nodocker)

clean-nodocker:
	rm -rf /build/*

self-update:
	curl -O https://raw.githubusercontent.com/gswly/raspberry-make/master/Makefile
