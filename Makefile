# raspberry-make
# https://github.com/gswly/raspberry-make

MAKEFILE_NAME := $(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))

# load config from external file (optional)
-include config

# config default values
BASE ?= https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-04-09/2019-04-08-raspbian-stretch-lite.zip
SIZE ?= 2G
HNAME ?= my-rpi
RESOLVCONF_TYPE ?= static
RESOLVCONF_CONTENT ?= 8.8.8.8
ADDITIONAL_HOSTS ?=
export ADDITIONAL_HOSTS
BUILD_DIR ?= $(PWD)/build

blank :=
define NL

$(blank)
endef

BASEHASH := $$(echo -n '$(BASE)' | sha256sum | head -c 8)
ROOT_START_SECTORS = $$(fdisk -l $(1) | tail -n1 | awk '{print $$2}')
BOOT_START_SECTORS = $$(fdisk -l $(1) | tail -n2 | head -n1 | awk '{print $$2}')
ROOT_LEN_SECTORS = $$(fdisk -l $(1) | tail -n1 | awk '{print $$4}')
BOOT_LEN_SECTORS = $$(fdisk -l $(1) | tail -n2 | head -n1 | awk '{print $$4}')
ROOT_START_BYTES = $$(($(ROOT_START_SECTORS)*512))
BOOT_START_BYTES = $$(($(BOOT_START_SECTORS)*512))
ROOT_LEN_BYTES = $$(($(ROOT_LEN_SECTORS)*512))
BOOT_LEN_BYTES = $$(($(BOOT_LEN_SECTORS)*512))

define PLAYBOOK_RUN
@echo -e "FROM raspberry-make-cur \n\
COPY . ./ \n\
USER pi \n\
RUN /ansible/lib/ld-musl-x86_64.so.1 --library-path=/ansible/lib:/ansible/usr/lib \
	/ansible/usr/bin/python3.6 /ansible/usr/bin/ansible-playbook -i /ansible/inv.ini playbook.yml \n\
USER root \n\
RUN rm -rf ./* \n\
" | docker build $(D) -f - -t raspberry-make-cur
endef

all:
  # build container and enter
	@echo "FROM amd64/alpine:3.9 \n\
	RUN apk add --no-cache make docker e2fsprogs dosfstools rsync util-linux" \
	| docker build - -t raspberry-make
	sudo modprobe loop
	sudo modprobe vfat
	docker run --rm --privileged \
	-v $(PWD):/s:ro -v $(BUILD_DIR):/b -v /var/run/docker.sock:/var/run/docker.sock:ro \
	raspberry-make sh -c "cd /s && make indocker"

