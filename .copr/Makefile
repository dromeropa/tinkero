# COPR "make_srpm" entry point. COPR runs, as root in a fresh chroot with network:
#   make -f <clone>/.copr/Makefile srpm outdir=<dir> spec=<path>
# Two kinds of package live in this repo:
#   * the tinkero RPM itself (spec= is empty or names tinkero.spec): rendered from
#     tinkero.spec.in and upstream.lock, sources fetched and verified by build/;
#   * the COPR package set under distro/fedora/specs/ (spec= names one of them):
#     handed to distro/fedora/specs/srpm.sh, which fetches, pin-verifies, vendors
#     and builds the source RPM.
TOP := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..
outdir ?= $(CURDIR)
spec ?= tinkero.spec

.PHONY: srpm srpm-tinkero srpm-package
srpm:
	@case "$(notdir $(spec))" in \
	  tinkero.spec|"") $(MAKE) -f $(lastword $(MAKEFILE_LIST)) srpm-tinkero outdir="$(outdir)" ;; \
	  *) $(MAKE) -f $(lastword $(MAKEFILE_LIST)) srpm-package outdir="$(outdir)" spec="$(spec)" ;; \
	esac

srpm-tinkero:
	dnf -y install git-core curl rpm-build
	cd $(TOP) && \
	  build/fetch-upstream >/dev/null && \
	  build/render-spec tinkero.spec && \
	  git archive --format=tar.gz -o .cache/tinkero-src.tar.gz HEAD
	cd $(TOP) && rpmbuild -bs tinkero.spec \
	  --define "_sourcedir $(abspath $(TOP))/.cache" \
	  --define "_srcrpmdir $(outdir)"

srpm-package:
	bash $(TOP)/distro/fedora/specs/srpm.sh "$(TOP)/distro/fedora/specs/$(notdir $(spec))" "$(outdir)"
