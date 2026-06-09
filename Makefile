COREOS      := 44.20260510.3.1
STREAM      ?= stable

BUILDDIR    := ./build
ASSETDIR    := $(BUILDDIR)/assets

DOCKER      ?= docker
DOCKERIMAGE ?= ghcr.io/escoand/evccos

# qemu
DATASIZE    := 1G
SYSTEMDISK  := $(BUILDDIR)/qemu.system.img
DATADISK    := $(BUILDDIR)/qemu.data.img
ARCH        := $(shell arch)
QEMUIMAGE   := $(ASSETDIR)/fedora-coreos-$(COREOS)-qemu.$(ARCH).qcow2
QEMU        := qemu-system-$(ARCH)
ifeq ($(OS),Windows_NT)
  QEMU      += -accel whpx
else
  QEMU      += -accel kvm
endif

# rpi4
RPI4DISK    := $(BUILDDIR)/rpi4.system.img
RPI4IMAGE   := $(ASSETDIR)/fedora-coreos-$(COREOS)-metal.aarch64.raw

all: qemu

$(BUILDDIR)/%.ign: infra/%.bu
	mkdir -p "$(BUILDDIR)"
	$(DOCKER) run --rm -i \
		-v .:/data \
		quay.io/coreos/butane:release \
			--files-dir /data --pretty --strict "/data/$<" > "$@"

$(ASSETDIR)/fedora-coreos-%:
	mkdir -p "$(ASSETDIR)"
	@name="$(@F)"; \
	ext="$${name##*.}"; \
	no_ext="$${name%.*}"; \
	arch="$${no_ext##*.}"; \
	plat_arch="$${no_ext##*-}"; \
	platform="$${plat_arch%.*}"; \
	$(DOCKER) run --rm -it \
		--security-opt label=disable \
		-v "$(ASSETDIR):/assets" \
		quay.io/coreos/coreos-installer:release \
			download \
				--architecture "$$arch" \
				--decompress \
				--directory /assets \
				--format "$$ext.xz" \
				--platform "$$platform" \
				--stream "$(STREAM)"

.PHONY: oci
oci:
	$(DOCKER) build --tag $(DOCKERIMAGE) .
	$(DOCKER) push $(DOCKERIMAGE)

# Qemu targets

$(SYSTEMDISK): $(QEMUIMAGE)
	qemu-img create -f qcow2 -F qcow2 -b "../$(QEMUIMAGE)" $@

$(DATADISK):
	mkdir -p "$(BUILDDIR)"
	qemu-img create -f raw "$@" "$(DATASIZE)"

$(BUILDDIR)/qemu.ign: $(BUILDDIR)/config.ign

.PHONY: qemu
qemu: $(BUILDDIR)/qemu.ign $(SYSTEMDISK) $(DATADISK)
	$(QEMU) \
		-m 4096 \
		-boot c \
		-drive "if=virtio,file=$(SYSTEMDISK)" \
		-drive "if=virtio,file=$(DATADISK),format=raw" \
		-fw_cfg "name=opt/com.coreos/config,file=$(BUILDDIR)/qemu.ign" \
		-nic "user,model=virtio,hostfwd=tcp::2222-:22,hostfwd=tcp:127.0.0.1:7070-:7070" \
		-chardev "vc,id=char0,logfile=$(BUILDDIR)/qemu.serial.log" \
		-serial chardev:char0

# Raspberry Pi targets

$(RPI4DISK):
	qemu-img create -f qcow2 "$@" 4G

rpi4-boot:
	mkdir -p "$(ASSETDIR)" "$(BUILDDIR)/$@/"
	$(DOCKER) run --rm \
		-v "$(ASSETDIR):/assets" \
		-v "$(BUILDDIR):/data" -w /data \
		fedora sh -c ' \
			dnf download \
				--destdir=/assets \
				--forcearch=aarch64 \
				--resolve \
				uboot-images-armv8 bcm283x-firmware bcm283x-overlays && \
			dnf install -qy cpio && \
			ls /assets/*.rpm | xargs -i sh -c " \
				rpm2cpio {} | \
				cpio -idD /data/$@/ ./boot/efi/* ./usr/share/uboot/rpi_arm64/u-boot.bin \
			" \
		'
	mv "$(BUILDDIR)/$@/usr/share/uboot/rpi_arm64/u-boot.bin" "$(BUILDDIR)/$@/boot/efi/"
	rm -rf "$(BUILDDIR)/$@/usr"

rpi4: rpi4-boot $(BUILDDIR)/config.ign

# Clean targets

.PHONY: clean
clean:
	rm -fr "$(BUILDDIR)"/*.ign "$(BUILDDIR)/rpi4-boot/" "$(SYSTEMDISK)" "$(RPI4DISK)"

.PHONY: clean-all
clean-all: clean
	rm -fr "$(BUILDDIR)"
