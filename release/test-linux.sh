#!/bin/bash
# Linux release test for LinShare (release/test-plan.md), run from the project root after
# the CI AppImage is in dist/<version>/ and its smoke artifacts in dist/<version>/smoke-x86_64.
#
#   XDISPLAY=:97 SCRATCH=/tmp/linshare-test bash release/test-linux.sh
#
# Needs a running Xvfb + Openbox on XDISPLAY, xdotool, ImageMagick, tesseract. Builds the
# muscled fixture into SCRATCH the first time. Writes dist/<version>/evidence/linux.txt.
set -u
. ./haiku-app.env; V=$VERSION; D=dist/$V; E=$D/evidence; S=$D/shots
P=$HOME/.claude/skills/beos-app-platforms/scripts
SCR=${SCRATCH:-/tmp/linshare-test}; mkdir -p "$SCR"
MUSCLED=$SCR/muscled-build/muscle/server/muscled
export DISPLAY=${XDISPLAY:-:97}
if [ ! -x "$MUSCLED" ]; then
	rm -rf "$SCR/muscled-build"; mkdir -p "$SCR/muscled-build"; cp -r source/muscle "$SCR/muscled-build/"
	( cd "$SCR/muscled-build/muscle/server" \
	  && sed -i 's/^muscled : $(OBJFILES) $(ZLIBOBJS)/& MemoryAllocator.o/' Makefile \
	  && make -s muscled CXXFLAGS="-std=gnu++17 -I.. -DMUSCLE_SINGLE_THREAD_ONLY \
	     -DMUSCLE_ENABLE_ZLIB_ENCODING -DMUSCLE_AVOID_IPV6 -DMUSCLE_64_BIT_PLATFORM \
	     -I../zlib/zlib" CFLAGS="-DZ_HAVE_UNISTD_H" > /dev/null 2>&1 ) \
	  || { echo "muscled build failed"; exit 1; }
fi
mkdir -p $E $S
HEAD=$(git rev-parse HEAD)
F=${APP_NAME}-${V}-x86_64.AppImage
APPIMG=$PWD/$D/$F
chmod +x "$APPIMG"
p=linux
X=$E/linux.txt
FAILS=0
chk() { n=$1 t=$2; shift 2
	if "$@"; then echo "CHECK $n PASS $t" >> $X; else echo "CHECK $n FAIL $t" >> $X; FAILS=$((FAILS+1)); fi; }
shot() { import -window root "$S/$1.png"; }
ocr() { sh $P/ocr-find.sh "$S/$1.png" --text 2>/dev/null; }
pos() { sh $P/ocr-find.sh "$S/$1.png" "$2" 2>/dev/null | awk 'NR==1{print $1, $2}'; }   # "X Y" of a word
click() { xdotool mousemove "$1" "$2"; sleep 0.3; xdotool mousedown 1; sleep 0.15; xdotool mouseup 1; sleep 0.3; }
win() { xdotool search --onlyvisible --name '^LinShare' | sort -n | sed -n "$1p"; }

xdotool getmouselocation > /dev/null || { echo "display $DISPLAY is dead"; exit 1; }
pkill -x LinShare; pkill -x muscled; sleep 1

# fixture
( $MUSCLED listen=127.0.0.1:2960 displaylevel=info > $E/linux-fixture.log 2>&1 & )
for i in $(seq 20); do ss -ltn | grep -q '127.0.0.1:2960' && break; sleep 0.25; done

# fresh state: two throwaway homes, A shares one file
H=$SCR/rt; rm -rf $H; mkdir -p $H/A/LinShare/shared $H/B $SCR/rt-bin
echo "hello from $p" > $H/A/LinShare/shared/hello-from-$p.txt
printf '#!/bin/sh\necho "xdg-open $*" >> %s/xdg-open.log\n' $H > $SCR/rt-bin/xdg-open; chmod +x $SCR/rt-bin/xdg-open
run() { ( env -u WAYLAND_DISPLAY -u XDG_CONFIG_HOME -u XDG_DATA_HOME COSMOE_BACKEND=x11 \
	PATH=$SCR/rt-bin:$PATH HOME=$H/$1 "$APPIMG" 127.0.0.1 > $H/app-$1.log 2>&1 & ); }

{
echo "platform: linux"
echo "artifact: $F"
echo "sha256: $(sha256sum $D/$F | cut -d' ' -f1)"
echo "commit: $HEAD"
echo "os: $(. /etc/os-release; echo $PRETTY_NAME) $(uname -r), X11 Xvfb/Openbox"
echo "ci-run: $(cat $D/ci-run)"
} > $X

ca=$(sh $P/check-artifact.sh appimage $D/$F 2>&1 | tail -1)
chk install "check-artifact.sh appimage $F -> $ca" test "${ca#CHECKS PASSED}" != "$ca"

ext=$SCR/rt-extract; rm -rf $ext; mkdir -p $ext
(cd $ext && "$APPIMG" --appimage-extract usr/bin/$APP_NAME > /dev/null 2>&1)
sig=$(strings -a $ext/squashfs-root/usr/bin/$APP_NAME | grep -m1 -F "$APP_SIG")
chk attrs "strings usr/bin/$APP_NAME -> \"$sig\"" test "$sig" = "$APP_SIG"

