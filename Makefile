NAME=hwdata
VERSION=$(shell awk '/Version:/ { print $$2 }' hwdata.spec)
RELEASE=$(shell rpm -q --define 'dist %{nil}' --specfile --qf "%{release}\n" hwdata.spec | head -n 1)
ifeq ($(shell git rev-parse --abbrev-ref HEAD | sed -n 's/^\([^0-9-]\+\).*/\L\1/p'), rhel)
    # add revision to tag name for rhel branches
    TAGNAME := $(NAME)-$(VERSION)-$(RELEASE)
else
    TAGNAME := $(NAME)-$(VERSION)
endif
SOURCEDIR := $(shell pwd)
ARCHIVE := $(TAGNAME).tar.bz2
HWDBNUMINCR := 2

CVSROOT = $(shell cat CVS/Root 2>/dev/null || :)

CVSTAG = $(NAME)-r$(subst .,-,$(VERSION))

FILES := pci.ids usb.ids oui.txt iab.txt pnp.ids sdio.ids
HWDBGENERATED := \
    20-OUI.hwdb \
    20-pci-classes.hwdb \
    20-pci-vendor-model.hwdb \
    20-sdio-classes.hwdb \
    20-sdio-vendor-model.hwdb \
    20-usb-classes.hwdb \
    20-usb-vendor-model.hwdb
HWDBUPSTREAM := \
    20-acpi-vendor.hwdb \
    20-bluetooth-vendor-product.hwdb \
    20-net-ifname.hwdb \
    60-evdev.hwdb \
    60-keyboard.hwdb \
    70-mouse.hwdb \
    70-pointingstick.hwdb
HWDBFILES := $(HWDBGENERATED) $(HWDBUPSTREAM)

.PHONY: all install tag force-tag check commit create-archive archive srpm-x \
    clean clog \
    new-pci-ids \
    new-usb-ids \
    new-oui \
    new-iab \
    new-pnp-ids \
    new-hwdb-files \
    new-sdio-ds \
    pnp.ids

include Makefile.inc

all:

Makefile.inc: configure
	./configure
	@echo "$@ generated. Run the make again."
	@exit 1

install: Makefile.inc
	mkdir -p -m 755 $(DESTDIR)$(datadir)/$(NAME)
	for foo in $(FILES) ; do \
		install -m 644 $$foo $(DESTDIR)$(datadir)/$(NAME) ;\
	done
	mkdir -p -m 755 $(DESTDIR)$(libdir)/udev/hwdb.d/
	perl ./ids-update.pl
	for foo in $(HWDBFILES) ; do \
		num=`echo $$foo | sed 's,^\(.*/\|\)\([0-9]\+\)-[^/]\+,\2,'`; \
		destname=`printf "%02d" $$((num + $(HWDBNUMINCR)))`-`basename $$foo | sed "s/^[0-9]\+-//"`; \
		install -m 644 $$foo $(DESTDIR)$(libdir)/udev/hwdb.d/$$destname; \
	done
	mkdir -p -m 755 $(DESTDIR)$(libdir)/modprobe.d
	install -m 644 -T blacklist.conf $(DESTDIR)$(libdir)/modprobe.d/dist-blacklist.conf

commit:
	git commit -a ||:

tag:
	@git tag -s -m "Tag as $(TAGNAME)" $(TAGNAME)
	@echo "Tagged as $(TAGNAME)"

force-tag:
	@git tag -s -f -m "Tag as $(TAGNAME)" $(TAGNAME)
	@echo "Tag forced as $(TAGNAME)"

changelog:
	@rm -f ChangeLog
	@(GIT_DIR=.git git log > .changelog.tmp && mv .changelog.tmp ChangeLog || rm -f .changelog.tmp) || (touch ChangeLog; echo 'git directory not found: installing possibly empty changelog.' >&2)

