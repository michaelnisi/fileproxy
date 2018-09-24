SWIFT=swift

all: build test

clean:
	rm -rf .build

build:
	$(SWIFT) build -Xswiftc "-target" -Xswiftc "x86_64-apple-macosx10.13"

test:
	./run_tests

.PHONY: clean, build, test
