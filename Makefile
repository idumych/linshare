# LinShare — HiShare (BeShare) built on Linux with Cosmoe/Hokku, and still on
# Haiku, from the same sources.
#
#   make          -> ./LinShare
#   make test     -> host-side unit tests (any OS, no Haiku API needed)
#   make install  -> copies the app to your apps folder
#
# Contract the packaging scripts rely on:
#   - `make` leaves the binary at ./$(NAME) and the compiled resources at
#     obj/$(NAME).rsrc (Haiku) or obj/$(NAME).rsrc.o (Cosmoe);
#   - CXXFLAGS/LDFLAGS from the command line ADD to ours (override +=);
#   - COSMOE_ROOT selects the Cosmoe install.
#
# source/hishare/Makefile is upstream HiShare's own Haiku build, kept as is.

NAME     := LinShare
RDEF     := source/hishare/LinShare.rdef
CXX      ?= g++
CC       ?= gcc
CXXFLAGS ?= -O2 -g
CFLAGS   ?= -O2 -g
UNAME    := $(shell uname -s)
ARCH     := $(shell uname -m)
COSMOE_ROOT ?= /usr

APP      := source/hishare
MUSCLE   := source/muscle
SANTA    := $(APP)/santa

SRCS := \
	$(addprefix $(APP)/, PortMapper.cpp ReflowingTextView.cpp ShareNetClient.cpp \
		ServerConnection.cpp ShareFileTransfer.cpp ChatWindow.cpp ShareApplication.cpp \
		ShareWindow.cpp PrivateChatWindow.cpp main.cpp RemoteFileItem.cpp \
		RemoteUserItem.cpp RemoteInfo.cpp ShareColumn.cpp ShareMIMEInfo.cpp \
		ShareUtils.cpp SplitPane.cpp md5.cpp ShareStrings.cpp ColorPicker.cpp \
		PirateDemo.cpp ShareSettingsWindow.cpp) \
	$(addprefix $(MUSCLE)/, system/MessageTransceiverThread.cpp system/Thread.cpp \
		system/AcceptSocketsThread.cpp message/Message.cpp system/SetupSystem.cpp \
		util/String.cpp syslog/SysLog.cpp iogateway/AbstractMessageIOGateway.cpp \
		util/PulseNode.cpp iogateway/MessageIOGateway.cpp \
		iogateway/PlainTextMessageIOGateway.cpp regex/PathMatcher.cpp \
		regex/QueryFilter.cpp besupport/ConvertMessages.cpp \
		util/NetworkUtilityFunctions.cpp util/SocketMultiplexer.cpp \
		reflector/SignalHandlerSession.cpp system/SignalMultiplexer.cpp \
		util/Directory.cpp util/FilePathInfo.cpp util/MiscUtilityFunctions.cpp \
		regex/StringMatcher.cpp reflector/ReflectServer.cpp \
		reflector/AbstractReflectSession.cpp reflector/DumbReflectSession.cpp \
		reflector/StorageReflectSession.cpp system/GlobalMemoryAllocator.cpp \
		reflector/DataNode.cpp reflector/ServerComponent.cpp \
		reflector/RateLimitSessionIOPolicy.cpp util/ByteBuffer.cpp \
		zlib/ZLibCodec.cpp zlib/ZLibUtilityFunctions.cpp util/MemoryAllocator.cpp) \
	$(addprefix $(SANTA)/, BetterScrollView/BetterScrollView.cpp \
		ColumnListView/CLVColumn.cpp ColumnListView/CLVColumnLabelView.cpp \
		ColumnListView/CLVEasyItem.cpp ColumnListView/CLVListItem.cpp \
		ColumnListView/ColumnListView.cpp Cursors/Cursors.cpp \
		NewStrings/NewStrings.cpp PrefilledBitmap/PrefilledBitmap.cpp \
		ScrollViewCorner/ScrollViewCorner.cpp)
CSRCS := $(addprefix $(MUSCLE)/zlib/zlib/, adler32.c deflate.c trees.c zutil.c \
		inflate.c inftrees.c inffast.c gzclose.c gzlib.c gzread.c gzwrite.c \
		crc32.c compress.c)
# The pirate intro's chiptune is x86-64 assembly; other CPUs use the C version
# in PirateDemo.cpp.
ifeq ($(ARCH),x86_64)
  ASRCS := $(APP)/pirate_asm.S
endif

INCLUDES := $(MUSCLE) $(SANTA) $(SANTA)/BetterScrollView $(SANTA)/ColumnListView \
	$(SANTA)/Cursors $(SANTA)/NewStrings $(SANTA)/PrefilledBitmap \
	$(SANTA)/ScrollViewCorner $(MUSCLE)/zlib/zlib
APP_LIBS :=