check:
	@[ -x /sbin/lspci ] && /sbin/lspci -i pci.ids > /dev/null || { echo "FAILURE: /sbin/lspci -i pci.ids"; exit 1; } && echo "OK: /sbin/lspci -i pci.ids"
	@./check-pci-ids.py || { echo "FAILURE: ./check-pci-ids.py"; exit 1; } && echo "OK: ./check-pci-ids.py"
	@if [[ -e /run/docker.sock ]]; then \
	    tmpdir=`mktemp -d`; \
	    echo "Listing usb devices:"; \
	    docker run -t --privileged --rm=true \
		-v `pwd`/usb.ids:/usr/share/hwdata/usb.ids:ro \
		-v "$$tmpdir:/mnt/out" \
		miminar/hwdata-check /bin/bash -c 'lsusb 2>/mnt/out/err.out'; \
	    if [[ `cat $$tmpdir/err.out | wc -l` -gt 0 ]]; then \
		echo "ERRORS:"; nl $$tmpdir/err.out; rm -rf $$tmpdir; exit 1; \
	    fi; \
	    rm -rf $$tmpdir; \
	fi
	@echo -n "CHECK date of pci.ids: "; grep "Date:" pci.ids | cut -d ' ' -f 5
	@echo -n "CHECK date of usb.ids: "; grep "Date:" usb.ids | cut -d ' ' -f 6

create-archive:
	@rm -rf $(TAGNAME) $(TAGNAME).tar*  2>/dev/null
	@make changelog
	@git archive --format=tar --prefix=$(TAGNAME)/ HEAD > $(TAGNAME).tar
	@mkdir $(TAGNAME)
	@cp ChangeLog $(TAGNAME)/
	@tar --append -f $(TAGNAME).tar $(TAGNAME)
	@bzip2 -f $(TAGNAME).tar
	@rm -rf $(TAGNAME)
	@echo ""
	@echo "The final archive is in $(TAGNAME).tar.bz2"

archive: check clean commit tag create-archive

upload:
	@scp $(TAGNAME).tar.bz2 fedorahosted.org:$(NAME)

dummy:

srpm-x: create-archive
	@echo Creating $(NAME) src.rpm
	@rpmbuild --nodeps -bs --define "_sourcedir $(SOURCEDIR)" --define "_srcrpmdir $(SOURCEDIR)" $(NAME).spec
	@echo SRPM is: $(NAME)-$(VERSION)-$(RELEASE).src.rpm

clean:
	@rm -f $(NAME)-*.gz $(NAME)-*.src.rpm new-pnp.xlsx pnp.ids.txt

clog: hwdata.spec
	@sed -n '/^%changelog/,/^$$/{/^%/d;/^$$/d;s/%%/%/g;p}' $< | tee $@

download: new-usb-ids new-pci-ids new-oui new-iab new-pnp-ids new-sdio-ids new-hwdb-files

new-usb-ids:
	@echo $@
	@curl -O http://www.linux-usb.org/usb.ids

new-pci-ids:
	@echo $@
	@curl -O http://pciids.sourceforge.net/pci.ids

new-oui:
	@echo $@
	@curl -O http://standards-oui.ieee.org/oui.txt

new-iab:
	@echo $@
	@curl -O http://standards.ieee.org/develop/regauth/iab/iab.txt

new-sdio-ids:
	@echo $@
	@curl -O http://cgit.freedesktop.org/systemd/systemd/plain/hwdb/sdio.ids

new-pnp-ids: pnp.ids

pnp.ids: pnp.ids.txt pnp.ids.patch
	patch -o $@ <pnp.ids.patch

pnp.ids.txt: new-pnp.xlsx
	@unoconv --stdout -f csv $? | \
	    tr ' ' ' ' | \
	    sed -n \
		-e 's/^\s*"\s*\(.*\)\s*"/\1/' \
		-e 's/\s\{2,\}/ /g' \
		-e 's/\s*(used as 2nd pnpid)\s*//' \
		-e 's:^\(.*\)\s*,\s*\([a-zA-Z@]\{3\}\)\s*,\s*\([0-9]\+/[0-9]\+/[0-9]\+\):\2\t\1:p' | \
	    sed 's/\s*$$//' | sort -u >$@

new-pnp.xlsx:
	@echo $@
	@curl -O $@ \
	    http://download.microsoft.com/download/7/E/7/7E7662CF-CBEA-470B-A97E-CE7CE0D98DC2/ISA_PNPID_List.xlsx

new-hwdb-files:
	@for file in $(HWDBUPSTREAM); do \
	    echo $$file; \
	    curl -O http://cgit.freedesktop.org/systemd/systemd/plain/hwdb/$$file; \
	done