run A; sleep 8; run B; sleep 8
A=$(win 1); B=$(win 2)
xdotool windowmove $A 160 60; xdotool windowsize $A 1000 600
xdotool windowmove $B 0 0; xdotool windowsize $B 1100 720; xdotool windowactivate $B; sleep 2
shot linux-launch; ocr linux-launch > $S/linux-launch.txt
chk launch "linux-launch.png: \"$(grep -m1 -o 'Connected' $S/linux-launch.txt)\", 2 windows ($A $B)" \
	bash -c "[ -n '$A' ] && [ -n '$B' ] && grep -q Connected $S/linux-launch.txt"

# query (in B)
xy=$(pos linux-launch Start); sx=${xy% *}; sy=${xy#* }
click $((sx - 130)) $sy; xdotool key ctrl+a; xdotool type --delay 30 'hello*'; sleep 0.3
click $((sx + 20)) $sy; sleep 4
shot linux-query; ocr linux-query > $E/linux-query.txt; cp $E/linux-query.txt $E/linux-screen.txt
chk query "linux-query.txt: \"$(grep -m1 -o "hello-from-$p.txt" $E/linux-query.txt)\"" grep -q "hello-from-$p\.txt" $E/linux-query.txt

# download
xy=$(pos linux-query "hello-from-$p.txt"); click ${xy% *} ${xy#* }
shot linux-selected
xy=$(pos linux-selected Download); [ -n "$xy" ] && click ${xy% *} ${xy#* }
for i in $(seq 30); do [ -s $H/B/LinShare/downloads/hello-from-$p.txt ] && break; sleep 0.5; done
a=$(sha256sum < $H/A/LinShare/shared/hello-from-$p.txt); b=$(sha256sum < $H/B/LinShare/downloads/hello-from-$p.txt 2>/dev/null)
rm -f $E/linux-download.txt
[ -n "$b" ] && [ "$a" = "$b" ] && echo "sha256 match hello-from-$p.txt" > $E/linux-download.txt
shot linux-download
chk download "linux-download.txt: \"$(cat $E/linux-download.txt 2>/dev/null)\" (${a%% *})" test -s $E/linux-download.txt

# chat: B types, A shows it
xy=$(pos linux-download Chat:); [ -n "$xy" ] && click $((${xy% *} + 400)) ${xy#* }
xdotool type --delay 30 "chat from $p B"; xdotool key Return; sleep 2
xdotool windowactivate $A; sleep 2
shot linux-chat; ocr linux-chat > $E/linux-chat.txt
chk chat "linux-chat.txt: \"$(grep -m1 -o "chat from $p B" $E/linux-chat.txt)\"" grep -q "chat from $p B" $E/linux-chat.txt

# menus: File -> About LinShare in B (opening a menu once raced in Hokku, logged by log-clean)
xdotool windowactivate $B; sleep 1
# (not eval --shell: that would overwrite X, the evidence file)
bx=$(xdotool getwindowgeometry --shell $B | sed -n 's/^X=//p'); by=$(xdotool getwindowgeometry --shell $B | sed -n 's/^Y=//p')
click $((bx + 18)) $((by + 10)); sleep 1
shot linux-menu
xy=$(pos linux-menu About); [ -n "$xy" ] && click $((${xy% *} + 30)) ${xy#* }; sleep 2
about=$(xdotool search --onlyvisible --name '^About LinShare' | head -1)
[ -n "$about" ] && { shot linux-about; xdotool windowactivate $about; sleep 0.5; xdotool key Return; sleep 1.5; }
gone=$(xdotool search --onlyvisible --name '^About LinShare' | head -1)
chk about "File menu -> About LinShare: window ${about:-none}, closed with Return: $([ -z "$gone" ] && echo yes || echo no)" \
	bash -c "[ -n '$about' ] && [ -z '$gone' ]"

# quit both with the app's own shortcut (Ctrl+Q on Linux)
for w in $A $B; do xdotool windowactivate $w; sleep 1; xdotool key ctrl+q; sleep 1; done
for i in $(seq 10); do pgrep -x LinShare > /dev/null || break; sleep 1; done
left=$(pgrep -x LinShare | wc -l)
chk quit "Ctrl+Q in each window -> $left LinShare processes after 10 s" test "$left" = 0
pkill -x LinShare

cat $H/app-A.log $H/app-B.log > $E/linux-app.log
bad=$(grep -ciE 'error|assert|crash|segment|abort|debugger|terminate|exception' $E/linux-app.log)
chk log-clean "linux-app.log: $(wc -l < $E/linux-app.log) lines, $bad bad" test "$bad" = 0

# Wayland: the CI smoke test of the same run
W=$D/smoke-x86_64/wayland-smoke
cp $W/app.log $E/linux-wayland.log 2>/dev/null
wl=$(sh $P/ocr-find.sh $W/wayland-screenshot.png --text 2>/dev/null | grep -m1 -oE 'LinShare|Connect[a-z]*|Server')
# grep -c prints 0 (and exits 1) when nothing matches; no log at all counts as bad
if [ -f $E/linux-wayland.log ]; then
	wbad=$(grep -ciE 'error|assert|crash|segment|abort|debugger|terminate|exception' $E/linux-wayland.log)
else wbad=nolog; fi
chk wayland "$W/wayland-screenshot.png: OCR \"$wl\"; app.log $(wc -l < $E/linux-wayland.log 2>/dev/null) lines, $wbad bad" \
	bash -c "[ -n '$wl' ] && [ '$wbad' = 0 ]"

pkill -x muscled
[ $FAILS = 0 ] && echo "RESULT: PASS" >> $X || echo "RESULT: FAIL" >> $X
cat $X
