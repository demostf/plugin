%.smx: %.sp
	docker run --rm -v "$(CURDIR)":/data spiretf/spcomp $<

all:demostf.smx