indocker:
	@losetup -d /dev/loop0 2>/dev/null || exit 0
	@losetup -d /dev/loop1 2>/dev/null || exit 0
	@rm -rf /b/*

  # download and import only if necessary
ifeq ($(shell docker image inspect raspberry-make-base-$(BASEHASH) >/dev/null 2>&1 || echo 1),1)
  # download
	wget -O /tmp/base.tmp.zip $(BASE)
	cd /tmp && unzip base.tmp.zip
	rm /tmp/base.tmp.zip
	mv /tmp/*img /tmp/base.tmp

  # mount root and boot, save partition table, save /etc/hosts
	losetup /dev/loop0 /tmp/base.tmp -o $(call ROOT_START_BYTES,/tmp/base.tmp)
	losetup /dev/loop1 /tmp/base.tmp -o $(call BOOT_START_BYTES,/tmp/base.tmp)
	mount /dev/loop0 /mnt
	mount /dev/loop1 /mnt/boot
	dd if=/tmp/base.tmp of=/mnt/pt bs=1M count=1
	cp /mnt/etc/hosts /mnt/etc/_hosts

  # import into docker
	tar -C /mnt -c . | docker import - raspberry-make-base-$(BASEHASH)

  # umount
	umount /mnt/boot
	umount /mnt
	losetup -d /dev/loop1
	losetup -d /dev/loop0
	rm /tmp/base.tmp
endif

  # add qemu and ansible
	docker run --rm --privileged multiarch/qemu-user-static:register --reset >/dev/null
	@echo -e "FROM multiarch/alpine:armhf-v3.9\n\
	FROM amd64/alpine:3.9 \n\
	RUN apk add --no-cache ansible \n\
	FROM raspberry-make-base-$(BASEHASH) \n\
	COPY --from=0 /usr/bin/qemu-arm-static /usr/bin/qemu-arm-static \n\
	RUN chmod 4755 /usr/bin/qemu-arm-static \n\
	COPY --from=1 / /ansible \n\
	RUN echo 'rpi ansible_connection=local ansible_python_interpreter=/usr/bin/python3' > /ansible/inv.ini \n\
	ENV ANSIBLE_FORCE_COLOR true \n\
	WORKDIR /playbook \n\
	" | docker build - -t raspberry-make-cur

  # run playbooks
	$(foreach D,$(shell ls */playbook.yml | xargs -n1 dirname),$(PLAYBOOK_RUN)$(NL))

  # allocate final image, restore partition table, adjust partition
	docker run --rm raspberry-make-cur cat /pt | tee /tmp/output.tmp >/dev/null
	truncate -s $(SIZE) /tmp/output.tmp
	printf "d;2;n;p;2;$(call ROOT_START_SECTORS,/tmp/output.tmp);;w;" | tr ";" "\n" | fdisk /tmp/output.tmp || exit 0
	losetup /dev/loop0 /tmp/output.tmp -o $(call ROOT_START_BYTES,/tmp/output.tmp) --sizelimit $(call ROOT_LEN_BYTES,/tmp/output.tmp)
	losetup /dev/loop1 /tmp/output.tmp -o $(call BOOT_START_BYTES,/tmp/output.tmp) --sizelimit $(call BOOT_LEN_BYTES,/tmp/output.tmp)

  # recreate file systems
  # https://github.com/RPi-Distro/pi-gen/blob/30a1528ae13f993291496ac8e73b5ac0a6f82585/export-image/prerun.sh#L58
	mkfs.ext4 -L rootfs -O '^huge_file,^metadata_csum,^64bit' /dev/loop0
	mkdosfs -n boot -F 32 /dev/loop1

  # mount
	mount /dev/loop0 /mnt
	mkdir /mnt/boot
	mount /dev/loop1 /mnt/boot

  # cleanup
	@echo -e "FROM raspberry-make-cur \n\
	RUN rm -rf /playbook /ansible /usr/bin/qemu-arm-static /pt \n\
	" | docker build - -t raspberry-make-cur

  # export
	@docker container rm raspberry-make-tmp >/dev/null 2>&1 || exit 0
	docker create --name raspberry-make-tmp raspberry-make-cur /bin/exit >/dev/null
	docker export raspberry-make-tmp | tar xf - -C /mnt/
	docker container rm raspberry-make-tmp >/dev/null
	rm /mnt/.dockerenv

  # set /etc/hostname
	echo $(HNAME) > /mnt/etc/hostname

  # set /etc/hosts
	mv /mnt/etc/_hosts /mnt/etc/hosts
	sed -i 's/^127\.0\.1\.1.\+$$/127.0.0.1       $(HNAME)/' /mnt/etc/hosts
ifeq ($(RESOLVCONF_TYPE),static)
	echo '$(RESOLVCONF_CONTENT)' > /mnt/etc/resolv.conf
else
	rm /mnt/etc/resolv.conf
	ln -s $(RESOLVCONF_CONTENT) /mnt/etc/resolv.conf
endif
	echo "$$ADDITIONAL_HOSTS" >> /mnt/etc/hosts

  # set /etc/mtab (normally done by systemd-tmpfiles-setup)
	rm /mnt/etc/mtab
	ln -s ../proc/self/mounts /mnt/etc/mtab

	umount /mnt/boot
	umount /mnt
	losetup -d /dev/loop0
	losetup -d /dev/loop1
	mv /tmp/output.tmp /b/output.img

self-update:
	curl -o $(MAKEFILE_NAME) https://raw.githubusercontent.com/gswly/raspberry-make/master/Makefile
