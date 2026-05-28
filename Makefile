CONFIG      := infra/config.bu
COREOS      := 44.20260510.3.1
STREAM      ?= stable

BUILDDIR    := ./build
IGNITION    := $(BUILDDIR)/config.ign
ASSETDIR    := $(BUILDDIR)/assets

# qemu
DATASIZE    := 1G
DATALABEL   := data
SYSTEMDISK  := $(BUILDDIR)/qemu.system.img
DATADISK    := $(BUILDDIR)/qemu.data.img
ARCH        := x86_64
QEMUIMAGE   := $(ASSETDIR)/fedora-coreos-$(COREOS)-qemu.$(ARCH).qcow2

# rpi4
RPI4DISK    := $(BUILDDIR)/rpi4.system.img
RPI4IMAGE   := $(ASSETDIR)/fedora-coreos-$(COREOS)-metal.aarch64.raw

.PHONY: all qemu clean

all: qemu

$(QEMUIMAGE):
	mkdir -p "$(ASSETDIR)"
	podman run --rm -it \
		--security-opt label=disable \
		-v "$(ASSETDIR):/assets" \
		quay.io/coreos/coreos-installer:release \
			download \
				--architecture "$(ARCH)" \
				--directory /assets \
				--decompress \
				--format qcow2.xz \
				--platform qemu \
				--stream "$(STREAM)"

$(IGNITION): $(CONFIG)
	mkdir -p "$(BUILDDIR)"
	podman run --rm -i \
		-v .:/data \
		quay.io/coreos/butane:release \
			--files-dir /data --pretty --strict "/data/$<" > "$@"

$(SYSTEMDISK): $(QEMUIMAGE)
	qemu-img create -f qcow2 -F qcow2 -b "../$<" $@

$(DATADISK):
	mkdir -p "$(BUILDDIR)"
	qemu-img create -f raw "$@" "$(DATASIZE)"

qemu: $(IGNITION) $(SYSTEMDISK) $(DATADISK)
	kvm \
		-m 4096 \
		-boot c \
		-drive "if=virtio,file=$(SYSTEMDISK)" \
		-drive "if=virtio,file=$(DATADISK),format=raw" \
		-fw_cfg "name=opt/com.coreos/config,file=$(IGNITION)" \
		-nic "user,model=virtio,hostfwd=tcp::2222-:22,hostfwd=tcp:127.0.0.1:8080-:7070" \
		-chardev "vc,id=char0,logfile=$(BUILDDIR)/qemu.serial.log" \
		-serial chardev:char0

$(RPI4IMAGE):
	mkdir -p "$(ASSETDIR)"
	podman run --rm -it \
		--security-opt label=disable \
		-v "$(ASSETDIR):/assets" \
		quay.io/coreos/coreos-installer:release \
			download \
				--architecture aarch64 \
				--directory /assets \
				--decompress \
				--format raw.xz \
				--platform metal \
				--stream "$(STREAM)"

$(RPI4DISK):
	qemu-img create -f qcow2 "$@" 4G

rpi4-boot:
	mkdir -p "$(ASSETDIR)" "$(BUILDDIR)/$@/"
	podman run --rm \
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

rpi4: rpi4-boot $(RPI4DISK) $(IGNITION)

clean:
	rm -fr "$(IGNITION)" "$(ASSETDIR)" "$(BUILDDIR)/rpi4-boot/" "$(SYSTEMDISK)" "$(RPI4DISK)"

clean-all: clean
	rm -fr "$(DATADISK)"