# MUSCLE: IPv4 only and pthreads, as upstream builds it (see source/hishare/Makefile)
DEFINES := -DMUSCLE_ENABLE_ZLIB_ENCODING -DMUSCLE_AVOID_IPV6 -DMUSCLE_USE_PTHREADS \
	-DMUSCLE_NO_EXCEPTIONS -D_BSD_SOURCE -D_DEFAULT_SOURCE
ifneq ($(filter x86_64 aarch64,$(ARCH)),)
  DEFINES += -DMUSCLE_64_BIT_PLATFORM
endif

override CXXFLAGS += -fno-exceptions -Wall -W -Wno-multichar $(DEFINES) \
	$(addprefix -I,$(INCLUDES))
override CFLAGS += -DZ_HAVE_UNISTD_H $(addprefix -I,$(INCLUDES))

ifeq ($(UNAME),Haiku)
  PLATFORM     := Haiku
  LIBS         := -lbe -lnetwork -lbnetapi -lroot -ltranslation -lmedia \
                  -llocalestub $(APP_LIBS)
  INSTALL_DIR  := $(shell finddir B_USER_NONPACKAGED_DIRECTORY)/apps
  RESOURCES     = rc -o obj/$(NAME).rsrc $(RDEF) && xres -o $@ obj/$(NAME).rsrc
else ifneq ($(wildcard $(COSMOE_ROOT)/include/os/app/Application.h),)
  # Plain Linux with Cosmoe (the Haiku API as a library on X11/Wayland)
  PLATFORM    := Cosmoe
  COSMOE_DIRS := config os os/app os/game os/interface os/kernel os/locale \
                 os/media os/net os/storage os/support os/translation \
                 os/be_apps/Tracker private/interface private/shared \
                 private/support posix
  override CXXFLAGS += -I$(COSMOE_ROOT)/include \
                 $(addprefix -I$(COSMOE_ROOT)/include/,$(COSMOE_DIRS)) \
                 -DAPP_COSMOE -fPIC
  override CFLAGS += -fPIC
  # libbe finds Cosmoe's add-ons and data next to itself, so the AppImage
  # (bin/App + lib/) works wherever it is mounted.
  COSMOE_RPATH ?= $$ORIGIN/../lib
  LIBS        := -L$(COSMOE_ROOT)/lib -lbe -lbnetapi -llocalestub $(APP_LIBS) \
                 -lpthread -Wl,-rpath,'$(COSMOE_RPATH)'
  INSTALL_DIR := $(HOME)/.local/bin
  # Cosmoe reads resources from a .cosmoe_rsrc section linked into the app
  EXTRA_OBJS  := obj/$(NAME).rsrc.o
  RESOURCES    = true
else
  PLATFORM     := none
endif

OBJS := $(patsubst %.cpp,obj/%.o,$(SRCS)) $(patsubst %.c,obj/%.o,$(CSRCS)) \
	$(patsubst %.S,obj/%.o,$(ASRCS))

all: check-platform $(NAME)

check-platform:
ifeq ($(PLATFORM),none)
	@echo "$(NAME) needs Haiku, or Linux with Cosmoe."
	@echo "Linux: Cosmoe installed under COSMOE_ROOT=$(COSMOE_ROOT)."
	@false
endif

obj/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

obj/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

obj/%.o: %.S
	@mkdir -p $(dir $@)
	$(CC) -c $< -o $@

# rc resolves the .hvif imports relative to the working directory
obj/$(NAME).rsrc.o: $(RDEF) $(wildcard $(APP)/*.hvif)
	@mkdir -p obj
	cd $(APP) && LD_LIBRARY_PATH=$(COSMOE_ROOT)/lib $(COSMOE_ROOT)/bin/rc \
		-o $(CURDIR)/obj/$(NAME).rsrc $(notdir $(RDEF))
	cd obj && ld -r -b binary $(NAME).rsrc -o $(NAME).rsrc.o
	objcopy --rename-section .data=.cosmoe_rsrc \
		--add-section .note.GNU-stack=/dev/null \
		--set-section-flags .note.GNU-stack=noload,readonly obj/$(NAME).rsrc.o

$(NAME): $(OBJS) $(EXTRA_OBJS) $(RDEF)
	@mkdir -p obj
	$(CXX) $(LDFLAGS) $(OBJS) $(EXTRA_OBJS) -o $@ $(LIBS)
	$(RESOURCES)
	@if command -v mimeset >/dev/null 2>&1; then mimeset -f $@; fi

# Upstream has no host-side tests (md5test needs the Haiku storage kit)
test:
	@echo "no host-side tests"

install: all
	mkdir -p "$(INSTALL_DIR)"
	cp $(NAME) "$(INSTALL_DIR)/"
	@if command -v mimeset >/dev/null 2>&1; then mimeset -f "$(INSTALL_DIR)/$(NAME)"; fi

clean:
	rm -rf obj $(NAME)

.PHONY: all check-platform test install clean
