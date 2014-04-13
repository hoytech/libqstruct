# Makefile for libqstruct

########################################################################
# Configuration.
########################################################################

CC     = gcc
W      = -W -Wall -Wbad-function-cast -Wextra -Wformat=2 -Wpointer-arith -Wfloat-equal -Wdeclaration-after-statement -Wshadow -Wunsafe-loop-optimizations -Wbad-function-cast -Wcast-qual -Wcast-align -Waggregate-return -Wmissing-field-initializers -Wredundant-decls -Woverlength-strings -Winline -Wdisabled-optimization -Wstack-protector
OPT    = -O2 -g
CFLAGS = $(OPT) $(W) -fPIC $(XCFLAGS)
LDLIBS =
SOLIBS =
prefix = /usr/local

########################################################################

INSTALLEDHDRS = qstruct_utils.h qstruct_compiler.h qstruct_loader.h qstruct_builder.h
PRIVATEHDRS = internal.h
INSTALLEDLIBS = libqstruct.a libqstruct.so
OBJS = parser.o compiler.o

all: $(INSTALLEDLIBS)

install: $(INSTALLEDLIBS) $(INSTALLEDHDRS)
	for f in $(INSTALLEDLIBS); do cp $$f $(DESTDIR)$(prefix)/lib; done
	for f in $(INSTALLEDHDRS); do cp $$f $(DESTDIR)$(prefix)/include; done

clean:
	rm -rf *.[ao] *.so parser.c

libqstruct.a: $(OBJS)
	ar rs $@ $(OBJS)

libqstruct.so: $(OBJS)
	$(CC) $(LDFLAGS) -shared -o $@ $(OBJS) $(SOLIBS)

parser.o: parser.c qstruct_compiler.h internal.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -c parser.c

parser.c: parser.rl
	ragel -G2 parser.rl

%: %.o
	$(CC) $(CFLAGS) $(LDFLAGS) $^ $(LDLIBS) -o $@

%.o: %.c $(INSTALLEDHDRS) $(PRIVATEHDRS)
	$(CC) $(CFLAGS) $(CPPFLAGS) -c $<
