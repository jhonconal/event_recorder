# Makefile for getevent and sendevent
# Cross-compilation example:
# make CC=aarch64-linux-gnu-gcc
# make CC=arm-linux-gnueabihf-gcc

CC ?= gcc
CFLAGS ?= -Wall -O2
LDFLAGS ?=

all: getevent sendevent

getevent: getevent.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

sendevent: sendevent.c
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f getevent sendevent

.PHONY: all clean
