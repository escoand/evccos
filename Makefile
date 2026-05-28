CONFIG      := infra/config.bu
COREOS      := 44.20260419.3.1
STREAM      := stable

BUILDDIR    := build
DATASIZE    := 1G
DATALABEL   := data
DATADISK    := $(BUILDDIR)/data.img
ARCH        := x86_64
LOCALIMAGE  := $(BUILDDIR)/fedora-coreos-$(COREOS)-qemu.$(ARCH).qcow2
IGNITION    := $(BUILDDIR)/config.ign
QUAYIO      ?= quay.io

.PHONY: all local data-disk upload remote clean

all: local

$(LOCALIMAGE):
	mkdir -p "$(BUILDDIR)"
	podman run --rm -it \
		--security-opt label=disable \
		--pull=always \
		-v ."/$(BUILDDIR)://data" -w //data \
		$(QUAYIO)/coreos/coreos-installer:release \
			download -s "$(STREAM)" -p qemu -a $(ARCH) -f qcow2.xz -C //data

$(IGNITION): $(CONFIG)
	mkdir -p "$(BUILDDIR)"
	podman run --rm -i \
		-v .://data -w //data \
		"$(QUAYIO)/coreos/butane:release" \
			--files-dir //data --pretty --strict "//data/$(CONFIG)" > $@

$(DATADISK):
	mkdir -p "$(BUILDDIR)"
	qemu-img create -f raw "$@" "$(DATASIZE)"
# mkfs.ext4 -L "$(DATALABEL)" "$@"

local: $(IGNITION) $(LOCALIMAGE) $(DATADISK)
	kvm \
		-m 4096 \
		-boot c \
		-drive "if=virtio,file=$(LOCALIMAGE),snapshot=on" \
		-drive "if=virtio,file=$(DATADISK),format=raw" \
		-fw_cfg "name=opt/com.coreos/config,file=$(IGNITION)" \
		-nic "user,model=virtio,hostfwd=tcp::2222-:22,hostfwd=tcp:127.0.0.1:8080-:7070" \
		-chardev "vc,id=char0,logfile=$(BUILDDIR)/qemu-serial.log" \
		-serial chardev:char0

clean:
	rm -f $(IGNITION) $(LOCALIMAGE) $(DATADISK)
