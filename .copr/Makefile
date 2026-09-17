# COPR "make_srpm" entry point. COPR runs, as root in a fresh chroot with network:
#   make -f <clone>/.copr/Makefile srpm outdir=<dir> spec=<path>
TOP := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))..
outdir ?= $(CURDIR)
# COPR also passes spec=<path>; it is ignored on purpose, the spec is always rendered from tinkero.spec.in.

.PHONY: srpm
srpm:
	dnf -y install git-core curl rpm-build
	cd $(TOP) && \
	  build/fetch-upstream >/dev/null && \
	  build/render-spec tinkero.spec && \
	  git archive --format=tar.gz -o .cache/tinkero-src.tar.gz HEAD
	cd $(TOP) && rpmbuild -bs tinkero.spec \
	  --define "_sourcedir $(abspath $(TOP))/.cache" \
	  --define "_srcrpmdir $(outdir)"
