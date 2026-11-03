# SelfCheckout Rice — CRT overlay build
# Written for the SelfCheckout rice.

CC      ?= gcc
CFLAGS  ?= -O2 -Wall -Wextra -std=c11
LDLIBS   = -lX11 -lXext -lGL

PREFIX  ?= $(HOME)/.local

crt-overlay: main.c
	$(CC) $(CFLAGS) -o $@ main.c $(LDLIBS)

install: crt-overlay
	install -d $(PREFIX)/bin
	install -m755 crt-overlay $(PREFIX)/bin/crt-overlay

clean:
	rm -f crt-overlay

.PHONY: install clean
