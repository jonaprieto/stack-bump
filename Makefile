
ORMOLUFILES = $(shell git ls-files '*.hs' '*.hs-boot' | grep -v '^contrib/')
ORMOLUFLAGS?=--no-cabal
ORMOLUMODE?=inplace

format:
	@stack exec -- ormolu ${ORMOLUFLAGS} \
		--ghc-opt -XStandaloneDeriving \
		--ghc-opt -XUnicodeSyntax \
		--ghc-opt -XDerivingStrategies \
		--ghc-opt -XMultiParamTypeClasses  \
		--ghc-opt -XTemplateHaskell \
		--ghc-opt -XImportQualifiedPost \
			--mode ${ORMOLUMODE} \
		$(ORMOLUFILES)

HLINTQUIET :=
.PHONY : hlint
hlint :
	@hlint src test ${HLINTQUIET}