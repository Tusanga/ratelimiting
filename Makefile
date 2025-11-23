SHELL=/bin/bash

help:                   # Show this help text
	@cat Makefile | grep -e '^[a-zA-Z]*:'

build:                  # Run dub build
	/usr/local/bin/dub build

unittest:               # Run dub test
	/usr/local/bin/dub test

