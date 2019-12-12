#
# Aerospike Backup/Restore
#
# Copyright (c) 2008-2017 Aerospike, Inc. All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

ifndef CLIENTREPO
$(error Please set the CLIENTREPO environment variable)
endif

OS := $(shell uname -s)
ARCH := $(shell uname -m)
PLATFORM := $(OS)-$(ARCH)
VERSION := $(shell git describe 2>/dev/null; if [ $${?} != 0 ]; then echo 'unknown'; fi)

CC := cc

DWARF := $(shell $(CC) -Wall -Wextra -O2 -o /tmp/asflags_$${$$} src/flags.c; \
		/tmp/asflags_$${$$}; rm /tmp/asflags_$${$$})
CFLAGS := -std=gnu99 $(DWARF) -O2 -march=nocona -fno-common -fno-strict-aliasing \
		-Wall -Wextra -Wconversion -Wsign-conversion -Wmissing-declarations \
		-D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -D_FORTIFY_SOURCE=2 -DMARCH_$(ARCH) \
		-DTOOL_VERSION=\"$(VERSION)\"

ifeq ($(OS), Linux)
CFLAGS += -pthread -fstack-protector -Wa,--noexecstack
endif

LD := $(CC)
LDFLAGS := $(CFLAGS)

DIR_INC := include
DIR_SRC := src
DIR_OBJ := obj
DIR_BIN := bin
DIR_DOCS := docs
DIR_ENV := env
DIR_TOML := src/toml

INCLUDES := -I$(DIR_INC)
INCLUDES += -I$(DIR_TOML)
INCLUDES += -I$(CLIENTREPO)/src/include
INCLUDES += -I$(CLIENTREPO)/modules/common/src/include
INCLUDES += -I/usr/local/opt/openssl/include

LIBRARIES := $(CLIENTREPO)/target/$(PLATFORM)/lib/libaerospike.a
LIBRARIES += -L/usr/local/opt/openssl/lib
LIBRARIES += -L/usr/local/lib
LIBRARIES += -lssl
LIBRARIES += -lcrypto
LIBRARIES += -lpthread
LIBRARIES += -lm
LIBRARIES += -lz

ifeq ($(OS), Linux)
LIBRARIES += -ldl -lrt
LIBRARIES += -L$(DIR_TOML) -Wl,-l,:libtoml.a
else
LIBRARIES += $(DIR_TOML)/libtoml.a
endif

src_to_obj = $(1:$(DIR_SRC)/%.c=$(DIR_OBJ)/%.o)
obj_to_dep = $(1:%.o=%.d)
src_to_lib = 

BACKUP_INC := $(DIR_INC)/backup.h $(DIR_INC)/enc_text.h $(DIR_INC)/shared.h $(DIR_INC)/utils.h $(DIR_INC)/msgpack_in.h
BACKUP_SRC := $(DIR_SRC)/backup.c $(DIR_SRC)/conf.c $(DIR_SRC)/utils.c $(DIR_SRC)/enc_text.c $(DIR_SRC)/msgpack_in.c
BACKUP_OBJ := $(call src_to_obj, $(BACKUP_SRC))
BACKUP_DEP := $(call obj_to_dep, $(BACKUP_OBJ))

RESTORE_INC := $(DIR_INC)/restore.h $(DIR_INC)/dec_text.h $(DIR_INC)/shared.h $(DIR_INC)/utils.h $(DIR_INC)/msgpack_in.h
RESTORE_SRC := $(DIR_SRC)/restore.c $(DIR_SRC)/conf.c $(DIR_SRC)/utils.c $(DIR_SRC)/dec_text.c $(DIR_SRC)/msgpack_in.c
RESTORE_OBJ := $(call src_to_obj, $(RESTORE_SRC))
RESTORE_DEP := $(call obj_to_dep, $(RESTORE_OBJ))

BACKUP := $(DIR_BIN)/asvalidation
RESTORE := $(DIR_BIN)/ascorrection
TOML := $(DIR_TOML)/libtoml.a

INCS := $(BACKUP_INC) $(RESTORE_INC)
SRCS := $(BACKUP_SRC) $(RESTORE_SRC)
OBJS := $(BACKUP_OBJ) $(RESTORE_OBJ)
DEPS := $(BACKUP_DEP) $(RESTORE_DEP)
BINS := $(TOML) $(BACKUP) $(RESTORE)

# sort removes duplicates
INCS := $(sort $(INCS))
SRCS := $(sort $(SRCS))
OBJS := $(sort $(OBJS))
DEPS := $(sort $(DEPS))

.PHONY: all clean ragel

all: $(BINS)

clean:
	$(MAKE) -C $(DIR_TOML) clean
	rm -f $(DEPS) $(OBJS) $(BINS)
	if [ -d $(DIR_OBJ) ]; then rmdir $(DIR_OBJ); fi
	if [ -d $(DIR_BIN) ]; then rmdir $(DIR_BIN); fi
	if [ -d $(DIR_DOCS) ]; then rm -r $(DIR_DOCS); fi
	if [ -d $(DIR_ENV) ]; then rm -r $(DIR_ENV); fi

tests:
	./tests.sh $(DIR_ENV)

ragel:
	ragel $(DIR_SRC)/spec.rl

$(DIR_DOCS): $(INCS) $(SRCS) README.md
	if [ ! -d $(DIR_DOCS) ]; then mkdir $(DIR_DOCS); fi
	doxygen doxyfile

$(DIR_OBJ):
	mkdir $(DIR_OBJ)

$(DIR_BIN):
	mkdir $(DIR_BIN)

$(DIR_OBJ)/%.o: $(DIR_SRC)/%.c | $(DIR_OBJ)
	$(CC) $(CFLAGS) -MMD -o $@ -c $(INCLUDES) $<

$(BACKUP): $(BACKUP_OBJ) | $(DIR_BIN)
	$(CC) $(LDFLAGS) -o $(BACKUP) $(BACKUP_OBJ) $(LIBRARIES)

$(RESTORE): $(RESTORE_OBJ) | $(DIR_BIN)
	$(CC) $(LDFLAGS) -o $(RESTORE) $(RESTORE_OBJ) $(LIBRARIES)

$(TOML):
	$(MAKE) -C $(DIR_TOML)

-include $(BACKUP_DEP)
-include $(RESTORE_DEP)

